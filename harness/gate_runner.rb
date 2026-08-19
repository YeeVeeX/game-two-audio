# harness/gate_runner.rb — the deterministic ship-gate (AGENTS non-negotiable 3
# mechanized; ADR 0001 decision 5).
#
# Per replay: scripted events -> AudioSystem (+ recorder) -> command log (md5,
# bit-exact by construction) -> noDevice render -> WAV artifact -> SECOND full
# fresh render -> byte-compare -> feature assertions (RMS windows, Goertzel cue
# presence/timing, silence floors, duck-depth ratios).
#
# Replay JSON:
#   { "name": ..., "duration_ticks": N,
#     "events": [[tick, "event", {payload}], ...],   # payload keys symbolized
#     "expectations": { "goertzel": [...], "rms": [...], "silence": [...],
#                        "ratio": [...], "log": [...], "peak": [...] } }
# Windows accept from_tick/ticks (mapped via engine.json tick_frames) or
# from_frame/frames. All analysis runs on render A (A == B is asserted first).
# M3 additions:
#   "log"  — exact command count over the canonical log: {op, id?, window?,
#            count} (catches steal/duck issuance regressions the WAV can't
#            isolate; window optional = whole replay);
#   "peak" — max |sample| bound over a window (window optional = whole
#            render): {max_peak} — the headroom gate. Sample peak, not
#            oversampled dBTP (see Analysis.sample_peak).
# A per-replay metrics block (peak/rms/crest/over-1.0) is computed always —
# informational (presentation axis input), only "peak" expectations gate.

require "json"
require "digest"
require "fileutils"
require "gta/native"
require "gta/wav"
require "gta/audio_system"
require "gta/fixtures"
require "gta/render"
require "gta/analysis"

