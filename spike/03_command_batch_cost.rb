# M1 spike 03 — ADR 0001 falsification item 3: worst-case tick command batch.
#
# 64 voices, EVERY tick, EVERY voice: volume + pan + fade + schedule-ahead
# (start-time or stop-with-fade, alternating) + start re-arm = 5 FFI calls
# per voice = 320 calls/tick. Two identical steady-state passes after warmup:
#   pass A (timing): p95 over 1000 ticks, clock_gettime around each batch.
#   pass B (allocation): SAME command stream, zero instrumentation in the loop
#     — probed 2026-08-17: Process.clock_gettime(:nanosecond) itself allocates
#     ~1 object/call on x64-mingw-ucrt, so the profiler must stay out of the
#     allocation assertion. Measurement floor: even an EMPTY while loop shows
#     ~1-4 objects (GC.stat harness noise), so zero-per-tick is proven by
#     SCALING: delta at 5000 ticks must not exceed delta at 1000 ticks (a real
#     1-object/tick leak would add +4000).
# PASS: p95 < 0.5 ms AND allocation delta does not scale with tick count.
#
# The 0.5 ms bound is the AUDIO-side command budget (ADR), not game-two's
# 16.6 ms tick law. Engine advance (read) is pumped between ticks OUTSIDE the
# timed region — in production that work lives on the device's audio thread.

require_relative "support/common"

Spike.banner("03 command batch cost (64 voices)")

VOICES = 64
WARMUP_TICKS = 100
MEASURE_TICKS = 1000
TICK_FRAMES = 800 # 48000 / 60
LUT_SIZE = 4096

e = Spike.make_engine
tones = [
  Spike.tone_fixture("tone_0330_1s", freq: 330.0, dur_s: 1.0, amp: 0.10),
  Spike.tone_fixture("tone_0550_1s", freq: 550.0, dur_s: 1.0, amp: 0.10),
  Spike.tone_fixture("tone_0660_1s", freq: 660.0, dur_s: 1.0, amp: 0.10),
  Spike.tone_fixture("tone_0770_1s", freq: 770.0, dur_s: 1.0, amp: 0.10)
]
n = Spike::N
sounds = Array.new(VOICES) { |i| Spike.load_sound(e, tones[i % tones.size]) }
sounds.each do |s|
  n.gta_sound_set_looping(s, 1)
  n.gta_sound_start(s)
end

# Preallocate EVERYTHING the steady-state loop touches (per-tick alloc law).
vol_lut = Array.new(LUT_SIZE) { |i| 0.05 + 0.9 * (i % 97) / 97.0 }
pan_lut = Array.new(LUT_SIZE) { |i| -1.0 + 2.0 * (i % 89) / 89.0 }
times_ns = Array.new(MEASURE_TICKS, 0)
adv_buf = FFI::MemoryPointer.new(:float, TICK_FRAMES * Spike::CHANNELS)
adv_read = FFI::MemoryPointer.new(:uint64)

run_tick = lambda do |tick|
  now = n.gta_engine_time_pcm(e)
  v = 0
  while v < VOICES
    s = sounds[v]
    idx = (tick + v) & (LUT_SIZE - 1)
    n.gta_sound_set_volume(s, vol_lut[idx])
    n.gta_sound_set_pan(s, pan_lut[idx])
    n.gta_sound_set_fade_pcm(s, -1.0, vol_lut[idx], 480)
    if ((tick + v) & 1).zero?
      n.gta_sound_set_start_time_pcm(s, now + 1600)
    else
      n.gta_sound_set_stop_time_with_fade_pcm(s, now + 2400, 480)
    end
    n.gta_sound_start(s)
    v += 1
  end
end

advance = lambda do
  n.gta_engine_read_f32(e, adv_buf, TICK_FRAMES, adv_read)
end

WARMUP_TICKS.times do |t|
  run_tick.call(t)
  advance.call
end

# Pass A — timing (instrumented).
t = 0
while t < MEASURE_TICKS
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
  run_tick.call(t)
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
  times_ns[t] = t1 - t0
  advance.call
  t += 1
end

# Pass B — allocation (identical command stream, no instrumentation inside).
# Two scales; a per-tick leak scales, fixed harness overhead does not.
alloc_pass = lambda do |ticks|
  GC.start
  before = GC.stat(:total_allocated_objects)
  t = 0
  while t < ticks
    run_tick.call(t)
    advance.call
    t += 1
  end
  GC.stat(:total_allocated_objects) - before
end
gc_count_before = GC.count
alloc_1k = alloc_pass.call(1000)
alloc_5k = alloc_pass.call(5000)
gc_runs = GC.count - gc_count_before

sorted = times_ns.sort
p50 = sorted[MEASURE_TICKS / 2] / 1_000_000.0
p95 = sorted[(MEASURE_TICKS * 95) / 100] / 1_000_000.0
p99 = sorted[(MEASURE_TICKS * 99) / 100] / 1_000_000.0
pmax = sorted[-1] / 1_000_000.0

puts "  ticks=#{MEASURE_TICKS} calls/tick=#{VOICES * 5} (vol+pan+fade+sched+start per voice)"
puts "  batch ms: p50=#{p50.round(4)} p95=#{p95.round(4)} p99=#{p99.round(4)} max=#{pmax.round(4)}"
puts "  GC (uninstrumented passes): delta@1000=#{alloc_1k} delta@5000=#{alloc_5k} gc_runs=#{gc_runs}"

Spike.check(p95 < 0.5, "p95 #{p95.round(4)} ms < 0.5 ms (ADR bound)")
Spike.check(alloc_5k <= alloc_1k, "allocations do not scale with ticks (5000-tick delta #{alloc_5k} <= 1000-tick delta #{alloc_1k} => 0/tick)")
Spike.check(alloc_1k < 16, "1000-tick delta #{alloc_1k} within harness noise floor (< 16 objects)")

sounds.each { |s| n.gta_sound_destroy(s) }
n.gta_engine_destroy(e)

Spike.pass!("64-voice worst-case batch p95=#{p95.round(4)} ms, per-tick allocations=0 (#{alloc_1k}@1k vs #{alloc_5k}@5k)")
