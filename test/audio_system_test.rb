require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "gta/audio_system"
require "gta/fixtures"
require "gta/render"

# Event -> command mapping, asserted on the recorded command log (real DLL,
# real noDevice engine, real recorder — no mocks; the log IS the FFI stream
# by construction). Data values come from data/audio/*.json, so expectations
# here are computed from the same tables the sink reads.
class AudioSystemTest < Minitest::Test
  DATA_DIR = File.expand_path("../data/audio", __dir__)
  FIXTURES = File.expand_path("../tmp/fixtures", __dir__)
  ENGINE_TBL = JSON.parse(File.read(File.join(DATA_DIR, "engine.json")))
  CUES_TBL = JSON.parse(File.read(File.join(DATA_DIR, "cues.json")))
  MUSIC_TBL = JSON.parse(File.read(File.join(DATA_DIR, "music.json")))
  TF = ENGINE_TBL["tick_frames"]

  def setup
    GTA::Fixtures.ensure!(File.join(DATA_DIR, "fixtures.json"), FIXTURES, sample_rate: ENGINE_TBL["sample_rate"])
    @engine = GTA::Native.gta_engine_create(0, ENGINE_TBL["channels"], ENGINE_TBL["sample_rate"])
    refute @engine.null?
    @log = GTA::CommandLog.new
    @audio = GTA::AudioSystem.new(engine: @engine, data_dir: DATA_DIR, fixture_dir: FIXTURES, log: @log)
    @renderer = GTA::Renderer.new(@engine, channels: ENGINE_TBL["channels"])
  end

  def teardown
    @audio.destroy
    GTA::Native.gta_engine_destroy(@engine)
  end

  def run_tick(tick, events = [])
    events.each { |name, payload| @audio.handle_event(tick, name, payload) }
    @audio.update(tick)
    @renderer.advance(TF)
  end

  def ops(op)
    @log.lines.select { |l| l.split(" ")[1] == op }
  end

  def fhex(v)
    [v].pack("e").unpack1("H8")
  end

  def test_construction_builds_bus_tree_and_starts_initial_stem
    creates = ops("group_create").map { |l| l.split(" ")[2..3] }
    assert_equal [%w[bus_master -], %w[bus_music bus_master], %w[bus_sfx bus_master], %w[bus_ui bus_master]], creates
    vols = ops("group_set_volume").map { |l| l.split(" ")[2..3] }
    expected = CUES_TBL["buses"].filter_map do |bus, t|
      ["bus_#{bus}", fhex(10.0**(t["volume_db"] / 20.0))] if t["volume_db"]
    end
    assert_equal expected, vols
    loads = ops("sound_load").map { |l| l.split(" ")[2..3] }
    MUSIC_TBL["stems"].each do |stem_id, stem|
      assert_includes loads, [stem_id, "#{stem['file']},bus_music"]
    end
    initial_stem = MUSIC_TBL["states"][MUSIC_TBL["initial_state"]]["stem"]
    assert_equal [initial_stem], ops("sound_start").map { |l| l.split(" ")[2] }
    assert(@log.lines.all? { |l| l.split(" ")[0] == "0" }, "construction commands must land at frame 0")
  end

  def test_cue_event_maps_to_load_volume_pan_start_on_its_bus
    run_tick(0)
    run_tick(1, [["toll_paid", nil]])
    cue = CUES_TBL["cues"]["toll_paid"]
    load = ops("sound_load").last.split(" ")
    assert_equal ["#{TF}", "sound_load", "sound_001", "#{cue['file']},bus_#{cue['bus']}"], load
    assert_equal "#{TF} sound_set_volume sound_001 #{fhex(cue['gain'])}", ops("sound_set_volume").last.strip
    assert_equal "#{TF} sound_set_pan sound_001 #{fhex(cue['pan'])}", ops("sound_set_pan").last.strip
    assert_includes ops("sound_start").map(&:strip), "#{TF} sound_start sound_001 -"
    assert_equal 1, @audio.active_voices
  end

  def test_unmapped_event_is_ignored
    run_tick(0)
    before = @log.lines.size
    run_tick(1, [["attack_hit", { pan: 0.5 }], ["zone_entered", nil]])
    assert_equal before, @log.lines.size
    assert_equal 0, @audio.active_voices
  end

  def test_spatial_cue_takes_pan_and_distance_from_payload
    run_tick(0, [["drone_low", { pan: -0.25, distance: 0.9 }]])
    assert_equal fhex(-0.25), ops("sound_set_pan").last.split(" ")[3]
    run_tick(1, [["toll_paid", { pan: 0.7 }]]) # spatial:false -> payload pan ignored
    assert_equal fhex(CUES_TBL["cues"]["toll_paid"]["pan"]), ops("sound_set_pan").last.split(" ")[3]
  end

  def test_duck_attack_at_event_frame_and_release_after_hold
    duck = CUES_TBL["cues"]["boss1_spawn"]["duck"]
    run_tick(0)
    run_tick(1, [["boss1_spawn", nil]])
    frame = 1 * TF
    gain = 10.0**(duck["duck_db"] / 20.0)
    attack = ops("group_fade_at").last.strip
    assert_equal "#{frame} group_fade_at bus_#{duck['bus']} #{fhex(-1.0)},#{fhex(gain)},#{duck['attack_frames']},#{frame}", attack

    duck_end = frame + duck["attack_frames"] + duck["hold_frames"]
    release_tick = nil
    (2..((duck_end / TF) + 2)).each do |t|
      before = ops("group_fade_at").size
      run_tick(t)
      if ops("group_fade_at").size > before
        release_tick = t
        break
      end
    end
    refute_nil release_tick, "duck release never issued"
    release = ops("group_fade_at").last.strip
    assert_equal "#{release_tick * TF} group_fade_at bus_#{duck['bus']} #{fhex(gain)},#{fhex(1.0)},#{duck['release_frames']},#{duck_end}", release
    assert release_tick * TF + TF > duck_end, "release issued too early"
    assert release_tick * TF <= duck_end, "release start frame in the past"
  end

  def test_duck_overlap_is_a_pure_hold_extension_single_release_then_reattack
    duck = CUES_TBL["cues"]["boss1_spawn"]["duck"]
    gain = 10.0**(duck["duck_db"] / 20.0)
    run_tick(0)
    run_tick(1, [["boss1_spawn", nil]])
    assert_equal 1, ops("group_fade_at").size, "first duck must attack"
    run_tick(2)
    run_tick(3, [["boss1_spawn", nil]]) # inside the hold: extension only
    assert_equal 1, ops("group_fade_at").size,
                 "same-depth overlap must not issue a fade (one pending fade slot per node)"

    duck_end = 3 * TF + duck["attack_frames"] + duck["hold_frames"] # the EXTENDED end
    release_tick = nil
    (4..((duck_end / TF) + 2)).each do |t|
      before = ops("group_fade_at").size
      run_tick(t)
      if ops("group_fade_at").size > before
        release_tick = t
        break
      end
    end
    refute_nil release_tick, "release never issued"
    assert_equal 2, ops("group_fade_at").size, "exactly one release for the merged episode"
    release = ops("group_fade_at").last.strip
    assert_equal "#{release_tick * TF} group_fade_at bus_#{duck['bus']} #{fhex(gain)},#{fhex(1.0)},#{duck['release_frames']},#{duck_end}", release

    run_tick(release_tick + 1, [["boss1_spawn", nil]]) # mid-release: re-attack
    assert_equal 3, ops("group_fade_at").size, "re-attack during release must issue"
    assert ops("group_fade_at").last.include?("#{fhex(-1.0)},#{fhex(gain)}"),
           "re-attack must start from current volume (beg=-1)"
  end

  def test_steal_stops_and_destroys_victim_before_loading_stealer
    run_tick(0, [["drone_low", nil]]) # priority 10 victim -> sound_001
    cap = CUES_TBL["voice_pool"]["per_category_caps"]["sfx"]
    (cap - 1).times { |i| @audio.handle_event(1, "filler_blip", { distance: i / 100.0 }) }
    @audio.update(1)
    @renderer.advance(TF)
    assert_equal cap, @audio.active_voices
    run_tick(2, [["boss1_spawn", nil]]) # sfx at cap -> in-category steal
    assert_equal cap, @audio.active_voices, "steal must reuse the slot, not grow the category"
    stop_idx = @log.lines.index { |l| l.include?("sound_stop sound_001") }
    destroy_idx = @log.lines.index { |l| l.include?("sound_destroy sound_001") }
    stealer_load_idx = @log.lines.index { |l| l.include?("sound_load sound_0#{cap + 1}") }
    refute_nil stop_idx, "victim not stopped"
    refute_nil destroy_idx, "victim not destroyed"
    refute_nil stealer_load_idx, "stealer not loaded"
    assert stop_idx < destroy_idx && destroy_idx < stealer_load_idx, "steal command order wrong"
  end

  def test_refused_steal_drops_cue_and_counts_it
    cap = CUES_TBL["voice_pool"]["per_category_caps"]["sfx"]
    cap.times { @audio.handle_event(0, "boss1_spawn", nil) } # priority 90 fills the sfx cap
    @audio.update(0)
    @renderer.advance(TF)
    assert_equal cap, @audio.active_voices
    before = @log.lines.size
    @audio.handle_event(1, "drone_low", nil) # priority 10 cannot steal priority 90 in-category
    assert_equal before, @log.lines.size, "refused cue must issue no commands"
    assert_equal 1, @audio.dropped_cues
  end

  def test_voice_end_is_polled_released_and_slot_reused
    run_tick(0, [["toll_paid", nil]]) # 0.2 s tone = 9600 frames
    assert_equal 1, @audio.active_voices
    (1..14).each { |t| run_tick(t) }
    assert_equal 0, @audio.active_voices, "ended voice not released by polling"
    assert(ops("sound_destroy").any? { |l| l.include?("sound_001") })
    run_tick(15, [["toll_paid", nil]])
    assert_equal 1, @audio.active_voices
  end

  def test_music_transition_is_bar_quantized_and_fully_scheduled_at_request
    (0..119).each { |t| run_tick(t) }
    run_tick(120, [["music_set_state", { state: "combat" }]])
    frame = 120 * TF                       # 96_000 = exactly bar 1
    boundary = 192_000                     # next boundary AFTER frame+TF
    fade = MUSIC_TBL["transition"]["crossfade_frames"]

    out_fade = ops("sound_fade_at").select { |l| l.split(" ")[2] == "stem_a" }.last.strip
    assert_equal "#{frame} sound_fade_at stem_a #{fhex(-1.0)},#{fhex(0.0)},#{fade},#{boundary}", out_fade
    assert_includes ops("sound_stop_at").map(&:strip), "#{frame} sound_stop_at stem_a #{boundary + fade}"
    in_fade = ops("sound_fade_at").select { |l| l.split(" ")[2] == "stem_b" }.last.strip
    assert_equal "#{frame} sound_fade_at stem_b #{fhex(0.0)},#{fhex(1.0)},#{fade},#{boundary}", in_fade
    assert_includes ops("sound_start_at").map(&:strip), "#{frame} sound_start_at stem_b #{boundary}"
    assert_includes ops("sound_seek").map(&:strip), "#{frame} sound_seek stem_b 0"
    assert_includes ops("sound_stop_at").map(&:strip), "#{frame} sound_stop_at stem_b #{GTA::AudioSystem::NEVER}"

    assert @audio.music_pending?
    before = @log.lines.size
    run_tick(121, [["music_set_state", { state: "calm" }]]) # ignored while pending
    assert_equal before, @log.lines.size
    assert_equal "calm", @audio.music_state

    done_tick = (boundary + fade) / TF
    (122..done_tick).each { |t| run_tick(t) }
    refute @audio.music_pending?
    assert_equal "combat", @audio.music_state
  end

  def test_music_request_for_current_state_is_a_no_op
    run_tick(0)
    before = @log.lines.size
    run_tick(1, [["music_set_state", { state: "calm" }]])
    assert_equal before, @log.lines.size
  end

  # -- clock-domain anchor (integration-readiness §3; M5 r2 mail) ------------

  def test_clock_anchor_stays_at_boot_in_lockstep
    assert_equal [0, 0], @audio.clock_anchor, "boot anchor must be (0, 0) in noDevice"
    (0..119).each { |t| run_tick(t) }
    run_tick(120, [["music_set_state", { state: "combat" }]])
    assert_equal [0, 0], @audio.clock_anchor,
                 "lockstep drift is 0 by construction — the anchor must never move in gate mode"
  end

  def test_reanchor_at_music_boundary_under_skewed_clock
    # Engine clock at HALF the tick rate (the deterministic device-drift
    # instrument — same mechanics as replay_clock_drift). At tick 130 the
    # request is the anchor point: predicted 104000, actual 52000.
    (0..129).each do |t|
      @audio.update(t)
      @renderer.advance(400)
    end
    @audio.handle_event(130, "music_set_state", { state: "combat" })
    assert_equal [130, 52_000], @audio.clock_anchor, "drift -52000 must re-snap the anchor"

    fade = MUSIC_TBL["transition"]["crossfade_frames"]
    out_fade = ops("sound_fade_at").select { |l| l.split(" ")[2] == "stem_a" }.last.strip
    assert_equal "52000 sound_fade_at stem_a #{fhex(-1.0)},#{fhex(0.0)},#{fade},96000", out_fade,
                 "boundary must quantize from the RE-ANCHORED clock (bar 1 = 96000), not tick math (192000)"
    assert_includes ops("sound_start_at").map(&:strip), "52000 sound_start_at stem_b 96000"
  end

  def test_drift_of_exactly_one_tick_does_not_reanchor
    # Threshold is "drift EXCEEDS a tick": 100 ticks at TF-8 frames/tick puts
    # the clock exactly 800 frames behind — the anchor must hold.
    (0..99).each do |t|
      @audio.update(t)
      @renderer.advance(TF - 8)
    end
    @audio.handle_event(100, "music_set_state", { state: "combat" })
    assert_equal [0, 0], @audio.clock_anchor, "|drift| == one tick must NOT re-anchor"
    out_fade = ops("sound_fade_at").select { |l| l.split(" ")[2] == "stem_a" }.last.strip
    assert out_fade.start_with?("#{100 * TF} "),
           "sub-threshold request must schedule from unshifted tick math: #{out_fade}"
  end

  def test_same_tick_double_duck_issues_one_attack_one_release
    duck = CUES_TBL["cues"]["boss1_spawn"]["duck"]
    gain = 10.0**(duck["duck_db"] / 20.0)
    run_tick(0)
    run_tick(1, [["boss1_spawn", nil], ["boss2_spawn", nil]]) # one frame, two duck cues
    assert_equal 2, @audio.active_voices, "both cue voices must play"
    assert_equal 1, ops("group_fade_at").size,
                 "same-tick same-depth double duck must issue exactly ONE attack fade"

    duck_end = 1 * TF + duck["attack_frames"] + duck["hold_frames"]
    release_tick = nil
    (2..((duck_end / TF) + 2)).each do |t|
      before = ops("group_fade_at").size
      run_tick(t)
      if ops("group_fade_at").size > before
        release_tick = t
        break
      end
    end
    refute_nil release_tick, "release never issued"
    assert_equal 2, ops("group_fade_at").size, "exactly one release for the shared episode"
    release = ops("group_fade_at").last.strip
    assert_equal "#{release_tick * TF} group_fade_at bus_#{duck['bus']} #{fhex(gain)},#{fhex(1.0)},#{duck['release_frames']},#{duck_end}", release
  end
end
