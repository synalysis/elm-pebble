defmodule Ide.Debugger.SpeakerEffectsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.{PackageCommandHandler, SpeakerEffects}

  test "PackageCommandHandler queues speaker effect for debugger audio hook" do
    row = %{
      "source" => "effect_command",
      "package" => "elm-pebble/elm-watch",
      "command" => %{
        "kind" => "cmd.effect.speaker",
        "variant" => "play_tone",
        "frequency_hz" => 440,
        "duration_ms" => 120,
        "volume" => 70,
        "waveform" => 0
      }
    }

    assert {:handled, next_state, event_payload, nil} =
             PackageCommandHandler.handle(%{}, "watch", "elm-pebble/elm-watch", row)

    assert event_payload.simulated == true
    assert %{"seq" => 1, "command" => %{"variant" => "play_tone"}} = SpeakerEffects.latest(next_state)
    assert Map.get(next_state, :pending_speaker_finished_ms) == 120
  end

  test "PackageCommandHandler handles light effect without applying an update step" do
    row = %{
      "source" => "effect_command",
      "package" => "elm-pebble/elm-watch",
      "command" => %{
        "kind" => "cmd.effect.light",
        "variant" => "enable"
      }
    }

    assert {:handled, next_state, event_payload, nil} =
             PackageCommandHandler.handle(%{}, "watch", "elm-pebble/elm-watch", row)

    assert event_payload.simulated == true
    assert event_payload.detail == "enable"
    refute Map.has_key?(next_state, :pending_speaker_finished_ms)
  end
end
