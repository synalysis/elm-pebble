defmodule Ide.Packages.GenericProvider do
  @moduledoc false
  @behaviour Ide.Packages.Provider

  alias Ide.Packages.Http
  alias Ide.Packages.IndexDiskCache
  alias Ide.Packages.ModuleDoc

  @impl true
  @spec search(term(), term()) :: term()
  def search(query, opts) do
    with {:ok, entries} <- load_search_index(opts) do
      filtered =
        entries
        |> Enum.filter(fn entry ->
          q = String.downcase(String.trim(query || ""))
          entry_name = Map.get(entry, :name, "") || ""
          entry_summary = Map.get(entry, :summary, "") || ""

          q == "" or
            String.contains?(String.downcase(entry_name), q) or
            String.contains?(String.downcase(entry_summary), q)
        end)
        |> Enum.sort_by(&Map.get(&1, :name, ""))

      {:ok, filtered}
    end
  end

  @impl true
  @spec package_details(term(), term()) :: term()
  def package_details(package, opts) do
    with {:ok, summaries} <- load_search_index(opts),
         {:ok, versions} <- versions(package, opts),
         {:ok, elm_json} <- package_elm_json(package, "latest", opts) do
      summary =
        Enum.find(summaries, fn entry -> Map.get(entry, :name) == package end) ||
          %{name: package}

      details = %{
        name: package,
        summary: pick_first([elm_json["summary"], Map.get(summary, :summary)]),
        license: pick_first([elm_json["license"], Map.get(summary, :license)]),
        latest_version: List.first(versions),
        versions: versions,
        exposed_modules: normalize_exposed_modules(elm_json["exposed-modules"]),
        elm_json: elm_json
      }

      {:ok, details}
    end
  end

  @impl true
  @spec versions(term(), term()) :: term()
  def versions(package, opts) do
    with {:ok, package_map} <- load_all_packages_map(opts) do
      versions =
        package_map
        |> Map.get(package, [])
        |> List.wrap()
        |> Enum.map(&to_string/1)
        |> Enum.uniq()
        |> Enum.sort(&(Version.compare(normalize_version(&1), normalize_version(&2)) == :gt))

      if versions == [] do
        {:error, :package_not_found}
      else
        {:ok, versions}
      end
    end
  end

  @impl true
  @spec readme(term(), term(), term()) :: term()
  def readme(package, version, opts) do
    encoded = encode_package(package)
    path = "/packages/#{encoded}/#{version}/README.md"
    Http.get_text(path, Keyword.put(opts, :accept, "text/markdown"))
  end

  @doc false
  @spec module_doc_markdown(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def module_doc_markdown(package, version, module_name, opts)
      when is_binary(package) and is_binary(version) and is_binary(module_name) do
    module_name = String.trim(module_name)

    if module_name == "" do
      {:error, :empty_module}
    else
      with {:ok, modules} <- load_docs_json(package, version, opts),
           {:ok, mod} <- find_module_doc(modules, module_name) do
        md = mod |> ModuleDoc.json_to_markdown() |> String.slice(0, 150_000)
        {:ok, md}
      end
    end
  end

  @impl true
  @spec package_release(term(), term(), term()) :: term()
  def package_release(package, version, opts) do
    package_elm_json(package, version, opts)
  end

  @spec load_search_index(term()) :: term()
  defp load_search_index(opts) do
    with {:ok, payload} <- load_search_payload(opts) do
      {:ok, normalize_search_entries(payload)}
    end
  end

  @spec load_search_payload(term()) :: term()
  defp load_search_payload(opts) do
    key = index_cache_key(:search_json, opts[:base_url])
    conditional = index_cache_validators(key)
    http_opts = index_request_opts(opts)

    case Http.get_json_conditional("/search.json", http_opts, conditional) do
      {:ok, payload, meta} ->
        index_cache_put(key, meta, payload)
        {:ok, payload}

      :not_modified ->
        case index_cache_get_payload(key) do
          nil -> search_payload_fallback_all_packages(opts)
          payload -> {:ok, payload}
        end

      {:error, _} ->
        case index_cache_get_payload(key) do
          nil -> search_payload_fallback_all_packages(opts)
          payload -> {:ok, payload}
        end
    end
  end

  @spec search_payload_fallback_all_packages(term()) :: term()
  defp search_payload_fallback_all_packages(opts) do
    maybe_progress(opts, {:phase, :fallback_all_packages_index})

    with {:ok, package_map} <- load_all_packages_map(opts) do
      {:ok, package_map}
    end
  end

  @spec load_all_packages_map(term()) :: term()
  defp load_all_packages_map(opts) do
    key = index_cache_key(:all_packages, opts[:base_url])
    conditional = index_cache_validators(key)
    http_opts = index_request_opts(opts)

    case Http.get_json_conditional("/all-packages", http_opts, conditional) do
      {:ok, payload, meta} when is_map(payload) ->
        index_cache_put(key, meta, payload)
        {:ok, payload}

      {:ok, _, _} ->
        {:error, :invalid_all_packages_payload}

      :not_modified ->
        case index_cache_get_payload(key) do
          nil -> {:error, :not_modified_without_cache}
          payload -> {:ok, payload}
        end

      {:error, _} = err ->
        case index_cache_get_payload(key) do
          nil -> err
          payload -> {:ok, payload}
        end
    end
  end

  @spec index_cache_key(term(), term()) :: term()
  defp index_cache_key(which, base_url) when is_atom(which) and is_binary(base_url) do
    {which, base_url}
  end

  @spec index_request_opts(term()) :: term()
  defp index_request_opts(opts) do
    http_opts =
      opts
      |> Keyword.drop([:progress])
      |> Keyword.put_new(:index_timeout_ms, 240_000)
      |> Keyword.put_new(:receive_timeout_ms, 120_000)

    case Keyword.get(opts, :progress) do
      fun when is_function(fun, 1) -> Keyword.put(http_opts, :download_progress, fun)
      _ -> http_opts
    end
  end

  @spec maybe_progress(term(), term()) :: term()
  defp maybe_progress(opts, msg) do
    case Keyword.get(opts, :progress) do
      fun when is_function(fun, 1) -> fun.(msg)
      _ -> :ok
    end
  end

  @spec index_cache_table() :: term()
  defp index_cache_table do
    ensure_named_ets_table(:ide_packages_index_cache, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])
  end

  @spec index_cache_validators(term()) :: term()
  defp index_cache_validators(key) do
    table = index_cache_table()

    case :ets.lookup(table, key) do
      [{^key, etag, last_modified, _payload}] ->
        index_validators_from(etag, last_modified)

      _ ->
        IndexDiskCache.hydrate_to_ets!(table, key)

        case :ets.lookup(table, key) do
          [{^key, etag, last_modified, _payload}] ->
            index_validators_from(etag, last_modified)

          _ ->
            %{}
        end
    end
  end

  @spec index_validators_from(term(), term()) :: term()
  defp index_validators_from(etag, last_modified) do
    %{}
    |> index_put_validator(:etag, etag)
    |> index_put_validator(:last_modified, last_modified)
  end

  @spec index_put_validator(term(), term(), term()) :: term()
  defp index_put_validator(acc, _k, v) when v in [nil, ""], do: acc

  defp index_put_validator(acc, k, v) when is_binary(v) do
    Map.put(acc, k, v)
  end

  @spec index_cache_put(term(), term(), term()) :: term()
  defp index_cache_put(key, meta, payload) do
    etag = Map.get(meta, :etag)
    last_modified = Map.get(meta, :last_modified)
    true = :ets.insert(index_cache_table(), {key, etag, last_modified, payload})
    IndexDiskCache.schedule_persist(key, meta, payload)
  end

  @spec index_cache_get_payload(term()) :: term()
  defp index_cache_get_payload(key) do
    case :ets.lookup(index_cache_table(), key) do
      [{^key, _, _, payload}] -> payload
      _ -> nil
    end
  end

  @spec package_elm_json(term(), term(), term()) :: term()
  defp package_elm_json(package, version, opts) do
    encoded = encode_package(package)
    Http.get_json("/packages/#{encoded}/#{version}/elm.json", opts)
  end

  @spec load_docs_json(term(), term(), term()) :: term()
  defp load_docs_json(package, version, opts) do
    encoded = encode_package(package)
    cache_key = {:docs_json, opts[:base_url], package, version}

    cached_fetch(cache_key, opts, fn ->
      path = "/packages/#{encoded}/#{version}/docs.json"

      case Http.get_json(path, opts) do
        {:ok, list} when is_list(list) -> {:ok, list}
        {:ok, _} -> {:error, :invalid_docs_json}
        {:error, _} = err -> err
      end
    end)
  end

  @spec find_module_doc(term(), term()) :: term()
  defp find_module_doc(modules, name) when is_list(modules) do
    case Enum.find(modules, fn m -> (m["name"] || "") == name end) do
      nil -> {:error, :module_not_in_docs}
      mod -> {:ok, mod}
    end
  end

  @spec normalize_search_entries(term()) :: term()
  defp normalize_search_entries(payload) when is_list(payload) do
    payload
    |> Enum.map(&normalize_search_entry/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_search_entries(payload) when is_map(payload) do
    payload
    |> Enum.map(fn {name, versions} ->
      version =
        versions
        |> List.wrap()
        |> Enum.map(&to_string/1)
        |> Enum.sort(&(Version.compare(normalize_version(&1), normalize_version(&2)) == :gt))
        |> List.first()

      %{name: name, summary: nil, license: nil, version: version}
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp normalize_search_entries(_), do: []

  @spec normalize_search_entry(term()) :: term()
  defp normalize_search_entry(%{"name" => name} = entry) do
    %{
      name: to_string(name),
      summary: normalize_string(entry["summary"]),
      license: normalize_string(entry["license"]),
      version: normalize_string(entry["version"])
    }
  end

  defp normalize_search_entry(%{"package" => name} = entry) do
    %{
      name: to_string(name),
      summary: normalize_string(entry["summary"]),
      license: normalize_string(entry["license"]),
      version: normalize_string(entry["version"])
    }
  end

  defp normalize_search_entry(_), do: nil

  @spec normalize_exposed_modules(term()) :: term()
  defp normalize_exposed_modules(nil), do: []
  defp normalize_exposed_modules(list) when is_list(list), do: list

  defp normalize_exposed_modules(map) when is_map(map) do
    map
    |> Map.values()
    |> List.flatten()
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_exposed_modules(_), do: []

  @spec normalize_version(term()) :: term()
  defp normalize_version(version) do
    case String.split(version, ".") do
      [major, minor] -> "#{major}.#{minor}.0"
      _ -> version
    end
  end

  @spec encode_package(term()) :: term()
  defp encode_package(package) do
    package
    |> String.split("/")
    |> Enum.map(&URI.encode/1)
    |> Enum.join("/")
  end

  @spec pick_first(term()) :: term()
  defp pick_first(values) do
    Enum.find(values, fn value -> is_binary(value) and value != "" end)
  end

  @spec normalize_string(term()) :: term()
  defp normalize_string(nil), do: nil
  defp normalize_string(value) when is_binary(value), do: value
  defp normalize_string(value), do: to_string(value)

  @spec cached_fetch(term(), term(), term()) :: term()
  defp cached_fetch(cache_key, opts, fun) do
    ttl_ms = opts[:cache_ttl_ms] || 120_000
    table = cache_table()
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(table, cache_key) do
      [{^cache_key, expires_at, value}] when expires_at > now ->
        {:ok, value}

      _ ->
        case fun.() do
          {:ok, value} = ok ->
            true = :ets.insert(table, {cache_key, now + ttl_ms, value})
            ok

          error ->
            error
        end
    end
  end

  @spec cache_table() :: term()
  defp cache_table do
    ensure_named_ets_table(:ide_packages_catalog_cache, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])
  end

  # Avoid TOCTOU when many Task workers hit package APIs at once (e.g. watch catalog filter).
  @spec ensure_named_ets_table(term(), term()) :: term()
  defp ensure_named_ets_table(name, opts) when is_atom(name) and is_list(opts) do
    case :ets.whereis(name) do
      :undefined ->
        try do
          :ets.new(name, opts)
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
