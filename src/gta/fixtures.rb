# gta/fixtures.rb — render the generated fixture manifest to WAV files.
#
# Two entry types under "tones" (the manifest key is the mechanical seam every
# validator/cue-ref uses; a "type" field selects the renderer):
#
#   (default / "sine") — the M1 spike formula, byte-identical for shared names:
#     amp * 32767 * sin(2*pi*(freq*i/sr + phase)), PCM16 mono.
#
#   "notes" — deterministic additive synthesis for the LISTEN track (M4: the
#     owner listen falsified raw sines as listen material — the presentation
#     axis needs musical fixtures; accuracy replays keep sines for goertzel/
#     ratio math). A fixture = { dur_s, gain, notes: [...] }; every musical
#     decision (pitch, rhythm, envelope, level) lives in the JSON (data-driven
#     law). Waveform harmonic tables below are formula, not tunables — the
#     per-asset knobs are all in data.
#
# No third-party audio, ever. Staleness: each WAV gets a .sig sidecar (sha256
# of the manifest entry + sample rate); the WAV re-renders when its entry
# drifts, so data retunes propagate without manual tmp/ cleanup.

require "json"
require "digest"
require "fileutils"
require_relative "wav"

module GTA
  module Fixtures
    # Band-limited additive waveform tables: [partial_multiple, amplitude].
    # Definitions (an instrument's identity), not tunables. Partials at or
    # above Nyquist for the note's highest fundamental are dropped.
    WAVE_PARTIALS = {
      "sine"   => [[1.0, 1.0]],
      "tri"    => [[1.0, 1.0], [3.0, -1.0 / 9], [5.0, 1.0 / 25], [7.0, -1.0 / 49], [9.0, 1.0 / 81]],
      "saw"    => (1..12).map { |k| [k.to_f, 1.0 / k] },
      "square" => [1, 3, 5, 7, 9, 11].map { |k| [k.to_f, 1.0 / k] },
      "bell"   => [[1.0, 1.0], [2.76, 0.5], [5.40, 0.25]]
    }.freeze

    module_function

    # Returns out_dir. Renders any manifest entry missing or stale in out_dir.
    def ensure!(manifest_path, out_dir, sample_rate:)
      manifest = JSON.parse(File.read(manifest_path))
      FileUtils.mkdir_p(out_dir)
      manifest.fetch("tones").each do |name, spec|
        path = File.join(out_dir, "#{name}.wav")
        sig_path = "#{path}.sig"
        sig = entry_signature(spec, sample_rate)
        next if File.exist?(path) && File.exist?(sig_path) && File.read(sig_path) == sig
        samples =
          case spec["type"] || "sine"
          when "sine" then render_sine(spec, sample_rate)
          when "notes" then render_notes(name, spec, sample_rate)
          else raise ArgumentError, "fixtures: #{name} unknown type #{spec['type']}"
          end
        GTA::Wav.write_pcm16(path, samples, channels: 1, sample_rate: sample_rate)
        File.write(sig_path, sig)
      end
      out_dir
    end

    def entry_signature(spec, sample_rate)
      Digest::SHA256.hexdigest("#{JSON.generate(spec)}|sr=#{sample_rate}|v1")
    end

    # The M1 spike formula, unchanged (shared fixture names stay byte-identical).
    def render_sine(tone, sample_rate)
      n = (tone.fetch("dur_s") * sample_rate).round
      freq = tone.fetch("freq_hz")
      amp = tone.fetch("amp")
      phase = tone.fetch("phase")
      Array.new(n) { |i| (amp * 32_767 * Math.sin(2.0 * Math::PI * (freq * i / sample_rate.to_f + phase))).round }
    end

    # Deterministic note-list synthesis. Note fields (all required unless
    # marked): t, dur, freq_hz (ignored for noise), amp (0..1], wave
    # (WAVE_PARTIALS key or "noise"), attack_s, release_s; optional:
    # decay_tau_s (exponential body after the attack), trem {rate_hz, depth},
    # glide_to_hz + glide_s (exponential pitch glide from freq_hz), seed
    # (required for noise). The mixed fixture must stay within [-1, 1] —
    # a hot mix raises instead of wrapping PCM16.
    def render_notes(name, spec, sample_rate)
      dur_s = spec.fetch("dur_s")
      n = (dur_s * sample_rate).round
      gain = spec.fetch("gain", 1.0)
      mix = Array.new(n, 0.0)
      spec.fetch("notes").each_with_index do |note, idx|
        render_note_into(mix, note, "#{name}[#{idx}]", dur_s, sample_rate)
      end
      peak = mix.max_by(&:abs).to_f.abs * gain
      raise ArgumentError, "fixture #{name}: mix peak #{format('%.4f', peak)} > 1.0 — lower note amps in the manifest" if peak > 1.0
      mix.map { |v| (v * gain * 32_767).round }
    end

    def render_note_into(mix, note, label, fixture_dur_s, sr)
      t0 = note.fetch("t")
      dur = note.fetch("dur")
      amp = note.fetch("amp")
      wave = note.fetch("wave")
      attack = note.fetch("attack_s")
      release = note.fetch("release_s")
      raise ArgumentError, "#{label}: t/dur out of fixture bounds" if t0.negative? || dur <= 0 || t0 + dur > fixture_dur_s + 1e-9
      raise ArgumentError, "#{label}: amp must be in (0,1]" unless amp.positive? && amp <= 1.0
      raise ArgumentError, "#{label}: attack_s + release_s must fit inside dur" if attack.negative? || release <= 0 || attack + release > dur

      nn = (dur * sr).round
      start = (t0 * sr).round
      osc = oscillator(note, label, wave, nn, sr)

      tau = note["decay_tau_s"]
      trem = note["trem"]
      trem_rate = trem && trem.fetch("rate_hz")
      trem_depth = trem && trem.fetch("depth")
      sr_f = sr.to_f
      two_pi = 2.0 * Math::PI

      nn.times do |i|
        t = i / sr_f
        env = t < attack ? (attack.zero? ? 1.0 : t / attack) : 1.0
        env *= Math.exp(-(t - attack) / tau) if tau && t > attack
        rem = dur - t
        env *= rem / release if rem < release
        env *= 1.0 - trem_depth * (0.5 - 0.5 * Math.cos(two_pi * trem_rate * t)) if trem
        mix[start + i] += amp * env * osc[i] if start + i < mix.size
      end
    end

    # Peak-normalized oscillator buffer for one note (normalization makes the
    # data's amp field mean "this note's peak", independent of wave richness).
    def oscillator(note, label, wave, nn, sr)
      sr_f = sr.to_f
      if wave == "noise"
        seed = note.fetch("seed") { raise ArgumentError, "#{label}: noise notes require a seed" }
        rng = Random.new(seed)
        return Array.new(nn) { rng.rand * 2.0 - 1.0 }
      end

      partials = WAVE_PARTIALS.fetch(wave) { raise ArgumentError, "#{label}: unknown wave #{wave}" }
      f0 = note.fetch("freq_hz")
      raise ArgumentError, "#{label}: freq_hz must be positive" unless f0.positive?
      glide_to = note["glide_to_hz"]
      glide_s = note["glide_s"]
      raise ArgumentError, "#{label}: glide_to_hz requires glide_s > 0" if glide_to && (glide_s.nil? || glide_s <= 0)
      f_max = [f0, glide_to || f0].max
      audible = partials.select { |mult, _| f_max * mult < sr_f / 2.0 }
      raise ArgumentError, "#{label}: all partials above Nyquist" if audible.empty?

      two_pi = 2.0 * Math::PI
      ratio = glide_to ? glide_to / f0 : 1.0
      phase = 0.0 # cycles of the fundamental
      buf = Array.new(nn) do |i|
        t = i / sr_f
        f = glide_to && t < glide_s ? f0 * (ratio**(t / glide_s)) : (glide_to || f0)
        phase += f / sr_f
        audible.sum { |mult, a| a * Math.sin(two_pi * mult * phase) }
      end
      peak = buf.max_by(&:abs).to_f.abs
      peak.zero? ? buf : buf.map { |v| v / peak }
    end
  end
end
