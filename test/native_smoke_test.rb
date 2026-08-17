require "minitest/autorun"

# Real-DLL integration smoke (no mocks — AGENTS law 5): binding loads the pinned
# vendor DLL, version matches vendor/VERSION, offline engine + full-decode load work.
require "gta/native"
require "gta/wav"

class NativeSmokeTest < Minitest::Test
  VERSION_FILE = File.read(File.expand_path("../vendor/VERSION", __dir__))

  def test_dll_version_matches_vendor_pin
    tag = VERSION_FILE[/release tag: (\S+)/, 1]
    assert_equal tag, GTA::Native.gta_version, "DLL miniaudio version != vendor/VERSION pin"
  end

  def test_offline_engine_lifecycle_and_full_decode_load
    engine = GTA::Native.gta_engine_create(0, 2, 48_000)
    refute engine.null?, "engine create failed: ma_result #{GTA::Native.gta_last_result}"
    assert_equal 48_000, GTA::Native.gta_engine_sample_rate(engine)
    assert_equal 2, GTA::Native.gta_engine_channels(engine)
    assert_equal 0, GTA::Native.gta_engine_time_pcm(engine)

    Dir.mktmpdir do |dir|
      tone = File.join(dir, "tone_440_smoke.wav")
      samples = (0...4800).map { |n| (0.5 * 32_767 * Math.sin(2.0 * Math::PI * 440.0 * n / 48_000.0)).round }
      GTA::Wav.write_pcm16(tone, samples, channels: 1, sample_rate: 48_000)

      sound = GTA::Native.gta_sound_create(engine, tone)
      refute sound.null?, "sound load failed: ma_result #{GTA::Native.gta_last_result}"
      assert_equal 0, GTA::Native.gta_sound_at_end(sound)
      GTA::Native.gta_sound_destroy(sound)
    end
    GTA::Native.gta_engine_destroy(engine)
  end

  def test_offline_read_advances_engine_clock
    engine = GTA::Native.gta_engine_create(0, 2, 48_000)
    refute engine.null?
    buf = FFI::MemoryPointer.new(:float, 512 * 2)
    read = FFI::MemoryPointer.new(:uint64)

    # Pinned miniaudio semantic (probed 2026-08-17): an EMPTY node graph reads 0
    # frames and does NOT advance the clock — render loops must attach sounds first.
    result = GTA::Native.gta_engine_read_f32(engine, buf, 512, read)
    assert_equal 0, result
    assert_equal 0, read.read_uint64, "empty-graph read semantics changed — re-verify render harness"

    Dir.mktmpdir do |dir|
      tone = File.join(dir, "tone_440_clock.wav")
      samples = (0...4800).map { |n| (16_000 * Math.sin(2.0 * Math::PI * 440.0 * n / 48_000.0)).round }
      GTA::Wav.write_pcm16(tone, samples, channels: 1, sample_rate: 48_000)
      sound = GTA::Native.gta_sound_create(engine, tone)
      refute sound.null?
      GTA::Native.gta_sound_start(sound)

      result = GTA::Native.gta_engine_read_f32(engine, buf, 512, read)
      assert_equal 0, result, "ma_engine_read_pcm_frames failed: #{result}"
      assert_equal 512, read.read_uint64
      assert_equal 512, GTA::Native.gta_engine_time_pcm(engine)
      GTA::Native.gta_sound_destroy(sound)
    end
    GTA::Native.gta_engine_destroy(engine)
  end
end

require "tmpdir"
