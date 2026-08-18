# gta/command_io.rb — the single choke point between AudioSystem and the FFI.
#
# Every engine command AudioSystem issues goes through one CommandIO method,
# which ALWAYS forwards to GTA::Native and, when a CommandLog is attached,
# appends one line per command. Same code path drives FFI and log, so the log
# cannot lie about what was issued.
#
# Modes (gate design, ADR decision 5):
#  - production (log nil): pure forwarding — zero Ruby allocations on the
#    steady-state path (proven by the scaling test, spike-03 pattern);
#  - gate (log attached): allocations tolerated, FFI behavior identical —
#    recorder-equivalence is integration-tested (same replay, recorder on vs
#    off, byte-identical render).
#
# Log line grammar (one command per line):
#   <frame> <op> <handle_id> <args>   # <human>
# Canonical part = everything before ' #'. Floats are serialized as IEEE-754
# f32 hex bits (exactly what crosses the FFI boundary); the bit-exact md5
# rides the canonical part only — the '%.9g' human column is decoration.
# Handle ids are mechanical (sound_007, bus_music, stem_a) — machine paths
# never enter the log.

require "digest"
require_relative "native"

module GTA
  class CommandLog
    def initialize
      @canonical = +""
      @pretty = +""
    end

    def add(frame, op, id, args, human)
      line = "#{frame} #{op} #{id} #{args}"
      @canonical << line << "\n"
      @pretty << line
      @pretty << "   # " << human unless human.empty?
      @pretty << "\n"
    end

    def md5
      Digest::MD5.hexdigest(@canonical)
    end

    def lines
      @canonical.lines
    end

    def write(path)
      File.binwrite(path, @pretty)
    end
  end

  class CommandIO
    N = GTA::Native

    attr_accessor :frame
    attr_reader :log

    def initialize(log: nil)
      @log = log
      @frame = 0
    end

    # -- lifecycle ---------------------------------------------------------

    def group_create(id, engine, parent, parent_id)
      g = N.gta_group_create(engine, parent)
      raise "group create failed (#{id}): ma_result #{N.gta_last_result}" if g.null?
      @log&.add(@frame, "group_create", id, parent_id, "")
      g
    end

    def group_destroy(id, group)
      N.gta_group_destroy(group)
      @log&.add(@frame, "group_destroy", id, "-", "")
      nil
    end

    def sound_create_in_group(id, engine, path, file_key, group, group_id)
      s = N.gta_sound_create_in_group(engine, path, group)
      raise "sound load failed (#{id}: #{file_key}): ma_result #{N.gta_last_result}" if s.null?
      @log&.add(@frame, "sound_load", id, "#{file_key},#{group_id}", "")
      s
    end

    def sound_destroy(id, sound)
      N.gta_sound_destroy(sound)
      @log&.add(@frame, "sound_destroy", id, "-", "")
      nil
    end

    # -- immediate controls ------------------------------------------------

    def sound_start(id, sound)
      N.gta_sound_start(sound)
      @log&.add(@frame, "sound_start", id, "-", "")
      nil
    end

    def sound_stop(id, sound)
      N.gta_sound_stop(sound)
      @log&.add(@frame, "sound_stop", id, "-", "")
      nil
    end

    def sound_set_volume(id, sound, v)
      N.gta_sound_set_volume(sound, v)
      @log&.add(@frame, "sound_set_volume", id, fhex(v), fhum(v))
      nil
    end

    def sound_set_pan(id, sound, v)
      N.gta_sound_set_pan(sound, v)
      @log&.add(@frame, "sound_set_pan", id, fhex(v), fhum(v))
      nil
    end

    def sound_set_looping(id, sound, flag)
      N.gta_sound_set_looping(sound, flag)
      @log&.add(@frame, "sound_set_looping", id, flag.to_s, "")
      nil
    end

    def sound_seek_pcm(id, sound, to_frame)
      N.gta_sound_seek_pcm(sound, to_frame)
      @log&.add(@frame, "sound_seek", id, to_frame.to_s, "")
      nil
    end

    def group_set_volume(id, group, v)
      N.gta_group_set_volume(group, v)
      @log&.add(@frame, "group_set_volume", id, fhex(v), fhum(v))
      nil
    end

    # -- schedule-ahead (absolute engine-clock PCM frames) -------------------

    def sound_set_start_time_pcm(id, sound, t)
      N.gta_sound_set_start_time_pcm(sound, t)
      @log&.add(@frame, "sound_start_at", id, t.to_s, "")
      nil
    end

    def sound_set_stop_time_pcm(id, sound, t)
      N.gta_sound_set_stop_time_pcm(sound, t)
      @log&.add(@frame, "sound_stop_at", id, t.to_s, "")
      nil
    end

    def sound_set_stop_time_with_fade_pcm(id, sound, stop, fade_len)
      N.gta_sound_set_stop_time_with_fade_pcm(sound, stop, fade_len)
      @log&.add(@frame, "sound_stop_fade_at", id, "#{stop},#{fade_len}", "")
      nil
    end

    def sound_set_fade_start_pcm(id, sound, beg, fin, len, abs_start)
      N.gta_sound_set_fade_start_pcm(sound, beg, fin, len, abs_start)
      @log&.add(@frame, "sound_fade_at", id, "#{fhex(beg)},#{fhex(fin)},#{len},#{abs_start}", "#{fhum(beg)} -> #{fhum(fin)}")
      nil
    end

    def group_set_fade_start_pcm(id, group, beg, fin, len, abs_start)
      N.gta_group_set_fade_start_pcm(group, beg, fin, len, abs_start)
      @log&.add(@frame, "group_fade_at", id, "#{fhex(beg)},#{fhex(fin)},#{len},#{abs_start}", "#{fhum(beg)} -> #{fhum(fin)}")
      nil
    end

    private

    # IEEE-754 f32 bits, little-endian hex — the value that crosses the FFI.
    def fhex(v)
      [v].pack("e").unpack1("H8")
    end

    def fhum(v)
      format("%.9g", v)
    end
  end
end
