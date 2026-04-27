defmodule Ide.Mcp.Audit do
  @moduledoc """
  Append-only audit log helpers for MCP action traces.
  """

  @spec append(map()) :: :ok
  def append(entry) when is_map(entry) do
    line = Jason.encode!(entry) <> "\n"
    _ = File.mkdir_p(audit_dir())
    _ = File.write(audit_path(), line, [:append])
    :ok
  end

  @spec recent(non_neg_integer()) :: [map()]
  def recent(limit \\ 20) when is_integer(limit) and limit >= 0 do
    case File.read(audit_path()) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reverse()
        |> Enum.take(limit)
        |> Enum.reverse()
        |> Enum.map(fn line ->
          case Jason.decode(line) do
            {:ok, entry} when is_map(entry) -> entry
            _ -> %{"raw" => line}
          end
        end)

      {:error, _reason} ->
        []
    end
  end

  @spec audit_path() :: String.t()
  def audit_path do
    Path.join(audit_dir(), "audit.log")
  end

  @spec audit_dir() :: term()
  defp audit_dir do
    Path.join(:code.priv_dir(:ide), "mcp")
  end
end
