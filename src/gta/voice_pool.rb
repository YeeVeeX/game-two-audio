# gta/voice_pool.rb — fixed-slot voice pool with data-driven steal policy.
#
# Pure policy: no FFI here. The caller owns sound handles and maps slots to
# them; acquire/release return decisions, the caller executes them (stop the
# stolen voice's sound, start the new one). Keeps the pool unit-testable
# without touching the DLL and keeps FFI on the game thread call sites.
#
# Steal chain (from data/audio/cues.json voice_pool.steal_order):
#   "lowest_priority" -> victim candidates = min priority among active voices
#   "furthest"        -> tie-break: max distance
#   "oldest"          -> tie-break: smallest start order (monotonic counter)
# A steal is REFUSED (acquire returns nil) when the best victim outranks the
# incoming cue (victim.priority > incoming priority).

module GTA
  class VoicePool
    Voice = Struct.new(:slot, :priority, :distance, :order, :active)

    attr_reader :max_voices, :steal_order

    def initialize(max_voices:, steal_order:)
      @max_voices = Integer(max_voices)
      @steal_order = steal_order.map(&:to_s).freeze
      unknown = @steal_order - %w[lowest_priority furthest oldest]
      raise ArgumentError, "unknown steal rule(s): #{unknown.join(', ')}" unless unknown.empty?
      @voices = Array.new(@max_voices) { |i| Voice.new(i, 0, 0.0, 0, false) }
      @counter = 0
    end

    def active_count
      @voices.count(&:active)
    end

    # => { slot: Integer, stolen: nil | { slot:, priority:, distance:, order: } }
    #    or nil when the pool is full and no active voice may be stolen.
    def acquire(priority:, distance: 0.0)
      @counter += 1
      free = @voices.find { |v| !v.active }
      if free
        occupy(free, priority, distance)
        return { slot: free.slot, stolen: nil }
      end

      victim = steal_candidate
      return nil if victim.nil? || victim.priority > priority

      stolen = { slot: victim.slot, priority: victim.priority, distance: victim.distance, order: victim.order }
      occupy(victim, priority, distance)
      { slot: victim.slot, stolen: stolen }
    end

    def release(slot)
      @voices.fetch(slot).active = false
    end

    private

    def occupy(voice, priority, distance)
      voice.priority = priority
      voice.distance = distance
      voice.order = @counter
      voice.active = true
    end

    def steal_candidate
      candidates = @voices.select(&:active)
      return nil if candidates.empty?
      @steal_order.each do |rule|
        break if candidates.size == 1
        candidates =
          case rule
          when "lowest_priority" then keep_min(candidates) { |v| v.priority }
          when "furthest"        then keep_max(candidates) { |v| v.distance }
          when "oldest"          then keep_min(candidates) { |v| v.order }
          end
      end
      candidates.first
    end

    def keep_min(voices)
      best = voices.map { |v| yield(v) }.min
      voices.select { |v| yield(v) == best }
    end

    def keep_max(voices)
      best = voices.map { |v| yield(v) }.max
      voices.select { |v| yield(v) == best }
    end
  end
end
