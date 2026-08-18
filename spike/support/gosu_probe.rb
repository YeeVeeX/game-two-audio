# spike/support/gosu_probe.rb — child process for spike 02. Modes (ARGV[0]):
#
#   entry        SDL_AUDIODRIVER=dummy set at PROCESS ENTRY, before require
#                "gosu" (the ADR claim). Boots a real Gosu window, renders
#                frames, plays a Gosu::Sample through mojoAL/SDL, runs
#                miniaudio on the REAL device concurrently, then reports.
#   control      No env override. Reports which driver SDL picks naturally
#                (must be a real one, or "dummy" would prove nothing).
#   post_require SDL_AUDIODRIVER=dummy set AFTER require "gosu" but before
#                first audio init — the timing probe (knowledge correction).
#
# Output: KEY=VALUE lines on stdout; parent parses. Exit 0 = probe completed.

MODE = ARGV[0] || "entry"
ENV["SDL_AUDIODRIVER"] = "dummy" if MODE == "entry" # before ANY require

require "gosu"

ENV["SDL_AUDIODRIVER"] = "dummy" if MODE == "post_require" # after require, before audio init

$LOAD_PATH.unshift File.expand_path("../../src", __dir__)
require "gta/native"
require "gta/wav"
require "ffi"
require "fileutils"

Thread.new { sleep 20; puts "WATCHDOG=timeout"; exit!(3) } # never wedge rake spike

module SDLProbe
  extend FFI::Library
  ffi_lib File.join(Gem::Specification.find_by_name("gosu").gem_dir, "lib64", "SDL2.dll")
  attach_function :SDL_GetCurrentAudioDriver, [], :string
  attach_function :SDL_WasInit, [:uint32], :uint32
end
SDL_INIT_AUDIO = 0x10

FIXTURES = File.expand_path("../../tmp/fixtures", __dir__)
FileUtils.mkdir_p(FIXTURES)
tone = File.join(FIXTURES, "tone_0440_probe.wav")
unless File.exist?(tone)
  samples = (0...28_800).map { |i| (0.4 * 32_767 * Math.sin(2.0 * Math::PI * 440.0 * i / 48_000.0)).round }
  GTA::Wav.write_pcm16(tone, samples, channels: 1, sample_rate: 48_000) # 0.6 s
end

puts "MODE=#{MODE}"
puts "GOSU_VERSION=#{Gosu::VERSION}"

if MODE == "entry"
  # miniaudio owns the REAL device (single-owner architecture).
  engine = GTA::Native.gta_engine_create(1, 2, 48_000)
  puts "MA_ENGINE=#{engine.null? ? "fail:#{GTA::Native.gta_last_result}" : 'ok'}"
  exit(2) if engine.null?
  sound = GTA::Native.gta_sound_create(engine, tone)
  puts "MA_SOUND=#{sound.null? ? "fail:#{GTA::Native.gta_last_result}" : 'ok'}"
  exit(2) if sound.null?
  ma_t0 = GTA::Native.gta_engine_time_pcm(engine)
  GTA::Native.gta_sound_start(sound)

  class ProbeWindow < Gosu::Window
    attr_reader :updates, :draws

    def initialize(gosu_tone)
      super(320, 240, fullscreen: false, update_interval: 16.66)
      self.caption = "spike02 probe"
      @updates = 0
      @draws = 0
      @sample = Gosu::Sample.new(gosu_tone) # forces mojoAL/SDL audio init
    end

    def update
      @updates += 1
      @sample.play(0.3) if @updates == 3 # silent under dummy; must not crash
      close! if @updates >= 60
    end

    def draw
      @draws += 1
      Gosu.draw_rect(20, 20, 280, 200, Gosu::Color::GREEN)
    end
  end

  w = ProbeWindow.new(tone)
  w.show
  puts "WINDOW_UPDATES=#{w.updates}"
  puts "WINDOW_DRAWS=#{w.draws}"
  puts "SDL_AUDIO_WASINIT=#{SDLProbe.SDL_WasInit(SDL_INIT_AUDIO) & SDL_INIT_AUDIO}"
  puts "SDL_DRIVER=#{SDLProbe.SDL_GetCurrentAudioDriver || '(none)'}"
  puts "MA_TIME_DELTA=#{GTA::Native.gta_engine_time_pcm(engine) - ma_t0}"
  puts "MA_AT_END=#{GTA::Native.gta_sound_at_end(sound)}"
  GTA::Native.gta_sound_destroy(sound)
  GTA::Native.gta_engine_destroy(engine)
else
  sample = Gosu::Sample.new(tone) # forces SDL audio init, no window needed
  channel = sample.play(0.05)
  sleep 0.3
  puts "SAMPLE_PLAYING=#{channel&.playing? ? 1 : 0}"
  puts "SDL_AUDIO_WASINIT=#{SDLProbe.SDL_WasInit(SDL_INIT_AUDIO) & SDL_INIT_AUDIO}"
  puts "SDL_DRIVER=#{SDLProbe.SDL_GetCurrentAudioDriver || '(none)'}"
end

puts "PROBE=done"
exit 0
