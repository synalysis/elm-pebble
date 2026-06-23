defmodule Ide.Debugger.SpeakerPlaybackTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.SpeakerPlayback

  test "play_tone duration uses command duration_ms" do
    assert SpeakerPlayback.duration_ms(%{
             "variant" => "play_tone",
             "duration_ms" => 250
           }) == 250
  end

  test "play_notes duration sums note segments" do
    assert SpeakerPlayback.duration_ms(%{
             "variant" => "play_notes",
             "note_values" => [60, 0, 100, 80, 0, 0, 50, 0]
           }) == 150
  end

  test "play_tracks duration sums nested note segments" do
    assert SpeakerPlayback.duration_ms(%{
             "variant" => "play_tracks",
             "track_values" => [2, 0, 60, 0, 100, 80, 64, 0, 120, 90]
           }) == 220
  end

  test "stop playback reports zero duration" do
    assert SpeakerPlayback.duration_ms(%{"variant" => "stop"}) == 0
  end
end