module GTA
  module Gate
    Check = Struct.new(:pass, :label, :detail)
    Result = Struct.new(:name, :log_md5, :wav_sha256, :render_match, :log_match, :checks, :diagnostics, :metrics) do
      def pass?
        render_match && log_match && checks.all?(&:pass)
      end
    end

    class Runner
      def initialize(replay_path, data_dir:, fixture_dir:, out_dir:, expectation_types: nil)
        @replay = JSON.parse(File.read(replay_path))
        @data_dir = data_dir
        @fixture_dir = fixture_dir
        @out_dir = out_dir
        @expectation_types = expectation_types
        @engine_tbl = JSON.parse(File.read(File.join(data_dir, "engine.json")))
        @tf = @engine_tbl["tick_frames"]
        @sr = @engine_tbl["sample_rate"]
        @channels = @engine_tbl["channels"]
        @events_by_tick = Hash.new { |h, k| h[k] = [] }
        @replay.fetch("events").each do |tick, name, payload|
          @events_by_tick[tick] << [name, symbolize(payload)]
        end
      end

      def run
        GTA::Fixtures.ensure!(File.join(@data_dir, "fixtures.json"), @fixture_dir, sample_rate: @sr)
        bytes_a, log_a, diag = render_replay
        bytes_b, log_b, _ = render_replay

        name = @replay.fetch("name")
        FileUtils.mkdir_p(@out_dir)
        wav_path = File.join(@out_dir, "#{name}.wav")
        GTA::Wav.write_f32(wav_path, bytes_a, channels: @channels, sample_rate: @sr)
        log_a.write(File.join(@out_dir, "#{name}.log"))

        checks = []
        samples = bytes_a.unpack("e*")
        expectations = @replay.fetch("expectations")
        (want(expectations, "goertzel") || []).each { |e| checks << check_goertzel(samples, e) }
        (want(expectations, "rms") || []).each { |e| checks << check_rms(samples, e) }
        (want(expectations, "silence") || []).each { |e| checks << check_silence(samples, e) }
        (want(expectations, "ratio") || []).each { |e| checks << check_ratio(samples, e) }
        (want(expectations, "log") || []).each { |e| checks << check_log(log_a, e) }
        (want(expectations, "peak") || []).each { |e| checks << check_peak(samples, e) }

        # wav_sha256 hashes the WAV FILE on disk (header + payload) — the
        # externally verifiable artifact identity. Hashing only the raw
        # sample buffer here while other tooling hashed the file produced
        # two hash domains for one identical render (M4b false alarm:
        # "determinism break" that was byte-identical audio). One domain.
        Result.new(name, log_a.md5, Digest::SHA256.file(wav_path).hexdigest,
                   bytes_a == bytes_b, log_a.md5 == log_b.md5, checks, diag, metrics(samples))
      end

      private

      # Expectation-type filter (listen track runs the SAME replays with only
      # material-independent types — peak/headroom; the sine-tuned goertzel/
      # ratio/rms/silence/log accuracy pins stay gate-only). nil = all types
      # (the gate default; behavior unchanged).
      def want(expectations, type)
        return nil if @expectation_types && !@expectation_types.include?(type)
        expectations[type]
      end

      # One full fresh render: fresh engine, fresh AudioSystem, recorder on.
      # Tick contract: events for tick T -> update(T) -> advance tick_frames.
      def render_replay
        engine = GTA::Native.gta_engine_create(0, @channels, @sr)
        raise "engine create failed: ma_result #{GTA::Native.gta_last_result}" if engine.null?
        log = GTA::CommandLog.new
        audio = GTA::AudioSystem.new(engine: engine, data_dir: @data_dir, fixture_dir: @fixture_dir, log: log)
        renderer = GTA::Renderer.new(engine, channels: @channels)
        capture = String.new(capacity: @replay.fetch("duration_ticks") * @tf * @channels * 4,
                             encoding: Encoding::BINARY)

        @replay.fetch("duration_ticks").times do |tick|
          @events_by_tick[tick].each { |name, payload| audio.handle_event(tick, name, payload) }
          audio.update(tick)
          renderer.advance(@tf, capture: capture)
        end

        diag = { active_voices: audio.active_voices, dropped_cues: audio.dropped_cues,
                 music_state: audio.music_state }
        audio.destroy
        GTA::Native.gta_engine_destroy(engine)
        [capture, log, diag]
      end

      def window(e)
        from = e["from_frame"] || (e.fetch("from_tick") * @tf)
        frames = e["frames"] || (e.fetch("ticks") * @tf)
        [from, frames]
      end

      # Window with whole-replay default (log/peak expectations).
      def window_or_all(e)
        if e["from_frame"] || e["from_tick"]
          window(e)
        else
          [0, @replay.fetch("duration_ticks") * @tf]
        end
      end

      # Mechanical presentation metrics over the full render (all channels).
      # Informational — the accuracy/presentation split (Rule 2): these feed
      # the listen sheet; only explicit "peak" expectations gate.
      def metrics(samples)
        total = samples.size / @channels
        peak = GTA::Analysis.sample_peak(samples, 0, total, channels: @channels)
        rms = GTA::Analysis.rms(samples, 0, total, channels: @channels, ch: nil)
        {
          peak: peak, peak_dbfs: GTA::Analysis.dbfs(peak),
          rms: rms, rms_dbfs: GTA::Analysis.dbfs(rms),
          crest_db: GTA::Analysis.dbfs(peak) - GTA::Analysis.dbfs(rms),
          over_1: GTA::Analysis.over_count(samples, 1.0)
        }
      end

      # Exact op-count over the canonical command log — deterministic by
      # construction (the log md5 already gates bit-exactness; this pins
      # issuance structure: steals, duck fades, ignored music requests).
      def check_log(log, e)
        from, frames = window_or_all(e)
        op = e.fetch("op")
        id = e["id"]
        count = 0
        log.lines.each do |line|
          frame_s, line_op, line_id, = line.split(" ", 4)
          next unless line_op == op
          next if id && line_id != id
          f = frame_s.to_i
          next if f < from || f >= from + frames
          count += 1
        end
        expected = e.fetch("count")
        Check.new(count == expected, "log #{op}#{id ? " #{id}" : ''} [#{from},#{from + frames})",
                  "count=#{count} expect=#{expected}")
      end

      # Headroom gate: max |sample| over the window (all channels unless ch).
      def check_peak(samples, e)
        from, frames = window_or_all(e)
        peak = GTA::Analysis.sample_peak(samples, from, frames, channels: @channels, ch: e["ch"])
        ok = true
        ok &&= peak <= e["max_peak"] if e["max_peak"]
        ok &&= peak >= e["min_peak"] if e["min_peak"]
        Check.new(ok, "peak ch#{e['ch'] || 'all'} [#{from},#{from + frames})",
                  format("peak=%.6g (%.2f dBFS) bounds=[%s,%s]", peak, GTA::Analysis.dbfs(peak),
                         e["min_peak"] || "-", e["max_peak"] || "-"))
      end

      def check_goertzel(samples, e)
        from, frames = window(e)
        amp = GTA::Analysis.goertzel_amp(samples, e.fetch("freq_hz"), from, frames,
                                         channels: @channels, ch: e.fetch("ch", 0), sr: @sr)
        label = "goertzel #{e['freq_hz']}Hz ch#{e.fetch('ch', 0)} [#{from},#{from + frames})"
        ok = true
        ok &&= amp >= e["min_amp"] if e["min_amp"]
        ok &&= amp <= e["max_amp"] if e["max_amp"]
        Check.new(ok, label, format("amp=%.6g bounds=[%s,%s]", amp, e["min_amp"] || "-", e["max_amp"] || "-"))
      end

      def check_rms(samples, e)
        from, frames = window(e)
        v = GTA::Analysis.rms(samples, from, frames, channels: @channels, ch: e["ch"])
        ok = true
        ok &&= v >= e["min"] if e["min"]
        ok &&= v <= e["max"] if e["max"]
        Check.new(ok, "rms ch#{e['ch'] || 'all'} [#{from},#{from + frames})",
                  format("rms=%.6g bounds=[%s,%s]", v, e["min"] || "-", e["max"] || "-"))
      end

      def check_silence(samples, e)
        from, frames = window(e)
        v = GTA::Analysis.rms(samples, from, frames, channels: @channels, ch: nil)
        Check.new(v <= e.fetch("max_rms"), "silence [#{from},#{from + frames})",
                  format("rms=%.6g floor=%g", v, e["max_rms"]))
      end

      # Duck depth and steal collapse: amplitude of freq in window b relative
      # to window a (machine-portable — independent of absolute bus gains).
      def check_ratio(samples, e)
        freq = e.fetch("freq_hz")
        ch = e.fetch("ch", 0)
        fa, na = window(e.fetch("a"))
        fb, nb = window(e.fetch("b"))
        amp_a = GTA::Analysis.goertzel_amp(samples, freq, fa, na, channels: @channels, ch: ch, sr: @sr)
        amp_b = GTA::Analysis.goertzel_amp(samples, freq, fb, nb, channels: @channels, ch: ch, sr: @sr)
        ratio = amp_b / (amp_a.abs < 1e-12 ? 1e-12 : amp_a)
        ok = true
        ok &&= ratio >= e["min_ratio"] if e["min_ratio"]
        ok &&= ratio <= e["max_ratio"] if e["max_ratio"]
        Check.new(ok, "ratio #{freq}Hz ch#{ch} [#{fb},#{fb + nb})/[#{fa},#{fa + na})",
                  format("ratio=%.6g (a=%.6g b=%.6g) bounds=[%s,%s]",
                         ratio, amp_a, amp_b, e["min_ratio"] || "-", e["max_ratio"] || "-"))
      end

      def symbolize(payload)
        return nil if payload.nil?
        payload.to_h { |k, v| [k.to_sym, v] }
      end
    end
  end
end
