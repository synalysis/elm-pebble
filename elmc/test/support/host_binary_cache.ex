defmodule Elmc.TestSupport.HostBinaryCache do
  @moduledoc false

  alias Elmc.TestSupport.CompileCache

  @doc """
  Content-addressed cache for host-linked test harness binaries.

  Keys are hashes of source file contents (not absolute paths), link flags, and
  compiler identity so warm TEA/RC/corpus runs can skip `cc` link.
  """
  @spec fetch_or_build!(String.t(), [String.t()], keyword(), (-> :ok)) :: :ok
  def fetch_or_build!(binary_path, sources, link_opts, build_fun)
      when is_binary(binary_path) and is_list(sources) and is_function(build_fun, 0) do
    if not enabled?() do
      build_fun.()
    else
      key = fingerprint(sources, link_opts)
      cached = entry_path(key)

      if File.regular?(cached) do
        File.mkdir_p!(Path.dirname(binary_path))
        File.cp!(cached, binary_path)
        _ = File.chmod(binary_path, 0o755)
        :ok
      else
        build_fun.()

        if File.regular?(binary_path) do
          File.mkdir_p!(Path.dirname(cached))
          File.cp!(binary_path, cached)
          _ = File.chmod(cached, 0o755)
        end

        :ok
      end
    end
  end

  @spec enabled?() :: boolean()
  def enabled? do
    case System.get_env("ELMC_TEST_HOST_BIN_CACHE") do
      v when v in ["0", "false", "no", "off"] -> false
      _ -> CompileCache.enabled?()
    end
  end

  @spec fingerprint([String.t()], keyword()) :: String.t()
  def fingerprint(sources, link_opts) when is_list(sources) and is_list(link_opts) do
    source_fps =
      sources
      |> Enum.map(fn path ->
        {Path.basename(path), CompileCache.file_hash(path)}
      end)
      |> Enum.sort()

    CompileCache.key({
      :host_binary_v1,
      source_fps,
      Keyword.take(link_opts, [:rc_track, :alloc_track, :alloc_probe, :extra_flags]),
      CompileCache.file_hash(Path.expand("elmc_host_stubs.h", __DIR__)),
      CompileCache.file_hash(Path.expand("elmc_host_trig_stubs.c", __DIR__)),
      CompileCache.compiler_identity()
    })
  end

  @spec cached_path(String.t()) :: String.t()
  def cached_path(key) when is_binary(key), do: entry_path(key)

  defp entry_path(key), do: Path.join([CompileCache.cache_root(), "host-bin", key])
end
