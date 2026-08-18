require "minitest/autorun"
require "gta/audio_data"
require "gta/fixtures"

# LISTEN-track mirror law (M4): data/audio_listen renders the SAME choreography
# as data/audio — only the audio material (fixture file refs) differs. If this
# drifts, the owner's ears would be scoring behaviors the gate corpus doesn't
# ship (stop-the-line). Pinned here mechanically:
#  - both dirs load + validate through AudioData (file refs resolve);
#  - engine timebase equal; buses + voice_pool equal (the -10 dB sfx staging
#    IS the balance question under listen — it must not silently diverge);
#  - every cue equal except "file"; music equal except stem file/freq_hz;
#  - mapped fixture durations equal (steal/duck/transition timing rides on
#    cue durations).
class ListenTrackTest < Minitest::Test
  GATE_DIR = File.expand_path("../data/audio", __dir__)
  LISTEN_DIR = File.expand_path("../data/audio_listen", __dir__)

  def setup
    @gate = GTA::AudioData.load(GATE_DIR)
    @listen = GTA::AudioData.load(LISTEN_DIR)
  end

  def test_engine_timebase_identical
    %w[sample_rate channels tick_frames].each do |k|
      assert_equal @gate.engine[k], @listen.engine[k], "engine.#{k} diverged"
    end
  end

  def test_buses_and_voice_pool_identical
    assert_equal @gate.buses, @listen.buses
    assert_equal @gate.voice_pool, @listen.voice_pool
  end

  def test_cues_identical_except_file
    assert_equal @gate.cues.keys.sort, @listen.cues.keys.sort
    @gate.cues.each do |id, gate_cue|
      listen_cue = @listen.cues[id]
      assert_equal gate_cue.except("file"), listen_cue.except("file"),
                   "cue #{id} diverged beyond the file ref"
      refute_equal gate_cue["file"], listen_cue["file"],
                   "cue #{id} still points at the sine fixture"
    end
  end

  def test_music_identical_except_stem_material
    %w[timing transition initial_state states].each do |k|
      assert_equal @gate.music[k], @listen.music[k], "music.#{k} diverged"
    end
    assert_equal @gate.music["stems"].keys.sort, @listen.music["stems"].keys.sort
    @gate.music["stems"].each do |id, gate_stem|
      listen_stem = @listen.music["stems"][id]
      assert_equal gate_stem.except("file", "freq_hz"), listen_stem.except("file", "freq_hz"),
                   "stem #{id} diverged beyond material fields"
    end
  end

  def test_mapped_fixture_durations_equal
    pairs = @gate.cues.map { |id, c| [id, c["file"], @listen.cues[id]["file"]] }
    pairs += @gate.music["stems"].map { |id, s| [id, s["file"], @listen.music["stems"][id]["file"]] }
    pairs.each do |label, gate_file, listen_file|
      gd = @gate.fixtures["tones"].fetch(gate_file).fetch("dur_s")
      ld = @listen.fixtures["tones"].fetch(listen_file).fetch("dur_s")
      assert_in_delta gd, ld, 1e-9, "#{label}: fixture duration diverged (#{gate_file} vs #{listen_file})"
    end
  end

  def test_listen_fixtures_are_notes_type
    @listen.fixtures["tones"].each do |name, spec|
      assert_equal "notes", spec["type"], "listen fixture #{name} is not musical synthesis"
    end
  end
end
