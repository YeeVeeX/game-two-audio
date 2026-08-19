require "minitest/autorun"
require_relative "../harness/reaper_bridge"

# Live-bridge integration test (M4b): real Reaper or skip loudly — no mocks
# (law 5). Read-only commands only: other sessions' open projects are owner
# documents.
class ReaperBridgeTest < Minitest::Test
  def test_bridge_answers_project_get_info
    alive, reason = GTA::ReaperBridge.status
    skip "reaper bridge not up (#{reason}) — open REAPER to exercise this" unless alive
    info = GTA::ReaperBridge.call!("project_get_info")
    %w[track_count bpm sample_rate file_path].each do |k|
      assert info.key?(k), "project_get_info missing #{k} (got #{info.keys.sort.join(', ')})"
    end
  end
end
