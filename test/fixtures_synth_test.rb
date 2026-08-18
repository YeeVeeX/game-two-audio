require "minitest/autorun"
require "json"
require "digest"
require "tmpdir"
require "gta/fixtures"
require "gta/wav"

# GTA::Fixtures "notes" synthesis (M4 listen track): deterministic, declicked,
# data-validated, staleness-aware. Pure Ruby, load-path-time only (never on
# the tick path), so no allocation constraints apply here.
class FixturesSynthTest < Minitest::Test
  SR = 48_000

  PLUCK = {
    "type" => "notes", "dur_s" => 0.5, "gain" => 1.0,
    "notes" => [
      { "t" => 0.0, "dur" => 0.4, "freq_hz" => 440.0, "amp" => 0.5, "wave" => "bell",
        "attack_s" => 0.002, "decay_tau_s" => 0.05, "release_s" => 0.05 },
      { "t" => 0.1, "dur" => 0.3, "freq_hz" => 220.0, "amp" => 0.3, "wave" => "saw",
        "attack_s" => 0.01, "release_s" => 0.05,
        "trem" => { "rate_hz" => 2.0, "depth" => 0.3 } },
      { "t" => 0.0, "dur" => 0.2, "freq_hz" => 330.0, "glide_to_hz" => 165.0, "glide_s" => 0.05,
        "amp" => 0.2, "wave" => "sine", "attack_s" => 0.002, "release_s" => 0.02 },
      { "t" => 0.2, "dur" => 0.1, "freq_hz" => 1.0, "amp" => 0.2, "wave" => "noise", "seed" => 7,
        "attack_s" => 0.002, "decay_tau_s" => 0.02, "release_s" => 0.02 }
    ]
  }.freeze

  def test_render_notes_is_deterministic
    a = GTA::Fixtures.render_notes("t", PLUCK, SR)
    b = GTA::Fixtures.render_notes("t", PLUCK, SR)
    assert_equal a, b
    assert_equal (0.5 * SR).round, a.size
    assert_operator a.map(&:abs).max, :>, 1000, "render is near-silent"
  end

  def test_edges_are_declicked
    samples = GTA::Fixtures.render_notes("t", PLUCK, SR)
    assert_operator samples.first.abs, :<=, 350, "clicky start (attack ramp missing)"
    assert_operator samples.last.abs, :<=, 350, "clicky end (release ramp missing)"
  end

  def test_hot_mix_raises_instead_of_wrapping_pcm16
    hot = { "type" => "notes", "dur_s" => 0.1, "gain" => 1.0,
            "notes" => [1, 2].map do |_|
              { "t" => 0.0, "dur" => 0.1, "freq_hz" => 440.0, "amp" => 0.9, "wave" => "sine",
                "attack_s" => 0.001, "release_s" => 0.01 }
            end }
    e = assert_raises(ArgumentError) { GTA::Fixtures.render_notes("hot", hot, SR) }
    assert_match(/mix peak/, e.message)
  end

  def test_noise_requires_seed_and_bounds_validate
    no_seed = { "type" => "notes", "dur_s" => 0.1, "gain" => 1.0,
                "notes" => [{ "t" => 0.0, "dur" => 0.1, "freq_hz" => 1.0, "amp" => 0.2,
                              "wave" => "noise", "attack_s" => 0.001, "release_s" => 0.01 }] }
    assert_raises(ArgumentError) { GTA::Fixtures.render_notes("n", no_seed, SR) }

    out_of_bounds = { "type" => "notes", "dur_s" => 0.1, "gain" => 1.0,
                      "notes" => [{ "t" => 0.05, "dur" => 0.1, "freq_hz" => 440.0, "amp" => 0.2,
                                    "wave" => "sine", "attack_s" => 0.001, "release_s" => 0.01 }] }
    assert_raises(ArgumentError) { GTA::Fixtures.render_notes("b", out_of_bounds, SR) }
  end

  def test_ensure_renders_sines_and_notes_and_tracks_staleness
    Dir.mktmpdir do |dir|
      manifest = File.join(dir, "fixtures.json")
      out = File.join(dir, "out")
      File.write(manifest, JSON.generate({ "tones" => {
        "sine_a" => { "freq_hz" => 440.0, "dur_s" => 0.1, "amp" => 0.5, "phase" => 0.0 },
        "notes_a" => PLUCK
      } }))
      GTA::Fixtures.ensure!(manifest, out, sample_rate: SR)
      sine_path = File.join(out, "sine_a.wav")
      notes_path = File.join(out, "notes_a.wav")
      assert File.exist?(sine_path) && File.exist?(notes_path)
      assert File.exist?("#{sine_path}.sig") && File.exist?("#{notes_path}.sig")

      # Legacy formula unchanged: byte-equal to the direct spike-era rendering.
      expected = (0.1 * SR).round.times.map { |i| (0.5 * 32_767 * Math.sin(2.0 * Math::PI * (440.0 * i / SR.to_f))).round }
      assert_equal expected, GTA::Wav.read_samples(sine_path).map { |s| (s * 32_768).round }

      # Unchanged manifest -> no re-render (mtime preserved).
      before = File.mtime(notes_path)
      GTA::Fixtures.ensure!(manifest, out, sample_rate: SR)
      assert_equal before, File.mtime(notes_path)

      # Entry drift -> re-render (the data-retune loop must not need tmp/ cleanup).
      sha_before = Digest::SHA256.file(notes_path).hexdigest
      drifted = JSON.parse(File.read(manifest))
      drifted["tones"]["notes_a"]["gain"] = 0.5
      File.write(manifest, JSON.generate(drifted))
      GTA::Fixtures.ensure!(manifest, out, sample_rate: SR)
      refute_equal sha_before, Digest::SHA256.file(notes_path).hexdigest,
                   "gain drift did not re-render the fixture"
    end
  end
end
