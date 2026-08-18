# gta/audio_data.rb — load + validate the data/audio/*.json tables (pure, no FFI).
#
# Data-driven law: every tunable lives in the JSON; this module only enforces
# STRUCTURAL constraints the code depends on:
#  - cue files / stem files must exist in the fixtures manifest;
#  - buses must form a master-rooted tree, cue/duck bus refs must be declared;
#  - one cue per event (the event->cue index is built here at load);
#  - duck.hold_frames >= engine.tick_frames — one pending fade slot per group
#    node (miniaudio fadeSettings), so the release fade is issued from update()
#    after the attack window has fully elapsed; the hold floor guarantees the
#    release start frame is never in the past;
#  - transition crossfade shorter than a bar; bar length integral in frames.
#
# Everything is parsed and frozen at load time (zero steady-state allocations).

require "json"

module GTA
  module AudioData
    Config = Data.define(:engine, :buses, :voice_pool, :cues, :events, :music, :fixtures)

    module_function

    def load(data_dir)
      engine = read(data_dir, "engine.json")
      cues_tbl = read(data_dir, "cues.json")
      music = read(data_dir, "music.json")
      fixtures = read(data_dir, "fixtures.json")

      validate_engine!(engine)
      validate_buses!(cues_tbl["buses"])
      validate_cues!(cues_tbl, fixtures, engine)
      validate_music!(music, fixtures, engine)

      events = {}
      cues_tbl["cues"].each do |id, cue|
        ev = cue["event"]
        raise ArgumentError, "cues.json: duplicate cue for event #{ev} (#{events[ev]} vs #{id})" if events.key?(ev)
        events[ev] = id
      end

      Config.new(
        engine: deep_freeze(engine),
        buses: deep_freeze(cues_tbl["buses"]),
        voice_pool: deep_freeze(cues_tbl["voice_pool"]),
        cues: deep_freeze(cues_tbl["cues"]),
        events: deep_freeze(events),
        music: deep_freeze(music),
        fixtures: deep_freeze(fixtures)
      )
    end

    # bar length in PCM frames; raises unless integral (music.json + engine.json)
    def bar_frames(music, engine)
      bpm = music["timing"]["bpm"]
      beats = music["timing"]["beats_per_bar"]
      num = engine["sample_rate"] * 60 * beats
      raise ArgumentError, "music.json: bar length not integral in frames (#{num} % #{bpm})" unless (num % bpm).zero?
      num / bpm
    end

    def read(data_dir, name)
      JSON.parse(File.read(File.join(data_dir, name)))
    end

    def validate_engine!(engine)
      raise ArgumentError, "engine.json: sample_rate must be positive" unless engine["sample_rate"].is_a?(Integer) && engine["sample_rate"].positive?
      raise ArgumentError, "engine.json: channels must be 1 or 2" unless [1, 2].include?(engine["channels"])
      raise ArgumentError, "engine.json: tick_frames must be positive" unless engine["tick_frames"].is_a?(Integer) && engine["tick_frames"].positive?
    end

    def validate_buses!(buses)
      raise ArgumentError, "cues.json: buses must include master" unless buses.key?("master")
      buses.fetch("master").fetch("children", []).each do |c|
        raise ArgumentError, "cues.json: undeclared bus #{c}" unless buses.key?(c)
      end
    end

    def validate_cues!(cues_tbl, fixtures, engine)
      buses = cues_tbl["buses"]
      validate_voice_pool!(cues_tbl["voice_pool"], buses)
      cues_tbl["cues"].each do |id, cue|
        %w[event file bus priority gain pan].each do |field|
          raise ArgumentError, "cues.json: cue #{id} missing #{field}" unless cue.key?(field)
        end
        raise ArgumentError, "cues.json: cue #{id} references undeclared bus #{cue['bus']}" unless buses.key?(cue["bus"])
        raise ArgumentError, "cues.json: cue #{id} file #{cue['file']} not in fixtures.json" unless fixtures["tones"].key?(cue["file"])
        raise ArgumentError, "cues.json: cue #{id} priority must be Integer" unless cue["priority"].is_a?(Integer)
        next unless (duck = cue["duck"])

        %w[bus duck_db attack_frames hold_frames release_frames].each do |field|
          raise ArgumentError, "cues.json: cue #{id} duck missing #{field}" unless duck.key?(field)
        end
        raise ArgumentError, "cues.json: cue #{id} ducks undeclared bus #{duck['bus']}" unless buses.key?(duck["bus"])
        raise ArgumentError, "cues.json: cue #{id} duck_db must be negative" unless duck["duck_db"].negative?
        %w[attack_frames hold_frames release_frames].each do |field|
          raise ArgumentError, "cues.json: cue #{id} duck #{field} must be positive" unless duck[field].is_a?(Integer) && duck[field].positive?
        end
        if duck["hold_frames"] < engine["tick_frames"]
          raise ArgumentError, "cues.json: cue #{id} duck hold_frames < tick_frames (release fade would start in the past — one pending fade slot per group node)"
        end
      end
    end

    # Per-category caps: keys ARE bus names (the cue's bus is its category);
    # each cap >= 1; caps may never promise more voices than the pool holds.
    def validate_voice_pool!(pool, buses)
      caps = pool["per_category_caps"]
      return if caps.nil?
      caps.each do |cat, cap|
        raise ArgumentError, "cues.json: per_category_caps key #{cat} is not a declared bus" unless buses.key?(cat)
        raise ArgumentError, "cues.json: per_category_caps #{cat} must be an Integer >= 1" unless cap.is_a?(Integer) && cap >= 1
      end
      total = caps.values.sum
      if total > pool["max_voices"]
        raise ArgumentError, "cues.json: per_category_caps sum (#{total}) exceeds max_voices (#{pool['max_voices']})"
      end
    end

    def validate_music!(music, fixtures, engine)
      bar = bar_frames(music, engine)
      fade = music["transition"]["crossfade_frames"]
      raise ArgumentError, "music.json: crossfade_frames must be positive" unless fade.is_a?(Integer) && fade.positive?
      raise ArgumentError, "music.json: crossfade_frames (#{fade}) must fit inside a bar (#{bar})" unless fade < bar

      stems = music["stems"]
      stems.each do |id, stem|
        raise ArgumentError, "music.json: stem #{id} missing file" unless stem.key?("file")
        raise ArgumentError, "music.json: stem #{id} file #{stem['file']} not in fixtures.json" unless fixtures["tones"].key?(stem["file"])
        raise ArgumentError, "music.json: stem #{id} missing gain" unless stem.key?("gain")
      end

      states = music.fetch("states")
      raise ArgumentError, "music.json: initial_state #{music['initial_state']} not declared" unless states.key?(music["initial_state"])
      states.each do |name, st|
        stem = st.fetch("stem", :missing)
        raise ArgumentError, "music.json: state #{name} missing stem field" if stem == :missing
        next if stem.nil?
        raise ArgumentError, "music.json: state #{name} references undeclared stem #{stem}" unless stems.key?(stem)
      end
    end

    def validate_fixtures!(fixtures)
      fixtures["tones"].each do |name, t|
        raise ArgumentError, "fixtures.json: #{name} freq_hz must be positive" unless t["freq_hz"].positive?
        raise ArgumentError, "fixtures.json: #{name} dur_s must be positive" unless t["dur_s"].positive?
        raise ArgumentError, "fixtures.json: #{name} amp must be in (0,1]" unless t["amp"].positive? && t["amp"] <= 1.0
      end
    end

    def deep_freeze(obj)
      case obj
      when Hash then obj.each_value { |v| deep_freeze(v) }.freeze
      when Array then obj.each { |v| deep_freeze(v) }.freeze
      else obj.freeze
      end
    end
  end
end
