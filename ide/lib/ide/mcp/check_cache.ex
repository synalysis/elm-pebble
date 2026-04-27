defmodule Ide.Mcp.CheckCache do
  @moduledoc """
  In-memory cache and short history of compiler check results for MCP context tools.
  """

  use Agent

  @default_history_limit 200

  @type cached_entry :: %{
          slug: String.t(),
          at: String.t(),
          result: map()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> %{latest: %{}, history: []} end, name: __MODULE__)
  end

  @spec put(String.t(), map()) :: :ok
  def put(slug, result) when is_binary(slug) and is_map(result) do
    entry = %{slug: slug, at: DateTime.utc_now() |> DateTime.to_iso8601(), result: result}

    Agent.update(__MODULE__, fn state ->
      history =
        [entry | state.history]
        |> Enum.take(@default_history_limit)

      %{
        latest: Map.put(state.latest, slug, entry),
        history: history
      }
    end)
  end

  @spec latest(String.t()) :: {:ok, cached_entry()} | {:error, :not_found}
  def latest(slug) when is_binary(slug) do
    Agent.get(__MODULE__, fn state ->
      case Map.get(state.latest, slug) do
        nil -> {:error, :not_found}
        entry -> {:ok, entry}
      end
    end)
  end

  @spec recent(non_neg_integer(), String.t() | nil) :: [cached_entry()]
  def recent(limit \\ 20, slug \\ nil)

  def recent(limit, slug)
      when is_integer(limit) and limit >= 0 and (is_binary(slug) or is_nil(slug)) do
    Agent.get(__MODULE__, fn state ->
      state.history
      |> Enum.filter(fn entry -> is_nil(slug) or entry.slug == slug end)
      |> Enum.take(limit)
    end)
  end
end
