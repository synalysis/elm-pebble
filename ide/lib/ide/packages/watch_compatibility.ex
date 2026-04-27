defmodule Ide.Packages.WatchCompatibility do
  @moduledoc false

  alias Ide.Packages.DependencyResolver

  @cache_table :ide_packages_watch_compat_cache

  @doc """
  Drops catalog entries whose latest-version dependency tree includes any
  `watch_forbidden_packages` (browser / DOM stack unsuitable for Pebble watch).
  """
  @spec filter_entries([map()], map()) :: [map()]
  def filter_entries(entries, provider) when is_list(entries) do
    # Own the ETS table in this process so short-lived Task workers cannot delete it.
    _ = cache_table()

    callbacks = build_callbacks(provider)
    forbidden = forbidden_packages()

    if length(entries) <= 1 do
      Enum.filter(entries, &entry_compatible?(&1, callbacks, forbidden))
    else
      entries
      |> Task.async_stream(
        fn entry ->
          if entry_compatible?(entry, callbacks, forbidden), do: {:keep, entry}, else: :drop
        end,
        max_concurrency: 8,
        ordered: true,
        timeout: :infinity
      )
      |> Enum.flat_map(fn
        {:ok, {:keep, e}} -> [e]
        {:ok, :drop} -> []
        {:exit, _} -> []
      end)
    end
  end

  @doc false
  @spec clear_cache!() :: term()
  def clear_cache! do
    case :ets.whereis(@cache_table) do
      :undefined -> :ok
      tid -> true = :ets.delete_all_objects(tid)
    end

    :ok
  end

  @spec entry_compatible?(term(), term(), term()) :: term()
  defp entry_compatible?(%{name: name}, callbacks, forbidden) when is_binary(name) do
    compatible_cached?(name, callbacks, forbidden)
  end

  defp entry_compatible?(%{"name" => name}, callbacks, forbidden) when is_binary(name) do
    compatible_cached?(name, callbacks, forbidden)
  end

  defp entry_compatible?(_, _, _), do: true

  @spec compatible_cached?(term(), term(), term()) :: term()
  defp compatible_cached?(package, callbacks, forbidden) do
    table = cache_table()
    key = cache_key(forbidden, package)

    case :ets.lookup(table, key) do
      [{^key, result}] ->
        result

      _ ->
        result = compute_compatible?(package, callbacks, forbidden)
        true = :ets.insert(table, {key, result})
        result
    end
  end

  # Version + forbidden-list hash so we never reuse entries from older logic or config.
  @spec cache_key(term(), term()) :: term()
  defp cache_key(forbidden, package) do
    {:pebble_watch_compat, 3, :erlang.phash2(forbidden), package}
  end

  @spec compute_compatible?(term(), term(), term()) :: term()
  defp compute_compatible?(package, callbacks, forbidden) do
    if package in forbidden do
      false
    else
      section = %{"direct" => %{}, "indirect" => %{}}

      case DependencyResolver.resolve(section, package, "direct", callbacks) do
        {:ok, %{assignments: assigned}} ->
          not Enum.any?(forbidden, &Map.has_key?(assigned, &1))

        {:error, _} ->
          # Fail closed: when resolution fails, hide if latest release directly lists a
          # forbidden package (catches elm/html, etc.). If metadata cannot be read, hide.
          case latest_release_dependency_names(package, callbacks) do
            {:ok, names} -> not Enum.any?(forbidden, &(&1 in names))
            :error -> false
          end
      end
    end
  end

  @spec latest_release_dependency_names(term(), term()) :: term()
  defp latest_release_dependency_names(package, callbacks) do
    with {:ok, versions} <- callbacks.versions.(package),
         ver when is_binary(ver) <- List.first(versions),
         {:ok, elm_json} <- callbacks.release.(package, ver) do
      {:ok, release_dependency_names(elm_json)}
    else
      _ -> :error
    end
  end

  @spec release_dependency_names(term()) :: term()
  defp release_dependency_names(elm_json) when is_map(elm_json) do
    deps = Map.get(elm_json, "dependencies", %{})

    names =
      cond do
        is_map(deps) and Map.has_key?(deps, "direct") ->
          Map.get(deps, "direct", %{})
          |> Map.keys()
          |> Kernel.++(Map.get(deps, "indirect", %{}) |> Map.keys())

        is_map(deps) ->
          Map.keys(deps)

        true ->
          []
      end

    names |> Enum.filter(&is_binary/1)
  end

  @spec build_callbacks(term()) :: term()
  defp build_callbacks(%{module: module, opts: opts}) do
    %{
      versions: fn pkg -> apply(module, :versions, [pkg, opts]) end,
      release: fn pkg, ver -> apply(module, :package_release, [pkg, ver, opts]) end
    }
  end

  @spec forbidden_packages() :: term()
  defp forbidden_packages do
    Application.get_env(:ide, Ide.Packages, [])
    |> Keyword.get(:watch_forbidden_packages, ~w(elm/html elm/browser elm/virtual-dom))
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  @spec cache_table() :: term()
  defp cache_table do
    name = @cache_table

    case :ets.whereis(name) do
      :undefined ->
        try do
          :ets.new(name, [:set, :public, :named_table, read_concurrency: true])
        rescue
          ArgumentError ->
            case :ets.whereis(name) do
              :undefined ->
                raise ArgumentError,
                      "ETS table #{inspect(name)} missing after concurrent :ets.new (name already exists)"

              tid ->
                tid
            end
        end

      tid ->
        tid
    end
  end
end
