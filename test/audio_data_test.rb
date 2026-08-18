require "minitest/autorun"
require "tmpdir"
require "json"
require "gta/audio_data"
require "gta/fixtures"
require "gta/wav"

# M2 grown-schema validation: the SHIPPED data files must load clean, and the
# structural constraints the code depends on must fail loudly when violated.
class AudioDataTest < Minitest::Test
  DATA_DIR = File.expand_path("../data/audio", __dir__)

  def test_shipped_data_loads_and_cross_references_resolve
    cfg = GTA::AudioData.load(DATA_DIR)
    assert_equal 800, cfg.engine["tick_frames"]
    assert_equal 96_000, GTA::AudioData.bar_frames(cfg.music, cfg.engine)
    assert cfg.events.key?("boss1_spawn")
    assert_equal "toll_paid", cfg.events["toll_paid"]
    cfg.cues.each_value { |cue| assert cfg.fixtures["tones"].key?(cue["file"]) }
    assert cfg.cues.frozen? && cfg.cues["boss1_spawn"].frozen?, "config must be frozen (load-time-only parse law)"
  end

  def test_duck_hold_floor_is_enforced
    with_patched_data("cues.json", ->(d) { d["cues"]["boss1_spawn"]["duck"]["hold_frames"] = 100 }) do |dir|
      err = assert_raises(ArgumentError) { GTA::AudioData.load(dir) }
      assert_match(/hold_frames < tick_frames/, err.message)
    end
  end

  def test_unknown_fixture_ref_is_rejected
    with_patched_data("cues.json", ->(d) { d["cues"]["toll_paid"]["file"] = "missing_tone" }) do |dir|
      assert_raises(ArgumentError) { GTA::AudioData.load(dir) }
    end
  end

  def test_duplicate_event_mapping_is_rejected
    with_patched_data("cues.json", ->(d) { d["cues"]["drone_low"]["event"] = "toll_paid" }) do |dir|
      assert_raises(ArgumentError) { GTA::AudioData.load(dir) }
    end
  end

  def test_undeclared_state_stem_is_rejected
    with_patched_data("music.json", ->(d) { d["states"]["calm"]["stem"] = "stem_zz" }) do |dir|
      assert_raises(ArgumentError) { GTA::AudioData.load(dir) }
    end
  end

  def test_crossfade_must_fit_inside_a_bar
    with_patched_data("music.json", ->(d) { d["transition"]["crossfade_frames"] = 96_000 }) do |dir|
      assert_raises(ArgumentError) { GTA::AudioData.load(dir) }
    end
  end

  def test_fixture_generation_is_deterministic_and_idempotent
    manifest = File.join(DATA_DIR, "fixtures.json")
    Dir.mktmpdir do |dir|
      GTA::Fixtures.ensure!(manifest, dir, sample_rate: 48_000)
      first = File.binread(File.join(dir, "tone_0880_200ms.wav"))
      GTA::Fixtures.ensure!(manifest, dir, sample_rate: 48_000) # idempotent
      assert_equal first, File.binread(File.join(dir, "tone_0880_200ms.wav"))
      w = GTA::Wav.read(File.join(dir, "tone_0880_200ms.wav"))
      assert_equal [1, 1, 48_000], [w[:format], w[:channels], w[:sample_rate]]
      assert_equal 9600 * 2, w[:data].bytesize # 0.2 s * 48k, PCM16 mono
    end
  end

  private

  # Copy data/audio into a tmpdir, apply one mutation to one file, yield dir.
  def with_patched_data(file, mutate)
    Dir.mktmpdir do |dir|
      Dir[File.join(DATA_DIR, "*.json")].each { |f| FileUtils.cp(f, dir) }
      doc = JSON.parse(File.read(File.join(dir, file)))
      mutate.call(doc)
      File.write(File.join(dir, file), JSON.generate(doc))
      yield dir
    end
  end
end

require "fileutils"
