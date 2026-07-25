defmodule ElmEx.IR.LowererCache do
  @moduledoc """
  Disk cache for per-module IR after `ElmEx.IR.Lowerer` rewrite.

  Entries are keyed by compiler version, global type/constructor fingerprint,
  reachable-set fingerprint, and the module source path digest.
  """

  alias ElmEx.IR.Module, as: IRModule

  # Bump when IR lowering shape changes (ports/callee retention, FnArgDesugar, etc.).
  @cache_version "ir-module-v6"

  @type t ::
          :disabled
          | %{
              dir: String.t(),
              global_fp: binary(),
              reachable_fp: binary()
            }

  @spec init(keyword(), binary(), String.t() | nil) :: t()
  def init(opts, global_fp, project_dir) when is_binary(global_fp) do
    enabled? = Keyword.get(opts, :cache, false) == true or is_binary(Keyword.get(opts, :cache_dir))

    if enabled? do
      dir =
        Keyword.get(opts, :cache_dir) ||
          default_cache_dir(project_dir)

      File.mkdir_p!(dir)

      reachable_fp =
        case Keyword.get(opts, :reachable_fp) do
          fp when is_binary(fp) -> fp
          _ -> "all"
        end

      %{dir: dir, global_fp: global_fp, reachable_fp: reachable_fp}
    else
      :disabled
    end
  end

  @spec default_cache_dir(String.t() | nil) :: String.t()
  def default_cache_dir(project_dir) when is_binary(project_dir) do
    Path.join(project_dir, ".elmc-cache/ir")
  end

  def default_cache_dir(_), do: Path.join(System.tmp_dir!(), "elmc-ir-cache")

  @spec fetch(t(), FrontendModule.t() | map()) :: {:hit, IRModule.t()} | :miss
  def fetch(:disabled, _), do: :miss

  def fetch(%{} = cache, %{name: _, path: _} = mod) do
    path = entry_path(cache, mod)

    with true <- File.regular?(path),
         {:ok, bin} <- File.read(path),
         {:ok, %IRModule{} = ir_mod} <- safe_binary_to_term(bin) do
      {:hit, ir_mod}
    else
      _ -> :miss
    end
  end

  @spec put(t(), FrontendModule.t() | map(), IRModule.t()) :: :ok
  def put(:disabled, _, _), do: :ok

  def put(%{} = cache, %{name: _, path: _} = mod, %IRModule{} = ir_mod) do
    path = entry_path(cache, mod)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(ir_mod, compressed: 1))
    :ok
  rescue
    _ -> :ok
  end

  @spec fingerprint_reachable(MapSet.t() | :all) :: binary()
  def fingerprint_reachable(:all), do: "all"

  def fingerprint_reachable(%MapSet{} = keys) do
    keys
    |> MapSet.to_list()
    |> Enum.sort()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, [&1]))
    |> Base.encode16(case: :lower)
  end

  defp entry_path(cache, %{name: name, path: path}) do
    key =
      :crypto.hash(:sha256, [
        @cache_version,
        cache.global_fp,
        cache.reachable_fp,
        name,
        source_digest(path)
      ])
      |> Base.encode16(case: :lower)

    Path.join(cache.dir, key <> ".etf")
  end

  defp source_digest(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %File.Stat{mtime: mtime, size: size}} ->
        :erlang.term_to_binary({path, mtime, size})

      _ ->
        path
    end
  end

  defp safe_binary_to_term(bin) when is_binary(bin) do
    try do
      case :erlang.binary_to_term(bin, [:safe]) do
        %IRModule{} = mod -> {:ok, mod}
        # Older/non-struct maps used in some IR shapes
        %{name: _, declarations: _} = mod -> {:ok, struct(IRModule, Map.take(mod, [:name, :imports, :declarations, :unions, :ports, :port_module]))}
        _ -> :error
      end
    rescue
      _ -> :error
    end
  end
end
