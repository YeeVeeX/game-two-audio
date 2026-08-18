# gta/fixtures.rb — render the generated-tone fixture manifest to WAV files.
#
# Same deterministic formula as the M1 spike fixtures (byte-identical for
# shared names): amp * 32767 * sin(2*pi*(freq*i/sr + phase)), PCM16 mono.
# No third-party audio, ever. Existing files are kept (content is a pure
# function of the manifest entry, so regeneration is idempotent).

require "json"
require "fileutils"
require_relative "wav"

module GTA
  module Fixtures
    module_function

    # Returns out_dir. Renders any manifest tone missing from out_dir.
    def ensure!(manifest_path, out_dir, sample_rate:)
      manifest = JSON.parse(File.read(manifest_path))
      FileUtils.mkdir_p(out_dir)
      manifest.fetch("tones").each do |name, tone|
        path = File.join(out_dir, "#{name}.wav")
        next if File.exist?(path)
        n = (tone.fetch("dur_s") * sample_rate).round
        freq = tone.fetch("freq_hz")
        amp = tone.fetch("amp")
        phase = tone.fetch("phase")
        samples = Array.new(n) { |i| (amp * 32_767 * Math.sin(2.0 * Math::PI * (freq * i / sample_rate.to_f + phase))).round }
        GTA::Wav.write_pcm16(path, samples, channels: 1, sample_rate: sample_rate)
      end
      out_dir
    end
  end
end
