defmodule Elmc.TestSupport.CachedCompile do
  @moduledoc false

  alias Elmc.TestSupport.CompileCache

  @doc """
  `Elmc.compile/2` with disk/process cache keyed by project sources + opts.
  """
  @spec compile(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def compile(project_dir, compile_opts) when is_binary(project_dir) and is_map(compile_opts) do
    out_dir = Map.fetch!(compile_opts, :out_dir)

    cache_key =
      CompileCache.key({
        :cached_compile_v1,
        Path.expand(project_dir),
        project_stamp(project_dir),
        Map.drop(compile_opts, [:out_dir]),
        CompileCache.compiler_identity()
      })

    case CompileCache.fetch(cache_key) do
      {:hit, result, out_cache} ->
        CompileCache.materialize_out(out_cache, out_dir)
        {:ok, result}

      :miss ->
        case Elmc.compile(project_dir, compile_opts) do
          {:ok, result} = ok ->
            CompileCache.store(cache_key, result, out_dir)
            ok

          other ->
            other
        end
    end
  end

  defp project_stamp(project_dir) do
    elm_json = Path.join(project_dir, "elm.json")

    source_dirs =
      case File.read(elm_json) do
        {:ok, body} ->
          case Jason.decode(body) do
            {:ok, %{"source-directories" => dirs}} when is_list(dirs) -> dirs
            _ -> ["src"]
          end

        _ ->
          ["src"]
      end

    {
      CompileCache.file_hash(elm_json),
      Enum.map(source_dirs, fn dir ->
        abs = Path.expand(dir, project_dir)
        CompileCache.dir_stamp(abs)
      end)
    }
  end
end
