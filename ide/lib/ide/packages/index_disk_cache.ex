defmodule Ide.Packages.IndexDiskCache do
  @moduledoc false

  @doc """
  Load a previously persisted index row into ETS so conditional HTTP can return 304 after restart.
  """
  @spec hydrate_to_ets!(atom() | :ets.tid(), term()) :: :ok
  def hydrate_to_ets!(ets_table, key) when is_atom(ets_table) or is_reference(ets_table) do
    if enabled?() do
      stem = stem_for(key)
      dir = cache_dir()
      meta_path = Path.join(dir, stem <> ".meta.json")
      payload_path = Path.join(dir, stem <> ".payload.json")

      with {:ok, meta_bin} <- File.read(meta_path),
           {:ok, meta_map} <- Jason.decode(meta_bin),
           true <- is_map(meta_map),
           {:ok, payload_bin} <- File.read(payload_path),
           {:ok, payload} <- Jason.decode(payload_bin) do
        etag = Map.get(meta_map, "etag")
        last_modified = Map.get(meta_map, "last_modified")
        true = :ets.insert(ets_table, {key, etag, last_modified, payload})
      else
        _ -> :ok
      end
    end

    :ok
  end

  @doc """
  Persist index payload and validators (async) after a successful download.
  """
  @spec schedule_persist(term(), map(), term()) :: :ok
  def schedule_persist(key, meta, payload) when is_map(meta) do
    if enabled?() do
      _ =
        Task.start(fn ->
          persist_sync(key, meta, payload)
        end)
    end

    :ok
  end

  @spec persist_sync(term(), term(), term()) :: term()
  defp persist_sync(key, meta, payload) do
    dir = cache_dir()
    :ok = File.mkdir_p(dir)

    stem = stem_for(key)
    etag = Map.get(meta, :etag)
    last_modified = Map.get(meta, :last_modified)

    meta_json =
      Jason.encode!(%{
        "etag" => etag,
        "last_modified" => last_modified
      })

    payload_json = Jason.encode!(payload)

    write_atomic(Path.join(dir, stem <> ".meta.json"), meta_json)
    write_atomic(Path.join(dir, stem <> ".payload.json"), payload_json)
  rescue
    _ -> :ok
  end

  @spec write_atomic(term(), term()) :: term()
  defp write_atomic(path, data) do
    tmp = path <> ".tmp." <> Integer.to_string(:erlang.unique_integer([:positive]))
    File.write!(tmp, data)
    File.rename!(tmp, path)
  end

  @spec stem_for(term()) :: term()
  defp stem_for(key) do
    digest =
      key
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "idx_" <> digest
  end

  @spec cache_dir() :: term()
  defp cache_dir do
    Application.get_env(:ide, Ide.Packages, [])
    |> Keyword.get(:index_disk_cache_dir) ||
      Path.join(System.user_home!(), ".cache/elm-pebble-ide/package-registry")
  end

  @spec enabled?() :: term()
  defp enabled? do
    Application.get_env(:ide, Ide.Packages, [])
    |> Keyword.get(:index_disk_cache, true)
  end
end
