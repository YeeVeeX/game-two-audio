require "minitest/autorun"
require "json"
require "digest"
require "tmpdir"
require_relative "../harness/export_midi"

# MIDI export (M4 owner production loop): deterministic serialization of the
# listen-track compositions. The owner re-voices these through Reaper/VST/
# analog and returns WAVs as type="file" fixtures — the .mid is the scaffold.
class MidiExportTest < Minitest::Test
  FIXTURE = {
    "type" => "notes", "dur_s" => 1.0, "gain" => 1.0,
    "notes" => [
      { "t" => 0.0, "dur" => 0.5, "freq_hz" => 440.0, "amp" => 0.25, "wave" => "tri",
        "attack_s" => 0.01, "release_s" => 0.05 },
      { "t" => 0.4, "dur" => 0.4, "freq_hz" => 440.0, "amp" => 0.25, "wave" => "tri",
        "attack_s" => 0.01, "release_s" => 0.05 },
      { "t" => 0.5, "dur" => 0.2, "freq_hz" => 1.0, "amp" => 0.2, "wave" => "noise", "seed" => 3,
        "attack_s" => 0.01, "release_s" => 0.05 }
    ]
  }.freeze

  def test_export_is_deterministic_and_structured
    a = GTA::MidiExport.fixture_to_smf("t", FIXTURE)
    b = GTA::MidiExport.fixture_to_smf("t", FIXTURE)
    assert_equal a, b, "MIDI export must be deterministic"

    assert_equal "MThd", a[0, 4]
    assert_equal [0, 1, 480], a[8, 6].unpack("nnn"), "format-0, one track, division 480"
    assert_equal "MTrk", a[14, 4]
    assert_equal a.bytesize - 22, a[18, 4].unpack1("N"), "track length must match"

    assert_equal 3, channel_events(a).count { |_, s, _| s == 0x90 }, "3 note-ons expected"
    assert_includes a, "noise burst", "noise marker missing"
    assert a.end_with?("\xFF\x2F\x00".b), "end-of-track missing"
  end

  def test_same_pitch_overlap_is_clipped
    smf = GTA::MidiExport.fixture_to_smf("t", FIXTURE)
    ticks = channel_events(smf)
    offs69 = ticks.select { |_, s, n| s == 0x80 && n == 69 }.map(&:first)
    ons69 = ticks.select { |_, s, n| s == 0x90 && n == 69 }.map(&:first)
    assert_equal [0, 384], ons69
    assert_equal 383, offs69.min, "first A4 off must clip to 1 tick before the second on"
  end

  # Minimal SMF walker: returns [[abs_tick, status, note], ...] for channel
  # note events; skips meta events.
  def channel_events(smf)
    track = smf[22..]
    ticks = []
    pos = 0
    abs = 0
    while pos < track.bytesize
      delta = 0
      loop do
        byte = track.getbyte(pos)
        pos += 1
        delta = (delta << 7) | (byte & 0x7F)
        break if byte < 0x80
      end
      abs += delta
      status = track.getbyte(pos)
      if status == 0xFF
        len_start = pos + 2
        len = 0
        loop do
          byte = track.getbyte(len_start)
          len_start += 1
          len = (len << 7) | (byte & 0x7F)
          break if byte < 0x80
        end
        pos = len_start + len
      else
        ticks << [abs, status, track.getbyte(pos + 1)] if [0x80, 0x90].include?(status)
        pos += 3
      end
    end
    ticks
  end

  def test_pitch_and_velocity_mapping
    assert_equal 69, GTA::MidiExport.freq_to_note(440.0)
    assert_equal 45, GTA::MidiExport.freq_to_note(110.0)
    assert_equal 88, GTA::MidiExport.freq_to_note(1318.51)
    assert_equal 45, GTA::MidiExport.freq_to_note(109.746), "detuned pair collapses to the ET note"
    assert_equal 127, GTA::MidiExport.amp_to_velocity(1.0)
    assert_equal (127 * Math.sqrt(0.1)).round, GTA::MidiExport.amp_to_velocity(0.1)
    assert_equal 1, GTA::MidiExport.amp_to_velocity(0.00001)
  end

  def test_export_writes_only_notes_fixtures
    Dir.mktmpdir do |dir|
      manifest = File.join(dir, "fixtures.json")
      File.write(manifest, JSON.generate({ "tones" => {
        "musical" => FIXTURE,
        "sine_x" => { "freq_hz" => 440.0, "dur_s" => 0.1, "amp" => 0.5, "phase" => 0.0 }
      } }))
      written = GTA::MidiExport.export!(manifest, File.join(dir, "midi"))
      assert_equal 1, written.size
      assert written.first.end_with?("musical.mid")
      assert File.exist?(written.first)
    end
  end
end
