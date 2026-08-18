# M1 spike 04 — ADR 0001 falsification item 4: voice pool + steal policy,
# assertable in the rendered WAV.
#
# 64 voices fill the pool (victim voice at 500 Hz with the unique LOWEST
# priority). At exactly frame 48_000 a 65th, higher-priority cue (1500 Hz)
# arrives: the pool must steal the victim's slot. Proof lives in the render:
# Goertzel amplitude at 500 Hz collapses after the steal, 1500 Hz appears at
# it, bystander voices continue, and concurrency never exceeds max_voices.
#
# Pool config (max_voices, steal_order) comes from data/audio/cues.json —
# data-driven law; the pool itself is pure Ruby (src/gta/voice_pool.rb).

require_relative "support/common"
require "gta/voice_pool"

Spike.banner("04 voice pool steal policy")

POOL_CFG = JSON.parse(File.read(File.join(Spike::DATA, "cues.json")))["voice_pool"]
MAX = POOL_CFG["max_voices"]
STEAL_FRAME = 48_000
RENDER_FRAMES = 120_000
WIN = 4_800 # Goertzel window: 10 Hz bins — all fixture freqs are multiples of 10

Spike.fail!("cues.json max_voices != 64 (got #{MAX})") unless MAX == 64

e = Spike.make_engine
n = Spike::N
pool = GTA::VoicePool.new(max_voices: MAX, steal_order: POOL_CFG["steal_order"])

victim_tone  = Spike.tone_fixture("tone_0500_4s", freq: 500.0, dur_s: 4.0, amp: 0.30)
stealer_tone = Spike.tone_fixture("tone_1500_2s", freq: 1500.0, dur_s: 2.0, amp: 0.30, phase: 0.25)
other_tones = 8.times.map do |i|
  Spike.tone_fixture("tone_#{2000 + i * 100}_4s", freq: (2000 + i * 100).to_f, dur_s: 4.0, amp: 0.02)
end

slot_sounds = Array.new(MAX)

# Fill all 64 slots. Slot 7 = victim (priority 10); all others priority 50.
MAX.times do |i|
  victim = i == 7
  res = pool.acquire(priority: victim ? 10 : 50, distance: victim ? 0.9 : 0.1 + (i % 7) * 0.1)
  Spike.fail!("unexpected steal while filling (slot #{i})") unless res && res[:stolen].nil?
  s = Spike.load_sound(e, victim ? victim_tone : other_tones[i % 8])
  n.gta_sound_set_pan(s, -0.8 + 1.6 * (i % 9) / 8.0)
  n.gta_sound_start(s)
  slot_sounds[res[:slot]] = s
end
Spike.check(pool.active_count == MAX, "pool filled to #{MAX} active voices")

playing = -> { slot_sounds.count { |s| n.gta_sound_is_playing(s) == 1 } }

# Render to the steal point, issue the steal, render the rest.
part1 = Spike.render_f32(e, STEAL_FRAME, chunk: 480)
count_before = playing.call
Spike.check(n.gta_engine_time_pcm(e) == STEAL_FRAME, "engine clock at steal point (#{STEAL_FRAME})")

res = pool.acquire(priority: 90, distance: 0.0)
Spike.fail!("pool refused the priority-90 steal") if res.nil?
Spike.check(res[:slot] == 7, "steal chain picked the lowest-priority victim (slot 7, got #{res[:slot]})")
Spike.check(res[:stolen][:priority] == 10, "victim priority 10 (got #{res[:stolen][:priority]})")

n.gta_sound_stop(slot_sounds[res[:slot]])          # execute the steal
n.gta_sound_destroy(slot_sounds[res[:slot]])
stealer = Spike.load_sound(e, stealer_tone)
n.gta_sound_set_pan(stealer, 0.0)
n.gta_sound_start(stealer)
slot_sounds[res[:slot]] = stealer

part2 = Spike.render_f32(e, RENDER_FRAMES - STEAL_FRAME, chunk: 480)
count_after = playing.call

bytes = part1 + part2
GTA::Wav.write_f32(File.join(Spike::TMP, "spike04_steal.wav"), bytes, channels: Spike::CHANNELS, sample_rate: Spike::SR)
puts "  artifact: tmp/spike04_steal.wav sha256=#{Digest::SHA256.hexdigest(bytes)[0, 16]}…"

samples = bytes.unpack("e*")
amp = ->(freq, from) { Spike.goertzel_amp(samples, freq, from, WIN) + Spike.goertzel_amp(samples, freq, from, WIN, ch: 1) }

v_before = amp.call(500.0, STEAL_FRAME - WIN)
v_after  = amp.call(500.0, STEAL_FRAME + 960)
s_before = amp.call(1500.0, STEAL_FRAME - WIN)
s_after  = amp.call(1500.0, STEAL_FRAME + 960)
b_before = amp.call(2300.0, STEAL_FRAME - WIN)
b_after  = amp.call(2300.0, STEAL_FRAME + 960)

puts "  goertzel amp   500 Hz: before=#{v_before.round(4)} after=#{v_after.round(6)}"
puts "  goertzel amp  1500 Hz: before=#{s_before.round(6)} after=#{s_after.round(4)}"
puts "  goertzel amp  2300 Hz: before=#{b_before.round(4)} after=#{b_after.round(4)}"
puts "  concurrent voices: before=#{count_before} after=#{count_after} (max #{MAX})"

Spike.check(count_before == MAX, "64 voices playing concurrently before steal")
Spike.check(count_after == MAX, "still exactly 64 playing after steal (stolen slot reused)")
Spike.check(v_before > 0.1, "victim (500 Hz) audible before steal")
Spike.check(v_after < v_before / 100.0, "victim (500 Hz) cut by steal (#{(v_before / [v_after, 1e-12].max).round} : 1 collapse)")
Spike.check(s_before < 0.01, "stealer (1500 Hz) absent before steal")
Spike.check(s_after > 0.1, "stealer (1500 Hz) audible after steal")
Spike.check(b_after > b_before * 0.5, "bystander voice (2300 Hz) survived the steal")

slot_sounds.each { |s| n.gta_sound_destroy(s) }
n.gta_engine_destroy(e)

Spike.pass!("steal policy audible in WAV: 500 Hz #{v_before.round(3)}->#{v_after.round(6)}, 1500 Hz #{s_before.round(6)}->#{s_after.round(3)} at frame #{STEAL_FRAME}")
