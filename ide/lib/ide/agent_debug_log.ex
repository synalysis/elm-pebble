defmodule Ide.AgentDebugLog do
  @moduledoc false

  @path "/home/ape/projects/elm-pebble/.cursor/debug-edf96a.log"
  @session_id "edf96a"

  def log(run_id, hypothesis_id, location, message, data \\ %{}) do
    payload = %{
      sessionId: @session_id,
      runId: run_id,
      hypothesisId: hypothesis_id,
      location: location,
      message: message,
      data: scrub(data),
      timestamp: System.system_time(:millisecond)
    }

    _ = File.mkdir_p(Path.dirname(@path))
    _ = File.write(@path, Jason.encode!(payload) <> "\n", [:append])
    :ok
  rescue
    _ -> :ok
  end

  defp scrub(value) when is_binary(value) do
    value
    |> String.replace(~r/https?:\/\/[^\s]+/, "[url]")
    |> truncate(2_000)
  end

  defp scrub(value) when is_map(value), do: Map.new(value, fn {k, v} -> {k, scrub(v)} end)
  defp scrub(value) when is_list(value), do: Enum.map(value, &scrub/1)
  defp scrub(value) when is_tuple(value), do: value |> Tuple.to_list() |> scrub()
  defp scrub(value), do: value

  defp truncate(value, max) when byte_size(value) > max,
    do: binary_part(value, 0, max) <> "...[truncated]"

  defp truncate(value, _max), do: value
end
