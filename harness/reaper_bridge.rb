# harness/reaper_bridge.rb — minimal client for the Reaper-MCP file-IPC bridge
# (M4b owner production loop).
#
# The bridge is the Lua ReaScript server the midi-writing-mcp project installs
# and auto-starts with REAPER (__startup.lua -> vendor Reaper-MCP
# reaper_mcp_server.lua). Protocol (sampled from that vendor code, the ground
# truth on this machine): write {"command","params"} JSON atomically to
# %TEMP%/reaper_mcp/command.json under the ipc.mutex file lock, poll
# response.json; server.lock mtime is the liveness heartbeat (10 s interval).
#
# This client is deliberately thin: no gems, no MCP layer — the Lua server is
# the API surface. Used by harness/reaper_setup_listen.rb and rake
# reaper:render. All calls are synchronous; renders can take a while, so
# callers pass timeouts explicitly.
#
# Scripts: script_run_start registers+runs <REAPER resource>/Scripts/<name>
# and the script reports back via
# reaper.SetExtState("reaper_mcp_script_result", "last_result", <string>);
# run_script! wraps the start+poll pair.

require "json"

module GTA
  module ReaperBridge
    BridgeError = Class.new(StandardError)
    HEARTBEAT_STALE_S = 60

    module_function

    def ipc_dir
      temp = ENV["TEMP"] or raise BridgeError, "no TEMP env var"
      File.join(temp.tr("\\", "/"), "reaper_mcp")
    end

    def scripts_dir
      appdata = ENV["APPDATA"] or raise BridgeError, "no APPDATA env var"
      dir = File.join(appdata.tr("\\", "/"), "REAPER", "Scripts")
      raise BridgeError, "REAPER Scripts dir not found at #{dir}" unless File.directory?(dir)
      dir
    end

    # [alive, reason]
    def status
      lock = File.join(ipc_dir, "server.lock")
      return [false, "no server.lock at #{lock} — is REAPER open with the bridge loaded?"] unless File.exist?(lock)
      age = Time.now - File.mtime(lock)
      return [false, format("server.lock heartbeat stale (%.0f s > %d s) — restart REAPER?", age, HEARTBEAT_STALE_S)] if age > HEARTBEAT_STALE_S
      [true, "ok"]
    end

    def assert_alive!
      alive, reason = status
      raise BridgeError, "bridge down: #{reason}" unless alive
    end

    # Sends one command, returns the response "data" hash (or the whole
    # response when no data envelope). Raises BridgeError on error/timeout.
    def call!(command, params = {}, timeout: 15)
      dir = ipc_dir
      cmd = File.join(dir, "command.json")
      cmd_tmp = File.join(dir, "command.tmp")
      rsp = File.join(dir, "response.json")
      File.open(File.join(dir, "ipc.mutex"), "a") do |mx|
        mx.flock(File::LOCK_EX)
        [cmd, rsp].each { |f| File.delete(f) if File.exist?(f) }
        File.write(cmd_tmp, JSON.generate({ "command" => command, "params" => params }))
        File.rename(cmd_tmp, cmd)
        deadline = Time.now + timeout
        while Time.now < deadline
          if File.exist?(rsp)
            raw = begin
              File.read(rsp, encoding: "utf-8")
            rescue StandardError
              ""
            end
            unless raw.empty?
              parsed = begin
                JSON.parse(raw)
              rescue JSON::ParserError
                nil # mid-write; keep polling
              end
              if parsed
                unless parsed["success"]
                  raise BridgeError, "#{command}: #{parsed['error'] || parsed.inspect}"
                end
                return parsed.key?("data") ? parsed["data"] : parsed
              end
            end
          end
          sleep 0.1
        end
        raise BridgeError, "#{command}: no response within #{timeout} s (a REAPER dialog may be waiting for a click)"
      end
    end

    # Runs Scripts/<script_name> and returns its ExtState result string.
    def run_script!(script_name, timeout: 30)
      call!("script_run_start", { "script_path" => script_name })
      deadline = Time.now + timeout
      while Time.now < deadline
        r = call!("script_read_result")
        value = r.is_a?(Hash) ? (r["value"] || r.dig("data", "value")) : nil
        return value if value && !value.empty?
        sleep 0.25
      end
      raise BridgeError, "script #{script_name}: no result within #{timeout} s"
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  command = ARGV[0] or abort "usage: reaper_bridge.rb <command> ['{\"param\":...}'] [timeout_s]"
  params = ARGV[1] ? JSON.parse(ARGV[1]) : {}
  timeout = (ARGV[2] || 15).to_f
  alive, reason = GTA::ReaperBridge.status
  abort "bridge down: #{reason}" unless alive
  puts JSON.pretty_generate(GTA::ReaperBridge.call!(command, params, timeout: timeout))
end
