defmodule IdeWeb.WorkspaceLive.DebuggerPage.SpeakerSamplesTest do
  use ExUnit.Case, async: true

  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.DebuggerPage.SpeakerSamples

  test "json encodes sample metadata with fetch URL" do
    project = %Project{id: 1, slug: "speaker-demo", owner_id: 3}

    json =
      SpeakerSamples.json(project, [
        %{
          resource_id: 1,
          filename: "beep.pcm",
          format: 2,
          base_midi_note: 60,
          loop: false
        }
      ])

    assert Jason.decode!(json) == [
             %{
               "index" => 1,
               "url" => "/projects/speaker-demo/speaker_samples/beep.pcm",
               "format" => 2,
               "base_midi_note" => 60,
               "loop" => false
             }
           ]
  end
end
