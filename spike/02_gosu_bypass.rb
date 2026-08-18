# M1 spike 02 — ADR 0001 falsification item 2: Gosu boots silent under
# SDL_AUDIODRIVER=dummy (set at process entry), miniaudio owns the real device,
# the game window renders normally, nothing crashes.
#
# Three child scenarios (spike/support/gosu_probe.rb), each its own process
# because the env-var timing IS the thing under test:
#   control      — no override: SDL must pick a REAL driver (otherwise "dummy"
#                  proves nothing on this machine).
#   entry        — the ADR claim: env at process entry => SDL audio inits on
#                  the dummy backend WHILE a Gosu window renders and miniaudio
#                  plays a tone on the real WASAPI device in the same process.
#   post_require — timing probe: env set AFTER require "gosu" but BEFORE first
#                  audio init. Not load-bearing for the ADR; the verdict is a
#                  knowledge-repo correction candidate either way.
#
# PASS: control driver real + entry scenario fully green (window frames,
# SDL=dummy, miniaudio device engine advancing). Requires the :spike bundler
# group (gosu 1.4.6) and a desktop session.

require_relative "support/common"
require "open3"
require "rbconfig"

Spike.banner("02 gosu bypass via SDL_AUDIODRIVER=dummy")

begin
  Gem::Specification.find_by_name("gosu")
rescue Gem::MissingSpecError
  Spike.fail!("gosu gem not installed — run: bundle install (spike group)")
end

PROBE = File.expand_path("support/gosu_probe.rb", __dir__)
RUBY = RbConfig.ruby

def run_probe(mode, env = {})
  out, status = Open3.capture2e(env, RUBY, PROBE, mode)
  kv = out.scan(/^([A-Z_]+)=(.*)$/).to_h
  puts "  [#{mode}] exit=#{status.exitstatus} #{kv.map { |k, v| "#{k.downcase}=#{v}" }.join(' ')}"
  [kv, status]
end

# Scenario 1: control — what does SDL pick with no override?
control, control_status = run_probe("control", { "SDL_AUDIODRIVER" => nil })
Spike.check(control_status.success?, "control probe completed")
Spike.check(control["SDL_AUDIO_WASINIT"].to_i != 0, "control: SDL audio subsystem initialized")
Spike.check(control["SDL_DRIVER"] != "dummy" && control["SDL_DRIVER"] != "(none)",
            "control: SDL picks a real driver without override (got #{control['SDL_DRIVER'].inspect})")

# Scenario 2: entry — the ADR claim under falsification.
entry, entry_status = run_probe("entry", { "SDL_AUDIODRIVER" => nil })
Spike.check(entry_status.success?, "entry probe completed (no crash)")
Spike.check(entry["WINDOW_UPDATES"].to_i >= 60, "Gosu window ran 60 update ticks (got #{entry['WINDOW_UPDATES']})")
Spike.check(entry["WINDOW_DRAWS"].to_i > 0, "Gosu window rendered frames (got #{entry['WINDOW_DRAWS']})")
Spike.check(entry["SDL_AUDIO_WASINIT"].to_i != 0, "entry: SDL audio subsystem initialized (Gosu::Sample built)")
Spike.check(entry["SDL_DRIVER"] == "dummy", "entry: SDL audio driver is 'dummy' (got #{entry['SDL_DRIVER'].inspect})")
Spike.check(entry["MA_ENGINE"] == "ok", "entry: miniaudio opened the real device alongside silent Gosu")
Spike.check(entry["MA_TIME_DELTA"].to_i > 24_000, "entry: real device pumped the engine clock (#{entry['MA_TIME_DELTA']} frames over ~1s of window time)")
Spike.check(entry["MA_AT_END"] == "1", "entry: miniaudio tone played to completion on the device")

# Scenario 3: post-require timing probe (informational — recorded for the
# knowledge repo; the ADR only claims process-entry).
post, post_status = run_probe("post_require", { "SDL_AUDIODRIVER" => nil })
post_verdict =
  if !post_status.success?
    "probe failed (exit #{post_status.exitstatus})"
  elsif post["SDL_DRIVER"] == "dummy"
    "dummy honored even when set post-require/pre-audio-init (SDL reads the hint at audio init, not at library load)"
  else
    "post-require set was TOO LATE (driver #{post['SDL_DRIVER'].inspect}) — env must be set at process entry"
  end
puts "  TIMING VERDICT (for knowledge repo): #{post_verdict}"

Spike.pass!("Gosu silent (SDL=dummy at entry), window rendered, miniaudio owned the real device; control=#{control['SDL_DRIVER']}; post-require=#{post['SDL_DRIVER'].inspect}")
