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

  # -- per-category caps (M3): category = the cue's bus ---------------------

  def make_capped_pool(max:, caps:)
    GTA::VoicePool.new(max_voices: max, steal_order: CONFIG["steal_order"], per_category_caps: caps)
  end

  def test_shipped_caps_are_bus_scoped_and_fit_the_pool
    caps = CONFIG["per_category_caps"]
    buses = JSON.parse(File.read(File.expand_path("../data/audio/cues.json", __dir__)))["buses"]
    refute_nil caps
    caps.each_key { |cat| assert buses.key?(cat), "cap key #{cat} is not a declared bus" }
    assert caps.values.all? { |c| c >= 1 }
    assert_operator caps.values.sum, :<=, CONFIG["max_voices"]
  end

  def test_category_at_cap_steals_within_category_despite_free_slots
    pool = make_capped_pool(max: 8, caps: { "ui" => 2 })
    low = pool.acquire(priority: 50, category: "ui")
    pool.acquire(priority: 60, category: "ui")
    res = pool.acquire(priority: 70, category: "ui")
    assert_equal low[:slot], res[:slot], "must steal in-category even with 6 free slots"
    assert_equal 50, res[:stolen][:priority]
    assert_equal 2, pool.active_count
    assert_equal 2, pool.category_count("ui")
  end

  def test_in_category_steal_ignores_the_global_best_victim
    pool = make_capped_pool(max: 8, caps: { "ui" => 2, "sfx" => 4 })
    global_best = pool.acquire(priority: 5, category: "sfx") # global chain would pick this
    ui_victim = pool.acquire(priority: 50, category: "ui")
    pool.acquire(priority: 60, category: "ui")
    res = pool.acquire(priority: 70, category: "ui")
    assert_equal ui_victim[:slot], res[:slot], "victim must come from the incoming cue's category"
    refute_equal global_best[:slot], res[:slot]
    assert_equal 1, pool.category_count("sfx")
  end

  def test_category_refuses_when_best_in_category_victim_outranks
    pool = make_capped_pool(max: 8, caps: { "ui" => 2 })
    pool.acquire(priority: 90, category: "ui")
    pool.acquire(priority: 90, category: "ui")
    assert_nil pool.acquire(priority: 50, category: "ui"), "cap must refuse, not spill into free slots"
    assert_equal 2, pool.active_count
    assert_equal 2, pool.category_count("ui")
  end

  def test_in_category_steal_uses_the_same_chain
    pool = make_capped_pool(max: 8, caps: { "sfx" => 3 })
    pool.acquire(priority: 50, distance: 0.2, category: "sfx")
    far_old = pool.acquire(priority: 50, distance: 0.9, category: "sfx")
    pool.acquire(priority: 50, distance: 0.9, category: "sfx")
    res = pool.acquire(priority: 60, distance: 0.0, category: "sfx")
    assert_equal far_old[:slot], res[:slot], "chain inside category: priority tie -> furthest tie -> oldest"
  end

  def test_release_decrements_the_category_count
    pool = make_capped_pool(max: 4, caps: { "ui" => 2 })
    a = pool.acquire(priority: 50, category: "ui")
    pool.acquire(priority: 60, category: "ui")
    pool.release(a[:slot])
    assert_equal 1, pool.category_count("ui")
    res = pool.acquire(priority: 40, category: "ui")
    assert_nil res[:stolen], "freed cap headroom must admit without stealing"
    assert_equal 2, pool.category_count("ui")
  end

  def test_under_cap_category_global_steals_when_pool_is_full
    pool = make_capped_pool(max: 2, caps: { "ui" => 2 })
    sfx_low = pool.acquire(priority: 50, category: "sfx") # capless category
    pool.acquire(priority: 60, category: "sfx")
    res = pool.acquire(priority: 90, category: "ui") # ui under cap, pool full
    assert_equal sfx_low[:slot], res[:slot], "global chain applies when the category is under cap"
    assert_equal 1, pool.category_count("ui")
    assert_equal 1, pool.category_count("sfx")
  end

  def test_nil_category_with_caps_configured_uses_the_global_chain
    pool = make_capped_pool(max: 2, caps: { "ui" => 1, "sfx" => 1 })
    ui_low = pool.acquire(priority: 50, category: "ui")
    pool.acquire(priority: 60, category: "sfx")
    res = pool.acquire(priority: 90)
    assert_equal ui_low[:slot], res[:slot]
    assert_equal 0, pool.category_count("ui")
  end

  def test_cap_validation_rejects_zero_and_oversubscription
    assert_raises(ArgumentError) { make_capped_pool(max: 4, caps: { "ui" => 0 }) }
    assert_raises(ArgumentError) { make_capped_pool(max: 4, caps: { "ui" => 3, "sfx" => 2 }) }
  end
end
