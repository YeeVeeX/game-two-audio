# harness/import_stems.rb — `rake stems:import`: the inbox half of the owner
# production loop (M4b, docs/listen-track.md).
#
# Contract: the owner renders stems into data/audio_listen/inbox/ named
# <slot>.wav (any subset of the manifest slots). For each inbox WAV this
# importer:
#   - refuses wrong sample rates (engine.json is the timebase authority);
#   - downmixes stereo to mono ((L+R)/2 in the source domain), reported;
#   - converts 24-bit int / 32-bit int / 32-bit float to PCM16 (round +
#     clamp; PCM16 mono input passes through sample-exact);
#     WAVE_FORMAT_EXTENSIBLE headers resolve through their sub-format GUID;
#   - conforms duration to the slot's dur_s exactly (pad/trim tolerances and
#     the silence floor live in data/audio_listen/import.json — durations
#     are choreography-load-bearing; gross mismatch refuses with
#     measured-vs-expected frames);
#   - on accept: writes data/audio_listen/stems/<slot>.wav, pins its sha256
#     in fixtures.json (type="file"; "_"-prefixed comment keys preserved;
#     JSON.pretty_generate, key order kept), and reports peak/rms dBFS
#     against the slot's KB level band.
#
# Inbox files are the owner's documents: never deleted, never modified —
# report and leave. Unknown .wav names refuse loudly (typo protection);
# non-.wav files get a note and are ignored. Any refusal exits non-zero.
#
# CLI (what `rake stems:import` runs): after any accepted import it
# re-renders the full listen track in-process (same Runner, same tmp/listen
# artifacts as `rake listen`) and prints old->new WAV sha heads — an
# accepted import legitimately moves that slot's listen shas and the M4
# verdict pins the final set. A listen sha that moves WITHOUT an import or
# data commit is still a stop-the-line event.

require "json"
require "digest"
require "fileutils"
require "gta/wav"

