# harness/reaper_setup_listen.rb — one-time builder for the owner's listen
# project (M4b), driven ENTIRELY through the live Reaper bridge: the owner
# never hand-configures tempo, tracks, MIDI placement, regions, or render
# bounds. REAPER serializes its own project file — nothing about the .rpp
# format is fabricated here.
#
# What it builds (data-driven from data/audio_listen/fixtures.json):
#   - backs up the CURRENTLY OPEN project to tmp/ first (owner document law);
#   - fresh project: 120 bpm 4/4 (the listen-track grid);
#   - one track per slot, slot k's MIDI item+notes created through ReaScript
#     at k*SLOT_SPACING_S seconds (no import dialogs; canonical mapping shared
#     with rake midi, so bridge items and committed .mid files stay in sync;
#     staggered so regions never overlap — each renders only its own slot);
#   - disposable built-in ReaSynth on every track, so the owner can audition
#     immediately and replace each with the chosen VST while playback loops;
#   - one region per slot spanning exactly [offset, offset+dur_s] (regions
#     are the render unit; $region naming makes files land as <slot>.wav);
#   - render settings via a generated ReaScript (documented
#     GetSetProjectInfo API): dir=data/audio_listen/inbox, pattern=$region,
#     48 kHz, mono, bounds=all regions, tail OFF (slot durations are
#     choreography-load-bearing; releases must fit inside dur_s);
#   - asks REAPER to serialize WAV itself, verifies the sampled v7.79
#     RENDER_CFG fourcc (`evaw`), saves owner_project.rpp, then saves an exact
#     generated-state copy as scaffold.rpp.
#
# REFUSES to run if owner_project.rpp already exists: after the first save
# that file is the owner's working document (their FX, their tweaks) — this
# script never overwrites it. Delete/rename it manually to rebuild. The
# generated scaffold may be regenerated, but never at the owner's path.
#
# Usage: ruby -Isrc -Iharness harness/reaper_setup_listen.rb

require "json"
require "fileutils"
require "base64"
require_relative "reaper_bridge"
require_relative "export_midi"

REPO = File.expand_path("..", __dir__)
LISTEN_DIR = File.join(REPO, "data/audio_listen")
PROJECT_PATH = File.join(LISTEN_DIR, "reaper/owner_project.rpp")
SCAFFOLD_PATH = File.join(LISTEN_DIR, "reaper/scaffold.rpp")
INBOX_DIR = File.join(LISTEN_DIR, "inbox")
MIDI_DIR = File.join(LISTEN_DIR, "midi")
SLOT_SPACING_S = 10.0 # > max slot dur (6 s), bar-aligned at 120 bpm (10 s = 5 bars)

B = GTA::ReaperBridge

def win_path(p) = p.tr("/", "\\")

abort "REFUSED: #{PROJECT_PATH} already exists — it is the owner's working document. Rename/delete it manually if a rebuild is truly wanted." if File.exist?(PROJECT_PATH)
B.assert_alive!

slots = JSON.parse(File.read(File.join(LISTEN_DIR, "fixtures.json"))).fetch("tones")
slots.each_key do |slot|
  mid = File.join(MIDI_DIR, "#{slot}.mid")
  abort "missing #{mid} — run `rake midi` first" unless File.exist?(mid)
end
FileUtils.mkdir_p(INBOX_DIR)
FileUtils.mkdir_p(File.dirname(PROJECT_PATH))

# 1. Backup whatever is open (their document; backup goes in OUR tmp/).
info = B.call!("project_get_info")
backup = File.join(REPO, "tmp", "reaper_backup_#{Time.now.strftime('%Y%m%d_%H%M%S')}.rpp")
FileUtils.mkdir_p(File.dirname(backup))
B.call!("project_backup", { "path" => win_path(backup) })
puts "backed up open project (#{File.basename(info['file_path'].to_s)}) -> #{backup}"

# 2. Fresh project. If REAPER pops a save-changes dialog the bridge waits —
#    the owner answers it (both answers are safe; the backup above is belt+
#    suspenders and their own file is untouched on disk).
puts "opening a new project — if REAPER asks about saving, answer as you like"
B.call!("project_new", {}, timeout: 120)
fresh = B.call!("project_get_info")
abort "project_new did not produce an empty project (track_count=#{fresh['track_count']}) — was a dialog cancelled?" unless fresh["track_count"].to_i.zero?

B.call!("transport_set_bpm", { "bpm" => 120 })
B.call!("transport_set_time_signature", { "numerator" => 4, "denominator" => 4 })

