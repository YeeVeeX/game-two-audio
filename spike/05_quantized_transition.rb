# M1 spike 05 — ADR 0001 falsification item 5: schedule-ahead quantized
# transition lands on the computed PCM frame (fade midpoint within ±1 frame).
#
# Timing comes from data/audio/music.json (120 bpm, 4/4 -> bar = 2.0 s =
# 96_000 frames @48k). The transition is scheduled at bar 2 (frame 192_000):
# stem_a fades 1->0, stem_b starts + fades 0->1 (crossfade_frames long), all
# via absolute-engine-clock schedule-ahead calls issued ~one bar EARLY. No
# polling loop adjusts anything afterwards — the landing precision IS the test.
#
# Measurement: stem_a hard-left, stem_b hard-right (ma_pan_mode_balance puts
# zero bleed in the opposite channel — verified against reference renders).
# Per-frame fade gain is extracted by dividing the crossfade render by
# unfaded reference renders (all renders deterministic — spike 01), then a
# least-squares line fit locates the fade start/midpoint at sub-frame
# precision. PASS: |fitted midpoint - (boundary + L/2)| <= 1 frame, both stems.

require_relative "support/common"

Spike.banner("05 quantized transition (schedule-ahead)")

MUSIC = JSON.parse(File.read(File.join(Spike::DATA, "music.json")))
BPM = MUSIC["timing"]["bpm"]
BEATS = MUSIC["timing"]["beats_per_bar"]
FADE = MUSIC["transition"]["crossfade_frames"]
BAR_FRAMES = (Spike::SR * 60.0 / BPM * BEATS).round # 96_000
BOUNDARY = 2 * BAR_FRAMES                           # 192_000
RENDER_FRAMES = 3 * BAR_FRAMES                      # 288_000
CHUNK = 480

Spike.fail!("bar length not integral") unless (Spike::SR * 60 * BEATS) % BPM == 0

stem_a_tone = Spike.tone_fixture("stem_0400_6s", freq: MUSIC["stems"]["stem_a"]["freq_hz"], dur_s: 6.0, amp: 0.5)
stem_b_tone = Spike.tone_fixture("stem_1000_6s", freq: MUSIC["stems"]["stem_b"]["freq_hz"], dur_s: 6.0, amp: 0.5, phase: 0.25)

n = Spike::N

# One deterministic render of a command program (fresh engine per render).
render = lambda do |commands|
  e = Spike.make_engine
  sa = Spike.load_sound(e, stem_a_tone)
  sb = Spike.load_sound(e, stem_b_tone)
  n.gta_sound_set_pan(sa, -1.0) # stem_a -> left only (balance mode)
  n.gta_sound_set_pan(sb, 1.0)  # stem_b -> right only
  commands.call(sa, sb)
  bytes = Spike.render_f32(e, RENDER_FRAMES, chunk: CHUNK)
  n.gta_sound_destroy(sa)
  n.gta_sound_destroy(sb)
  n.gta_engine_destroy(e)
  bytes.unpack("e*")
end

# R1: the real transition, fully scheduled ahead at t=0 (one bar early).
r1 = render.call(lambda do |sa, sb|
  n.gta_sound_start(sa)
  n.gta_sound_set_fade_start_pcm(sa, -1.0, 0.0, FADE, BOUNDARY)
  n.gta_sound_set_stop_time_pcm(sa, BOUNDARY + FADE)
  n.gta_sound_set_start_time_pcm(sb, BOUNDARY)
  n.gta_sound_set_fade_start_pcm(sb, 0.0, 1.0, FADE, BOUNDARY)
  n.gta_sound_start(sb)
end)

# R2: stem_a alone, no fade (left-channel gain reference).
r2 = render.call(lambda do |sa, _sb|
  n.gta_sound_start(sa)
end)

# R3: stem_b alone, started at the boundary, no fade (right-channel reference).
r3 = render.call(lambda do |_sa, sb|
  n.gta_sound_set_start_time_pcm(sb, BOUNDARY)
  n.gta_sound_start(sb)
end)

