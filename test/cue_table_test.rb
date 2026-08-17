require "minitest/autorun"
require "json"

# Day-1 smoke: the cue table is valid JSON and carries the ADR-mandated structure.
# Real integration tests (real DLL, real render — no mocks) arrive with M1.
class CueTableTest < Minitest::Test
  DATA = JSON.parse(File.read(File.expand_path("../data/audio/cues.json", __dir__)))

  def test_buses_form_a_master_rooted_tree
    assert DATA["buses"].key?("master")
    DATA["buses"]["master"]["children"].each { |c| assert DATA["buses"].key?(c), "undeclared bus #{c}" }
  end

  def test_voice_pool_caps_do_not_exceed_max
    pool = DATA["voice_pool"]
    assert pool["per_category_caps"].values.sum <= pool["max_voices"]
  end

  def test_cues_reference_declared_buses
    DATA["cues"].each do |name, cue|
      assert DATA["buses"].key?(cue["bus"]), "cue #{name} references undeclared bus"
    end
  end
end
