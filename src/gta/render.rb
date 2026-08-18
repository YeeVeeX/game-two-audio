# gta/render.rb — offline render loop for the noDevice gate engine.
#
# Fixed chunk cadence (same read pattern every render — the same-machine
# determinism contract from spike 01). Buffers preallocated; advancing without
# capture performs zero Ruby allocations (steady-state law), capturing appends
# raw f32 bytes to the caller's binary String.
#
# Since the bus graph exists (started-by-default groups attached to the
# endpoint), reads never starve — the graph renders exact silence when idle
# (pinned in native_smoke_test).

require_relative "native"

module GTA
  class Renderer
    def initialize(engine, channels:, chunk: 512)
      @engine = engine
      @channels = channels
      @chunk = chunk
      @buf = FFI::MemoryPointer.new(:float, chunk * channels)
      @read = FFI::MemoryPointer.new(:uint64)
    end

    # Advance the engine clock by total_frames. capture: binary String to
    # append interleaved f32 frames to, or nil to discard (alloc-free).
    def advance(total_frames, capture: nil)
      remaining = total_frames
      while remaining > 0
        n = remaining < @chunk ? remaining : @chunk
        result = Native.gta_engine_read_f32(@engine, @buf, n, @read)
        raise "engine read failed: ma_result #{result}" unless result.zero?
        got = @read.read_uint64
        raise "engine read returned #{got}/#{n} frames — graph starved" if got != n
        capture << @buf.get_bytes(0, n * @channels * 4) if capture
        remaining -= n
      end
      nil
    end
  end
end
