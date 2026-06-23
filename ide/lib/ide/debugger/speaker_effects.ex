defmodule Ide.Debugger.SpeakerEffects do
  @moduledoc false

  alias Ide.Debugger

  alias Ide.Debugger.SpeakerPlayback

  @type runtime_state :: Debugger.runtime_state()
  @type speaker_cmd :: map()

  @spec enqueue(runtime_state(), speaker_cmd()) :: runtime_state()
  def enqueue(state, %{} = command) when is_map(state) do
    seq = Map.get(state, :speaker_effect_seq, 0) + 1

    state
    |> Map.put(:speaker_effect_seq, seq)
    |> Map.put(:speaker_effect, %{
      "seq" => seq,
      "command" => command
    })
    |> maybe_queue_finished_followup(command)
  end

  def enqueue(state, _command), do: state

  defp maybe_queue_finished_followup(state, command) do
    case SpeakerPlayback.duration_ms(command) do
      duration_ms when is_integer(duration_ms) and duration_ms > 0 ->
        Map.put(state, :pending_speaker_finished_ms, duration_ms)

      _ ->
        Map.delete(state, :pending_speaker_finished_ms)
    end
  end

  @spec latest(runtime_state()) :: map() | nil
  def latest(state) when is_map(state), do: Map.get(state, :speaker_effect)
  def latest(_), do: nil
end
