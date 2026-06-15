defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Replay.LiveDrift do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type events :: Types.events()
  @type maybe_non_neg_integer :: Types.maybe_non_neg_integer()
  @type replay_drift_severity :: Types.replay_drift_severity()

  @spec warning?(String.t(), maybe_non_neg_integer(), events()) :: boolean()
  def warning?(mode, preview_seq, events) when is_binary(mode) and is_list(events) do
    mode == "live" and is_integer(preview_seq) and drift(mode, preview_seq, events) != nil
  end

  @spec drift(String.t(), maybe_non_neg_integer(), events()) :: non_neg_integer() | nil
  def drift(mode, preview_seq, events) when is_binary(mode) and is_list(events) do
    with true <- mode == "live",
         seq when is_integer(seq) <- preview_seq,
         latest when is_integer(latest) <- latest_event_seq(events),
         true <- latest > seq do
      latest - seq
    else
      _ -> nil
    end
  end

  @spec severity(non_neg_integer() | nil) :: replay_drift_severity()
  def severity(nil), do: :none
  def severity(drift) when is_integer(drift) and drift <= 3, do: :mild
  def severity(drift) when is_integer(drift) and drift <= 10, do: :medium
  def severity(drift) when is_integer(drift), do: :high

  @spec latest_event_seq(events()) :: non_neg_integer() | nil
  defp latest_event_seq([]), do: nil

  defp latest_event_seq(events) when is_list(events) do
    events
    |> Enum.map(& &1.seq)
    |> Enum.max()
  end
end
