defmodule Ide.Debugger.CursorSeq do
  @moduledoc false

  @spec resolve_at_or_before([map()], integer() | nil) :: integer() | nil
  def resolve_at_or_before(events, requested_seq) when is_list(events) do
    seqs = event_seqs(events)

    cond do
      seqs == [] ->
        nil

      is_integer(requested_seq) and requested_seq >= 0 ->
        valid = Enum.filter(seqs, &(&1 <= requested_seq))
        if valid == [], do: Enum.max(seqs), else: Enum.max(valid)

      true ->
        Enum.max(seqs)
    end
  end

  @spec resolve_before([map()], integer() | nil, integer() | nil) :: integer() | nil
  def resolve_before(events, current_seq, requested_seq \\ nil)

  def resolve_before(events, current_seq, requested_seq)
      when is_list(events) and is_integer(current_seq) and current_seq >= 0 do
    prior =
      events
      |> event_seqs()
      |> Enum.filter(&(&1 < current_seq))

    cond do
      prior == [] ->
        nil

      is_integer(requested_seq) and requested_seq >= 0 ->
        valid = Enum.filter(prior, &(&1 <= requested_seq))
        if valid == [], do: Enum.min(prior), else: Enum.max(valid)

      true ->
        Enum.max(prior)
    end
  end

  def resolve_before(_events, _current_seq, _requested_seq), do: nil

  @spec event_seqs(term()) :: term()
  defp event_seqs(events) when is_list(events) do
    events
    |> Enum.map(&Map.get(&1, :seq))
    |> Enum.filter(&is_integer/1)
  end
end
