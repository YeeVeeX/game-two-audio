require "minitest/autorun"
require "json"
require "digest"
require "tmpdir"
require "stringio"
require "gta/wav"
require_relative "../harness/import_stems"

# Inbox importer (M4b owner production loop): every conversion and refusal
# path exercised on REAL WAV bytes in a tmpdir — no mocks. The importer is
# the seam between the owner's Reaper renders and the sha-pinned fixture
# manifest, so wrong-accepts here would corrupt the listen track silently.
class StemImportTest < Minitest::Test
  SR = 48_000
  SLOT_A_FRAMES = 480 # dur_s 0.01
  SLOT_B_FRAMES = 240 # dur_s 0.005

  def setup
    @dir = Dir.mktmpdir("stem_import")
    @inbox = File.join(@dir, "inbox")
    FileUtils.mkdir_p(@inbox)
    File.write(File.join(@dir, "engine.json"),
               JSON.generate("sample_rate" => SR, "channels" => 2, "tick_frames" => 800))
    File.write(File.join(@dir, "import.json"), JSON.generate(
                 "pad_tolerance_s" => 0.001,   # 48 frames
                 "trim_tolerance_s" => 0.002,  # 96 frames
                 "silence_floor" => 0.001,
                 "bands" => { "slot_a" => "test band prose" }
               ))
    @manifest_path = File.join(@dir, "fixtures.json")
    File.write(@manifest_path, JSON.generate(
                 "_comment" => "test manifest",
                 "tones" => {
                   "slot_a" => { "type" => "notes", "dur_s" => SLOT_A_FRAMES / SR.to_f,
                                 "_what" => "slot_a placeholder", "notes" => [] },
                   "slot_b" => { "type" => "notes", "dur_s" => SLOT_B_FRAMES / SR.to_f,
                                 "_what" => "slot_b placeholder", "notes" => [] }
                 }
               ))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # --- WAV byte builders (real files, arbitrary fmt) ---

  def wav_bytes(tag:, channels:, bits:, payload:, sr: SR, extensible_sub: nil)
    block = channels * bits / 8
    fmt = [extensible_sub ? 0xFFFE : tag, channels, sr, sr * block, block, bits].pack("vvVVvv")
    if extensible_sub
      guid = [extensible_sub].pack("V") + [0, 0x0010].pack("vv") + "\x80\x00\x00\xAA\x00\x38\x9B\x71".b
      fmt += [22, bits].pack("vv") + [0].pack("V") + guid
    end
    body = "fmt " + [fmt.bytesize].pack("V") + fmt +
           "data" + [payload.bytesize].pack("V") + payload + (payload.bytesize.odd? ? "\x00" : "")
    "RIFF" + [4 + body.bytesize].pack("V") + "WAVE" + body
  end

  def pack_i24(values)
    values.map { |v| [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF].pack("CCC") }.join
  end

  def drop(name, bytes)
    File.binwrite(File.join(@inbox, name), bytes)
  end

  def run_import
    io = StringIO.new
    result = GTA::StemImport.run!(@dir, io: io)
    [result, io.string]
  end

  def stems_samples(slot)
    GTA::Wav.read(File.join(@dir, "stems", "#{slot}.wav"))[:data].unpack("s<*")
  end

  def manifest_entry(slot)
    JSON.parse(File.read(@manifest_path)).fetch("tones").fetch(slot)
  end

  # --- accept paths ---

  def test_pcm16_mono_exact_passthrough_and_manifest_pin
    samples = Array.new(SLOT_A_FRAMES) { |i| (i % 100) - 50 }
    drop("slot_a.wav", wav_bytes(tag: 1, channels: 1, bits: 16, payload: samples.pack("s<*")))
    result, out = run_import

    assert_equal ["slot_a"], result[:accepted]
    assert_empty result[:refused]
    assert_equal samples, stems_samples("slot_a"), "PCM16 mono must pass through sample-exact"

    entry = manifest_entry("slot_a")
    sha = Digest::SHA256.file(File.join(@dir, "stems", "slot_a.wav")).hexdigest
    assert_equal %w[type dur_s path sha256 _what], entry.keys, "key order pinned; _what preserved"
    assert_equal "file", entry["type"]
    assert_equal "stems/slot_a.wav", entry["path"]
    assert_equal sha, entry["sha256"]
    assert_in_delta SLOT_A_FRAMES / SR.to_f, entry["dur_s"], 1e-12
    assert_equal "slot_a placeholder", entry["_what"]
    assert_equal "notes", manifest_entry("slot_b")["type"], "untouched slots stay as they were"
    assert File.exist?(File.join(@inbox, "slot_a.wav")), "inbox files are never deleted"
    assert_includes out, "ACCEPTED"
    assert_includes out, "test band prose"
  end

  def test_stereo_downmix_is_average_of_channels
    l = [100, 201, -300, 32_767]
    r = [300, -100, -300, 32_767]
    drop("slot_a.wav", wav_bytes(tag: 1, channels: 2, bits: 16,
                                 payload: l.zip(r).flatten.pack("s<*") +
                                          Array.new((SLOT_A_FRAMES - 4) * 2, 0).pack("s<*")))
    result, out = run_import
    assert_equal ["slot_a"], result[:accepted]
    assert_equal [200, 51, -300, 32_767], stems_samples("slot_a")[0, 4] # (201-100)/2=50.5 rounds half-up
    assert_includes out, "stereo -> mono downmix (L+R)/2"
  end

  def test_24bit_conversion_known_values
    values = [8_388_607, -8_388_608, 4_194_304, 0, -4_194_304]
    payload = pack_i24(values) + pack_i24(Array.new(SLOT_A_FRAMES - values.size, 0))
    drop("slot_a.wav", wav_bytes(tag: 1, channels: 1, bits: 24, payload: payload))
    result, out = run_import
    assert_equal ["slot_a"], result[:accepted]
    assert_equal [32_767, -32_767, 16_384, 0, -16_384], stems_samples("slot_a")[0, 5]
    assert_includes out, "24-bit int -> PCM16"
  end

  def test_32bit_int_and_float_conversion_known_values
    ints = [2**30, -(2**31), 0] + Array.new(SLOT_A_FRAMES - 3, 0)
    drop("slot_a.wav", wav_bytes(tag: 1, channels: 1, bits: 32, payload: ints.pack("l<*")))
    floats = [0.5, 1.5, -2.0, 1.0, -1.0] + Array.new(SLOT_B_FRAMES - 5, 0.0)
    drop("slot_b.wav", wav_bytes(tag: 3, channels: 1, bits: 32, payload: floats.pack("e*")))
    result, out = run_import
    assert_equal %w[slot_a slot_b], result[:accepted].sort
    assert_equal [16_384, -32_767, 0], stems_samples("slot_a")[0, 3]
    assert_equal [16_384, 32_767, -32_768, 32_767, -32_767], stems_samples("slot_b")[0, 5],
                 "hot floats clamp instead of wrapping"
    assert_includes out, "32-bit int -> PCM16"
    assert_includes out, "32-bit float -> PCM16"
  end

  def test_extensible_header_resolves_subformat
    samples = Array.new(SLOT_A_FRAMES, 1000)
    drop("slot_a.wav", wav_bytes(tag: 1, channels: 1, bits: 16,
                                 payload: samples.pack("s<*"), extensible_sub: 1))
    result, = run_import
    assert_equal ["slot_a"], result[:accepted]
    assert_equal samples, stems_samples("slot_a")
  end

  # --- duration conformance boundaries ---

  def test_pad_just_inside_tolerance
    short = Array.new(SLOT_A_FRAMES - 48) { 500 }
    drop("slot_a.wav", wav_bytes(tag: 1, channels: 1, bits: 16, payload: short.pack("s<*")))
    result, out = run_import
    assert_equal ["slot_a"], result[:accepted]
    got = stems_samples("slot_a")
    assert_equal SLOT_A_FRAMES, got.size
    assert_equal Array.new(48, 0), got[-48, 48], "deficit padded with zeros"
    assert_includes out, "padded 48 frame(s)"
  end

  def test_pad_just_outside_tolerance_refuses
    drop("slot_a.wav", wav_bytes(tag: 1, channels: 1, bits: 16,
                                 payload: Array.new(SLOT_A_FRAMES - 49, 500).pack("s<*")))
    result, out = run_import
    assert_empty result[:accepted]
    assert_equal 1, result[:refused].size
    assert_includes out, "too short: 431 frames"
    assert_includes out, "480"
    refute File.exist?(File.join(@dir, "stems", "slot_a.wav"))
    assert_equal "notes", manifest_entry("slot_a")["type"], "manifest untouched on refusal"
  end

  def test_trim_silent_overhang_inside_tolerance
    payload = (Array.new(SLOT_A_FRAMES, 500) + Array.new(96, 0)).pack("s<*")
    drop("slot_a.wav", wav_bytes(tag: 1, channels: 1, bits: 16, payload: payload))
    result, out = run_import
    assert_equal ["slot_a"], result[:accepted]
    assert_equal SLOT_A_FRAMES, stems_samples("slot_a").size
    assert_includes out, "trimmed 96 frame(s)"
  end

  def test_trim_refuses_audible_overhang
    payload = (Array.new(SLOT_A_FRAMES, 500) + Array.new(95, 0) + [500]).pack("s<*")
    drop("slot_a.wav", wav_bytes(tag: 1, channels: 1, bits: 16, payload: payload))
    result, out = run_import
    assert_empty result[:accepted]
    assert_includes out, "not silence"
    assert_includes out, "never chops audible audio"
  end

  def test_trim_refuses_past_tolerance_even_if_silent
    payload = (Array.new(SLOT_A_FRAMES, 500) + Array.new(97, 0)).pack("s<*")
    drop("slot_a.wav", wav_bytes(tag: 1, channels: 1, bits: 16, payload: payload))
    result, out = run_import
    assert_empty result[:accepted]
    assert_includes out, "too long: 577 frames"
  end

  # --- refusal / skip paths ---

  def test_wrong_sample_rate_refuses_with_reaper_fix
    drop("slot_a.wav", wav_bytes(tag: 1, channels: 1, bits: 16, sr: 44_100,
                                 payload: Array.new(441, 0).pack("s<*")))
    result, out = run_import
    assert_empty result[:accepted]
    assert_includes out, "sample rate 44100, need 48000"
    assert_includes out, "Render dialog"
  end

  def test_unknown_slot_name_refuses_loudly_and_leaves_file
    drop("slot_zzz.wav", wav_bytes(tag: 1, channels: 1, bits: 16,
                                   payload: Array.new(10, 0).pack("s<*")))
    result, out = run_import
    assert_equal [["slot_zzz.wav", "unknown slot"]], result[:refused]
    assert_includes out, "no slot named \"slot_zzz\""
    assert_includes out, "Valid slots: slot_a, slot_b"
    assert File.exist?(File.join(@inbox, "slot_zzz.wav"))
  end

  def test_non_wav_files_noted_not_refused
    File.write(File.join(@inbox, "notes.txt"), "reaper session scratch")
    result, out = run_import
    assert_equal ["notes.txt"], result[:noted]
    assert_empty result[:refused]
    assert_includes out, "not a .wav — ignored"
  end

  def test_unsupported_format_refuses
    drop("slot_a.wav", wav_bytes(tag: 1, channels: 1, bits: 8,
                                 payload: Array.new(SLOT_A_FRAMES, 128).pack("C*")))
    result, out = run_import
    assert_empty result[:accepted]
    assert_includes out, "unsupported WAV format"
  end

  def test_mixed_batch_good_import_lands_bad_refuses
    drop("slot_a.wav", wav_bytes(tag: 1, channels: 1, bits: 16,
                                 payload: Array.new(SLOT_A_FRAMES, 250).pack("s<*")))
    drop("slot_b.wav", wav_bytes(tag: 1, channels: 1, bits: 16, sr: 44_100,
                                 payload: Array.new(220, 0).pack("s<*")))
    result, = run_import
    assert_equal ["slot_a"], result[:accepted]
    assert_equal 1, result[:refused].size
    assert_equal "file", manifest_entry("slot_a")["type"]
    assert_equal "notes", manifest_entry("slot_b")["type"]
  end
end
