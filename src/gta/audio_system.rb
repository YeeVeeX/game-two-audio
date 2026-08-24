# gta/audio_system.rb — the pure event sink (ADR 0001 decision 4).
#
# Consumes (tick, event, payload) tuples against the data/audio tables and
# drives the engine exclusively through CommandIO (so the gate's command log
# and the FFI stream are the same thing by construction). Never feeds state
# back into the sim — the only readers are diagnostics.
#
# Structural laws honored here:
#  - The audio thread never enters Ruby: control is schedule-ahead absolute
#    PCM frames + polling in update(); no callbacks anywhere.
#  - All timing derives from (event stream, tick) through an ANCHORED linear
#    map: frame = anchor_frame + (tick - anchor_tick) * tick_frames
#    (tick_frames from data/audio/engine.json). The engine clock is read at
#    exactly two anchor points — once at boot, and at a music transition
#    that is about to schedule (integration-readiness §3) — never per-command,
#    never per-tick. Rationale: on a real device the tick clock and the device
#    clock are different oscillators (measured 2026-08-18 on the integration
#    machine: ~800 frames/s linear drift, tick clock ~1.7% fast); a boot-time
#    anchor alone cannot absorb a linear rate, so the anchor re-snaps at music
#    boundaries when |engine_now - frame_for(tick)| exceeds one tick. In
#    noDevice gate mode the harness advances the clock in lockstep (engine
#    time == tick * tick_frames at every control moment), drift is 0 by
#    construction and the anchor never moves — the gate corpus is mechanically
#    inert to this path (md5 pins unchanged; replay_clock_drift skews the
#    harness clock deterministically to exercise the re-anchor).
#  - One pending fade slot per engine node (miniaudio fadeSettings): the duck
#    release fade is issued from update() on the last tick before the hold
#    expires — never pre-stacked with the attack. AudioData validates
#    hold_frames >= tick_frames so the release start is never in the past.
#  - Music transitions are quantized to the next bar boundary at least one
#    tick ahead and fully scheduled at request time (spike 05 pattern), then
#    never adjusted. A request arriving while one is pending is ignored
#    (deterministic policy); so is a request for the current state.
#  - Zero Ruby allocations on the steady-state update() path (proven by the
#    scaling test). Per-EVENT work (cue starts) may allocate O(1) handles.
#
# Voice steal executes exactly like spike 04: stop victim, destroy, load new
# sound into the slot. End-of-sound is polled via gta_sound_at_end.

require_relative "audio_data"
require_relative "voice_pool"
require_relative "command_io"

