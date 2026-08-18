# gta/analysis.rb — offline-render feature analysis (pure math, no FFI).
#
# Promoted verbatim from spike/support/common.rb in M2 (the spike delegates
# here — the M1 floor keeps running through the same arithmetic). Used by the
# gate harness for RMS windows, Goertzel cue presence/timing, and fade fits.

module GTA
  module Analysis
    module_function

    # samples: interleaved Float array; window in FRAMES over channel ch
    # (ch nil = all channels pooled).
    def rms(samples, from_frame, frames, channels:, ch: nil)
      acc = 0.0
      count = 0
      frames.times do |i|
        base = (from_frame + i) * channels
        if ch
          v = samples[base + ch] || 0.0
          acc += v * v
          count += 1
        else
          channels.times do |c|
            v = samples[base + c] || 0.0
            acc += v * v
            count += 1
          end
        end
      end
      Math.sqrt(acc / count)
    end

    # Goertzel single-bin amplitude of freq over [from_frame, from_frame+frames)
    # on channel ch. Returns sine peak amplitude estimate (2*|X|/N).
    def goertzel_amp(samples, freq, from_frame, frames, channels:, ch: 0, sr:)
      w = 2.0 * Math::PI * freq / sr
      coeff = 2.0 * Math.cos(w)
      s0 = 0.0
      s1 = 0.0
      s2 = 0.0
      frames.times do |i|
        x = samples[(from_frame + i) * channels + ch] || 0.0
        s0 = x + coeff * s1 - s2
        s2 = s1
        s1 = s0
      end
      power = s1 * s1 + s2 * s2 - coeff * s1 * s2
      2.0 * Math.sqrt(power.abs) / frames
    end

    # Max |sample| over the window (SAMPLE peak, not oversampled dBTP true
    # peak — stated honestly; generated pure tones keep inter-sample overshoot
    # small, and real assets arrive with their own -1 dBTP ceiling from the
    # game-two-assets pipeline). ch nil = max across all channels.
    def sample_peak(samples, from_frame, frames, channels:, ch: nil)
      best = 0.0
      frames.times do |i|
        base = (from_frame + i) * channels
        if ch
          v = (samples[base + ch] || 0.0).abs
          best = v if v > best
        else
          c = 0
          while c < channels
            v = (samples[base + c] || 0.0).abs
            best = v if v > best
            c += 1
          end
        end
      end
      best
    end

    # Samples strictly above the threshold in magnitude (f32 legality counter:
    # >1.0 is legal in an f32 WAV but clips on any integer/DAC path).
    def over_count(samples, threshold)
      samples.count { |s| s.abs > threshold }
    end

    def dbfs(x)
      return -Float::INFINITY if x <= 0.0
      20.0 * Math.log10(x)
    end

    # Least-squares line fit: ys over xs => [slope, intercept]
    def linear_fit(xs, ys)
      n = xs.size.to_f
      sx = xs.sum(0.0)
      sy = ys.sum(0.0)
      sxx = xs.sum(0.0) { |x| x * x }
      sxy = 0.0
      xs.each_index { |i| sxy += xs[i] * ys[i] }
      slope = (n * sxy - sx * sy) / (n * sxx - sx * sx)
      [slope, (sy - slope * sx) / n]
    end
  end
end
