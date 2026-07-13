defmodule ElmEx.Test.TreeSitterCorpus do
  @moduledoc false

  alias ElmEx.TestSupport.Types, as: SupportTypes

  alias ElmEx.Frontend.GeneratedParser

  @corpus_dir Path.expand("../../../vendor/tree-sitter-elm-test-corpus", __DIR__)
  @default_max_bytes 512_000
  @default_timeout_ms 10_000

  @smoke_tests [
    "0ui/elm-task-parallel/examples/FetchTwo.elm",
    "BrianHicks/elm-trend/tests/Helpers.elm",
    "FuJa0815/elm-ui/src/Element.elm",
    "Microsoft/elm-json-tree-view/src/JsonTree.elm",
    "NoRedInk/elm-json-decode-pipeline/src/Json/Decode/Pipeline.elm",
    "elm/core/src/Basics.elm",
    "elm/html/src/Html.elm",
    "elm/parser/src/Parser.elm",
    "jfmengels/elm-lint/src/Lint.elm",
    "mdgriffith/elm-ui/src/Element.elm",
    "rtfeldman/elm-css/src/Css.elm",
    "rtfeldman/elm-iso8601-date-strings/src/Iso8601.elm",
    "stil4m/elm-syntax/src/Elm/Syntax/Expression.elm",
    "zwilias/elm-utf-tools/src/String/UTF8.elm",
    "7hoenix/elm-chess/src/Chess/View/Board.elm",
    "Chadtech/unique-list/src/List/Unique.elm",
    "dillonkearns/elm-graphql/src/Graphql/Http.elm",
    "hecrj/html-parser/src/Html/Parser/Util.elm",
    "mgold/elm-nonempty-list/src/List/Nonempty.elm",
    "Morgan-Stanley/morphir-elm/src/Morphir/TypeScript/Backend/Values.elm",
    "pablohirafuji/elm-markdown/src/Markdown.elm",
    "gampleman/elm-visualization/src/Histogram.elm",
    "burnable-tech/elm-ethereum/src/Eth/RPC.elm",
    "the-sett/elm-syntax-dsl/src/ImportsAndExposing.elm",
    "MartinSStewart/elm-serialize/tests/AstCodec.elm"
  ]

  @spec corpus_dir() :: String.t()
  def corpus_dir do
    System.get_env("TREE_SITTER_CORPUS_DIR") || @corpus_dir
  end

  @spec available?() :: boolean()
  def available? do
    root = corpus_dir()
    File.dir?(root) and corpus_dir_has_elm_files?(root)
  end

  @spec corpus_sha() :: String.t() | nil
  def corpus_sha do
    root = corpus_dir()

    case System.cmd("git", ["-C", root, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> nil
    end
  end

  @spec smoke_tests() :: [String.t()]
  def smoke_tests do
    @smoke_tests
    |> Enum.filter(&File.exists?(corpus_path(&1)))
  end

  @spec discover_paths() :: [String.t()]
  def discover_paths do
    corpus_dir()
    |> Path.join("**/*.elm")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, corpus_dir()))
    |> Enum.sort()
  end

  @spec eligible_paths() :: [String.t()]
  def eligible_paths do
    max_bytes = max_bytes()

    discover_paths()
    |> Enum.reject(fn rel ->
      File.stat!(corpus_path(rel)).size > max_bytes
    end)
  end

  @spec skipped_large_paths() :: [String.t()]
  def skipped_large_paths do
    max_bytes = max_bytes()

    discover_paths()
    |> Enum.filter(fn rel ->
      File.stat!(corpus_path(rel)).size > max_bytes
    end)
  end

  @spec run_parse_gate!(keyword()) :: SupportTypes.corpus_scorecard()
  def run_parse_gate!(opts \\ []) do
    paths = Keyword.get(opts, :paths, eligible_paths())
    timeout_ms = Keyword.get(opts, :timeout_ms, timeout_ms())
    progress? = Keyword.get(opts, :progress, false)
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online() * 2)

    started = System.monotonic_time(:millisecond)

    results =
      paths
      |> Task.async_stream(
        fn rel_path -> parse_probe(rel_path, timeout_ms) end,
        max_concurrency: max_concurrency,
        ordered: true,
        timeout: :infinity,
        on_timeout: :kill_task,
        zip_input_on_exit: true
      )
      |> Enum.map(fn
        {:ok, result} ->
          if progress?, do: IO.write(:stderr, "ts corpus #{result["path"]} #{result["status"]}\n")
          result

        {:exit, {rel_path, :timeout}} ->
          %{
            "path" => rel_path,
            "status" => "crashed",
            "detail" => "task timeout after #{timeout_ms + 2_000}ms",
            "elapsed_ms" => timeout_ms + 2_000
          }

        {:exit, {rel_path, reason}} ->
          %{
            "path" => rel_path,
            "status" => "crashed",
            "detail" => inspect(reason, limit: 8),
            "elapsed_ms" => timeout_ms
          }
      end)

    elapsed_ms = System.monotonic_time(:millisecond) - started

    ok = Enum.count(results, &(&1["status"] == "ok"))
    failed = Enum.count(results, &(&1["status"] == "failed"))
    crashed = Enum.count(results, &(&1["status"] == "crashed"))

    %{
      "corpus_sha" => corpus_sha(),
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "max_bytes" => max_bytes(),
      "timeout_ms" => timeout_ms,
      "summary" => %{
        "attempted" => length(results),
        "parse_ok" => ok,
        "parse_failed" => failed,
        "parse_crashed" => crashed,
        "skipped_large" => length(skipped_large_paths()),
        "elapsed_ms" => elapsed_ms,
        "parse_ok_pct" =>
          if(length(results) == 0,
            do: 0.0,
            else: Float.round(ok * 100.0 / length(results), 2)
          )
      },
      "results" => results
    }
  end

  @spec write_scorecard!(SupportTypes.corpus_scorecard(), String.t()) :: String.t()
  def write_scorecard!(scorecard, out_dir) do
    File.mkdir_p!(out_dir)

    json_path = Path.join(out_dir, "tree_sitter_corpus_scorecard.json")
    md_path = Path.join(out_dir, "tree_sitter_corpus_scorecard.md")

    File.write!(json_path, Jason.encode!(scorecard, pretty: true) <> "\n")
    File.write!(md_path, render_scorecard_md(scorecard))

    json_path
  end

  @spec render_scorecard_md(SupportTypes.corpus_scorecard()) :: String.t()
  def render_scorecard_md(scorecard) do
    summary = scorecard["summary"]

    failed =
      scorecard["results"]
      |> Enum.filter(&(&1["status"] != "ok"))
      |> Enum.take(40)

    failure_lines =
      Enum.map(failed, fn row ->
        "- `#{row["path"]}`: #{row["detail"]}"
      end)

    failures_section =
      if failure_lines == [] do
        "_none_\n"
      else
        Enum.join(failure_lines, "\n") <> "\n"
      end

    """
    # tree-sitter-elm parse corpus scorecard

    - corpus SHA: `#{scorecard["corpus_sha"]}`
    - generated: #{scorecard["generated_at"]}
    - max file bytes: #{scorecard["max_bytes"]}
    - per-file timeout: #{scorecard["timeout_ms"]}ms

    ## Summary

    | metric | value |
    | --- | ---: |
    | attempted | #{summary["attempted"]} |
    | parse ok | #{summary["parse_ok"]} |
    | parse failed | #{summary["parse_failed"]} |
    | parse crashed | #{summary["parse_crashed"]} |
    | skipped (large) | #{summary["skipped_large"]} |
    | elapsed ms | #{summary["elapsed_ms"]} |
    | ok % | #{summary["parse_ok_pct"]} |

    ## Sample failures

    #{failures_section}
    """
  end

  defp parse_probe(rel_path, timeout_ms) do
    started = System.monotonic_time(:millisecond)
    abs_path = corpus_path(rel_path)
    timeout_ms = timeout_ms_for_file(abs_path, timeout_ms)

    task =
      Task.async(fn ->
        try do
          case GeneratedParser.parse_file(abs_path) do
            {:ok, _} -> {:ok, nil}
            {:error, reason} -> {:error, inspect(reason, limit: 8)}
          end
        rescue
          exception -> {:crash, Exception.message(exception)}
        catch
          kind, reason -> {:crash, "#{kind}: #{inspect(reason, limit: 8)}"}
        end
      end)

    {status, detail} =
      try do
        case Task.await(task, timeout_ms) do
          {:ok, nil} -> {:ok, nil}
          {:error, reason} -> {:failed, reason}
          {:crash, reason} -> {:crashed, reason}
        end
      catch
        :exit, {:timeout, _} ->
          Task.shutdown(task, :brutal_kill)
          {:crashed, "timeout after #{timeout_ms}ms"}
      end

    elapsed_ms = System.monotonic_time(:millisecond) - started

    %{
      "path" => rel_path,
      "status" => Atom.to_string(status),
      "detail" => detail,
      "elapsed_ms" => elapsed_ms
    }
  end

  defp corpus_path(rel_path) when is_binary(rel_path) do
    Path.join(corpus_dir(), rel_path)
  end

  defp corpus_dir_has_elm_files?(root) do
    root
    |> Path.join("**/*.elm")
    |> Path.wildcard()
    |> case do
      [_ | _] -> true
      _ -> false
    end
  end

  defp max_bytes do
    case System.get_env("TREE_SITTER_CORPUS_MAX_BYTES") do
      nil -> @default_max_bytes
      value -> String.to_integer(value)
    end
  end

  defp timeout_ms do
    case System.get_env("TREE_SITTER_CORPUS_TIMEOUT_MS") do
      nil -> @default_timeout_ms
      value -> String.to_integer(value)
    end
  end

  defp timeout_ms_for_file(path, default_timeout_ms) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > 200_000 -> max(default_timeout_ms, 30_000)
      _ -> default_timeout_ms
    end
  end
end
