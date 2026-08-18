# gta/native.rb — ruby-ffi binding to the pinned vendor/miniaudio.dll (gta_* shim).
#
# ADR 0001 structural laws enforced by construction here:
#  - Flat functions with primitives/opaque pointers ONLY. No miniaudio struct
#    layout crosses the FFI boundary (see vendor/gta_shim.c header comment).
#  - No Ruby procs are ever registered as callbacks. The audio thread never
#    enters Ruby. Control is poll + schedule-ahead (absolute PCM frames).
#
# Handles:
#  - engine: opaque pointer from gta_engine_create (use_device: 0 offline/noDevice,
#    1 real default device). Destroy sounds BEFORE their engine.
#  - sound:  opaque pointer from gta_sound_create (synchronous full decode:
#    DECODE | NO_PITCH | NO_SPATIALIZATION; 2D control = volume + pan).

require "ffi"

module GTA
  module Native
    extend FFI::Library

    DLL_PATH = File.expand_path("../../vendor/miniaudio.dll", __dir__)
    ffi_lib DLL_PATH

    # diagnostics
    attach_function :gta_version, [], :string
    attach_function :gta_last_result, [], :int

    # engine lifecycle + clock (noDevice mode: caller drives clock via read)
    attach_function :gta_engine_create, [:int, :uint32, :uint32], :pointer
    attach_function :gta_engine_destroy, [:pointer], :void
    attach_function :gta_engine_read_f32, [:pointer, :pointer, :uint64, :pointer], :int
    attach_function :gta_engine_time_pcm, [:pointer], :uint64
    attach_function :gta_engine_sample_rate, [:pointer], :uint32
    attach_function :gta_engine_channels, [:pointer], :uint32

    # sound lifecycle (synchronous full decode at load — determinism precondition)
    attach_function :gta_sound_create, [:pointer, :string], :pointer
    attach_function :gta_sound_destroy, [:pointer], :void

    # immediate controls
    attach_function :gta_sound_start, [:pointer], :int
    attach_function :gta_sound_stop, [:pointer], :int
    attach_function :gta_sound_set_volume, [:pointer, :float], :void
    attach_function :gta_sound_set_pan, [:pointer, :float], :void
    attach_function :gta_sound_set_looping, [:pointer, :int], :void

    # polling (never callbacks)
    attach_function :gta_sound_at_end, [:pointer], :int
    attach_function :gta_sound_is_playing, [:pointer], :int
    attach_function :gta_sound_seek_pcm, [:pointer, :uint64], :int

    # schedule-ahead (absolute engine-clock PCM frames)
    attach_function :gta_sound_set_start_time_pcm, [:pointer, :uint64], :void
    attach_function :gta_sound_set_stop_time_pcm, [:pointer, :uint64], :void
    attach_function :gta_sound_set_stop_time_with_fade_pcm, [:pointer, :uint64, :uint64], :void
    attach_function :gta_sound_set_fade_pcm, [:pointer, :float, :float, :uint64], :void
    attach_function :gta_sound_set_fade_start_pcm, [:pointer, :float, :float, :uint64, :uint64], :void

    # bus graph (M2): sound groups. Groups are started by default and attached
    # to the endpoint (parent NULL) or a parent group — once buses exist the
    # engine graph always produces frames (empty-graph starvation is gone).
    attach_function :gta_group_create, [:pointer, :pointer], :pointer
    attach_function :gta_group_destroy, [:pointer], :void
    attach_function :gta_group_set_volume, [:pointer, :float], :void
    attach_function :gta_group_get_volume, [:pointer], :float
    attach_function :gta_group_set_fade_pcm, [:pointer, :float, :float, :uint64], :void
    attach_function :gta_group_set_fade_start_pcm, [:pointer, :float, :float, :uint64, :uint64], :void
    attach_function :gta_sound_create_in_group, [:pointer, :string, :pointer], :pointer
  end
end
