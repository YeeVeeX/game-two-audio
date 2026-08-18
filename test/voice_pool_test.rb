require "minitest/autorun"
require "json"
require "gta/voice_pool"

# Pure-policy unit tests for the steal chain (no FFI — the pool is deliberately
# free of native calls; integration proof of audible steals is spike 04).
class VoicePoolTest < Minitest::Test
  CONFIG = JSON.parse(File.read(File.expand_path("../data/audio/cues.json", __dir__)))["voice_pool"]

  def make_pool(max: 4)
    GTA::VoicePool.new(max_voices: max, steal_order: CONFIG["steal_order"])
  end

  def test_config_steal_order_is_the_pinned_chain
    assert_equal %w[lowest_priority furthest oldest], CONFIG["steal_order"]
  end

  def test_fills_free_slots_before_stealing
    pool = make_pool
    slots = 4.times.map { pool.acquire(priority: 50)[:slot] }
    assert_equal [0, 1, 2, 3], slots
    assert_equal 4, pool.active_count
  end

  def test_steals_lowest_priority_first
    pool = make_pool
    pool.acquire(priority: 50)
    low = pool.acquire(priority: 10)
    pool.acquire(priority: 50)
    pool.acquire(priority: 50)
    res = pool.acquire(priority: 90)
    assert_equal low[:slot], res[:slot]
    assert_equal 10, res[:stolen][:priority]
  end

  def test_priority_tie_breaks_by_furthest_distance
    pool = make_pool
    pool.acquire(priority: 50, distance: 0.2)
    far = pool.acquire(priority: 50, distance: 0.9)
    pool.acquire(priority: 50, distance: 0.5)
    pool.acquire(priority: 50, distance: 0.1)
    res = pool.acquire(priority: 60, distance: 0.0)
    assert_equal far[:slot], res[:slot]
  end

  def test_full_tie_breaks_by_oldest
    pool = make_pool
    first = pool.acquire(priority: 50, distance: 0.5)
    3.times { pool.acquire(priority: 50, distance: 0.5) }
    res = pool.acquire(priority: 50, distance: 0.5)
    assert_equal first[:slot], res[:slot]
    assert_equal 1, res[:stolen][:order]
  end

  def test_refuses_to_steal_from_higher_priority
    pool = make_pool(max: 2)
    pool.acquire(priority: 90)
    pool.acquire(priority: 90)
    assert_nil pool.acquire(priority: 50)
    assert_equal 2, pool.active_count
  end

  def test_release_frees_the_slot
    pool = make_pool(max: 2)
    a = pool.acquire(priority: 90)
    pool.acquire(priority: 90)
    pool.release(a[:slot])
    res = pool.acquire(priority: 10)
    assert_equal a[:slot], res[:slot]
    assert_nil res[:stolen]
  end
end
