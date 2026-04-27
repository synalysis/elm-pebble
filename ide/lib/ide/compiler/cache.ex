defmodule Ide.Compiler.Cache do
  @moduledoc """
  In-memory cache for compile results keyed by project slug and revision.
  """

  use Agent

  @history_limit 200

  @type entry :: %{
          slug: String.t(),
          revision: String.t(),
          at: String.t(),
          result: map()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> %{by_key: %{}, latest_by_slug: %{}, history: []} end, name: __MODULE__)
  end

  @spec put(String.t(), String.t(), map()) :: :ok
  def put(slug, revision, result)
      when is_binary(slug) and is_binary(revision) and is_map(result) do
    entry = %{
      slug: slug,
      revision: revision,
      at: DateTime.utc_now() |> DateTime.to_iso8601(),
      result: result
    }

    Agent.update(__MODULE__, fn state ->
      key = {slug, revision}

      %{
        by_key: Map.put(state.by_key, key, entry),
        latest_by_slug: Map.put(state.latest_by_slug, slug, entry),
        history: [entry | state.history] |> Enum.take(@history_limit)
      }
    end)
  end

  @spec get(String.t(), String.t()) :: {:ok, entry()} | {:error, :not_found}
  def get(slug, revision) when is_binary(slug) and is_binary(revision) do
    Agent.get(__MODULE__, fn state ->
      case Map.get(state.by_key, {slug, revision}) do
        nil -> {:error, :not_found}
        entry -> {:ok, entry}
      end
    end)
  end

  @spec latest(String.t()) :: {:ok, entry()} | {:error, :not_found}
  def latest(slug) when is_binary(slug) do
    Agent.get(__MODULE__, fn state ->
      case Map.get(state.latest_by_slug, slug) do
        nil -> {:error, :not_found}
        entry -> {:ok, entry}
      end
    end)
  end

  @spec recent(non_neg_integer(), String.t() | nil) :: [entry()]
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