module GTA
  class AudioSystem
    MUSIC_EVENT = "music_set_state"
    NEVER = 0xFFFFFFFFFFFFFFFF # miniaudio sentinel: default/cleared stop time

    # Runtime user-volume trim bounds (J-6 contract, game-two menu — mail
    # done/from-game-two-j6-volume-api.md; docs/integration-readiness.md §2b).
    # CONTRACT constants, not mix tunables (same class as NEVER and the log
    # grammar): the game persists raw trim dBs in its prefs, so a data-table
    # edit must never silently re-interpret them; and game-two carries its own
    # data/audio tables, so a new required JSON field would break its boot.
    # Ceiling 0.0 is structural: a user trim can only ATTENUATE, never push a
    # bus past the authored balance — the M3 headroom proof (−1 dBFS ceiling,
    # sfx −10 dB budget) therefore holds at every user setting. At the floor
    # the gain snaps to exactly 0.0 (true digital mute).
    USER_TRIM_DB_FLOOR = -60.0
    USER_TRIM_DB_CEILING = 0.0

    DuckState = Struct.new(:bus_id, :group, :phase, :duck_end, :duck_gain, :release_frames)
    DuckRule = Struct.new(:state, :gain, :attack, :hold, :release)

    attr_reader :music_state, :dropped_cues, :config

    def initialize(engine:, data_dir:, fixture_dir:, log: nil)
      @engine = engine
      @cfg = AudioData.load(data_dir)
      @config = @cfg
      @fixture_dir = fixture_dir
      @io = CommandIO.new(log: log)
      @tf = @cfg.engine["tick_frames"]
      @bar_frames = AudioData.bar_frames(@cfg.music, @cfg.engine)
      @crossfade = @cfg.music["transition"]["crossfade_frames"]

      @io.frame = 0
      @anchor_tick = 0
      @anchor_frame = Native.gta_engine_time_pcm(@engine) # boot anchor (0 in noDevice)
      build_buses
      build_duck_states
      build_voice_pool
      build_music
      @dropped_cues = 0
      @sound_seq = 0
    end

    # -- event sink ----------------------------------------------------------

    def handle_event(tick, name, payload = nil)
      key = name.is_a?(Symbol) ? name.name : name
      if key == MUSIC_EVENT
        request_music_state(tick, payload.fetch(:state))
        return nil
      end
      frame = frame_for(tick)
      @io.frame = frame
      cue_id = @cfg.events[key]
      return nil if cue_id.nil? # audio is a sink: unmapped events are not ours
      start_cue(frame, cue_id, payload)
      nil
    end

    # Call once per tick AFTER that tick's events, BEFORE advancing the engine.
    def update(tick)
      frame = frame_for(tick)
      @io.frame = frame

      # 1. poll voice ends (never callbacks)
      i = 0
      while i < @max_voices
        s = @slot_sounds[i]
        if s && Native.gta_sound_at_end(s) == 1
          @io.sound_destroy(@slot_ids[i], s)
          @slot_sounds[i] = nil
          @slot_ids[i] = nil
          @pool.release(i)
        end
        i += 1
      end

      # 2. duck releases: issue on the last tick before the hold expires
      i = 0
      while i < @duck_list.size
        ds = @duck_list[i]
        if ds.phase == :ducked && frame + @tf > ds.duck_end
          @io.group_set_fade_start_pcm(@group_log_ids[ds.bus_id], ds.group,
                                       ds.duck_gain, 1.0, ds.release_frames, ds.duck_end)
          ds.phase = :idle
        end
        i += 1
      end

      # 3. music transition completion (pure tick math)
      if @music_pending && frame >= @music_pending_done
        @music_state = @music_pending
        @music_pending = nil
      end
      nil
    end

    # -- runtime bus volume (public control surface; J-6, game-two menu) ------

    # set_bus_volume(bus_id, db) -> applied trim db (Float, post-clamp)
    #
    # db is a USER TRIM in dB relative to the AUTHORED bus volume_db from
    # cues.json: effective gain = db_to_gain(authored_db + trim). The trim is
    # clamped to [USER_TRIM_DB_FLOOR, USER_TRIM_DB_CEILING]; at the floor the
    # gain snaps to exactly 0.0 (true mute — the menu quick-mute is
    # set_bus_volume(bus, USER_TRIM_DB_FLOOR), restore = re-apply the prior
    # trim). Unknown bus_id is a NAMED REFUSAL (ArgumentError, loud by design,
    # same policy as unknown music states) — render menu rows from bus_ids so
    # unknown ids stay a programming error, never user-reachable.
    #
    # Control-thread only, like every public method here. Applies immediately
    # (menu-rate, unfaded) through the ordinary command path — one logged
    # group_set_volume line, stamped at the last ticked frame. DUCK
    # INDEPENDENCE: ducks ride the group's FADER (group_fade_at); this trim
    # drives the group's node volume (gta_group_set_volume) — two independent
    # multipliers in the miniaudio engine node, so a trim change mid-duck
    # applies at once and the duck attack/hold/release schedule is untouched
    # (the release still restores the fader to 1.0 on time; pinned by
    # replay_bus_volume's group_fade_at count and the mid-duck unit test).
    def set_bus_volume(bus_id, db)
      key = bus_id.is_a?(Symbol) ? bus_id.name : bus_id
      group = @groups[key]
      raise ArgumentError, "unknown bus #{key}" if group.nil?
      trim = Float(db).clamp(USER_TRIM_DB_FLOOR, USER_TRIM_DB_CEILING)
      gain = trim <= USER_TRIM_DB_FLOOR ? 0.0 : db_to_gain(@bus_authored_db.fetch(key) + trim)
      @io.group_set_volume(@group_log_ids.fetch(key), group, gain)
      trim
    end

    # Bus ids in build order (master first, then master's children), frozen —
    # the menu renders volume rows from this truth instead of hardcoding.
    def bus_ids
      @group_order
    end

    # -- diagnostics (read-only; audio never feeds the sim) -------------------

    def active_voices
      @pool.active_count
    end

    def music_pending?
      !@music_pending.nil?
    end

    # [anchor_tick, anchor_frame] of the tick->frame map (clock-domain anchor,
    # integration-readiness §3). Diagnostic only — audio never feeds the sim.
    def clock_anchor
      [@anchor_tick, @anchor_frame]
    end

    # Destroy sounds before groups, children before master, groups before the
    # caller destroys the engine.
    def destroy
      i = 0
      while i < @max_voices
        s = @slot_sounds[i]
        if s
          @io.sound_destroy(@slot_ids[i], s)
          @slot_sounds[i] = nil
          @pool.release(i)
        end
        i += 1
      end
      @stem_ptrs.each { |id, ptr| @io.sound_destroy(id, ptr) }
      @group_order.reverse_each { |bus| @io.group_destroy(@group_log_ids[bus], @groups[bus]) }
      nil
    end

    private

    # -- construction (frame 0; all tables parsed here, never on the path) ----

    def build_buses
      @groups = {}
      @group_log_ids = {}
      @group_order = []
      @bus_authored_db = {}
      buses = @cfg.buses
      create_bus("master", FFI::Pointer::NULL, "-", buses["master"])
      buses["master"].fetch("children", []).each do |bus_id|
        create_bus(bus_id, @groups["master"], "bus_master", buses[bus_id])
      end
      @group_order.freeze
    end

    def create_bus(bus_id, parent_ptr, parent_log_id, table)
      log_id = "bus_#{bus_id}"
      g = @io.group_create(log_id, @engine, parent_ptr, parent_log_id)
      @groups[bus_id] = g
      @group_log_ids[bus_id] = log_id
      @group_order << bus_id
      db = table["volume_db"]
      @bus_authored_db[bus_id] = db || 0.0 # absent volume_db = engine default (0 dB)
      @io.group_set_volume(log_id, g, db_to_gain(db)) if db
    end

    def build_duck_states
      @duck_states = {}
      @duck_list = []
      @cfg.buses.each_key do |bus_id|
        ds = DuckState.new(bus_id, @groups[bus_id], :idle, 0, 1.0, 0)
        @duck_states[bus_id] = ds
        @duck_list << ds
      end
      @duck_rules = {}
      @cfg.cues.each do |cue_id, cue|
        rule = cue["duck"]
        next unless rule
        @duck_rules[cue_id] = DuckRule.new(
          @duck_states.fetch(rule["bus"]),
          db_to_gain(rule["duck_db"]),
          rule["attack_frames"], rule["hold_frames"], rule["release_frames"]
        )
      end
    end

    def build_voice_pool
      pool_cfg = @cfg.voice_pool
      @max_voices = pool_cfg["max_voices"]
      @pool = VoicePool.new(max_voices: @max_voices, steal_order: pool_cfg["steal_order"],
                            per_category_caps: pool_cfg["per_category_caps"])
      @slot_sounds = Array.new(@max_voices)
      @slot_ids = Array.new(@max_voices)
    end

    def build_music
      @stem_ptrs = {}
      music_group = @groups.fetch("music")
      @cfg.music["stems"].each do |stem_id, stem|
        path = fixture_path(stem["file"])
        ptr = @io.sound_create_in_group(stem_id, @engine, path, stem["file"], music_group, "bus_music")
        @io.sound_set_looping(stem_id, ptr, stem["loop"] ? 1 : 0)
        @io.sound_set_volume(stem_id, ptr, stem["gain"])
        @stem_ptrs[stem_id] = ptr
      end
      @music_state = @cfg.music["initial_state"]
      @music_pending = nil
      @music_pending_done = 0
      initial_stem = @cfg.music["states"].fetch(@music_state)["stem"]
      @io.sound_start(initial_stem, @stem_ptrs.fetch(initial_stem)) if initial_stem
    end

    # -- cues -----------------------------------------------------------------

    def start_cue(frame, cue_id, payload)
      cue = @cfg.cues[cue_id]
      distance = payload && payload[:distance] ? payload[:distance] : 0.0
      res = @pool.acquire(priority: cue["priority"], distance: distance, category: cue["bus"])
      if res.nil? # pool/category full and the best victim outranks the cue: drop, count
        @dropped_cues += 1
        return
      end
      slot = res[:slot]
      if res[:stolen] # execute the steal exactly like spike 04
        @io.sound_stop(@slot_ids[slot], @slot_sounds[slot])
        @io.sound_destroy(@slot_ids[slot], @slot_sounds[slot])
      end
      @sound_seq += 1
      id = format("sound_%03d", @sound_seq)
      bus_id = cue["bus"]
      s = @io.sound_create_in_group(id, @engine, fixture_path(cue["file"]), cue["file"],
                                    @groups.fetch(bus_id), @group_log_ids.fetch(bus_id))
      @io.sound_set_volume(id, s, cue["gain"])
      pan = cue["spatial"] && payload && payload[:pan] ? payload[:pan] : cue["pan"]
      @io.sound_set_pan(id, s, pan)
      @io.sound_start(id, s)
      @slot_sounds[slot] = s
      @slot_ids[slot] = id

      duck = @duck_rules[cue_id]
      apply_duck(frame, duck) if duck
    end

    # Attack fade starts at the event frame (the chunk containing it is always
    # rendered after handle_event returns — tick loop contract). beg = -1.0 is
    # miniaudio's "from current volume": a re-duck mid-release re-attacks
    # smoothly, and the constant serializes identically in the command log.
    #
    # Overlap while already ducked at the same depth is a PURE HOLD EXTENSION:
    # duck_end moves, no fade is issued (the group already sits at the target
    # gain — a redundant flat fade would only occupy the node's one pending
    # fade slot), and the single release still issues from update() at the
    # EXTENDED end. A different depth re-issues the attack (last-writer-wins,
    # deterministic).
    def apply_duck(frame, rule)
      ds = rule.state
      end_frame = frame + rule.attack + rule.hold
      ds.duck_end = ds.duck_end > end_frame ? ds.duck_end : end_frame
      ds.release_frames = rule.release
      return if ds.phase == :ducked && ds.duck_gain == rule.gain

      ds.duck_gain = rule.gain
      ds.phase = :ducked
      @io.group_set_fade_start_pcm(@group_log_ids[ds.bus_id], ds.group,
                                   -1.0, rule.gain, rule.attack, frame)
    end

    # -- music ----------------------------------------------------------------

    def request_music_state(tick, state_name)
      return if @music_pending          # ignored while pending (documented)
      return if state_name == @music_state
      states = @cfg.music["states"]
      target = states[state_name]
      raise ArgumentError, "unknown music state #{state_name}" if target.nil?
      incoming = target["stem"]
      outgoing = states.fetch(@music_state)["stem"]
      return if incoming == outgoing

      frame = reanchor(tick) # pinned anchor point: a transition is about to schedule
      @io.frame = frame
      earliest = frame + @tf # schedule-ahead: at least one tick
      boundary = ((earliest + @bar_frames - 1) / @bar_frames) * @bar_frames
      fade = @crossfade

      if outgoing
        ptr = @stem_ptrs.fetch(outgoing)
        @io.sound_set_fade_start_pcm(outgoing, ptr, -1.0, 0.0, fade, boundary)
        @io.sound_set_stop_time_pcm(outgoing, ptr, boundary + fade)
      end
      if incoming
        ptr = @stem_ptrs.fetch(incoming)
        @io.sound_seek_pcm(incoming, ptr, 0)              # deterministic phase on stem reuse
        @io.sound_set_stop_time_pcm(incoming, ptr, NEVER) # clear stale scheduled stop
        @io.sound_set_start_time_pcm(incoming, ptr, boundary)
        @io.sound_set_fade_start_pcm(incoming, ptr, 0.0, 1.0, fade, boundary)
        @io.sound_start(incoming, ptr)
      end
      @music_pending = state_name
      @music_pending_done = boundary + fade
    end

    # -- helpers --------------------------------------------------------------

    # The anchored tick->frame map. Pure integer math — allocation-free on the
    # steady-state path.
    def frame_for(tick)
      @anchor_frame + (tick - @anchor_tick) * @tf
    end

    # Clock-domain re-anchor (integration-readiness §3; measured 2026-08-18:
    # linear ~800 frames/s on the integration machine). Called ONLY when a
    # music transition is about to schedule — the one recurring anchor point.
    # The read is a diagnostic-class Native call (never a logged command; a
    # pure read mutates nothing, so recorder equivalence is untouched). The
    # one-tick threshold is structural (contract text: "drift exceeds a
    # tick"), sized by tick_frames from engine.json — it also absorbs the
    # sub-tick sampling jitter of reading mid-tick on a live device. In
    # noDevice lockstep the read returns frame_for(tick) exactly, drift is 0,
    # and this is a no-op forever (gate md5s prove it). After a re-anchor the
    # whole map shifts: in-flight duck windows (duck_end) keep their old-map
    # absolute frames — update()'s release check tracks the new map, so a
    # release lands where the DEVICE clock meets duck_end (uniformly late
    # pre-correction, exact after; if the map jumped forward past duck_end,
    # miniaudio evaluates the release fade as partially elapsed — graceful).
    def reanchor(tick)
      predicted = frame_for(tick)
      now = Native.gta_engine_time_pcm(@engine)
      return predicted unless (now - predicted).abs > @tf

      @anchor_tick = tick
      @anchor_frame = now
      now
    end

    def fixture_path(file_key)
      File.join(@fixture_dir, "#{file_key}.wav")
    end

    def db_to_gain(db)
      10.0**(db / 20.0)
    end
  end
end
