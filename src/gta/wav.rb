# gta/wav.rb — minimal WAV I/O for fixtures and render artifacts. No gems.
#
# Writers: PCM16 (fixture tones fed to miniaudio) and IEEE float32 (render
# artifacts; 18-byte fmt chunk + fact chunk per spec). Reader handles both.

module GTA
  module Wav
    module_function

    # samples: interleaved Integer array (-32768..32767)
    def write_pcm16(path, samples, channels:, sample_rate:)
      data = samples.pack("s<*")
      block_align = channels * 2
      File.binwrite(path, [
        "RIFF", 36 + data.bytesize, "WAVE",
        "fmt ", 16, 1, channels, sample_rate, sample_rate * block_align, block_align, 16,
        "data", data.bytesize
      ].pack("a4Va4a4VvvVVvva4V") + data)
    end

    # data: binary String of interleaved little-endian float32 frames
    def write_f32(path, data, channels:, sample_rate:)
      block_align = channels * 4
      frames = data.bytesize / block_align
      File.binwrite(path, [
        "RIFF", 12 + 26 + 12 + data.bytesize, "WAVE",
        "fmt ", 18, 3, channels, sample_rate, sample_rate * block_align, block_align, 32, 0,
        "fact", 4, frames,
        "data", data.bytesize
      ].pack("a4Va4a4VvvVVvvva4VVa4V") + data)
    end

    # Returns { format:, channels:, sample_rate:, bits:, data: <binary String> }
    def read(path)
      raw = File.binread(path)
      raise ArgumentError, "not RIFF/WAVE: #{path}" unless raw[0, 4] == "RIFF" && raw[8, 4] == "WAVE"
      pos = 12
      fmt = nil
      data = nil
      while pos + 8 <= raw.bytesize
        cid = raw[pos, 4]
        csz = raw[pos + 4, 4].unpack1("V")
        body = raw[pos + 8, csz]
        case cid
        when "fmt " then fmt = body.unpack("vvVVvv") # tag, ch, rate, byterate, align, bits
        when "data" then data = body
        end
        pos += 8 + csz + (csz.odd? ? 1 : 0)
      end
      raise ArgumentError, "missing fmt/data chunk: #{path}" if fmt.nil? || data.nil?
      { format: fmt[0], channels: fmt[1], sample_rate: fmt[2], bits: fmt[5], data: data }
    end

    # Returns interleaved Float samples (f32 or pcm16 sources normalized to -1..1)
    def read_samples(path)
      w = read(path)
      case [w[:format], w[:bits]]
      when [3, 32] then w[:data].unpack("e*")
      when [1, 16] then w[:data].unpack("s<*").map { |s| s / 32768.0 }
      else raise ArgumentError, "unsupported wav format #{w[:format]}/#{w[:bits]}: #{path}"
      end
    end
  end
end
