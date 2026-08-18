require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "src"
  t.pattern = "test/**/*_test.rb"
  t.warning = false
end

task default: :test

desc "M2 deterministic gate: scripted replays -> command log md5 -> noDevice render -> WAV -> double-render byte-compare -> feature assertions"
task :gate do
  replays = Dir["harness/replays/*.json"].sort
  abort "No replays under harness/replays/" if replays.empty?
  sh "ruby -Isrc -Iharness harness/run_gate.rb #{replays.join(' ')}"
end

desc "M4 listen track: same replays, musical fixtures (data/audio_listen) -> WAVs under tmp/listen for the owner's ears"
task :listen do
  replays = Dir["harness/replays/*.json"].sort
  abort "No replays under harness/replays/" if replays.empty?
  sh "ruby -Isrc -Iharness harness/run_listen.rb #{replays.join(' ')}"
end

namespace :stems do
  desc "Owner production loop: import inbox renders (data/audio_listen/inbox) -> validated stems + manifest sha pins + listen re-render"
  task :import do
    sh "ruby -Isrc -Iharness harness/import_stems.rb"
  end
end

desc "Export listen-track placeholder compositions as MIDI (data/audio_listen/midi/) for the owner's DAW/analog re-voicing loop"
task :midi do
  sh "ruby -Isrc -Iharness harness/export_midi.rb"
end

desc "M1 spike falsification runner (one script per ADR item under spike/)"
task :spike do
  scripts = Dir["spike/[0-9]*_*.rb"].sort
  abort "No spike scripts yet — see docs/adr/0001 falsification list" if scripts.empty?
  failures = scripts.reject { |s| sh("ruby -Isrc #{s}") { |ok, _| ok } }
  abort "SPIKE FAILURES: #{failures.join(', ')}" unless failures.empty?
  puts "spike: all #{scripts.size} items passed"
end

desc "Rebuild vendor/miniaudio.dll from the committed amalgamation (bumps VERSION; rerun full gate)"
task :dll do
  abort <<~MSG
    Deliberate manual step (see AGENTS.md vendor law). From an MSYS2 UCRT64 shell:
      gcc -shared -O2 -o vendor/miniaudio.dll vendor/miniaudio_impl.c vendor/gta_shim.c
    Then: sha256sum vendor/*.dll vendor/*.c vendor/*.h -> update vendor/VERSION, rerun rake + gate.
  MSG
end
