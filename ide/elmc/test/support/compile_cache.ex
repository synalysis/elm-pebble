defmodule Elmc.TestSupport.CompileCache do
  @moduledoc false

  @table :elmc_test_compile_cache
  @env_disable "ELMC_TEST_COMPILE_CACHE"

  @spec enabled?() :: boolean()
  def enabled? do
    case System.get_env(@env_disable) do
      v when v in ["0", "false", "no", "off"] -> false
      _ -> true
    end
  end

  @spec cache_root() :: String.t()
  def cache_root do
    case System.get_env("ELMC_TEST_COMPILE_CACHE_DIR") do
      dir when is_binary(dir) and dir != "" -> dir
      _ -> Path.join(System.tmp_dir!(), "elmc-test-compile-cache")
    end
  end

  @spec ensure_table!() :: :ok
  def ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  @spec fetch(String.t()) :: {:hit, term(), String.t()} | :miss
  def fetch(key) when is_binary(key) do
    if not enabled?() do
      :miss
    else
      ensure_table!()

      case :ets.lookup(@table, key) do
        [{^key, result, out_cache}] ->
          if File.dir?(out_cache) and File.regular?(Path.join(entry_dir(key), "result.etf")) do
            {:hit, result, out_cache}
          else
            load_disk(key)
          end

        [] ->
          load_disk(key)
      end
    end
  end

  @spec store(String.t(), term(), String.t()) :: :ok
  def store(key, result, out_dir) when is_binary(key) and is_binary(out_dir) do
    if not enabled?() do
      :ok
    else
      ensure_table!()
      entry = entry_dir(key)
      out_cache = Path.join(entry, "out")
      File.rm_rf!(entry)
      File.mkdir_p!(entry)
      # Destination must not exist yet — otherwise Elixir nests basename(out_dir) under it.
      File.cp_r!(out_dir, out_cache)
      File.write!(Path.join(entry, "result.etf"), :erlang.term_to_binary(result, compressed: 1))
      :ets.insert(@table, {key, result, out_cache})
      :ok
    end
  end

  @spec materialize_out(String.t(), String.t()) :: :ok
  def materialize_out(out_cache, dest_out) when is_binary(out_cache) and is_binary(dest_out) do
    File.rm_rf!(dest_out)
    File.mkdir_p!(Path.dirname(dest_out))
    # Destination must not exist yet — otherwise Elixir nests basename(out_cache) under it.
    File.cp_r!(out_cache, dest_out)
    :ok
  end

  @spec key(term()) :: String.t()
  def key(fingerprint) do
    fingerprint
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec compiler_identity() :: term()
  def compiler_identity do
    case :persistent_term.get({__MODULE__, :compiler_identity}, :unset) do
      :unset ->
        id = {
          Application.spec(:elmc, :vsn),
          Application.spec(:elm_ex, :vsn),
          ebin_stamp(:elmc),
          ebin_stamp(:elm_ex)
        }

        :persistent_term.put({__MODULE__, :compiler_identity}, id)
        id

      id ->
        id
    end
  end

  @spec dir_stamp(String.t()) :: term()
  def dir_stamp(path) when is_binary(path) do
    case :persistent_term.get({__MODULE__, :dir_stamp, path}, :unset) do
      :unset ->
        stamp =
          if File.dir?(path) do
            path
            |> Path.join("**/*.{elm,ex,hrl,c,h}")
            |> Path.wildcard()
            |> Enum.sort()
            |> Enum.reduce({0, 0}, fn file, {count, hash} ->
              case File.stat(file) do
                {:ok, %{mtime: mtime, size: size}} ->
                  {count + 1, :erlang.phash2({hash, file, mtime, size})}

                _ ->
                  {count, hash}
              end
            end)
          else
            {:missing, path}
          end

        :persistent_term.put({__MODULE__, :dir_stamp, path}, stamp)
        stamp

      stamp ->
        stamp
    end
  end

  @spec file_hash(String.t()) :: String.t() | nil
  def file_hash(path) when is_binary(path) do
    case File.read(path) do
      {:ok, body} -> Base.encode16(:crypto.hash(:sha256, body), case: :lower)
      _ -> nil
    end
  end

  @spec content_hash(iodata()) :: String.t()
  def content_hash(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp entry_dir(key), do: Path.join([cache_root(), "entries", key])

  defp load_disk(key) do
    entry = entry_dir(key)
    etf = Path.join(entry, "result.etf")
    out_cache = Path.join(entry, "out")

    with true <- File.regular?(etf),
         true <- File.dir?(out_cache),
         {:ok, bin} <- File.read(etf) do
      try do
        result = :erlang.binary_to_term(bin)
        ensure_table!()
        :ets.insert(@table, {key, result, out_cache})
        {:hit, result, out_cache}
      rescue
        _ -> :miss
      end
    else
      _ -> :miss
    end
  end

  defp ebin_stamp(app) do
    case Application.app_dir(app, "ebin") do
      path when is_binary(path) ->
        path
        |> Path.join("*.beam")
        |> Path.wildcard()
        |> Enum.reduce({0, 0}, fn beam, {count, hash} ->
          case File.stat(beam) do
            {:ok, %{mtime: mtime, size: size}} ->
              {count + 1, :erlang.phash2({hash, Path.basename(beam), mtime, size})}

            _ ->
              {count, hash}
          end
        end)

      _ ->
        {0, 0}
    end
  end
end
