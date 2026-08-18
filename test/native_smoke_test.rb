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

  # M2 bus-graph facts, pinned live on the rebuilt DLL (2026-08-18):
  #  - groups are started by default (miniaudio.h L77064): attaching a group to
  #    the endpoint makes the graph produce (silent) frames — the M1 empty-graph
  #    starvation no longer applies once buses exist;
  #  - gta_group_set_fade_start_pcm delegates ma_sound_set_fade_start_in_pcm_frames
  #    on the group pointer (ma_sound_group IS ma_sound, L11274) — a scheduled
  #    group fade lands sample-exact, verified through a rendered tone.
  def test_group_graph_reads_full_frames_and_scheduled_group_fade_applies
    engine = GTA::Native.gta_engine_create(0, 2, 48_000)
    refute engine.null?
    master = GTA::Native.gta_group_create(engine, FFI::Pointer::NULL)
    refute master.null?, "master group create failed: ma_result #{GTA::Native.gta_last_result}"
    sfx = GTA::Native.gta_group_create(engine, master)
    refute sfx.null?, "child group create failed: ma_result #{GTA::Native.gta_last_result}"

    buf = FFI::MemoryPointer.new(:float, 512 * 2)
    read = FFI::MemoryPointer.new(:uint64)
    result = GTA::Native.gta_engine_read_f32(engine, buf, 512, read)
    assert_equal 0, result
    assert_equal 512, read.read_uint64, "started-by-default group no longer feeds the graph — render loops starve again"
    assert_equal 0.0, buf.get_bytes(0, 512 * 2 * 4).unpack("e*").sum, "empty bus graph must render exact silence"

    Dir.mktmpdir do |dir|
      tone = File.join(dir, "tone_0440_group.wav")
      samples = (0...48_000).map { |n| (16_000 * Math.cos(2.0 * Math::PI * 440.0 * n / 48_000.0)).round }
      GTA::Wav.write_pcm16(tone, samples, channels: 1, sample_rate: 48_000)
      sound = GTA::Native.gta_sound_create_in_group(engine, tone, sfx)
      refute sound.null?, "in-group load failed: ma_result #{GTA::Native.gta_last_result}"
      GTA::Native.gta_sound_start(sound)

      # Scheduled group fade 1.0 -> 0.0 over [4096, 8192) on the PARENT group.
      GTA::Native.gta_group_set_fade_start_pcm(master, 1.0, 0.0, 4096, 4096)
      total = 12_288
      out = String.new(capacity: total * 8, encoding: Encoding::BINARY)
      (total / 512).times do
        GTA::Native.gta_engine_read_f32(engine, buf, 512, read)
        assert_equal 512, read.read_uint64
        out << buf.get_bytes(0, 512 * 2 * 4)
      end
      s = out.unpack("e*")
      pre  = Math.sqrt((0...2048).sum { |f| s[f * 2]**2 } / 2048.0)
      post = Math.sqrt((8192...12_288).sum { |f| s[f * 2]**2 } / 4096.0)
      assert_operator pre, :>, 0.2, "tone inaudible before the scheduled group fade"
      assert_equal 0.0, post, "group fade to zero must silence the bus exactly"
      GTA::Native.gta_sound_destroy(sound)
    end

    GTA::Native.gta_group_destroy(sfx)
    GTA::Native.gta_group_destroy(master)
    GTA::Native.gta_engine_destroy(engine)
  end
end

require "tmpdir"
