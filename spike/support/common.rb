# spike/support/common.rb — shared helpers for M1 falsification scripts.
# Not matched by the rake spike glob (spike/[0-9]*_*.rb).

$LOAD_PATH.unshift File.expand_path("../../src", __dir__) unless $LOAD_PATH.include?(File.expand_path("../../src", __dir__))

require "gta/native"
require "gta/wav"
require "gta/analysis"
require "digest"
require "fileutils"
require "json"

module Spike
  N = GTA::Native
  SR = 48_000
  CHANNELS = 2
  TMP = File.expand_path("../../tmp", __dir__)
  FIXTURES = File.join(TMP, "fixtures")
  DATA = File.expand_path("../../data/audio", __dir__)

  module_function

  def banner(name)
    puts "== M1 spike: #{name} =="
    puts "   miniaudio #{N.gta_version} | #{RUBY_DESCRIPTION}"
    FileUtils.mkdir_p(FIXTURES)
  end

  def pass!(msg)
    puts "PASS: #{msg}"
    exit 0
  end

  def fail!(msg)
    puts "FAIL: #{msg}"
    exit 1
  end

  def check(cond, msg)
    fail!(msg) unless cond
    puts "  ok: #{msg}"
  end

  # Deterministic PCM16 mono sine fixture. phase in cycles (0.25 => cosine,
  # so sample 0 is nonzero — needed by first-nonzero-frame assertions).
  def tone_fixture(name, freq:, dur_s:, amp: 0.5, phase: 0.0, sr: SR)
    path = File.join(FIXTURES, "#{name}.wav")
    return path if File.exist?(path)
    n = (dur_s * sr).round
    samples = Array.new(n) { |i| (amp * 32_767 * Math.sin(2.0 * Math::PI * (freq * i / sr.to_f + phase))).round }
    GTA::Wav.write_pcm16(path, samples, channels: 1, sample_rate: sr)
    path
  end

  def make_engine(use_device: 0, channels: CHANNELS, sr: SR)
    e = N.gta_engine_create(use_device, channels, sr)
    fail!("engine create failed: ma_result #{N.gta_last_result}") if e.null?
    e
  end

  def load_sound(engine, path)
    s = N.gta_sound_create(engine, path)
    fail!("sound load failed (#{path}): ma_result #{N.gta_last_result}") if s.null?
    s
  end

  # Offline render: fixed chunk cadence, returns interleaved f32 binary String.
  # The same read pattern is used for every render (same-machine gate contract).
  def render_f32(engine, total_frames, chunk: 512, channels: CHANNELS)
    buf = FFI::MemoryPointer.new(:float, chunk * channels)
    read = FFI::MemoryPointer.new(:uint64)
    out = String.new(capacity: total_frames * channels * 4, encoding: Encoding::BINARY)
    remaining = total_frames
    while remaining > 0
      n = remaining < chunk ? remaining : chunk
      result = N.gta_engine_read_f32(engine, buf, n, read)
      fail!("engine read failed: ma_result #{result}") unless result.zero?
      got = read.read_uint64
      fail!("engine read returned #{got}/#{n} frames — graph starved (no attached sounds?)") if got != n
      out << buf.get_bytes(0, n * channels * 4)
      remaining -= n
    end
    out
  end

  # samples: interleaved Float array; window in FRAMES over channel ch.
  # Delegates to GTA::Analysis (promoted there in M2; same arithmetic).
  def rms(samples, from_frame, frames, channels: CHANNELS, ch: nil)
    GTA::Analysis.rms(samples, from_frame, frames, channels: channels, ch: ch)
  end

  # Goertzel single-bin amplitude of freq over [from_frame, from_frame+frames) on channel ch.
  # Returns sine peak amplitude estimate (2*|X|/N).
  def goertzel_amp(samples, freq, from_frame, frames, channels: CHANNELS, ch: 0, sr: SR)
    GTA::Analysis.goertzel_amp(samples, freq, from_frame, frames, channels: channels, ch: ch, sr: sr)
  end

  # Least-squares line fit: ys over xs => [slope, intercept]
  def linear_fit(xs, ys)
    GTA::Analysis.linear_fit(xs, ys)
  end
end
