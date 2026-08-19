# harness/export_midi.rb — export the listen-track placeholder compositions as
# standard MIDI files (M4, owner production loop).
#
# The composition source of truth is data/audio_listen/fixtures.json (type
# "notes" entries). This exporter serializes each fixture to SMF format-0 so
# the owner can re-voice the SAME composition through Reaper/VST instruments
# or analog synths (KB music-production/moog-dfam.md carries game-audio patch
# recipes), render to WAV per docs/listen-track.md, and drop the file back in
# as a type="file" fixture. Deterministic: same JSON -> byte-identical .mid.
#
# Mapping notes (lossy by design — MIDI is the scaffold, the owner re-voices):
#  - freq_hz -> nearest equal-tempered MIDI note (A4=440=69). All listen
#    pitches are ET already; detuned pairs collapse to the same note and get
#    a text marker instead (re-create detune on the instrument).
#  - amp -> velocity: round(127 * sqrt(amp)), clamped to [1,127].
#  - wave/envelope/trem -> one text marker per note group (params live in the
#    JSON; markers keep the DAW view self-describing).
#  - "noise" notes -> note 36 (C1) + marker (re-sound-design; no pitch).
#  - glide_to_hz -> marker (no pitch-bend emitted; keep the scaffold simple).
#  - Same-pitch overlaps: earlier note-off clipped 1 tick before the next
#    note-on (SMF same-channel overlap is ambiguous on hardware gates).
#  - End-of-track padded to the fixture's exact dur_s so DAW length == slot
#    length (durations are choreography-load-bearing).
#
# Usage: ruby -Isrc -Iharness harness/export_midi.rb [manifest] [out_dir]
# Default: data/audio_listen/fixtures.json -> data/audio_listen/midi/

require "json"
require "fileutils"

module GTA
  module MidiExport
    DIVISION = 480 # ticks per quarter note
    TEMPO_BPM = 120 # matches data/audio_listen/music.json timing
    TICKS_PER_SECOND = DIVISION * TEMPO_BPM / 60 # 960

    module_function

    def export!(manifest_path, out_dir)
      manifest = JSON.parse(File.read(manifest_path))
      FileUtils.mkdir_p(out_dir)
      written = []
      manifest.fetch("tones").each do |name, spec|
        next unless spec["type"] == "notes"
        bytes = fixture_to_smf(name, spec)
        path = File.join(out_dir, "#{name}.mid")
        File.binwrite(path, bytes)
        written << path
      end
      written
    end

    def freq_to_note(freq_hz)
      (69 + 12 * Math.log2(freq_hz / 440.0)).round.clamp(0, 127)
    end

    def amp_to_velocity(amp)
      (127 * Math.sqrt(amp)).round.clamp(1, 127)
    end

    def vlq(value)
      bytes = [value & 0x7F]
      bytes.unshift(((value >>= 7) & 0x7F) | 0x80) while value > 0x7F
      bytes.pack("C*")
    end

    def meta(type, payload)
      [0xFF, type].pack("CC") + vlq(payload.bytesize) + payload.b
    end

    # Canonical note-event mapping shared by SMF export AND the live Reaper
    # bridge project builder. Keeping it here prevents the committed .mid
    # scaffolds from drifting from bridge-created MIDI items.
    def fixture_note_events(spec)
      notes = spec.fetch("notes").map do |n|
        pitch = n["wave"] == "noise" ? 36 : freq_to_note(n.fetch("freq_hz"))
        on = (n.fetch("t") * TICKS_PER_SECOND).round
        off = ((n.fetch("t") + n.fetch("dur")) * TICKS_PER_SECOND).round
        { pitch: pitch, on: on, off: [off, on + 1].max, vel: amp_to_velocity(n.fetch("amp")), src: n }
      end
      # Clip same-pitch overlaps: for each pitch, note-off may not reach the
      # next note-on of the same pitch (same-channel overlap is ambiguous on
      # hardware gates and in some VST instruments).
      notes.group_by { |n| n[:pitch] }.each_value do |group|
        sorted = group.sort_by { |n| n[:on] }
        sorted.each_cons(2) do |a, b|
          a[:off] = [b[:on] - 1, a[:on] + 1].max if a[:off] >= b[:on]
        end
      end
      notes
    end

    def fixture_to_smf(name, spec)
      # events: [tick, order, bytes] — order sorts offs (0) before ons (2),
      # markers (1) between, at equal ticks.
      events = []
      events << [0, 1, meta(0x03, name)] # track name
      events << [0, 1, meta(0x51, [500_000].pack("N")[1, 3])] # 120 bpm
      events << [0, 1, meta(0x01, "placeholder composition; authoritative params in data/audio_listen/fixtures.json")]

      notes = fixture_note_events(spec)
      notes.each do |n|
        src = n[:src]
        marks = []
        marks << "noise burst — re-sound-design" if src["wave"] == "noise"
        marks << format("glide %.5gHz->%.5gHz over %.3gs", src["freq_hz"], src["glide_to_hz"], src["glide_s"]) if src["glide_to_hz"]
        marks << format("wave=%s%s%s", src["wave"],
                        src["decay_tau_s"] ? format(" decay_tau=%.3gs", src["decay_tau_s"]) : "",
                        src["trem"] ? format(" trem=%.3gHz/%.2g", src["trem"]["rate_hz"], src["trem"]["depth"]) : "")
        events << [n[:on], 1, meta(0x06, marks.join("; "))] unless marks.empty?
        events << [n[:on], 2, [0x90, n[:pitch], n[:vel]].pack("CCC")]
        events << [n[:off], 0, [0x80, n[:pitch], 0].pack("CCC")]
      end

      end_tick = [(spec.fetch("dur_s") * TICKS_PER_SECOND).round, events.map(&:first).max].max
      events.sort_by! { |tick, order, _| [tick, order] }

      track = String.new(encoding: Encoding::BINARY)
      last = 0
      events.each do |tick, _, bytes|
        track << vlq(tick - last) << bytes
        last = tick
      end
      track << vlq(end_tick - last) << meta(0x2F, "")

      header = "MThd" + [6].pack("N") + [0, 1, DIVISION].pack("nnn")
      header + "MTrk" + [track.bytesize].pack("N") + track
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  manifest = ARGV[0] || File.expand_path("../data/audio_listen/fixtures.json", __dir__)
  out_dir = ARGV[1] || File.expand_path("../data/audio_listen/midi", __dir__)
  written = GTA::MidiExport.export!(manifest, out_dir)
  written.each { |p| puts "midi: #{p} (#{File.size(p)} bytes)" }
  puts "midi: #{written.size} file(s) exported"
end
