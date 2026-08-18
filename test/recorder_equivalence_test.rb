require "minitest/autorun"
require "gta/audio_system"
require "gta/fixtures"
require "gta/render"

# Recorder-equivalence (integration, real DLL, no mocks): the same replay with
# the recorder ON vs OFF must render byte-identically — the log layer may never
# change engine behavior. This is what licenses the zero-alloc production mode
# to skip logging entirely.
class RecorderEquivalenceTest < Minitest::Test
  DATA_DIR = File.expand_path("../data/audio", __dir__)
  FIXTURES = File.expand_path("../tmp/fixtures", __dir__)
  TF = JSON.parse(File.read(File.join(DATA_DIR, "engine.json")))["tick_frames"]

  EVENTS = {
    2 => [["toll_paid", nil]],
    5 => [["music_set_state", { state: "combat" }]],
    10 => [["boss1_spawn", { pan: 0.25 }]],
    12 => [["drone_low", { pan: -0.5, distance: 0.4 }]]
  }.freeze
  TICKS = 60

  def render_replay(log)
    GTA::Fixtures.ensure!(File.join(DATA_DIR, "fixtures.json"), FIXTURES, sample_rate: 48_000)
    engine = GTA::Native.gta_engine_create(0, 2, 48_000)
    refute engine.null?
    audio = GTA::AudioSystem.new(engine: engine, data_dir: DATA_DIR, fixture_dir: FIXTURES, log: log)
    renderer = GTA::Renderer.new(engine, channels: 2)
    capture = String.new(capacity: TICKS * TF * 8, encoding: Encoding::BINARY)
    TICKS.times do |tick|
      (EVENTS[tick] || []).each { |name, payload| audio.handle_event(tick, name, payload) }
      audio.update(tick)
      renderer.advance(TF, capture: capture)
    end
    audio.destroy
    GTA::Native.gta_engine_destroy(engine)
    capture
  end

  def test_recorder_on_and_off_render_byte_identically
    log = GTA::CommandLog.new
    recorded = render_replay(log)
    plain = render_replay(nil)
    assert_equal recorded.bytesize, plain.bytesize
    assert recorded == plain, "recorder changed engine behavior — renders differ"
    refute_empty log.lines
    assert_equal 32, log.md5.length
  end
end
