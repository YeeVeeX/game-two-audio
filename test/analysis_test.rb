require "minitest/autorun"
require "gta/analysis"

# Pure-math unit tests for the M3 presentation metrics (sample peak, over-1.0
# counter, dBFS). The Goertzel/RMS paths are exercised end-to-end by the M1
# spike floor and the gate smoke; these pin the new helpers' edge semantics.
class AnalysisTest < Minitest::Test
  A = GTA::Analysis

  def test_sample_peak_scans_all_channels_by_default
    samples = [0.1, -0.9, 0.5, 0.2] # 2 frames, 2 channels
    assert_in_delta 0.9, A.sample_peak(samples, 0, 2, channels: 2), 1e-12
    assert_in_delta 0.5, A.sample_peak(samples, 0, 2, channels: 2, ch: 0), 1e-12
  end

  def test_sample_peak_respects_the_window
    samples = [0.1, 0.1, 2.0, 2.0, 0.3, 0.3]
    assert_in_delta 0.3, A.sample_peak(samples, 2, 1, channels: 2), 1e-12
  end

  def test_over_count_is_strictly_above_threshold
    samples = [0.5, -1.0, 1.0, 1.0001, -1.5]
    assert_equal 2, A.over_count(samples, 1.0)
    assert_equal 0, A.over_count([0.9999, -0.9999], 1.0)
  end

  def test_dbfs_reference_points
    assert_in_delta 0.0, A.dbfs(1.0), 1e-12
    assert_in_delta(-6.0206, A.dbfs(0.5), 1e-3)
    assert_in_delta(-1.0, A.dbfs(0.8913), 1e-3) # the headroom bound
    assert_equal(-Float::INFINITY, A.dbfs(0.0))
  end
end
