# M1 spike 01 — ADR 0001 falsification item 1: offline render determinism.
#
# init -> load tones (full decode, jobThreadCount=0, NO_THREADING) -> schedule
# starts/stops/pans/volumes/fades -> noDevice render -> twice, fresh engine each
# time -> byte-identical on this machine. Any relaxation of the preconditions
# invalidates this item (AGENTS law).
#
# Exit 0 = PASS, nonzero = FAIL.

require_relative "support/common"

Spike.banner("01 offline render determinism")

RENDER_FRAMES = (3.0 * Spike::SR).to_i # 144_000 — s3 (2s @ frame 24k) ends at 120k
CHUNK = 512

def build_and_render
  e = Spike.make_engine
  t440 = Spike.tone_fixture("tone_0440_1s", freq: 440.0, dur_s: 1.0)
  t880 = Spike.tone_fixture("tone_0880_hs", freq: 880.0, dur_s: 0.5, amp: 0.4)
  t220 = Spike.tone_fixture("tone_0220_2s", freq: 220.0, dur_s: 2.0, amp: 0.6)

  s1 = Spike.load_sound(e, t440)
  s2 = Spike.load_sound(e, t880)
  s3 = Spike.load_sound(e, t220)

  n = Spike::N
  # Command program exercising the whole spike surface (absolute PCM frames):
  n.gta_sound_set_volume(s1, 0.8)
  n.gta_sound_set_pan(s1, -0.7)
  n.gta_sound_set_start_time_pcm(s1, 0)
  n.gta_sound_set_stop_time_with_fade_pcm(s1, 48_000, 12_000) # fade out over [36k,48k]
  n.gta_sound_start(s1)

  n.gta_sound_set_volume(s2, 0.6)
  n.gta_sound_set_pan(s2, 0.5)
  n.gta_sound_set_start_time_pcm(s2, 12_000)
  n.gta_sound_start(s2)

  n.gta_sound_set_volume(s3, 1.0)
  n.gta_sound_set_fade_start_pcm(s3, 0.0, 1.0, 24_000, 24_000) # fade in over [24k,48k]
  n.gta_sound_set_start_time_pcm(s3, 24_000)
  n.gta_sound_start(s3)

  bytes = Spike.render_f32(e, RENDER_FRAMES, chunk: CHUNK)

  [s1, s2, s3].each { |s| n.gta_sound_destroy(s) }
  n.gta_engine_destroy(e)
  bytes
end

a = build_and_render
b = build_and_render

sha_a = Digest::SHA256.hexdigest(a)
sha_b = Digest::SHA256.hexdigest(b)
md5_a = Digest::MD5.hexdigest(a)
md5_b = Digest::MD5.hexdigest(b)

GTA::Wav.write_f32(File.join(Spike::TMP, "spike01_render_a.wav"), a, channels: Spike::CHANNELS, sample_rate: Spike::SR)
GTA::Wav.write_f32(File.join(Spike::TMP, "spike01_render_b.wav"), b, channels: Spike::CHANNELS, sample_rate: Spike::SR)

puts "  render A: #{a.bytesize} bytes  sha256=#{sha_a}  md5=#{md5_a}"
puts "  render B: #{b.bytesize} bytes  sha256=#{sha_b}  md5=#{md5_b}"

Spike.check(a.bytesize == RENDER_FRAMES * Spike::CHANNELS * 4, "render length = #{RENDER_FRAMES} frames")

# Guard against a false pass from two identical SILENT renders: assert content.
samples = a.unpack("e*")
rms_early = Spike.rms(samples, 6_000, 4_800)   # s1 region
rms_mid   = Spike.rms(samples, 30_000, 4_800)  # s1+s2+s3 overlap region
rms_tail  = Spike.rms(samples, 130_000, 4_800) # after everything ended (s3 ends at 120k)
puts "  rms early=#{rms_early.round(5)} mid=#{rms_mid.round(5)} tail=#{rms_tail.round(6)}"
Spike.check(rms_early > 0.05, "render is not silent in s1 region (rms #{rms_early.round(4)} > 0.05)")
Spike.check(rms_mid > 0.05, "render is not silent in overlap region (rms #{rms_mid.round(4)} > 0.05)")
Spike.check(rms_tail < 1e-6, "tail after all stops is silent (rms #{rms_tail.round(8)} < 1e-6)")

if a == b
  Spike.pass!("double noDevice render byte-identical (#{a.bytesize} bytes, sha256 #{sha_a[0, 16]}…)")
else
  first_diff = (0...[a.bytesize, b.bytesize].min).find { |i| a.getbyte(i) != b.getbyte(i) }
  Spike.fail!("renders differ (first differing byte at #{first_diff.inspect}, frame #{first_diff ? first_diff / (Spike::CHANNELS * 4) : 'n/a'})")
end
