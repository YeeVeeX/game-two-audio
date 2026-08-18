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
#
# Per-category caps (M3; data/audio/cues.json voice_pool.per_category_caps,
# keys ARE bus names — the cue's bus is its category):
#   - acquire(category:) with the category AT its cap steals WITHIN the
#     category using the same chain, candidates restricted to that category —
#     even when free slots exist (a cap is a ceiling, not a reservation).
#     Refused (nil) when the best in-category victim outranks the incoming.
#   - category nil, or a category without a cap entry: global-only behavior,
#     byte-for-byte the M1/M2 contract (spike 04 floor).
#   - The global max always binds on top. Structural consequence (documented,
#     not enforced): with sum(caps) == max_voices a full pool means every
#     category sits exactly at its cap, so the global steal path is only
#     reachable for capless/nil categories.

module GTA
  class VoicePool
    Voice = Struct.new(:slot, :priority, :distance, :order, :active, :category)

    attr_reader :max_voices, :steal_order, :per_category_caps

    def initialize(max_voices:, steal_order:, per_category_caps: nil)
      @max_voices = Integer(max_voices)
      @steal_order = steal_order.map(&:to_s).freeze
      unknown = @steal_order - %w[lowest_priority furthest oldest]
      raise ArgumentError, "unknown steal rule(s): #{unknown.join(', ')}" unless unknown.empty?
      @per_category_caps = validate_caps(per_category_caps)
      @category_counts = Hash.new(0)
      @voices = Array.new(@max_voices) { |i| Voice.new(i, 0, 0.0, 0, false, nil) }
      @counter = 0
    end

    def active_count
      @voices.count(&:active)
    end

    def category_count(category)
      @category_counts[category]
    end

    # => { slot: Integer, stolen: nil | { slot:, priority:, distance:, order: } }
    #    or nil when no slot may be taken (pool/category full and the best
    #    victim outranks the incoming cue).
    def acquire(priority:, distance: 0.0, category: nil)
      @counter += 1

      cap = category && @per_category_caps ? @per_category_caps[category] : nil
      if cap && @category_counts[category] >= cap
        return steal(priority, distance, category, scope: category)
      end

      free = @voices.find { |v| !v.active }
      if free
        occupy(free, priority, distance, category)
        return { slot: free.slot, stolen: nil }
      end

      steal(priority, distance, category, scope: nil)
    end

    def release(slot)
      voice = @voices.fetch(slot)
      if voice.active && voice.category
        @category_counts[voice.category] -= 1
      end
      voice.active = false
    end

    private

    def steal(priority, distance, category, scope:)
      victim = steal_candidate(scope)
      return nil if victim.nil? || victim.priority > priority

      stolen = { slot: victim.slot, priority: victim.priority, distance: victim.distance, order: victim.order }
      @category_counts[victim.category] -= 1 if victim.category
      occupy(victim, priority, distance, category)
      { slot: victim.slot, stolen: stolen }
    end

    def occupy(voice, priority, distance, category)
      voice.priority = priority
      voice.distance = distance
      voice.order = @counter
      voice.active = true
      voice.category = category
      @category_counts[category] += 1 if category
    end

    # scope nil = all active voices (global); scope = category name restricts
    # candidates to that category (in-category steal, same data-driven chain).
    def steal_candidate(scope)
      candidates = @voices.select { |v| v.active && (scope.nil? || v.category == scope) }
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

    def validate_caps(caps)
      return nil if caps.nil?
      caps.each do |cat, cap|
        raise ArgumentError, "per_category_caps: #{cat} must be an Integer >= 1" unless cap.is_a?(Integer) && cap >= 1
      end
      total = caps.values.sum
      if total > @max_voices
        raise ArgumentError, "per_category_caps sum (#{total}) exceeds max_voices (#{@max_voices})"
      end
      caps.freeze
    end
  end
end
