defmodule Elmc.Test.ElmRunCorpus do
  @moduledoc false

  @corpus_dir Path.expand("../../../vendor/elm-run-test_corpus", __DIR__)
  @index_path Path.expand("../fixtures/elm_run_corpus_index.json", __DIR__)

  @stdlib_modules MapSet.new(~w(
    Basics List Maybe Result String Char Tuple Dict Set Array Bitwise Debug Platform Task Process Json
  ))

  @metadata_skip_types ~w(skip known_bug)
  @metadata_compile_error_types ~w(error_pattern exit_code timeout)

  @parity_smoke_tests [
    "Basics/DecTest.elm"
  ]

  @execution_smoke_candidates [
    "Basics/ChainedArithmetic.elm",
    "Basics/BoolIntrinsicWrappers.elm",
    "Basics/DecTest.elm",
    "Basics/MainLiteral.elm",
    "Advanced/MainRecordUpdateNested.elm",
    "Unicode/CharLiterals.elm",
    "TailDef/Main.elm"
  ]

  @smoke_tests [
    "Basics/ChainedArithmetic.elm",
    "Basics/BoolIntrinsicWrappers.elm",
    "Basics/AsBound.elm",
    "Advanced/MainRecordUpdateNested.elm",
    "Parser/MainDeepAst.elm",
    "TailDef/Main.elm",
    "Bitwise/BitwiseSpec.elm",
    "Array/PushSharedBranches.elm",
    "Optimization/DictInsertKeysAssert.elm",
    "KernelLowering/JsArrayFilter.elm",
    "Unicode/CharCase.elm",
    "Iterative/Collections.elm",
    "Kernel/DiagAbs10.elm",
    "Json/MainDecodeArrayPrimitive.elm",
    "Binary/FixedWidthHash.elm",
    "Graph/MainDictGet.elm",
    "Compiler/BccBinopTypeLoss.elm",
    "Bugs/A64FieldArgCorruption.elm",
    "Compatibility/ProcessSendDead.elm",
    "Collections/BenchDictIntLookup.elm"
  ]

  @type tier ::
          :skip
          | :elm_run_only
          | :compile_error_expected
          | :compile_candidate
          | :run_scalar
          | :run_structured

  @type entry :: %{
          path: String.t(),
          category: String.t(),
          module: String.t(),
          tier: tier(),
          skip_reason: String.t() | nil,
          metadata: map(),
          has_expected: boolean(),
          imports: [String.t()]
        }

  @spec corpus_dir() :: String.t()
  def corpus_dir do
    System.get_env("ELM_RUN_CORPUS_DIR") || @corpus_dir
  end

  @spec index_path() :: String.t()
  def index_path, do: @index_path

  @spec available?() :: boolean()
  def available? do
    root = corpus_dir()
    File.dir?(root) and File.exists?(Path.join(root, "test_metadata.txt"))
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
  def smoke_tests, do: @smoke_tests

  @spec parity_smoke_tests() :: [String.t()]
  def parity_smoke_tests, do: @parity_smoke_tests

  @spec execution_smoke_tests() :: [String.t()]
  def execution_smoke_tests do
    Enum.filter(@execution_smoke_candidates, &File.exists?(expected_path(&1)))
  end

  @spec discover_paths() :: [String.t()]
  def discover_paths do
    corpus_dir()
    |> Path.join("*/*.elm")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, corpus_dir()))
    |> Enum.sort()
  end

  @spec load_metadata() :: %{String.t() => map()}
  def load_metadata do
    metadata_path = Path.join(corpus_dir(), "test_metadata.txt")

    metadata_path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      cond do
        line == "" ->
          acc

        String.starts_with?(line, "#") ->
          acc

        true ->
          case String.split(line, "|", parts: 3) do
            [path, type, value] ->
              Map.update(acc, path, %{type => value}, &Map.put(&1, type, value))

            _ ->
              acc
          end
      end
    end)
  end

  @spec build_index() :: map()
  def build_index do
    metadata = load_metadata()
    siblings_by_category = build_siblings_index()

    entries =
      discover_paths()
      |> Enum.map(fn path ->
        entry = build_entry(path, metadata, Map.fetch!(siblings_by_category, category(path)))
        Map.put(entry, :path, path)
      end)

    summary = summarize(entries)

    %{
      "corpus_sha" => corpus_sha(),
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "summary" => summary,
      "entries" => Enum.map(entries, &entry_to_map/1)
    }
  end

  @spec write_index!(map() | nil) :: String.t()
  def write_index!(index \\ nil) do
    index = index || build_index()
    File.mkdir_p!(Path.dirname(@index_path))
    File.write!(@index_path, Jason.encode!(index, pretty: true) <> "\n")
    @index_path
  end

  @spec read_index() :: map()
  def read_index do
    @index_path
    |> File.read!()
    |> Jason.decode!()
  end

  @spec compile_candidates(map()) :: [map()]
  def compile_candidates(index) do
    index["entries"]
    |> Enum.filter(&(&1["tier"] == "compile_candidate"))
  end

  @spec compile_eligible(map()) :: [map()]
  def compile_eligible(index) do
    eligible_tiers = MapSet.new(~w(compile_candidate run_scalar run_structured))

    index["entries"]
    |> Enum.filter(&(MapSet.member?(eligible_tiers, &1["tier"])))
  end

  @spec compile_eligible_paths(map()) :: [String.t()]
  def compile_eligible_paths(index) do
    compile_eligible(index)
    |> Enum.map(& &1["path"])
  end

  @spec run_eligible(map()) :: [map()]
  def run_eligible(index) do
    run_tiers = MapSet.new(~w(run_scalar run_structured))

    index["entries"]
    |> Enum.filter(&(MapSet.member?(run_tiers, &1["tier"])))
  end

  @spec run_eligible_paths(map()) :: [String.t()]
  def run_eligible_paths(index) do
    metadata = load_metadata()

    run_eligible(index)
    |> Enum.reject(fn entry ->
      meta = Map.get(metadata, entry["path"], %{})
      Map.has_key?(meta, "known_gold_diff") or Map.has_key?(meta, "known_bug")
    end)
    |> Enum.map(& &1["path"])
  end

  @spec read_expected!(String.t()) :: String.t()
  def read_expected!(rel_path) do
    rel_path
    |> expected_path()
    |> File.read!()
    |> normalize_output()
  end

  @spec normalize_output(String.t()) :: String.t()
  def normalize_output(text) when is_binary(text) do
    text |> String.trim() |> String.trim_trailing("\n")
  end

  @spec write_execution_project!(String.t(), String.t()) :: {String.t(), String.t()}
  def write_execution_project!(rel_path, tmp_root) do
    target_module = module_name(rel_path)
    tmp_dir = Path.join(tmp_root, path_slug(rel_path) <> "__exec")
    src_dir = Path.join(tmp_dir, "src")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(src_dir)

    File.cp!(
      Path.join(corpus_dir(), rel_path),
      Path.join(src_dir, "#{target_module}.elm")
    )

    File.write!(Path.join(src_dir, "CorpusHost.elm"), host_module_source(target_module))

    File.write!(
      Path.join(tmp_dir, "elm.json"),
      Jason.encode!(host_elm_json(), pretty: true) <> "\n"
    )

    {tmp_dir, "CorpusHost"}
  end

  @spec run_elmc_execution!(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def run_elmc_execution!(rel_path, tmp_root, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)
    {project_dir, entry_module} = write_execution_project!(rel_path, tmp_root)
    out_dir = Path.join(project_dir, "out")

    task =
      Task.async(fn ->
        with {:ok, _} <-
               Elmc.compile(project_dir, %{
                 out_dir: out_dir,
                 strip_dead_code: false,
                 entry_module: entry_module,
                 named_record_literals: true
               }),
             {:ok, stdout} <- run_elmc_harness(out_dir, entry_module) do
          {:ok, normalize_output(stdout)}
        end
      end)

    try do
      Task.await(task, timeout_ms)
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  @spec run_elmx_execution!(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def run_elmx_execution!(rel_path, tmp_root, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)
    {project_dir, entry_module} = write_execution_project!(rel_path, tmp_root)

    task =
      Task.async(fn ->
        try do
          with {:ok, result} <-
                 Elmx.compile_in_memory(project_dir, %{
                   entry_module: entry_module,
                   strip_dead_code: false,
                   mode: :library,
                   revision: "corpus-" <> path_slug(rel_path)
                 }),
               output when is_binary(output) <-
                 apply(result.entry_module, :"elmx_fn_#{entry_module}_main", []) do
            {:ok, normalize_output(output)}
          else
            {:error, reason} -> {:error, reason}
            other -> {:error, other}
          end
        rescue
          exception -> {:error, Exception.message(exception)}
        catch
          kind, reason -> {:error, {kind, reason}}
        end
      end)

    try do
      Task.await(task, timeout_ms)
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  @spec run_execution_probe!(atom(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def run_execution_probe!(backend, rel_path, tmp_root, opts \\ []) do
    case backend do
      :elmc -> run_elmc_execution!(rel_path, tmp_root, opts)
      :elmx -> run_elmx_execution!(rel_path, tmp_root, opts)
    end
  end

  @spec run_execution_gate!(keyword()) :: map()
  def run_execution_gate!(opts \\ []) do
    index = Keyword.get_lazy(opts, :index, &build_index/0)
    backend = Keyword.get(opts, :backend, :elmc)
    tmp_root = Keyword.get(opts, :tmp_root, Path.expand("../tmp/elm_run_corpus_run", __DIR__)) |> Path.expand()
    paths = Keyword.get(opts, :paths, run_eligible_paths(index))
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)
    progress? = Keyword.get(opts, :progress, false)

    File.mkdir_p!(tmp_root)

    results =
      Enum.map(paths, fn path ->
        if progress?, do: IO.write(:stderr, "corpus run #{backend} #{path}\n")

        started = System.monotonic_time(:millisecond)
        gold = read_expected!(path)

        {status, detail, actual} =
          case run_probe(backend, path, tmp_root, timeout_ms) do
            {:ok, output} ->
              if output == gold do
                {:ok, nil, output}
              else
                {:mismatch, mismatch_detail(output, gold), output}
              end

            {:error, :timeout} ->
              {:error, "timeout after #{timeout_ms}ms", nil}

            {:error, reason} ->
              {:error, inspect(reason, limit: 8), nil}
          end

        elapsed_ms = System.monotonic_time(:millisecond) - started

        %{
          "path" => path,
          "status" => Atom.to_string(status),
          "detail" => detail,
          "actual" => actual,
          "expected" => gold,
          "elapsed_ms" => elapsed_ms
        }
      end)

    ok = Enum.count(results, &(&1["status"] == "ok"))
    mismatch = Enum.count(results, &(&1["status"] == "mismatch"))
    failed = Enum.count(results, &(&1["status"] == "error"))

    %{
      "backend" => Atom.to_string(backend),
      "corpus_sha" => index["corpus_sha"],
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "summary" => %{
        "attempted" => length(results),
        "run_ok" => ok,
        "run_mismatch" => mismatch,
        "run_failed" => failed,
        "run_ok_pct" =>
          if(length(results) == 0,
            do: 0.0,
            else: Float.round(ok * 100.0 / length(results), 2)
          )
      },
      "results" => results
    }
  end

  @spec write_execution_scorecard!(map(), String.t()) :: String.t()
  def write_execution_scorecard!(scorecard, out_dir) do
    File.mkdir_p!(out_dir)

    json_path = Path.join(out_dir, "elm_run_corpus_execution_scorecard.json")
    md_path = Path.join(out_dir, "elm_run_corpus_execution_scorecard.md")
    safe_scorecard = json_safe_execution_scorecard(scorecard)

    File.write!(json_path, Jason.encode!(safe_scorecard, pretty: true, escape: :unicode) <> "\n")
    File.write!(md_path, render_execution_scorecard_md(scorecard))

    json_path
  end

  defp json_safe_execution_scorecard(%{"results" => results} = scorecard) do
    Map.put(
      scorecard,
      "results",
      Enum.map(results, fn row ->
        row
        |> Map.update("actual", nil, &json_safe_text_field/1)
        |> Map.update("expected", nil, &json_safe_text_field/1)
        |> Map.update("detail", nil, &json_safe_text_field/1)
      end)
    )
  end

  defp json_safe_execution_scorecard(scorecard), do: scorecard

  defp json_safe_text_field(value) when is_binary(value) do
    if String.valid?(value), do: value, else: "base64:" <> Base.encode64(value)
  end

  defp json_safe_text_field(value), do: value

  @spec render_execution_scorecard_md(map()) :: String.t()
  def render_execution_scorecard_md(scorecard) do
    summary = scorecard["summary"]

    issues =
      scorecard["results"]
      |> Enum.filter(&(&1["status"] != "ok"))
      |> Enum.take(40)

    issue_lines =
      Enum.map(issues, fn row ->
        "- `#{row["path"]}` (#{row["status"]}): #{row["detail"] || row["actual"]}"
      end)

    issues_section =
      if issue_lines == [] do
        "_No mismatches or failures._\n"
      else
        Enum.join(issue_lines, "\n") <> "\n"
      end

    """
    # elm-run Corpus Execution Scorecard (#{scorecard["backend"]})

    Generated: `#{scorecard["generated_at"]}`
    Corpus SHA: `#{scorecard["corpus_sha"]}`

    ## Summary

    - Attempted: #{summary["attempted"]}
    - Run OK: #{summary["run_ok"]}
    - Mismatch: #{summary["run_mismatch"]}
    - Failed: #{summary["run_failed"]}
    - Success rate: #{summary["run_ok_pct"]}%

    ## Issues (first 40)

    #{issues_section}
    """
  end

  defp run_probe(:elmc, path, tmp_root, timeout_ms) do
    run_elmc_execution!(path, tmp_root, timeout_ms: timeout_ms)
  end

  defp run_probe(:elmx, path, tmp_root, timeout_ms) do
    run_elmx_execution!(path, tmp_root, timeout_ms: timeout_ms)
  end

  defp run_elmc_harness(out_dir, entry_module) do
    cc = System.find_executable("cc")

    if is_nil(cc) do
      {:error, :cc_not_available}
    else
      harness_path = Path.join(out_dir, "c/corpus_execution_harness.c")
      binary_path = Path.join(out_dir, "corpus_execution_harness") |> Path.expand()

      File.write!(harness_path, elmc_execution_harness_source(entry_module))

      {compile_out, compile_code} =
        System.cmd(
          cc,
          [
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-I#{Path.join(out_dir, "runtime")}",
            "-I#{Path.join(out_dir, "ports")}",
            "-I#{Path.join(out_dir, "c")}",
            Path.join(out_dir, "runtime/elmc_runtime.c"),
            Path.join(out_dir, "ports/elmc_ports.c"),
            harness_path,
            "-lm",
            "-o",
            binary_path
          ],
          stderr_to_stdout: true
        )

        if compile_code != 0 or not File.exists?(binary_path) do
          {:error, {:harness_compile, compile_out}}
        else
          {run_out, run_code} = System.cmd(binary_path, [], stderr_to_stdout: true)

          if run_code == 0 do
            {:ok, run_out}
          else
            {:error, {:harness_run, run_code, run_out}}
          end
        end
    end
  end

  defp elmc_execution_harness_source(entry_module) do
    fn_name = "elmc_fn_#{entry_module}_main"

    """
    #include "elmc_generated.h"
    #include "elmc_generated.c"
    #include <stdio.h>

    int main(void) {
      ElmcValue *result = #{fn_name}(NULL, 0);
      if (result && result->tag == ELMC_TAG_STRING && result->payload) {
        fputs((const char *)result->payload, stdout);
        fputc('\\n', stdout);
      }
      elmc_release(result);
      return 0;
    }
    """
  end

  defp host_module_source(target_module) do
    """
    module CorpusHost exposing (main)

    import #{target_module}
    import Debug

    main : String
    main =
        Debug.toString #{target_module}.main
    """
  end

  defp mismatch_detail(actual, gold) do
    "expected #{inspect(gold)} got #{inspect(actual)}"
  end

  defp host_elm_json do
    %{
      "type" => "application",
      "source-directories" => ["src"],
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{"elm/core" => "1.0.5"},
        "indirect" => %{}
      },
      "test-dependencies" => %{
        "direct" => %{},
        "indirect" => %{}
      }
    }
  end

  @spec compile_probe!(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def compile_probe!(rel_path, tmp_root, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)

    task =
      Task.async(fn ->
        do_compile_probe(rel_path, tmp_root)
      end)

    try do
      Task.await(task, timeout_ms)
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  defp do_compile_probe(rel_path, tmp_root) do
    module = module_name(rel_path)
    tmp_dir = Path.join(tmp_root, path_slug(rel_path))
    src_path = Path.join(corpus_dir(), rel_path)

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    File.cp!(src_path, Path.join(tmp_dir, Path.basename(src_path)))

    File.write!(
      Path.join(tmp_dir, "elm.json"),
      Jason.encode!(minimal_elm_json(), pretty: true) <> "\n"
    )

    out_dir = Path.join(tmp_dir, "out")

    case Elmc.compile(tmp_dir, %{
           out_dir: out_dir,
           strip_dead_code: false,
           entry_module: module
         }) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec run_compile_gate!(keyword()) :: map()
  def run_compile_gate!(opts \\ []) do
    index = Keyword.get_lazy(opts, :index, &build_index/0)
    tmp_root = Keyword.get(opts, :tmp_root, Path.expand("../tmp/elm_run_corpus_compile", __DIR__)) |> Path.expand()
    paths = Keyword.get(opts, :paths, compile_eligible_paths(index))
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)
    progress? = Keyword.get(opts, :progress, false)

    File.mkdir_p!(tmp_root)

    results =
      Enum.map(paths, fn path ->
        if progress?, do: IO.write(:stderr, "corpus compile #{path}\n")

        started = System.monotonic_time(:millisecond)

        {status, detail} =
          case compile_probe!(path, tmp_root, timeout_ms: timeout_ms) do
            :ok -> {:ok, nil}
            {:error, :timeout} -> {:error, "timeout after #{timeout_ms}ms"}
            {:error, reason} -> {:error, inspect(reason, limit: 8)}
          end

        elapsed_ms = System.monotonic_time(:millisecond) - started

        %{
          "path" => path,
          "status" => Atom.to_string(status),
          "detail" => detail,
          "elapsed_ms" => elapsed_ms
        }
      end)

    ok = Enum.count(results, &(&1["status"] == "ok"))
    failed = length(results) - ok

  %{
      "corpus_sha" => index["corpus_sha"],
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "summary" => %{
        "attempted" => length(results),
        "compile_ok" => ok,
        "compile_failed" => failed,
        "compile_ok_pct" =>
          if(length(results) == 0,
            do: 0.0,
            else: Float.round(ok * 100.0 / length(results), 2)
          )
      },
      "results" => results
    }
  end

  @spec write_scorecard!(map(), String.t()) :: String.t()
  def write_scorecard!(scorecard, out_dir) do
    File.mkdir_p!(out_dir)

    json_path = Path.join(out_dir, "elm_run_corpus_scorecard.json")
    md_path = Path.join(out_dir, "elm_run_corpus_scorecard.md")

    File.write!(json_path, Jason.encode!(scorecard, pretty: true) <> "\n")
    File.write!(md_path, render_scorecard_md(scorecard))

    json_path
  end

  @spec render_scorecard_md(map()) :: String.t()
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
        "_No failures._\n"
      else
        Enum.join(failure_lines, "\n") <> "\n"
      end

    """
    # elm-run Corpus Compile Scorecard

    Generated: `#{scorecard["generated_at"]}`
    Corpus SHA: `#{scorecard["corpus_sha"]}`

    ## Summary

    - Attempted: #{summary["attempted"]}
    - Compile OK: #{summary["compile_ok"]}
    - Compile failed: #{summary["compile_failed"]}
    - Success rate: #{summary["compile_ok_pct"]}%

    ## Failures (first 40)

    #{failures_section}
    """
  end

  defp build_siblings_index do
    corpus_dir()
    |> File.ls!()
    |> Enum.filter(fn name -> File.dir?(Path.join(corpus_dir(), name)) end)
    |> Map.new(fn category ->
      siblings =
        category
        |> sibling_modules()
        |> MapSet.new()

      {category, siblings}
    end)
  end

  defp sibling_modules(category) do
    corpus_dir()
    |> Path.join([category, "*.elm"])
    |> Path.wildcard()
    |> Enum.map(&module_name/1)
  end

  defp build_entry(path, metadata, siblings) do
    imports = extract_imports(Path.join(corpus_dir(), path))
    has_expected = File.exists?(expected_path(path))
    meta = Map.get(metadata, path, %{})

    {tier, skip_reason} =
      cond do
        metadata_skip?(meta) ->
          {:skip, meta["skip"] || meta["known_bug"] || "metadata_skip"}

        metadata_compile_error?(meta) ->
          {:compile_error_expected, meta["error_pattern"] || meta["exit_code"] || "expected_failure"}

        external_imports?(imports, siblings) ->
          {:elm_run_only, "external_import"}

        has_expected and scalar_expected?(path) ->
          {:run_scalar, nil}

        has_expected ->
          {:run_structured, nil}

        true ->
          {:compile_candidate, nil}
      end

    %{
      path: path,
      category: category(path),
      module: module_name(path),
      tier: tier,
      skip_reason: skip_reason,
      metadata: meta,
      has_expected: has_expected,
      imports: imports
    }
  end

  defp metadata_skip?(meta) do
    Enum.any?(@metadata_skip_types, &Map.has_key?(meta, &1))
  end

  defp metadata_compile_error?(meta) do
    Enum.any?(@metadata_compile_error_types, &Map.has_key?(meta, &1))
  end

  defp external_imports?(imports, siblings) do
    Enum.any?(imports, fn mod ->
      not MapSet.member?(@stdlib_modules, mod) and not MapSet.member?(siblings, mod)
    end)
  end

  defp scalar_expected?(path) do
    path
    |> expected_path()
    |> File.read!()
    |> String.trim()
    |> then(fn text ->
      text != "" and not String.starts_with?(text, "{") and not String.starts_with?(text, "[")
    end)
  rescue
    _ -> false
  end

  defp extract_imports(source_path) do
    source_path
    |> File.read!()
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "import "))
    |> Enum.map(fn line ->
      case Regex.run(~r/^import\s+(\S+)/, String.trim(line)) do
        [_, mod] -> mod |> String.split(".") |> hd()
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp summarize(entries) do
    counts =
      entries
      |> Enum.group_by(& &1.tier)
      |> Map.new(fn {tier, group} -> {Atom.to_string(tier), length(group)} end)

    %{
      "total" => length(entries),
      "skip" => Map.get(counts, "skip", 0),
      "elm_run_only" => Map.get(counts, "elm_run_only", 0),
      "compile_error_expected" => Map.get(counts, "compile_error_expected", 0),
      "compile_candidate" => Map.get(counts, "compile_candidate", 0),
      "run_scalar" => Map.get(counts, "run_scalar", 0),
      "run_structured" => Map.get(counts, "run_structured", 0)
    }
  end

  defp entry_to_map(entry) do
    %{
      "path" => entry.path,
      "category" => entry.category,
      "module" => entry.module,
      "tier" => Atom.to_string(entry.tier),
      "skip_reason" => entry.skip_reason,
      "has_expected" => entry.has_expected,
      "imports" => entry.imports,
      "metadata" => entry.metadata
    }
  end

  defp category(path), do: path |> String.split("/") |> hd()

  defp module_name(path) do
    path
    |> Path.basename()
    |> String.replace_suffix(".elm", "")
  end

  defp expected_path(rel_path) do
    rel_path
    |> String.replace_suffix(".elm", ".expected")
    |> then(&Path.join(corpus_dir(), &1))
  end

  defp path_slug(rel_path) do
    rel_path
    |> String.replace("/", "__")
    |> String.replace_suffix(".elm", "")
  end

  defp minimal_elm_json do
    %{
      "type" => "application",
      "source-directories" => ["."],
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{"elm/core" => "1.0.5"},
        "indirect" => %{}
      },
      "test-dependencies" => %{
        "direct" => %{},
        "indirect" => %{}
      }
    }
  end
end
