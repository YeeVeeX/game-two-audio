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
    assert File.exist?(File.expand_path("../tmp/gate/mini_smoke.wav", __dir__))
    assert File.exist?(File.expand_path("../tmp/gate/mini_smoke.log", __dir__))
  end
end