# 3. Tracks + MIDI items + regions, one slot at a time.
slots.each_with_index do |(slot, spec), i|
  offset = i * SLOT_SPACING_S
  dur = spec.fetch("dur_s")
  B.call!("track_create", { "index" => i, "name" => slot })
  item = B.call!("item_create_midi", { "track_index" => i, "position" => offset, "length" => dur })
  notes = GTA::MidiExport.fixture_note_events(spec).map do |n|
    {
      "pitch" => n[:pitch], "velocity" => n[:vel], "channel" => 0,
      "start" => offset + n[:on] / GTA::MidiExport::TICKS_PER_SECOND.to_f,
      "end" => offset + n[:off] / GTA::MidiExport::TICKS_PER_SECOND.to_f
    }
  end
  inserted = B.call!("midi_insert_notes_batch",
                     { "track_index" => i, "item_index" => item.fetch("index"),
                       "notes" => JSON.generate(notes) })
  fx = B.call!("fx_add", { "track_index" => i, "fx_name" => "ReaSynth" })
  B.call!("marker_add_region", { "start" => offset, "end" => offset + dur, "name" => slot })
  puts format("  slot %-18s track %d  %2d notes @ %5.1f s  region [%.1f, %.3f]  fx=%s",
              slot, i, inserted.fetch("inserted_count"), offset, offset, offset + dur,
              fx.fetch("fx_chain").first.fetch("name"))
end

# 4. Render settings via ReaScript (self-verifying: reads every value back).
lua = <<~LUA
  -- gta_render_config.lua — generated by game-two-audio reaper_setup_listen.rb.
  -- Sets the listen-loop render settings on the current project and reports
  -- the READ-BACK values (not the intended ones) through the bridge ExtState.
  local proj = 0
  reaper.GetSetProjectInfo_String(proj, "RENDER_FILE", [[#{win_path(INBOX_DIR)}]], true)
  reaper.GetSetProjectInfo_String(proj, "RENDER_PATTERN", "$region", true)
  reaper.GetSetProjectInfo(proj, "RENDER_SRATE", 48000, true)
  reaper.GetSetProjectInfo(proj, "RENDER_CHANNELS", 1, true)
  reaper.GetSetProjectInfo(proj, "RENDER_BOUNDSFLAG", 3, true) -- all project regions
  reaper.GetSetProjectInfo(proj, "RENDER_SETTINGS", 0, true)   -- master mix
  reaper.GetSetProjectInfo(proj, "RENDER_TAILFLAG", 0, true)   -- no tail: slot durations are load-bearing
  reaper.GetSetProjectInfo(proj, "RENDER_TAILMS", 0, true)
  local back = string.format(
    "RENDER_FILE=%s|PATTERN=%s|SRATE=%d|CH=%d|BOUNDS=%d|SETTINGS=%d|TAIL=%d",
    select(2, reaper.GetSetProjectInfo_String(proj, "RENDER_FILE", "", false)),
    select(2, reaper.GetSetProjectInfo_String(proj, "RENDER_PATTERN", "", false)),
    reaper.GetSetProjectInfo(proj, "RENDER_SRATE", 0, false),
    reaper.GetSetProjectInfo(proj, "RENDER_CHANNELS", 0, false),
    reaper.GetSetProjectInfo(proj, "RENDER_BOUNDSFLAG", 0, false),
    reaper.GetSetProjectInfo(proj, "RENDER_SETTINGS", 0, false),
    reaper.GetSetProjectInfo(proj, "RENDER_TAILFLAG", 0, false))
  reaper.SetExtState("reaper_mcp_script_result", "last_result", back, false)
LUA
script_path = File.join(B.scripts_dir, "gta_render_config.lua")
File.write(script_path, lua)
puts "render config read-back: #{B.run_script!('gta_render_config.lua')}"

# 5. Save as the owner's project inside this repo. Forward slashes are
# accepted by REAPER on Windows and avoid JSON/shell backslash escape traps.
B.call!("project_save_as", { "path" => PROJECT_PATH }, timeout: 60)

# REAPER owns the opaque render-format blob; sampled v7.79 serializes WAV as
# a little-endian fourcc (`evaw`). Validate the actual file instead of
# fabricating or trusting defaults silently.
rpp = File.read(PROJECT_PATH)
encoded_cfg = rpp[/<RENDER_CFG\s+([A-Za-z0-9+\/=]+)\s+>/m, 1]
format_bytes = encoded_cfg && Base64.strict_decode64(encoded_cfg)
abort "REAPER did not serialize WAV render format — open File > Render, select WAV, save, then rerun setup" unless format_bytes&.start_with?("evaw")

# Generated-state reference. This is a save-copy through REAPER, not an RPP
# text clone, and it never changes the active owner_project path.
B.call!("project_backup", { "path" => SCAFFOLD_PATH }, timeout: 60)
final = B.call!("project_get_info")
regions = B.call!("marker_get_all")
region_count = (regions["markers"] || []).count { |m| m["is_region"] } rescue nil
puts "saved owner: #{final['file_path']}  (bpm=#{final['bpm']} tracks=#{final['track_count']} items=#{final['item_count']} markers/regions=#{final['marker_count']})"
puts "saved generated scaffold: #{SCAFFOLD_PATH} (format=WAV verified from REAPER serialization)"
puts region_count ? "regions visible: #{region_count}" : "regions: see marker_count above"
puts <<~NEXT

  READY: mstem_calm_6s can loop immediately through disposable ReaSynth.
  Replace each ReaSynth with your chosen VST and tweak while it plays. Say
  "render" when ready; the bridge renders all regions to inbox and the
  importer validates, pins, reports levels, and rebuilds tmp/listen/*.wav.
NEXT
