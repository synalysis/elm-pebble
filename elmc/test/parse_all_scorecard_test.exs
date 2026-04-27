defmodule Elmc.ParseAllScorecardTest do
  use ExUnit.Case

  alias ElmEx.Frontend.GeneratedExpressionParser
  alias ElmEx.Frontend.GeneratedParser

  @artifact_dir Path.expand("tmp/parse_all", __DIR__)
  @json_path Path.join(@artifact_dir, "scorecard.json")
  @md_path Path.join(@artifact_dir, "scorecard.md")
  @expected_module_parse_failures []
  @expected_elm_make_failure_modules []

  setup_all do
    scorecard = build_scorecard()
    :ok = write_scorecard(scorecard)
    {:ok, scorecard: scorecard}
  end

  test "writes parse-all scorecard artifacts", %{scorecard: scorecard} do
    assert File.exists?(@json_path)
    assert File.exists?(@md_path)

    assert scorecard.corpus_files.total > 0
    assert map_size(scorecard.fixtures) > 1
  end

  test "parse-all corpus gate stays green", %{scorecard: scorecard} do
    expected_expr_failures = expected_expression_parse_failures(scorecard.fixture_configs)
    expected_unsupported = expected_unsupported_expr_roots(scorecard.fixture_configs)
    expected_elm_excluded = expected_elm_make_excluded_modules(scorecard.fixture_configs)

    assert scorecard.module_parse_failures == @expected_module_parse_failures
    assert scorecard.expression_parse_failures == expected_expr_failures
    assert scorecard.unsupported_expr_roots == expected_unsupported

    if scorecard.elm_compiler.available do
      failure_modules =
        scorecard.elm_compiler.module_make_failures
        |> Enum.map(& &1.module)
        |> Enum.sort()

      assert failure_modules == Enum.sort(@expected_elm_make_failure_modules)
      assert scorecard.elm_compiler.excluded_modules == expected_elm_excluded
    end
  end

  defp build_scorecard do
    file_paths = corpus_paths()
    supplemental_paths = supplemental_corpus_paths()
    fixture_configs = fixture_configs()
    per_file = score_paths(file_paths)
    supplemental_per_file = score_paths(supplemental_paths)

    parse_errors =
      per_file
      |> Enum.filter(&(&1.status == "parse_error"))
      |> Enum.map(fn row -> %{file: row.file, error: row.parse_error} end)

    expr_failures =
      per_file
      |> Enum.flat_map(& &1.expr_parse_failures)
      |> Enum.sort()

    unsupported_roots =
      per_file
      |> Enum.flat_map(& &1.unsupported_roots)
      |> Enum.sort()

    fixtures = fixture_rollup(per_file)
    supplemental_fixtures = fixture_rollup(supplemental_per_file)
    elm_compiler = elm_make_score(per_file, fixture_configs)

    supplemental_parse_errors =
      supplemental_per_file
      |> Enum.filter(&(&1.status == "parse_error"))
      |> Enum.map(fn row -> %{file: row.file, error: row.parse_error} end)

    supplemental_expr_failures =
      supplemental_per_file
      |> Enum.flat_map(& &1.expr_parse_failures)
      |> Enum.sort()

    supplemental_unsupported =
      supplemental_per_file
      |> Enum.flat_map(& &1.unsupported_roots)
      |> Enum.sort()

    %{
      generated_at: Date.utc_today() |> Date.to_iso8601(),
      corpus_files: %{total: length(file_paths)},
      supplemental_corpus: %{
        enabled: include_package_cache_corpus?(),
        total: length(supplemental_paths),
        fixtures: supplemental_fixtures,
        module_parse_failures: supplemental_parse_errors,
        expression_parse_failures: supplemental_expr_failures,
        unsupported_expr_roots: supplemental_unsupported
      },
      fixtures: fixtures,
      fixture_configs: fixture_configs,
      module_parse_failures: parse_errors,
      expression_parse_failures: expr_failures,
      unsupported_expr_roots: unsupported_roots,
      elm_compiler: elm_compiler
    }
  end

  defp corpus_paths do
    fixture_root = Path.expand("fixtures", __DIR__)
    shared_root = Path.expand("../shared/elm", File.cwd!())

    (Path.wildcard(Path.join(fixture_root, "*/src/**/*.elm")) ++
       Path.wildcard(Path.join(shared_root, "**/*.elm")))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp supplemental_corpus_paths do
    if include_package_cache_corpus?() do
      package_cache_paths()
    else
      []
    end
  end

  defp include_package_cache_corpus? do
    case System.get_env("ELMC_PARSE_ALL_INCLUDE_PACKAGE_CACHE", "0") do
      value when value in ["1", "true", "TRUE", "yes", "YES"] -> true
      _ -> false
    end
  end

  defp package_cache_paths do
    owner_root = Path.expand("~/.elm/0.19.1/packages/elm")

    if File.dir?(owner_root) do
      owner_root
      |> Path.join("*/")
      |> Path.wildcard()
      |> Enum.flat_map(fn package_dir ->
        case latest_version_path(package_dir) do
          nil -> []
          version_dir -> Path.wildcard(Path.join(version_dir, "src/**/*.elm"))
        end
      end)
      |> Enum.uniq()
      |> Enum.sort()
    else
      []
    end
  end

  defp latest_version_path(package_dir) do
    version_dirs =
      package_dir
      |> Path.join("*/")
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)

    case version_dirs do
      [] -> nil
      dirs -> Enum.max_by(dirs, &version_sort_key/1)
    end
  end

  defp version_sort_key(path) do
    version =
      path
      |> String.trim_trailing("/")
      |> Path.basename()

    version
    |> String.split(".")
    |> Enum.map(fn segment ->
      case Integer.parse(segment) do
        {int, _rest} -> int
        :error -> 0
      end
    end)
  end

  defp score_paths(file_paths) do
    Enum.map(file_paths, fn path ->
      fixture = fixture_name(path)
      relative = relative_module_path(path)

      case safe_parse_file(path) do
        {:ok, module} ->
          function_decls =
            module.declarations
            |> Enum.filter(
              &(&1.kind == :function_definition and is_binary(&1.body) and &1.body != "")
            )

          expr_parse_failures =
            function_decls
            |> Enum.filter(fn decl ->
              match?({:error, _}, GeneratedExpressionParser.parse(decl.body))
            end)
            |> Enum.map(&"#{relative}##{&1.name}")

          unsupported_roots =
            function_decls
            |> Enum.filter(fn decl -> collect_unsupported(decl.expr) != [] end)
            |> Enum.map(&"#{relative}##{&1.name}")

          %{
            fixture: fixture,
            file: relative,
            status: "ok",
            expr_parse_failures: expr_parse_failures,
            unsupported_roots: unsupported_roots
          }

        {:error, reason} ->
          %{
            fixture: fixture,
            file: relative,
            status: "parse_error",
            parse_error: inspect(reason),
            expr_parse_failures: [],
            unsupported_roots: []
          }
      end
    end)
  end

  defp safe_parse_file(path) when is_binary(path) do
    try do
      GeneratedParser.parse_file(path)
    rescue
      exception ->
        {:error, {:exception, Exception.message(exception)}}
    catch
      kind, reason ->
        {:error, {:caught, kind, reason}}
    end
  end

  defp write_scorecard(scorecard) do
    File.mkdir_p!(@artifact_dir)
    File.write!(@json_path, Jason.encode!(scorecard, pretty: true) <> "\n")
    File.write!(@md_path, render_markdown(scorecard))
    :ok
  end

  defp render_markdown(scorecard) do
    parse_failures = scorecard.module_parse_failures
    expr_failures = scorecard.expression_parse_failures
    unsupported = scorecard.unsupported_expr_roots
    elm_compiler = scorecard.elm_compiler
    supplemental = scorecard.supplemental_corpus

    """
    # Parse-All Scorecard

    Generated: `#{scorecard.generated_at}`

    ## Corpus

    - Files scanned: `#{scorecard.corpus_files.total}`
    - Fixture projects: `#{map_size(scorecard.fixtures)}`
    - Module parse failures: `#{length(parse_failures)}`
    - Expression parse failures: `#{length(expr_failures)}`
    - Unsupported expression roots: `#{length(unsupported)}`
    - Elm compiler available: `#{elm_compiler.available}`
    - Elm make module failures: `#{length(elm_compiler.module_make_failures)}`

    ## Supplemental corpus (non-gating)

    - Enabled: `#{supplemental.enabled}`
    - Files scanned: `#{supplemental.total}`
    - Fixture groups: `#{map_size(supplemental.fixtures)}`
    - Module parse failures: `#{length(supplemental.module_parse_failures)}`
    - Expression parse failures: `#{length(supplemental.expression_parse_failures)}`
    - Unsupported expression roots: `#{length(supplemental.unsupported_expr_roots)}`

    supplemental fixtures:
    #{markdown_fixture_summary(supplemental.fixtures)}

    supplemental module parse failures:
    #{markdown_list(supplemental.module_parse_failures, fn row -> "`#{row.file}` :: #{row.error}" end)}

    supplemental expression parse failures:
    #{markdown_list(supplemental.expression_parse_failures, &"`#{&1}`")}

    supplemental unsupported expression roots:
    #{markdown_list(supplemental.unsupported_expr_roots, &"`#{&1}`")}

    ## Fixtures

    #{markdown_fixture_summary(scorecard.fixtures)}

    ## Module parse failures

    #{markdown_list(parse_failures, fn row -> "`#{row.file}` :: #{row.error}" end)}

    ## Expression parse failures

    #{markdown_list(expr_failures, &"`#{&1}`")}

    ## Unsupported expression roots

    #{markdown_list(unsupported, &"`#{&1}`")}

    ## Elm compiler parity

    #{markdown_elm_compiler_section(elm_compiler)}
    """
  end

  defp markdown_list([], _formatter), do: "- (none)"

  defp markdown_list(items, formatter) do
    items
    |> Enum.map(fn item -> "- " <> formatter.(item) end)
    |> Enum.join("\n")
  end

  defp markdown_fixture_summary(fixtures) when map_size(fixtures) == 0, do: "- (none)"

  defp markdown_fixture_summary(fixtures) do
    fixtures
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map(fn {name, info} ->
      "- `#{name}` files=#{info.files} parse_failures=#{info.parse_failures} expr_failures=#{info.expr_failures} unsupported_roots=#{info.unsupported_roots}"
    end)
    |> Enum.join("\n")
  end

  defp markdown_elm_compiler_section(%{available: false}) do
    "- skipped (elm executable not found)"
  end

  defp markdown_elm_compiler_section(%{available: true} = elm_compiler) do
    """
    - version: `#{elm_compiler.version}`
    - modules checked: `#{elm_compiler.modules_checked}`
    - modules excluded: `#{length(elm_compiler.excluded_modules)}`
    - failures: `#{length(elm_compiler.module_make_failures)}`

    excluded:
    #{markdown_list(elm_compiler.excluded_modules, &"`#{&1}`")}

    failures:
    #{markdown_list(elm_compiler.module_make_failures, fn row -> "`#{row.module}` :: #{row.error}" end)}
    """
  end

  defp fixture_rollup(per_file_rows) do
    per_file_rows
    |> Enum.group_by(& &1.fixture)
    |> Map.new(fn {fixture, rows} ->
      parse_failures = Enum.count(rows, &(&1.status == "parse_error"))
      expr_failures = rows |> Enum.flat_map(& &1.expr_parse_failures) |> length()
      unsupported_roots = rows |> Enum.flat_map(& &1.unsupported_roots) |> length()

      {fixture,
       %{
         files: length(rows),
         parse_failures: parse_failures,
         expr_failures: expr_failures,
         unsupported_roots: unsupported_roots
       }}
    end)
  end

  defp fixture_name(path) when is_binary(path) do
    if cache = package_cache_path_info(path) do
      "cache_#{cache.owner}_#{cache.package}"
    else
      parts = Path.split(path)
      fixture_idx = Enum.find_index(parts, &(&1 == "fixtures"))

      if is_integer(fixture_idx) and fixture_idx + 1 < length(parts) do
        Enum.at(parts, fixture_idx + 1)
      else
        shared_idx = Enum.find_index(parts, &(&1 == "shared"))

        if is_integer(shared_idx) and shared_idx + 1 < length(parts) and
             Enum.at(parts, shared_idx + 1) == "elm" do
          "shared_elm"
        else
          "unknown"
        end
      end
    end
  end

  defp relative_module_path(path) when is_binary(path) do
    if cache = package_cache_path_info(path) do
      Path.join(["cache", cache.owner, cache.package, cache.version | cache.rest])
    else
      parts = Path.split(path)
      fixture_idx = Enum.find_index(parts, &(&1 == "fixtures"))

      cond do
        is_integer(fixture_idx) ->
          parts |> Enum.drop(fixture_idx) |> Path.join()

        true ->
          shared_idx = Enum.find_index(parts, &(&1 == "shared"))

          if is_integer(shared_idx) and shared_idx + 1 < length(parts) and
               Enum.at(parts, shared_idx + 1) == "elm" do
            parts |> Enum.drop(shared_idx) |> Path.join()
          else
            Path.relative_to(path, File.cwd!())
          end
      end
    end
  end

  defp package_cache_path_info(path) when is_binary(path) do
    parts = Path.split(path)
    idx = Enum.find_index(parts, &(&1 == ".elm"))

    if is_integer(idx) do
      case Enum.drop(parts, idx) do
        [".elm", "0.19.1", "packages", owner, package, version | rest] ->
          %{owner: owner, package: package, version: version, rest: rest}

        _ ->
          nil
      end
    else
      nil
    end
  end

  defp fixture_configs do
    fixture_root = Path.expand("fixtures", __DIR__)

    fixture_configs =
      Path.wildcard(Path.join(fixture_root, "*/"))
      |> Enum.map(&Path.basename/1)
      |> Enum.sort()
      |> Map.new(fn fixture ->
        {fixture, load_fixture_config(fixture)}
      end)

    Map.put_new(fixture_configs, "shared_elm", load_shared_config())
  end

  defp load_fixture_config(fixture) when is_binary(fixture) do
    cfg_path = Path.expand("fixtures/#{fixture}/parse_all.json", __DIR__)

    case File.read(cfg_path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{} = decoded} ->
            normalize_fixture_config(decoded)

          _ ->
            %{elm_make_enabled: true, elm_make_excluded_modules: []}
        end

      _ ->
        %{elm_make_enabled: true, elm_make_excluded_modules: []}
    end
  end

  defp normalize_fixture_config(%{} = cfg) do
    enabled =
      case Map.get(cfg, "elm_make_enabled", true) do
        false -> false
        "false" -> false
        _ -> true
      end

    raw = Map.get(cfg, "elm_make_excluded_modules", [])

    excluded =
      if is_list(raw) do
        raw
        |> Enum.filter(&is_binary/1)
        |> Enum.sort()
      else
        []
      end

    expected_expr =
      cfg
      |> Map.get("expected_expression_parse_failures", [])
      |> normalize_expected_failure_list()

    expected_unsupported =
      cfg
      |> Map.get("expected_unsupported_expr_roots", [])
      |> normalize_expected_failure_list()

    %{
      elm_make_enabled: enabled,
      elm_make_excluded_modules: excluded,
      expected_expression_parse_failures: expected_expr,
      expected_unsupported_expr_roots: expected_unsupported
    }
  end

  defp normalize_expected_failure_list(list) when is_list(list) do
    list
    |> Enum.filter(&is_binary/1)
    |> Enum.sort()
  end

  defp normalize_expected_failure_list(_), do: []

  defp load_shared_config do
    cfg_path = Path.expand("../shared/parse_all.json", File.cwd!())

    case File.read(cfg_path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{} = decoded} ->
            normalize_fixture_config(decoded)

          _ ->
            %{elm_make_enabled: false, elm_make_excluded_modules: []}
        end

      _ ->
        %{elm_make_enabled: false, elm_make_excluded_modules: []}
    end
  end

  defp expected_expression_parse_failures(fixture_configs) do
    fixture_configs
    |> Map.values()
    |> Enum.flat_map(&Map.get(&1, :expected_expression_parse_failures, []))
    |> Enum.sort()
  end

  defp expected_unsupported_expr_roots(fixture_configs) do
    fixture_configs
    |> Map.values()
    |> Enum.flat_map(&Map.get(&1, :expected_unsupported_expr_roots, []))
    |> Enum.sort()
  end

  defp expected_elm_make_excluded_modules(fixture_configs) do
    fixture_configs
    |> Map.values()
    |> Enum.flat_map(&Map.get(&1, :elm_make_excluded_modules, []))
    |> Enum.sort()
  end

  defp elm_make_fixture_dir("shared_elm"), do: Path.expand("../shared", File.cwd!())
  defp elm_make_fixture_dir(fixture), do: Path.expand("fixtures/#{fixture}", __DIR__)

  defp absolute_module_path(module) when is_binary(module) do
    cond do
      String.starts_with?(module, "fixtures/") ->
        Path.expand(module, Path.expand("test", File.cwd!()))

      String.starts_with?(module, "shared/elm/") ->
        Path.expand(module, Path.expand("..", File.cwd!()))

      true ->
        Path.expand(module, File.cwd!())
    end
  end

  defp elm_make_score(per_file_rows, fixture_configs)
       when is_list(per_file_rows) and is_map(fixture_configs) do
    case System.find_executable("elm") do
      nil ->
        %{available: false, modules_checked: 0, module_make_failures: []}

      _elm ->
        File.mkdir_p!(@artifact_dir)

        version =
          case System.cmd("elm", ["--version"], stderr_to_stdout: true) do
            {output, 0} -> String.trim(output)
            {output, _} -> "unknown (#{String.trim(output)})"
          end

        modules =
          per_file_rows
          |> Enum.filter(&(&1.status == "ok"))
          |> Enum.filter(fn row -> fixture_elm_make_enabled?(fixture_configs, row.fixture) end)
          |> Enum.map(fn row -> %{fixture: row.fixture, module: row.file} end)
          |> Enum.sort_by(& &1.module)

        excluded_modules =
          modules
          |> Enum.filter(fn row ->
            row.module in fixture_elm_excluded_modules(fixture_configs, row.fixture)
          end)
          |> Enum.map(& &1.module)
          |> Enum.sort()

        modules =
          Enum.reject(modules, fn row ->
            row.module in fixture_elm_excluded_modules(fixture_configs, row.fixture)
          end)

        failures =
          modules
          |> Enum.flat_map(fn %{fixture: fixture, module: module} ->
            path = absolute_module_path(module)
            fixture_dir = elm_make_fixture_dir(fixture)
            rel_module = Path.relative_to(path, fixture_dir)
            docs_out = Path.join(@artifact_dir, "elm-docs-#{fixture}.json")

            case System.cmd("elm", ["make", rel_module, "--docs=#{docs_out}"],
                   cd: fixture_dir,
                   stderr_to_stdout: true
                 ) do
              {_output, 0} ->
                []

              {output, _exit} ->
                [%{module: module, error: first_non_empty_line(output)}]
            end
          end)

        %{
          available: true,
          version: version,
          modules_checked: length(modules),
          excluded_modules: excluded_modules,
          module_make_failures: failures
        }
    end
  end

  defp fixture_elm_excluded_modules(fixture_configs, fixture) do
    fixture_configs
    |> Map.get(fixture, %{elm_make_enabled: true, elm_make_excluded_modules: []})
    |> Map.get(:elm_make_excluded_modules, [])
  end

  defp fixture_elm_make_enabled?(fixture_configs, fixture) do
    fixture_configs
    |> Map.get(fixture, %{elm_make_enabled: true, elm_make_excluded_modules: []})
    |> Map.get(:elm_make_enabled, true)
  end

  defp first_non_empty_line(output) when is_binary(output) do
    output
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      trimmed = String.trim(line)
      if trimmed == "", do: nil, else: trimmed
    end)
    |> case do
      nil -> "(no compiler output)"
      line -> line
    end
  end

  defp collect_unsupported(%{op: :unsupported} = expr), do: [expr]

  defp collect_unsupported(expr) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.flat_map(fn value ->
      cond do
        is_map(value) ->
          collect_unsupported(value)

        is_list(value) ->
          value
          |> Enum.flat_map(fn item ->
            if is_map(item), do: collect_unsupported(item), else: []
          end)

        true ->
          []
      end
    end)
  end

  defp collect_unsupported(_), do: []
end
