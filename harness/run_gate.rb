# harness/run_gate.rb — CLI for the replay gate. Usage:
#   ruby -Isrc -Iharness harness/run_gate.rb harness/replays/*.json
# Compact PASS/FAIL table per replay; nonzero exit on any failure.

require_relative "gate_runner"

DATA_DIR = File.expand_path("../data/audio", __dir__)
FIXTURE_DIR = File.expand_path("../tmp/fixtures", __dir__)
OUT_DIR = File.expand_path("../tmp/gate", __dir__)

paths = ARGV
abort "usage: run_gate.rb <replay.json>..." if paths.empty?

all_pass = true
paths.each do |path|
  result = GTA::Gate::Runner.new(path, data_dir: DATA_DIR, fixture_dir: FIXTURE_DIR, out_dir: OUT_DIR).run
  puts "== gate: #{result.name} =="
  puts "   command log md5    #{result.log_md5}"
  puts "   wav sha256         #{result.wav_sha256}"
  puts "   artifacts          tmp/gate/#{result.name}.wav  tmp/gate/#{result.name}.log"
  puts format("   %s double render byte-identical", result.render_match ? "PASS" : "FAIL")
  puts format("   %s double command-log md5 match", result.log_match ? "PASS" : "FAIL")
  result.checks.each do |c|
    puts format("   %s %-52s %s", c.pass ? "PASS" : "FAIL", c.label, c.detail)
  end
  d = result.diagnostics
  puts "   diagnostics: voices=#{d[:active_voices]} dropped=#{d[:dropped_cues]} music=#{d[:music_state]}"
  m = result.metrics
  puts format("   metrics: peak=%.4f (%.2f dBFS) rms=%.4f (%.2f dBFS) crest=%.2f dB over_1.0=%d",
              m[:peak], m[:peak_dbfs], m[:rms], m[:rms_dbfs], m[:crest_db], m[:over_1])
  all_pass &&= result.pass?
end

if all_pass
  puts "gate: all #{paths.size} replay(s) passed"
else
  puts "GATE FAILURES — see table above"
  exit 1
end
