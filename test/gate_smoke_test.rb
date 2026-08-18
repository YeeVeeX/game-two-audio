require "minitest/autorun"
require_relative "../harness/gate_runner"

# Gate smoke in the default suite: a mini replay through the REAL gate code
# path (GTA::Gate::Runner — same class rake gate uses). Heavy replays stay
# under rake gate; this keeps the hook suite fast while proving the harness.
class GateSmokeTest < Minitest::Test
  def test_mini_replay_passes_the_full_gate
    result = GTA::Gate::Runner.new(
      File.expand_path("replays/mini_smoke.json", __dir__),
      data_dir: File.expand_path("../data/audio", __dir__),
      fixture_dir: File.expand_path("../tmp/fixtures", __dir__),
      out_dir: File.expand_path("../tmp/gate", __dir__)
    ).run

    assert result.render_match, "double render not byte-identical"
    assert result.log_match, "command log md5 differs between renders"
    result.checks.each { |c| assert c.pass, "#{c.label}: #{c.detail}" }
    assert result.pass?
    assert(result.checks.any? { |c| c.label.start_with?("log ") }, "log expectation type not exercised")
    assert(result.checks.any? { |c| c.label.start_with?("peak ") }, "peak expectation type not exercised")
    assert_operator result.metrics[:peak], :>, 0.1, "metrics block missing or silent render"
    assert_equal 0, result.metrics[:over_1]
    assert File.exist?(File.expand_path("../tmp/gate/mini_smoke.wav", __dir__))
    assert File.exist?(File.expand_path("../tmp/gate/mini_smoke.log", __dir__))
  end

  # Listen-track harness contract (M4): expectation_types filters the checks
  # to material-independent types; run_listen.rb relies on this to reuse the
  # gate replays against musical fixtures without the sine-tuned pins.
  def test_expectation_types_filter_keeps_only_requested_checks
    result = GTA::Gate::Runner.new(
      File.expand_path("replays/mini_smoke.json", __dir__),
      data_dir: File.expand_path("../data/audio", __dir__),
      fixture_dir: File.expand_path("../tmp/fixtures", __dir__),
      out_dir: File.expand_path("../tmp/gate", __dir__),
      expectation_types: %w[peak]
    ).run

    assert result.render_match && result.log_match, "determinism must still assert under the filter"
    refute_empty result.checks, "peak checks missing (mini_smoke should carry one)"
    result.checks.each do |c|
      assert c.label.start_with?("peak "), "non-peak check leaked through the filter: #{c.label}"
      assert c.pass, "#{c.label}: #{c.detail}"
    end
  end
end