GTA::Wav.write_f32(File.join(Spike::TMP, "spike05_transition.wav"), r1.pack("e*"), channels: Spike::CHANNELS, sample_rate: Spike::SR)
puts "  artifact: tmp/spike05_transition.wav sha256=#{Digest::SHA256.hexdigest(r1.pack('e*'))[0, 16]}…"

# Channel-isolation sanity: hard pans must leave the opposite channel at 0.
bleed_a = Spike.rms(r2, BOUNDARY - 24_000, 4_800, ch: 1)
bleed_b = Spike.rms(r3, BOUNDARY + 24_000, 4_800, ch: 0)
Spike.check(bleed_a < 1e-9, "pan -1 leaves right channel silent (bleed rms #{bleed_a})")
Spike.check(bleed_b < 1e-9, "pan +1 leaves left channel silent (bleed rms #{bleed_b})")

# First audible frame of stem_b in R1 (phase 0.25 tone => nonzero sample 0;
# fade gain 0 at the boundary frame itself may zero frame 0).
first_b = (BOUNDARY - 480...BOUNDARY + 480).find { |f| r1[f * 2 + 1].abs > 1e-9 }
puts "  stem_b first nonzero frame: #{first_b} (boundary #{BOUNDARY})"
Spike.check(!first_b.nil? && (first_b - BOUNDARY).abs <= 1, "stem_b enters at the boundary ±1 (offset #{first_b ? first_b - BOUNDARY : 'none'})")

# Extract per-frame fade gains by division against references; fit lines.
fit_gain = lambda do |mix, ref, ch, from, to|
  xs = []
  ys = []
  (from...to).each do |f|
    denom = ref[f * 2 + ch]
    next if denom.abs < 0.05 # skip near-zero carrier samples
    xs << f.to_f
    ys << mix[f * 2 + ch] / denom
  end
  Spike.fail!("gain fit starved (#{xs.size} points)") if xs.size < FADE / 4
  Spike.linear_fit(xs, ys)
end

margin = 480
slope_out, icpt_out = fit_gain.call(r1, r2, 0, BOUNDARY + margin, BOUNDARY + FADE - margin)
slope_in,  icpt_in  = fit_gain.call(r1, r3, 1, BOUNDARY + margin, BOUNDARY + FADE - margin)

mid_out = (0.5 - icpt_out) / slope_out
mid_in  = (0.5 - icpt_in) / slope_in
expected_mid = BOUNDARY + FADE / 2.0

puts "  fade-out fit: slope=#{slope_out.round(10)} (expect #{(-1.0 / FADE).round(10)}) midpoint=#{mid_out.round(3)}"
puts "  fade-in  fit: slope=#{slope_in.round(10)} (expect #{(1.0 / FADE).round(10)}) midpoint=#{mid_in.round(3)}"
puts "  expected midpoint: #{expected_mid} (boundary #{BOUNDARY} + fade #{FADE}/2)"
puts "  offsets: out=#{(mid_out - expected_mid).round(3)} frames, in=#{(mid_in - expected_mid).round(3)} frames"

Spike.check((mid_out - expected_mid).abs <= 1.0, "fade-out midpoint within ±1 frame (offset #{(mid_out - expected_mid).round(3)})")
Spike.check((mid_in - expected_mid).abs <= 1.0, "fade-in midpoint within ±1 frame (offset #{(mid_in - expected_mid).round(3)})")

# Post-transition state: stem_a silent (stopped at boundary+FADE), stem_b at full level.
tail_a = Spike.rms(r1, BOUNDARY + FADE + 4_800, 4_800, ch: 0)
tail_b = Spike.goertzel_amp(r1, MUSIC["stems"]["stem_b"]["freq_hz"], BOUNDARY + FADE + 4_800, 4_800, ch: 1)
puts "  post-transition: stem_a rms=#{tail_a} stem_b amp=#{tail_b.round(4)}"
Spike.check(tail_a < 1e-9, "stem_a fully stopped after fade")
Spike.check(tail_b > 0.4, "stem_b at full level after fade")

Spike.pass!("quantized transition landed: midpoint offsets out=#{(mid_out - expected_mid).round(3)}, in=#{(mid_in - expected_mid).round(3)} frames (bound ±1)")
