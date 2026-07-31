defmodule Elmc.TestSupport.CachedCompile do
  @moduledoc false

  alias Elmc.TestSupport.CompileCache

  @doc """
  `Elmc.compile/2` with disk/process cache keyed by project sources + opts.

  Always injects the shared test IR cache. Cache keys use **content** hashes for
  project-local sources (not mtimes) so rewriting the same Main.elm into a tmp
  project on a warm run still hits. Absolute package source dirs keep mtime stamps.
  """
  @spec compile(String.t(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def compile(project_dir, compile_opts) when is_binary(project_dir) do
    project_dir = Path.expand(project_dir)

    compile_opts =
      compile_opts
      |> CompileCache.inject_compile_opts()
      |> Map.put_new(:out_dir, Path.join(System.tmp_dir!(), "elmc-cached-out"))

    out_dir = Map.fetch!(compile_opts, :out_dir)

    cache_key =
      CompileCache.key({
        :cached_compile_v3,
        project_stamp(project_dir),
        Map.drop(compile_opts, [:out_dir, :ir_cache_dir]),
        CompileCache.compiler_identity()
      })

    case CompileCache.fetch(cache_key) do
      {:hit, result, out_cache} ->
        CompileCache.materialize_out(out_cache, out_dir, :auto)
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
    project_dir = Path.expand(project_dir)

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

        if project_local_dir?(project_dir, abs) do
          {:content, content_dir_stamp(abs)}
        else
          {:mtime, CompileCache.dir_stamp(abs)}
        end
      end)
    }
  end

  defp project_local_dir?(project_dir, abs) do
    project = Path.expand(project_dir) <> "/"
    String.starts_with?(Path.expand(abs) <> "/", project) or Path.expand(abs) == Path.expand(project_dir)
  end

  # Content-hash `.elm` files so identical sources hit across tmp rewrites / mtime changes.
  defp content_dir_stamp(path) when is_binary(path) do
    if File.dir?(path) do
      path
      |> Path.join("**/*.elm")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.map(fn file ->
        rel = Path.relative_to(file, path)
        {rel, CompileCache.file_hash(file)}
      end)
    else
      {:missing, path}
    end
  end
end
