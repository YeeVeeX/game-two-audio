# harness/run_listen.rb — LISTEN-track renderer (M4, presentation axis).
#
# Runs the SAME replay corpus as the gate through the SAME Runner code path,
# but against data/audio_listen (musical fixtures; owner listen 2026-08-19
# falsified raw sines as listen material — drafts/_m4-owner-scores.md).
# Choreography is identical by the mirror law (test/listen_track_test.rb);
# only the audio material differs, so the ear can finally judge the behaviors.
#
# Expectations are filtered to material-independent types: "peak" (the
# -1 dBFS headroom ceiling is global policy and gates listen renders too).
# Determinism (double render byte-compare + double log md5) still asserts —
# the listen track is not exempt from the determinism law. Sine-tuned
# accuracy pins (goertzel/ratio/rms/silence/log) stay gate-only.
#
# Usage: ruby -Isrc -Iharness harness/run_listen.rb harness/replays/*.json
# Artifacts: tmp/listen/<name>.wav + .log

require_relative "gate_runner"

DATA_DIR = File.expand_path("../data/audio_listen", __dir__)
FIXTURE_DIR = File.expand_path("../tmp/fixtures_listen", __dir__)
OUT_DIR = File.expand_path("../tmp/listen", __dir__)

paths = ARGV
abort "usage: run_listen.rb <replay.json>..." if paths.empty?

all_pass = true
paths.each do |path|
  result = GTA::Gate::Runner.new(path, data_dir: DATA_DIR, fixture_dir: FIXTURE_DIR,
                                 out_dir: OUT_DIR, expectation_types: %w[peak]).run
  puts "== listen: #{result.name} =="
  puts "   command log md5    #{result.log_md5}"
  puts "   wav sha256         #{result.wav_sha256}"
  puts "   artifacts          tmp/listen/#{result.name}.wav  tmp/listen/#{result.name}.log"
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
  puts "listen: all #{paths.size} replay(s) rendered clean"
else
  puts "LISTEN FAILURES — see table above"
  exit 1
end
