require "minitest/autorun"
require "gta/audio_system"
require "gta/fixtures"
require "gta/render"

# Production-mode allocation law: with the recorder OFF, the steady-state path
# (update + engine advance, no events) allocates zero Ruby objects per tick.
# Proof is scaling-based (spike 03 pattern, pinned fact 4: the profiler itself
# allocates, and GC.stat harness noise is a few objects) — a real 1-object/tick
# leak would add +4000 at the 5000-tick pass.
class SteadyStateAllocTest < Minitest::Test
  DATA_DIR = File.expand_path("../data/audio", __dir__)
  FIXTURES = File.expand_path("../tmp/fixtures", __dir__)
  TF = JSON.parse(File.read(File.join(DATA_DIR, "engine.json")))["tick_frames"]

  def test_update_plus_advance_allocates_zero_per_tick_with_recorder_off
    GTA::Fixtures.ensure!(File.join(DATA_DIR, "fixtures.json"), FIXTURES, sample_rate: 48_000)
    engine = GTA::Native.gta_engine_create(0, 2, 48_000)
    refute engine.null?
    audio = GTA::AudioSystem.new(engine: engine, data_dir: DATA_DIR, fixture_dir: FIXTURES, log: nil)
    renderer = GTA::Renderer.new(engine, channels: 2)

    # Steady state under load: music playing + 8 active voices. The duck
    # release (boss cue at warmup tick 90 -> release ~tick 123) and the
    # at_end voice destroys (tones end ticks ~210-240) land INSIDE the first
    # measured window — those update() paths must hold the zero-alloc law
    # too (one-off, so the 5k-scaling assert stays the arbiter).
    8.times { |i| audio.handle_event(0, "filler_blip", { distance: i / 10.0 }) }
    tick = 0
    100.times do # warmup
      audio.handle_event(tick, "boss1_spawn", nil) if tick == 90
      audio.update(tick)
      renderer.advance(TF)
      tick += 1
    end

    measure = lambda do |ticks|
      GC.start
      before = GC.stat(:total_allocated_objects)
      ticks.times do
        audio.update(tick)
        renderer.advance(TF)
        tick += 1
      end
      GC.stat(:total_allocated_objects) - before
    end

    delta_1k = measure.call(1000)
    delta_5k = measure.call(5000)

    assert delta_5k <= delta_1k, "allocations scale with ticks (#{delta_1k}@1k vs #{delta_5k}@5k) — steady-state path allocates"
    assert delta_1k < 16, "1000-tick delta #{delta_1k} exceeds harness noise floor"

    audio.destroy
    GTA::Native.gta_engine_destroy(engine)
  end
end
