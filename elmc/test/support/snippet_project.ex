defmodule Elmc.TestSupport.SnippetProject do
  @moduledoc false

  @repo_root Path.expand("../../..", __DIR__)

  alias Elmc.TestSupport.CompileCache
  alias Elmc.TestSupport.ElmJson
  alias Elmc.TestSupport.GeneratedCLint

  @doc """
  Compiles a one-module Main.elm pebble app (simple_project-shaped deps).

  Results are cached by Main source + compile opts + compiler identity.
  Returns `{:ok, result}` where `result` includes `:out_dir`.
  """
  @spec compile_main(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def compile_main(main_source, opts \\ []) when is_binary(main_source) do
    name = Keyword.get(opts, :name, "snippet")

    out_dir =
      Keyword.get_lazy(opts, :out_dir, fn ->
        Path.join(
          System.tmp_dir!(),
          "elmc-snippet-out-#{name}-#{System.unique_integer([:positive])}"
        )
      end)

    compile_opts =
      %{
        out_dir: out_dir,
        entry_module: "Main"
      }
      |> Map.merge(normalize_compile_opts(Keyword.get(opts, :compile, %{})))
      |> Map.put(:out_dir, out_dir)
      |> CompileCache.inject_compile_opts()

    materialize = Keyword.get(opts, :materialize, :auto)

    cache_key =
      CompileCache.key({
        :snippet_project_v2,
        CompileCache.content_hash(main_source),
        Map.drop(compile_opts, [:out_dir, :ir_cache_dir]),
        platform_stamp(),
        CompileCache.compiler_identity()
      })

    case CompileCache.fetch(cache_key) do
      {:hit, result, out_cache} ->
        CompileCache.materialize_out(out_cache, out_dir, materialize)
        {:ok, enrich_result(result, out_dir)}

      :miss ->
        do_compile(main_source, name, compile_opts, cache_key)
    end
  end

  @doc "Like `compile_main/2` but asserts success and returns `out_dir`."
  @spec compile_main!(String.t(), keyword()) :: String.t()
  def compile_main!(main_source, opts \\ []) do
    case compile_main(main_source, opts) do
      {:ok, result} ->
        maybe_check_generated_c!(result, opts)
        result.out_dir

      {:error, reason} ->
        raise "snippet compile failed: #{inspect(reason, limit: 8)}"
    end
  end

  @doc """
  Compile a snippet, lint record-get bases, and host-typecheck generated C.

  Returns `{result, generated_c}`. Use this for new direct-render / ABI snippets
  so undeclared identifiers fail in `elmc` tests instead of Pebble `-Werror`.
  """
  @spec compile_checked!(String.t(), keyword()) :: {map(), String.t()}
  def compile_checked!(main_source, opts \\ []) do
    opts = Keyword.merge([typecheck: true, lint_c: true], opts)

    case compile_main(main_source, opts) do
      {:ok, result} ->
        generated = File.read!(Path.join(result.out_dir, "c/elmc_generated.c"))
        maybe_check_generated_c!(result, opts, generated)
        {result, generated}

      {:error, reason} ->
        raise "snippet compile failed: #{inspect(reason, limit: 8)}"
    end
  end

  defp maybe_check_generated_c!(result, opts, generated \\ nil) do
    generated =
      generated ||
        File.read!(Path.join(result.out_dir, "c/elmc_generated.c"))

    if Keyword.get(opts, :lint_c, false) do
      GeneratedCLint.assert_record_get_bases_bound!(generated)
    end

    if Keyword.get(opts, :typecheck, false) do
      Elmc.TestSupport.GeneratedCTypecheck.assert_typechecks!(result.out_dir)
    end

    :ok
  end

  @doc "Compiles and returns `c/elmc_generated.c` contents (no full out materialize on hit)."
  @spec generated_c!(String.t(), keyword()) :: String.t()
  def generated_c!(main_source, opts \\ []) do
    name = Keyword.get(opts, :name, "snippet")

    compile_opts =
      %{
        entry_module: "Main"
      }
      |> Map.merge(normalize_compile_opts(Keyword.get(opts, :compile, %{})))
      |> CompileCache.inject_compile_opts()

    cache_key =
      CompileCache.key({
        :snippet_project_v2,
        CompileCache.content_hash(main_source),
        Map.drop(compile_opts, [:out_dir, :ir_cache_dir]),
        platform_stamp(),
        CompileCache.compiler_identity()
      })

    case CompileCache.fetch(cache_key) do
      {:hit, _result, out_cache} ->
        case CompileCache.read_generated_c(out_cache) do
          {:ok, body} -> body
          :error -> raise "cached snippet missing elmc_generated.c for #{name}"
        end

      :miss ->
        out_dir = compile_main!(main_source, opts)
        File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    end
  end

  defp normalize_compile_opts(%{} = map), do: map
  defp normalize_compile_opts(list) when is_list(list), do: Map.new(list)

  defp do_compile(main_source, name, compile_opts, cache_key) do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elmc-snippet-#{name}-#{System.unique_integer([:positive])}"
      )

    try do
      File.mkdir_p!(Path.join(tmp, "src"))
      File.write!(Path.join(tmp, "src/Main.elm"), main_source)

      ElmJson.write!(Path.join(tmp, "elm.json"),
        source_directories: [
          "src",
          Path.join(@repo_root, "packages/elm-pebble/elm-watch/src"),
          Path.join(@repo_root, "shared/elm"),
          Path.join(@repo_root, "ide/priv/internal_packages/elm-random/src")
        ],
        direct: %{
          "elm/core" => "1.0.5",
          "elm/json" => "1.1.3",
          "elm/random" => "1.0.0",
          "elm/time" => "1.0.0"
        }
      )

      case Elmc.compile(tmp, compile_opts) do
        {:ok, result} ->
          # Snippet tests almost never need the full IR in the ETF; drop it to
          # shrink cache entries (generated C + runtime still stored under out/).
          CompileCache.store(cache_key, result, compile_opts.out_dir, drop_ir: true)
          {:ok, enrich_result(result, compile_opts.out_dir)}

        other ->
          other
      end
    after
      File.rm_rf(tmp)
    end
  end

  defp enrich_result(result, out_dir) when is_map(result) do
    Map.put(result, :out_dir, out_dir)
  end

  defp platform_stamp do
    {
      CompileCache.dir_stamp(Path.join(@repo_root, "packages/elm-pebble/elm-watch/src")),
      CompileCache.dir_stamp(Path.join(@repo_root, "shared/elm")),
      CompileCache.dir_stamp(Path.join(@repo_root, "ide/priv/internal_packages/elm-random/src"))
    }
  end
end