module GTA
  module StemImport
    Refusal = Class.new(StandardError)

    module_function

    # Imports every file in <listen_dir>/inbox. Returns
    # { accepted: ["slot", ...], refused: [[basename, reason], ...],
    #   noted: [basename, ...] }. Writes stems/ + fixtures.json on accept.
    def run!(listen_dir, io: $stdout)
      manifest_path = File.join(listen_dir, "fixtures.json")
      manifest = JSON.parse(File.read(manifest_path))
      slots = manifest.fetch("tones")
      cfg = JSON.parse(File.read(File.join(listen_dir, "import.json")))
      sr = JSON.parse(File.read(File.join(listen_dir, "engine.json"))).fetch("sample_rate")

      inbox = File.join(listen_dir, "inbox")
      files = File.directory?(inbox) ? Dir[File.join(inbox, "*")].sort : []
      io.puts "stems:import — inbox: #{inbox}"
      result = { accepted: [], refused: [], noted: [] }
      io.puts "  (empty — render stems there as <slot>.wav)" if files.empty?

      files.each do |path|
        base = File.basename(path)
        unless base.downcase.end_with?(".wav")
          result[:noted] << base
          io.puts "  #{base}: not a .wav — ignored, left in place"
          next
        end
        slot = base.sub(/\.wav\z/i, "")
        unless slots.key?(slot)
          result[:refused] << [base, "unknown slot"]
          io.puts "  #{base}: REFUSED — no slot named #{slot.inspect}. Valid slots: #{slots.keys.join(', ')}. File left in inbox."
          next
        end
        begin
          import_one(path, slot, slots, cfg, listen_dir, sr, io)
          result[:accepted] << slot
        rescue Refusal => e
          result[:refused] << [base, e.message]
          io.puts "  #{slot}: REFUSED — #{e.message} File left in inbox."
        end
      end

      unless result[:accepted].empty?
        File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")
        io.puts "  fixtures.json updated: #{result[:accepted].join(', ')} pinned as type=\"file\""
      end
      result
    end

    def import_one(src, slot, slots, cfg, listen_dir, sr, io)
      spec = slots.fetch(slot)
      w = read_wav(src)
      unless w[:sample_rate] == sr
        raise Refusal, "sample rate #{w[:sample_rate]}, need #{sr}. Reaper fix: set Sample rate #{sr} in the Render dialog (File > Render), or File > Project settings > #{sr}."
      end
      samples, conversions = decode_to_pcm16(w)
      samples, duration_note = conform_duration(samples, spec.fetch("dur_s"), sr, cfg)

      stems_dir = File.join(listen_dir, "stems")
      FileUtils.mkdir_p(stems_dir)
      dest = File.join(stems_dir, "#{slot}.wav")
      GTA::Wav.write_pcm16(dest, samples, channels: 1, sample_rate: sr)
      sha = Digest::SHA256.file(dest).hexdigest

      entry = { "type" => "file", "dur_s" => spec.fetch("dur_s"),
                "path" => "stems/#{slot}.wav", "sha256" => sha }
      spec.each { |k, v| entry[k] = v if k.start_with?("_") }
      slots[slot] = entry

      peak = samples.map(&:abs).max / 32768.0
      rms = Math.sqrt(samples.sum { |s| (s / 32768.0)**2 } / samples.size)
      io.puts "  #{slot}: ACCEPTED -> stems/#{slot}.wav  sha256 #{sha[0, 12]}…"
      conversions.each { |c| io.puts "     #{c}" }
      io.puts "     #{duration_note}" if duration_note
      io.puts "     stem peak #{dbfs(peak)}  rms #{dbfs(rms)}  target band: #{cfg.fetch('bands', {})[slot] || '(no band note in import.json)'}"
    end

    # -> [mono PCM16 Integer samples, [conversion note, ...]]
    def decode_to_pcm16(w)
      conversions = []
      tag = w[:tag]
      if tag == 0xFFFE
        raise Refusal, "WAVE_FORMAT_EXTENSIBLE header without a readable sub-format." if w[:sub_tag].nil?
        tag = w[:sub_tag]
      end

      native, to16 =
        case [tag, w[:bits]]
        when [1, 16]
          [w[:data].unpack("s<*"), ->(v) { v.round }]
        when [1, 24]
          conversions << "24-bit int -> PCM16 (round + clamp)"
          [unpack_i24(w[:data]), ->(v) { to_i16(v / 8_388_608.0) }]
        when [1, 32]
          conversions << "32-bit int -> PCM16 (round + clamp)"
          [w[:data].unpack("l<*"), ->(v) { to_i16(v / 2_147_483_648.0) }]
        when [3, 32]
          conversions << "32-bit float -> PCM16 (round + clamp)"
          [w[:data].unpack("e*"), ->(v) { to_i16(v) }]
        else
          raise Refusal, "unsupported WAV format (tag=#{w[:tag]}, #{w[:bits]}-bit) — render 16/24-bit PCM or 32-bit float."
        end

      case w[:channels]
      when 1
        pcm16_passthrough = [tag, w[:bits]] == [1, 16]
        [pcm16_passthrough ? native : native.map { |v| to16.call(v) }, conversions]
      when 2
        conversions.unshift "stereo -> mono downmix (L+R)/2"
        mono = native.each_slice(2).map { |l, r| (l + r) / 2.0 }
        [mono.map { |v| to16.call(v) }, conversions]
      else
        raise Refusal, "#{w[:channels]} channels — render mono or stereo only."
      end
    end

    # Exact-frame conformance to the slot duration (docs/listen-track.md:
    # durations are choreography-load-bearing). Policy in import.json.
    def conform_duration(samples, dur_s, sr, cfg)
      expected = (dur_s * sr).round
      frames = samples.size
      return [samples, nil] if frames == expected

      if frames < expected
        deficit = expected - frames
        if deficit <= (cfg.fetch("pad_tolerance_s") * sr).round
          padded = samples + Array.new(deficit, 0)
          [padded, format("padded %d frame(s) (%.1f ms) of trailing silence to the slot's exact %.3f s",
                          deficit, deficit * 1000.0 / sr, dur_s)]
        else
          raise Refusal, format("too short: %d frames (%.4f s), slot needs %d (%.4f s) — %.1f ms missing exceeds pad_tolerance_s=%s. Lengthen the render (the scaffold's region is exact).",
                                frames, frames / sr.to_f, expected, dur_s,
                                deficit * 1000.0 / sr, cfg.fetch("pad_tolerance_s"))
        end
      else
        over = frames - expected
        if over > (cfg.fetch("trim_tolerance_s") * sr).round
          raise Refusal, format("too long: %d frames (%.4f s) vs expected %d (%.4f s) — %.3f s overhang exceeds trim_tolerance_s=%s. Render the region exactly (durations are choreography-load-bearing).",
                                frames, frames / sr.to_f, expected, dur_s,
                                over / sr.to_f, cfg.fetch("trim_tolerance_s"))
        end
        floor = cfg.fetch("silence_floor")
        tail_peak = samples[expected, over].map(&:abs).max / 32768.0
        if tail_peak >= floor
          raise Refusal, format("trailing overhang (%d frame(s), %.1f ms) is not silence — peak %s is over the silence_floor (%s). Shorten the tail in Reaper or render the region exactly; the importer never chops audible audio.",
                                over, over * 1000.0 / sr, dbfs(tail_peak), dbfs(floor))
        end
        [samples[0, expected],
         format("trimmed %d frame(s) (%.1f ms) of trailing silence (peak %s, under the %s floor)",
                over, over * 1000.0 / sr, dbfs(tail_peak), dbfs(floor))]
      end
    end

    # Full RIFF walk (GTA::Wav.read drops the fmt-chunk tail this needs for
    # WAVE_FORMAT_EXTENSIBLE sub-format resolution).
    def read_wav(path)
      raw = File.binread(path)
      raise Refusal, "not a RIFF/WAVE file." unless raw[0, 4] == "RIFF" && raw[8, 4] == "WAVE"
      pos = 12
      fmt = nil
      data = nil
      while pos + 8 <= raw.bytesize
        cid = raw[pos, 4]
        csz = raw[pos + 4, 4].unpack1("V")
        case cid
        when "fmt " then fmt = raw[pos + 8, csz]
        when "data" then data = raw[pos + 8, csz]
        end
        pos += 8 + csz + (csz.odd? ? 1 : 0)
      end
      raise Refusal, "missing fmt/data chunk." if fmt.nil? || data.nil?
      tag, channels, rate, _byterate, _align, bits = fmt.unpack("vvVVvv")
      sub_tag = tag == 0xFFFE && fmt.bytesize >= 26 ? fmt[24, 2].unpack1("v") : nil
      { tag: tag, sub_tag: sub_tag, channels: channels, sample_rate: rate, bits: bits, data: data }
    end

    def unpack_i24(data)
      bytes = data.unpack("C*")
      (bytes.size / 3).times.map do |i|
        v = bytes[3 * i] | (bytes[3 * i + 1] << 8) | (bytes[3 * i + 2] << 16)
        v >= 8_388_608 ? v - 16_777_216 : v
      end
    end

    def to_i16(x)
      (x * 32_767).round.clamp(-32_768, 32_767)
    end

    def dbfs(v)
      return "-inf dBFS" if v <= 0
      format("%.2f dBFS", 20.0 * Math.log10(v))
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  listen_dir = ARGV[0] || File.expand_path("../data/audio_listen", __dir__)
  out_dir = File.expand_path("../tmp/listen", __dir__)
  old_shas = Dir[File.join(out_dir, "*.wav")].sort
                                             .to_h { |p| [File.basename(p), Digest::SHA256.file(p).hexdigest] }

  result = GTA::StemImport.run!(listen_dir)
  refusals = result[:refused].size

  if result[:accepted].empty?
    puts "stems:import — nothing imported#{refusals.zero? ? '' : " (#{refusals} refusal(s), see above)"}"
    exit(refusals.zero? ? 0 : 1)
  end

  # Auto listen re-render: same Runner, same artifacts as `rake listen`.
  require_relative "gate_runner"
  fixture_dir = File.expand_path("../tmp/fixtures_listen", __dir__)
  puts "stems:import — re-rendering the listen track (tmp/listen; peak ceiling + determinism still gate)"
  all_pass = true
  Dir[File.expand_path("replays/*.json", __dir__)].sort.each do |replay|
    r = GTA::Gate::Runner.new(replay, data_dir: listen_dir, fixture_dir: fixture_dir,
                              out_dir: out_dir, expectation_types: %w[peak]).run
    all_pass &&= r.pass?
    old = old_shas["#{r.name}.wav"]
    sha_note = old.nil? ? "sha #{r.wav_sha256[0, 8]} (first render)" :
               old == r.wav_sha256 ? "sha #{r.wav_sha256[0, 8]} (unchanged)" :
               "sha #{old[0, 8]} -> #{r.wav_sha256[0, 8]}"
    puts format("  %s %-20s %s  peak %.2f dBFS", r.pass? ? "PASS" : "FAIL", r.name, sha_note, r.metrics[:peak_dbfs])
    r.checks.reject(&:pass).each { |c| puts "       FAIL #{c.label} #{c.detail}" } unless r.pass?
  end

  puts "stems:import — imported: #{result[:accepted].join(', ')}. Play tmp/listen/*.wav."
  puts "  (an accepted import legitimately moves that slot's listen shas; the M4 verdict pins the final set)"
  if all_pass && refusals.zero?
    exit 0
  else
    puts "stems:import — #{refusals} refusal(s); listen render #{all_pass ? 'clean' : 'FAILED (see above)'}"
    exit 1
  end
end
