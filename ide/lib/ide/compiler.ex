defmodule Ide.Compiler do
  alias Ide.Compiler.Cache
  alias Ide.Compiler.Diagnostics
  alias Ide.Debugger.Types.ElmcCliIngestBridge
  alias Ide.Compiler.ManifestCache
  alias Ide.PebbleToolchain
  alias ElmEx.Frontend.Bridge

  @moduledoc """
  Boundary for compiler job orchestration and diagnostics streaming.
  """

  @type project_slug :: String.t()
  @type opts :: keyword()
  @type diagnostic :: %{
          severity: String.t(),
          message: String.t(),
          source: String.t(),
          file: String.t() | nil,
          line: integer() | nil,
          column: integer() | nil
        }
  @type check_result :: %{
          status: :ok | :error,
          diagnostics: [diagnostic()],
          error_count: non_neg_integer(),
          warning_count: non_neg_integer(),
          output: String.t(),
          checked_path: String.t()
        }
  @type compile_result :: %{
          required(:status) => :ok | :error,
          required(:diagnostics) => [diagnostic()],
          required(:error_count) => non_neg_integer(),
          required(:warning_count) => non_neg_integer(),
          required(:output) => String.t(),
          required(:compiled_path) => String.t(),
          required(:revision) => String.t(),
          required(:cached?) => boolean(),
          optional(:elmx_manifest) => Ide.Debugger.Types.elmx_manifest(),
          optional(:elmx_revision) => String.t()
        }
  @type elm_json :: %{
          optional(String.t()) => String.t() | integer() | boolean() | list() | map() | nil
        }

  @type elm_report :: %{optional(String.t()) => term()}

  @type dependency_compatibility_row :: %{
          required(:package) => String.t(),
          required(:status) => String.t(),
          optional(:reason_code) => String.t() | nil,
          optional(:message) => String.t() | nil
        }

  @type normalized_manifest :: %{
          required(:schema_version) => pos_integer(),
          required(:supported_packages) => [String.t()],
          required(:excluded_packages) => [String.t()],
          required(:modules_detected) => [String.t()],
          required(:dependency_compatibility) => [dependency_compatibility_row()]
        }

  @type manifest_data :: normalized_manifest()

  @type compiler_error :: atom() | String.t() | tuple()

  @type manifest_result :: %{
          status: :ok | :error,
          diagnostics: [diagnostic()],
          error_count: non_neg_integer(),
          warning_count: non_neg_integer(),
          output: String.t(),
          manifest_path: String.t(),
          revision: String.t(),
          cached?: boolean(),
          strict?: boolean(),
          manifest: manifest_data() | nil
        }

  @callback check(project_slug(), opts()) :: {:ok, check_result()} | {:error, compiler_error()}
  @callback compile(project_slug(), opts()) ::
              {:ok, compile_result()} | {:error, compiler_error()}
  @callback manifest(project_slug(), opts()) ::
              {:ok, manifest_result()} | {:error, compiler_error()}

  @doc """
  Runs `elmc check` for a workspace and returns parsed diagnostics.
  """
  @spec check(project_slug(), opts()) :: {:ok, check_result()} | {:error, compiler_error()}
  def check(_project_slug, opts) do
    workspace_root = Keyword.fetch!(opts, :workspace_root)
    source_roots = Keyword.get(opts, :source_roots)
    check_path = detect_check_path(workspace_root, source_roots)

    case check_path do
      nil ->
        diagnostics =
          Diagnostics.normalize_list([
            %{
              severity: "error",
              source: "elmc",
              message: missing_elm_json_message(workspace_root, source_roots),
              file: nil,
              line: nil,
              column: nil
            }
          ])

        counts = Diagnostics.summary(diagnostics)

        {:ok,
         %{
           status: :error,
           checked_path: workspace_root,
           output: "No elm.json found in workspace roots.",
           diagnostics: diagnostics,
           error_count: counts.error_count,
           warning_count: counts.warning_count
         }}

      project_dir ->
        run_elmc_check(project_dir)
    end
  end

  @doc """
  Runs the editor save-time check for a specific source root.

  The companion phone app is validated with the upstream Elm compiler. Watch-side
  roots are validated with elmc so the editor matches the Pebble runtime compiler.
  """
  @spec check_source_root(project_slug(), opts()) ::
          {:ok, check_result()} | {:error, compiler_error()}
  def check_source_root(project_slug, opts) do
    workspace_root = Keyword.fetch!(opts, :workspace_root)
    source_root = opts |> Keyword.get(:source_root, "watch") |> to_string()
    source_dir = Path.join(workspace_root, source_root)

    project_dir =
      if File.exists?(Path.join(source_dir, "elm.json")), do: source_dir, else: workspace_root

    if source_root == "phone" do
      run_elm_check(project_dir)
    else
      case run_editor_parser_check(project_dir) do
        {:ok, %{status: :ok}} -> check(project_slug, workspace_root: project_dir)
        {:ok, result} -> {:ok, result}
      end
    end
  end

  @doc """
  Returns Elm project roots that should be checked before packaging or building.
  """
  @spec workspace_check_roots(String.t(), [String.t()] | nil) :: [{String.t(), String.t()}]
  def workspace_check_roots(workspace_root, source_roots \\ nil)
      when is_binary(workspace_root) do
    candidates =
      case source_roots do
        roots when is_list(roots) and roots != [] ->
          [{"workspace", workspace_root} | Enum.map(roots, &{&1, Path.join(workspace_root, &1)})]

        _ ->
          Ide.Projects.FileStore.compiler_root_candidates(workspace_root)
          |> Enum.map(fn path ->
            label =
              case Path.relative_to(path, workspace_root) do
                "." -> "workspace"
                rel -> rel
              end

            {label, path}
          end)
      end

    roots =
      candidates
      |> Enum.uniq_by(fn {_label, path} -> path end)
      |> Enum.filter(fn {_label, path} -> Ide.Projects.FileStore.elm_project_dir?(path) end)

    case roots do
      [] ->
        fallback_label =
          case source_roots do
            [first | _] -> first
            _ -> "watch"
          end

        [{fallback_label, Path.join(workspace_root, fallback_label)}]

      found ->
        found
    end
  end

  @doc """
  Runs elmc check for every Elm project root in a workspace.

  Packaging and release flows use this to match the Build page gate.
  """
  @spec check_workspace(project_slug(), opts()) ::
          :ok | {:error, {:compiler_check_failed, String.t(), check_result()}}
  def check_workspace(project_slug, opts) do
    workspace_root = Keyword.fetch!(opts, :workspace_root)
    source_roots = Keyword.get(opts, :source_roots)

    workspace_check_roots(workspace_root, source_roots)
    |> Enum.reduce_while(:ok, fn {label, root_path}, :ok ->
      scoped_slug = Ide.Projects.compiler_cache_key(project_slug, label)

      case check(scoped_slug, workspace_root: root_path, source_roots: nil) do
        {:ok, %{status: :ok}} ->
          {:cont, :ok}

        {:ok, check_result} ->
          {:halt, {:error, {:compiler_check_failed, label, check_result}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Runs `elmc compile` for a workspace and returns parsed diagnostics.
  """
  @spec compile(project_slug(), opts()) :: {:ok, compile_result()} | {:error, compiler_error()}
  def compile(project_slug, opts) do
    workspace_root = Keyword.fetch!(opts, :workspace_root)
    source_roots = Keyword.get(opts, :source_roots)
    compile_path = detect_check_path(workspace_root, source_roots)

    case compile_path do
      nil ->
        diagnostics =
          Diagnostics.normalize_list([
            %{
              severity: "error",
              source: "elmc",
              message: missing_elm_json_message(workspace_root, source_roots),
              file: nil,
              line: nil,
              column: nil
            }
          ])

        counts = Diagnostics.summary(diagnostics)

        {:ok,
         %{
           status: :error,
           compiled_path: workspace_root,
           revision: "none",
           cached?: false,
           output: "No elm.json found in workspace roots.",
           diagnostics: diagnostics,
           error_count: counts.error_count,
           warning_count: counts.warning_count
         }}

      project_dir ->
        revision = workspace_revision(project_dir)

        case Cache.get(project_slug, revision) do
          {:ok, entry} ->
            cached_result = Map.merge(entry.result, %{cached?: true, revision: revision})

            {:ok, maybe_attach_runtime_artifacts(cached_result, project_dir, revision, opts)}

          {:error, :not_found} ->
            {:ok, result} = run_elmc_compile(project_dir, revision, opts)
            :ok = Cache.put(project_slug, revision, result)
            {:ok, result}
        end
    end
  end

  @doc """
  Runs `elmc manifest` for a workspace and returns parsed diagnostics and JSON payload.
  """
  @spec manifest(project_slug(), opts()) :: {:ok, manifest_result()} | {:error, compiler_error()}
  def manifest(project_slug, opts) do
    workspace_root = Keyword.fetch!(opts, :workspace_root)
    source_roots = Keyword.get(opts, :source_roots)
    strict? = Keyword.get(opts, :strict, false)
    manifest_path = detect_check_path(workspace_root, source_roots)

    case manifest_path do
      nil ->
        diagnostics =
          Diagnostics.normalize_list([
            %{
              severity: "error",
              source: "elmc",
              message: missing_elm_json_message(workspace_root, source_roots),
              file: nil,
              line: nil,
              column: nil
            }
          ])

        counts = Diagnostics.summary(diagnostics)

        {:ok,
         %{
           status: :error,
           manifest_path: workspace_root,
           revision: "none",
           cached?: false,
           strict?: strict?,
           manifest: nil,
           output: "No elm.json found in workspace roots.",
           diagnostics: diagnostics,
           error_count: counts.error_count,
           warning_count: counts.warning_count
         }}

      project_dir ->
        revision = workspace_revision(project_dir) <> ":strict=#{strict?}"

        case ManifestCache.get(project_slug, revision) do
          {:ok, entry} ->
            {:ok, Map.merge(entry.result, %{cached?: true, revision: revision})}

          {:error, :not_found} ->
            case run_elmc_manifest(project_dir, revision, strict?) do
              {:ok, result} ->
                :ok = ManifestCache.put(project_slug, revision, result)
                {:ok, result}

              {:error, reason} ->
                {:error, reason}
            end
        end
    end
  end

  @spec run_elmc_check(String.t()) :: {:ok, check_result()} | {:error, compiler_error()}
  defp run_elmc_check(project_dir) do
    project_dir
    |> Elmc.CLI.check_project()
    |> ElmcCliIngestBridge.to_check_result(checked_path: project_dir)
    |> then(&{:ok, &1})
  rescue
    error -> {:error, error}
  end

  @spec run_elm_check(String.t()) :: {:ok, check_result()} | {:error, compiler_error()}
  defp run_elm_check(project_dir) do
    with {:ok, elm_json} <- read_elm_json(project_dir),
         {:ok, elm_bin} <- PebbleToolchain.elm_bin(),
         {:ok, entries} <- elm_make_entries(project_dir, elm_json) do
      case entries do
        [] ->
          {:ok,
           elm_check_result(:error, project_dir, "No Elm source files found for elm make.", [
             %{
               severity: "error",
               source: "elm",
               message: "No Elm source files found for elm make.",
               file: nil,
               line: nil,
               column: nil
             }
           ])}

        [_ | _] ->
          output_path =
            Path.join(
              System.tmp_dir!(),
              "elm-pebble-editor-check-#{System.unique_integer([:positive])}.js"
            )

          try do
            {output, exit_code} =
              System.cmd(
                elm_bin,
                ["make" | entries] ++ ["--report=json", "--output", output_path],
                cd: project_dir,
                stderr_to_stdout: true
              )

            status = if exit_code == 0, do: :ok, else: :error

            diagnostics =
              status
              |> parse_elm_diagnostics(output, project_dir)
              |> Diagnostics.normalize_list()

            {:ok, elm_check_result(status, project_dir, output, diagnostics)}
          after
            File.rm(output_path)
          end
      end
    else
      {:error, reason} ->
        diagnostics =
          Diagnostics.normalize_list([
            %{
              severity: "error",
              source: "elm",
              message: "Could not run Elm check: #{inspect(reason)}",
              file: nil,
              line: nil,
              column: nil
            }
          ])

        {:ok, elm_check_result(:error, project_dir, inspect(reason), diagnostics)}
    end
  rescue
    error -> {:error, error}
  end

  @spec run_editor_parser_check(String.t()) :: {:ok, check_result()}
  defp run_editor_parser_check(project_dir) do
    diagnostics =
      project_dir
      |> elm_source_files_for_check()
      |> Enum.flat_map(fn path ->
        with {:ok, source} <- File.read(path) do
          path
          |> parser_diagnostics_for_source(source)
          |> Enum.map(&Map.put(&1, :file, Path.relative_to(path, project_dir)))
        else
          {:error, reason} ->
            [
              %{
                severity: "error",
                source: "elmc/parser",
                message: "Could not read source file: #{inspect(reason)}",
                file: Path.relative_to(path, project_dir),
                line: nil,
                column: nil
              }
            ]
        end
      end)
      |> Diagnostics.normalize_list()

    counts = Diagnostics.summary(diagnostics)

    status = if counts.error_count > 0 or counts.warning_count > 0, do: :error, else: :ok

    {:ok,
     %{
       status: status,
       checked_path: project_dir,
       output: parser_check_output(status, diagnostics),
       diagnostics: diagnostics,
       error_count: counts.error_count,
       warning_count: counts.warning_count
     }}
  rescue
    error -> {:error, error}
  end

  @spec elm_source_files_for_check(String.t()) :: [String.t()]
  defp elm_source_files_for_check(project_dir) do
    project_dir
    |> Path.join("**/*.elm")
    |> Path.wildcard()
    |> Enum.reject(&String.contains?(&1, "/elm-stuff/"))
    |> Enum.sort()
  end

  @spec parser_diagnostics_for_source(String.t(), String.t()) :: [diagnostic()]
  defp parser_diagnostics_for_source(path, source) do
    source
    |> Ide.Tokenizer.tokenize(mode: :compiler)
    |> Map.get(:diagnostics, [])
    |> Enum.map(fn diag ->
      %{
        severity: "error",
        source: "elmc/parser",
        message: Map.get(diag, :message) || Map.get(diag, "message") || inspect(diag),
        file: path,
        line: Map.get(diag, :line) || Map.get(diag, "line"),
        column: Map.get(diag, :column) || Map.get(diag, "column")
      }
    end)
  end

  @spec parser_check_output(:ok | :error, [diagnostic()]) :: String.t()
  defp parser_check_output(:ok, _diagnostics), do: "parser check: ok"

  defp parser_check_output(:error, diagnostics) do
    diagnostics
    |> Enum.map(fn diag ->
      file = Map.get(diag, :file) || "unknown"
      line = Map.get(diag, :line) || "?"
      column = Map.get(diag, :column) || "?"
      message = Map.get(diag, :message) || ""
      "#{file}:#{line}:#{column}: #{message}"
    end)
    |> Enum.join("\n\n")
  end

  @spec run_elmc_compile(String.t(), String.t(), opts()) :: {:ok, compile_result()}
  defp run_elmc_compile(project_dir, revision, opts) do
    out_dir = Path.join(project_dir, ".elmc-build")

    result =
      try do
        project_dir
        |> Elmc.CLI.compile_project(out_dir)
        |> ElmcCliIngestBridge.to_compile_result(compiled_path: out_dir, revision: revision)
      rescue
        error -> compile_result_from_exception(error, out_dir, revision)
      end

    {:ok, maybe_attach_runtime_artifacts(result, project_dir, revision, opts)}
  end

  @spec compile_result_from_exception(term(), String.t(), String.t()) :: compile_result()
  defp compile_result_from_exception(error, compiled_path, revision) do
    message = Exception.message(error)

    diagnostics =
      Diagnostics.normalize_list([
        %{
          severity: "error",
          source: "elmc",
          message: message,
          file: nil,
          line: nil,
          column: nil
        }
      ])

    counts = Diagnostics.summary(diagnostics)

    %{
      status: :error,
      compiled_path: compiled_path,
      revision: revision,
      cached?: false,
      output: message,
      diagnostics: diagnostics,
      error_count: counts.error_count,
      warning_count: counts.warning_count
    }
  end

  @spec maybe_attach_runtime_artifacts(compile_result(), String.t(), String.t(), opts()) ::
          compile_result()
  defp maybe_attach_runtime_artifacts(result, project_dir, revision, opts)
       when is_map(result) and is_binary(project_dir) do
    result
    |> maybe_attach_debugger_contract(project_dir)
    |> maybe_attach_elmx_artifacts(project_dir, revision, opts)
    |> maybe_attach_stack_report(project_dir)
  end

  defp maybe_attach_runtime_artifacts(result, _project_dir, _revision, _opts), do: result

  @spec maybe_attach_stack_report(compile_result(), String.t()) :: compile_result()
  defp maybe_attach_stack_report(result, project_dir) when is_map(result) do
    stack_report_path = Path.join(project_dir, ".elmc-build/elmc_stack_report.json")

    case Elmc.Backend.CCodegen.StackReport.read_linked_binary(stack_report_path) do
      %{"available" => true} = linked ->
        result
        |> Map.put(:elmc_linked_binary, linked)
        |> maybe_put_stack_report_detail(linked)

      _ ->
        result
    end
  end

  defp maybe_put_stack_report_detail(result, linked) do
    case Elmc.Backend.CCodegen.StackReport.flash_detail(linked) do
      detail when is_binary(detail) -> Map.put(result, :detail, detail)
      _ -> result
    end
  end

  @spec maybe_attach_debugger_contract(compile_result(), String.t()) :: compile_result()
  defp maybe_attach_debugger_contract(result, project_dir)
       when is_map(result) and is_binary(project_dir) do
    with {:ok, project} <- Bridge.load_project(project_dir),
         {:ok, contract} <- Ide.Debugger.CompileContract.build_from_project(project) do
      Map.merge(result, Ide.Debugger.CompileContract.artifact_fields(contract))
    else
      _ -> result
    end
  end

  @spec maybe_attach_elmx_artifacts(compile_result(), String.t(), String.t(), opts()) ::
          compile_result()
  defp maybe_attach_elmx_artifacts(result, project_dir, revision, opts)
       when is_map(result) and is_binary(project_dir) do
    elmx_opts =
      [revision: revision]
      |> maybe_put_elmx_entry_module(Keyword.get(opts, :entry_module))

    case build_elmx_artifacts_in_memory(project_dir, elmx_opts) do
      {:ok, fields} ->
        Map.merge(result, fields)

      {:error, reason} ->
        result
        |> Map.merge(elmx_compile_failure_fields(reason))
        |> record_elmx_compile_gap()
    end
  end

  defp elmx_compile_failure_fields(reason) do
    message = elmx_compile_error_message(reason)

    %{
      elmx_compile_error: reason,
      elmx_compile_error_message: message,
      diagnostics:
        Diagnostics.normalize_list([
          %{
            severity: "warning",
            source: "elmx",
            message: message <> " (debugger runtime only; PBW build uses elmc)",
            file: nil,
            line: nil,
            column: nil
          }
        ])
    }
  end

  defp elmx_compile_error_message({:unsupported_op, op, detail}) when is_binary(detail),
    do: "elmx unsupported op #{inspect(op)}: #{detail}"

  defp elmx_compile_error_message({:unsupported_op, op, detail}),
    do: "elmx unsupported op #{inspect(op)}: #{inspect(detail)}"

  defp elmx_compile_error_message(reason), do: "elmx compile failed: #{inspect(reason)}"

  # elmx is debugger-only; keep elmc compile status so PBW packaging is not blocked.
  @spec record_elmx_compile_gap(map()) :: map()
  defp record_elmx_compile_gap(result) when is_map(result) do
    Map.update(result, :output, nil, fn existing ->
      message = Map.get(result, :elmx_compile_error_message)

      cond do
        is_binary(message) and message != "" ->
          note = message <> " (debugger runtime only; PBW build uses elmc)"

          if is_binary(existing) and existing != "",
            do: existing <> "\n\n" <> note,
            else: note

        true ->
          existing
      end
    end)
  end

  @doc """
  Resolves the Elm entry module for in-memory `elmx` compiles from `src/*.elm` layout.
  Prefers `CompanionApp` when present (phone/pebble companion workspaces), else `Main`.
  """
  @spec default_elmx_entry_module(String.t()) :: String.t()
  def default_elmx_entry_module(project_dir) when is_binary(project_dir) do
    src_dir = Path.join(project_dir, "src")

    cond do
      File.exists?(Path.join(src_dir, "CompanionApp.elm")) ->
        "CompanionApp"

      File.exists?(Path.join(src_dir, "Main.elm")) ->
        "Main"

      true ->
        case src_elm_entry_modules(src_dir) do
          [single] -> single
          _ -> "Main"
        end
    end
  end

  @spec src_elm_entry_modules(String.t()) :: [String.t()]
  defp src_elm_entry_modules(src_dir) when is_binary(src_dir) do
    if File.dir?(src_dir) do
      src_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".elm"))
      |> Enum.map(&Path.rootname/1)
      |> Enum.sort()
    else
      []
    end
  end

  @spec maybe_put_elmx_entry_module(keyword(), String.t() | nil) :: keyword()
  defp maybe_put_elmx_entry_module(opts, entry_module)
       when is_list(opts) and is_binary(entry_module) and entry_module != "" do
    Keyword.put(opts, :entry_module, entry_module)
  end

  defp maybe_put_elmx_entry_module(opts, _entry_module) when is_list(opts), do: opts

  @doc """
  Compiles Elm → Elixir → BEAM in memory for debugger hot-reload (`:compiled_elixir` backend).
  """
  @spec build_elmx_artifacts_in_memory(String.t(), keyword()) ::
          {:ok, %{elmx_manifest: Ide.Debugger.Types.elmx_manifest(), elmx_revision: String.t()}}
          | {:error, term()}
  def build_elmx_artifacts_in_memory(project_dir, opts \\ []) when is_binary(project_dir) do
    revision = Keyword.get(opts, :revision)
    entry_module = Keyword.get(opts, :entry_module) || default_elmx_entry_module(project_dir)

    with {:ok, %Elmx.CompileResult{} = compile_result} <-
           Elmx.compile_in_memory(project_dir, %{
             entry_module: entry_module,
             revision: revision,
             mode: :ide_runtime,
             strip_dead_code: Keyword.get(opts, :strip_dead_code, false)
           }) do
      rev = revision || Map.get(compile_result.manifest, "revision") || "unknown"

      {:ok,
       %{
         elmx_manifest: compile_result.manifest,
         elmx_revision: rev
       }}
    end
  end

  @spec run_elmc_manifest(String.t(), String.t(), boolean()) ::
          {:ok, manifest_result()} | {:error, compiler_error()}
  defp run_elmc_manifest(project_dir, revision, strict?) do
    run = Elmc.CLI.manifest_project(project_dir)
    {normalized_manifest, manifest_diagnostics} = normalize_manifest_payload(run.manifest)

    base =
      ElmcCliIngestBridge.to_manifest_result(run,
        manifest_path: project_dir,
        revision: revision,
        strict?: strict?,
        extra_diagnostics: manifest_diagnostics,
        manifest: normalized_manifest
      )

    {status, diagnostics} = apply_manifest_strict_mode(base.status, base.diagnostics, strict?)
    counts = Diagnostics.summary(diagnostics)

    {:ok,
     %{
       base
       | status: status,
         diagnostics: diagnostics,
         error_count: counts.error_count,
         warning_count: counts.warning_count
     }}
  rescue
    error -> {:error, error}
  end

  @spec elm_check_result(:ok | :error, String.t(), String.t(), [diagnostic()]) :: check_result()
  defp elm_check_result(status, project_dir, output, diagnostics) do
    counts = Diagnostics.summary(diagnostics)

    %{
      status: status,
      checked_path: project_dir,
      output: output,
      diagnostics: diagnostics,
      error_count: counts.error_count,
      warning_count: counts.warning_count
    }
  end

  @spec read_elm_json(String.t()) :: {:ok, elm_json()} | {:error, compiler_error()}
  defp read_elm_json(project_dir) do
    project_dir
    |> Path.join("elm.json")
    |> File.read()
    |> case do
      {:ok, content} -> Jason.decode(content)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec elm_make_entries(String.t(), elm_json()) ::
          {:ok, [String.t()]} | {:error, compiler_error()}
  defp elm_make_entries(project_dir, _elm_json) when is_binary(project_dir) do
    preferred_entries =
      [
        Path.join([project_dir, "src", "CompanionApp.elm"]),
        Path.join([project_dir, "src", "Main.elm"])
      ]
      |> Enum.filter(&File.exists?/1)

    entries =
      case preferred_entries do
        [] -> Path.wildcard(Path.join([project_dir, "src", "**", "*.elm"]))
        [_ | _] -> preferred_entries
      end
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(&Path.relative_to(&1, project_dir))

    {:ok, entries}
  end

  @spec parse_elm_diagnostics(:ok | :error, String.t(), String.t()) :: [diagnostic()]
  defp parse_elm_diagnostics(:ok, output, _project_dir) do
    [
      %{
        severity: "info",
        source: "elm",
        message: String.trim(output) |> empty_fallback("elm make: ok"),
        file: nil,
        line: nil,
        column: nil
      }
    ]
  end

  defp parse_elm_diagnostics(:error, output, project_dir) do
    case decode_elm_report(output) do
      {:ok, %{"type" => "compile-errors", "errors" => errors}} when is_list(errors) ->
        Enum.flat_map(errors, &elm_compile_error_diagnostics(&1, project_dir))

      {:ok, %{} = report} ->
        [elm_problem_to_diagnostic(report, Map.get(report, "path"), project_dir)]

      _ ->
        [
          %{
            severity: "error",
            source: "elm",
            message:
              String.trim(output) |> empty_fallback("elm make failed without JSON diagnostics."),
            file: nil,
            line: nil,
            column: nil
          }
        ]
    end
  end

  @spec decode_elm_report(String.t()) :: {:ok, elm_report()} | :error
  defp decode_elm_report(output) do
    trimmed = String.trim(output || "")

    with start when is_integer(start) <- :binary.match(trimmed, "{") |> match_index(),
         stop when is_integer(stop) <- last_match_index(trimmed, "}") do
      trimmed
      |> binary_part(start, stop - start + 1)
      |> Jason.decode()
      |> case do
        {:ok, %{} = report} -> {:ok, report}
        _ -> :error
      end
    else
      _ -> :error
    end
  end

  @spec elm_compile_error_diagnostics(elm_report(), String.t()) :: [diagnostic()]
  defp elm_compile_error_diagnostics(%{"path" => path, "problems" => problems}, project_dir)
       when is_list(problems) do
    Enum.map(problems, &elm_problem_to_diagnostic(&1, path, project_dir))
  end

  defp elm_compile_error_diagnostics(_, _project_dir), do: []

  @spec elm_problem_to_diagnostic(elm_report(), String.t() | nil, String.t()) :: diagnostic()
  defp elm_problem_to_diagnostic(problem, path, project_dir) when is_map(problem) do
    region = Map.get(problem, "region", %{})
    start = Map.get(region, "start", %{})

    title =
      problem
      |> Map.get("title", "Elm compiler error")
      |> to_string()

    body = elm_message_to_text(Map.get(problem, "message"))

    %{
      severity: "error",
      source: "elm",
      message: [title, body] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n"),
      file: normalize_elm_report_path(path, project_dir),
      line: normalize_json_integer(Map.get(start, "line")),
      column: normalize_json_integer(Map.get(start, "column"))
    }
  end

  @spec normalize_elm_report_path(String.t() | nil, String.t()) :: String.t() | nil
  defp normalize_elm_report_path(path, project_dir) when is_binary(path) do
    if Path.type(path) == :absolute do
      Path.relative_to(path, project_dir)
    else
      path
    end
  end

  defp normalize_elm_report_path(_path, _project_dir), do: nil

  @spec elm_message_to_text(list() | map() | String.t()) :: String.t()
  defp elm_message_to_text(message) when is_list(message) do
    message
    |> Enum.map(&elm_message_to_text/1)
    |> Enum.join("")
    |> String.trim()
  end

  defp elm_message_to_text(%{"string" => string}) when is_binary(string), do: string
  defp elm_message_to_text(message) when is_binary(message), do: message
  defp elm_message_to_text(_), do: ""

  @spec match_index({integer(), integer()} | :nomatch | nil) :: integer() | nil
  defp match_index({index, _length}), do: index
  defp match_index(:nomatch), do: nil

  @spec last_match_index(String.t(), String.t()) :: integer() | nil
  defp last_match_index(text, pattern) do
    text
    |> :binary.matches(pattern)
    |> List.last()
    |> match_index()
  end

  @spec normalize_json_integer(String.t() | integer() | nil) :: integer() | nil
  defp normalize_json_integer(value) when is_integer(value), do: value
  defp normalize_json_integer(_), do: nil

  @spec detect_check_path(String.t(), [String.t()] | nil) :: String.t() | nil
  defp detect_check_path(workspace_root, source_roots) do
    resolve_elm_project_dir(workspace_root, source_roots)
  end

  @doc """
  Resolves the Elm project directory containing `elm.json` for a workspace.
  """
  @spec resolve_elm_project_dir(String.t(), [String.t()] | nil) :: String.t() | nil
  def resolve_elm_project_dir(workspace_root, source_roots \\ nil)
      when is_binary(workspace_root) do
    candidates =
      case source_roots do
        roots when is_list(roots) and roots != [] ->
          [workspace_root | Enum.map(roots, &Path.join(workspace_root, &1))]

        _ ->
          Ide.Projects.FileStore.compiler_root_candidates(workspace_root)
      end

    Enum.find(candidates, &Ide.Projects.FileStore.elm_project_dir?/1)
  end

  @spec missing_elm_json_message(String.t(), [String.t()] | nil) :: String.t()
  defp missing_elm_json_message(workspace_root, source_roots) do
    tried =
      case source_roots do
        roots when is_list(roots) and roots != [] ->
          [workspace_root | Enum.map(roots, &Path.join(workspace_root, &1))]

        _ ->
          Ide.Projects.FileStore.compiler_root_candidates(workspace_root)
      end
      |> Enum.map_join(", ", &Path.join(&1, "elm.json"))
      |> empty_fallback("unknown locations")

    "Could not run compiler: no elm.json found. Checked: #{tried}."
  end

  @spec workspace_revision(String.t()) :: String.t()
  defp workspace_revision(path) do
    path
    |> source_files_for_revision()
    |> Enum.map(fn file ->
      rel = Path.relative_to(file, path)

      case File.stat(file) do
        {:ok, stat} -> "#{rel}:#{stat.size}:#{inspect(stat.mtime)}"
        {:error, reason} -> "#{rel}:error:#{inspect(reason)}"
      end
    end)
    |> Enum.join("|")
    |> then(fn payload ->
      :crypto.hash(:sha256, payload)
      |> Base.encode16(case: :lower)
    end)
  end

  @spec source_files_for_revision(String.t()) :: [String.t()]
  defp source_files_for_revision(path) do
    elm = Path.wildcard(Path.join(path, "**/*.elm"))
    json = Path.wildcard(Path.join(path, "**/*.json"))

    (elm ++ json)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Normalizes manifest payloads into a stable schema and emits validation diagnostics.
  """
  @spec normalize_manifest_payload(manifest_data() | map() | nil) ::
          {normalized_manifest() | nil, [diagnostic()]}
  def normalize_manifest_payload(nil) do
    {nil,
     [
       %{
         severity: "warning",
         source: "elmc/manifest",
         message: "Manifest JSON payload missing or invalid.",
         file: nil,
         line: nil,
         column: nil
       }
     ]}
  end

  def normalize_manifest_payload(payload) when is_map(payload) do
    {supported_packages, supported_issues} =
      normalize_string_list(Map.get(payload, "supported_packages"))

    {excluded_packages, excluded_issues} =
      normalize_string_list(Map.get(payload, "excluded_packages"))

    {modules_detected, modules_issues} =
      normalize_string_list(Map.get(payload, "modules_detected"))

    {dependency_compatibility, compatibility_issues} =
      normalize_dependency_compatibility(Map.get(payload, "dependency_compatibility"))

    normalized = %{
      schema_version: 1,
      supported_packages: supported_packages,
      excluded_packages: excluded_packages,
      modules_detected: modules_detected,
      dependency_compatibility: dependency_compatibility
    }

    issues = supported_issues ++ excluded_issues ++ modules_issues ++ compatibility_issues

    diagnostics =
      Enum.map(issues, fn issue ->
        %{
          severity: "warning",
          source: "elmc/manifest",
          message: issue,
          file: nil,
          line: nil,
          column: nil
        }
      end)

    {normalized, diagnostics}
  end

  @spec normalize_string_list(list() | map() | nil) :: {[String.t()], [String.t()]}
  defp normalize_string_list(value) when is_list(value) do
    if Enum.all?(value, &is_binary/1) do
      {value, []}
    else
      filtered = Enum.filter(value, &is_binary/1)
      {filtered, ["Manifest contained non-string list entries; dropped invalid values."]}
    end
  end

  defp normalize_string_list(nil) do
    {[], ["Manifest missing expected list field; using empty list."]}
  end

  defp normalize_string_list(_other) do
    {[], ["Manifest field had unexpected type; using empty list."]}
  end

  @spec normalize_dependency_compatibility(list() | map() | nil) ::
          {[dependency_compatibility_row()], [String.t()]}
  defp normalize_dependency_compatibility(value) when is_list(value) do
    rows =
      value
      |> Enum.filter(&is_map/1)
      |> Enum.map(fn row ->
        %{
          package: Map.get(row, "package"),
          status: Map.get(row, "status"),
          reason_code: Map.get(row, "reason_code"),
          message: Map.get(row, "message")
        }
      end)
      |> Enum.filter(fn row -> is_binary(row.package) and is_binary(row.status) end)

    dropped = length(value) - length(rows)

    issues =
      if dropped > 0, do: ["Manifest compatibility rows contained invalid entries."], else: []

    {rows, issues}
  end

  defp normalize_dependency_compatibility(nil), do: {[], []}

  defp normalize_dependency_compatibility(_),
    do: {[], ["Manifest compatibility field had unexpected type."]}

  @spec apply_manifest_strict_mode(:ok | :error, [diagnostic()], boolean()) ::
          {:ok | :error, [diagnostic()]}
  defp apply_manifest_strict_mode(status, diagnostics, false), do: {status, diagnostics}

  defp apply_manifest_strict_mode(status, diagnostics, true) do
    has_manifest_warnings? =
      Enum.any?(diagnostics, fn diag ->
        diag.source == "elmc/manifest" and diag.severity in ["warning", "error"]
      end)

    if has_manifest_warnings? do
      strict_diag = %{
        severity: "error",
        source: "elmc/manifest",
        message: "Manifest strict mode failed due to validation warnings.",
        file: nil,
        line: nil,
        column: nil
      }

      {:error, diagnostics ++ [strict_diag]}
    else
      {status, diagnostics}
    end
  end

  @spec empty_fallback(String.t(), String.t()) :: String.t()
  defp empty_fallback("", fallback), do: fallback
  defp empty_fallback(value, _fallback), do: value
end
