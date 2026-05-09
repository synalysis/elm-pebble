defmodule Ide.Compiler do
  alias Ide.Compiler.Cache
  alias Ide.Compiler.Diagnostics
  alias Ide.Compiler.ManifestCache
  alias ElmEx.CoreIR
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer

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
          optional(:elm_executor_core_ir_b64) => String.t(),
          optional(:elm_executor_metadata) => map()
        }
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
          manifest: map() | nil
        }

  @callback check(project_slug(), opts()) :: {:ok, [diagnostic()]} | {:error, term()}
  @callback compile(project_slug(), opts()) :: {:ok, map()} | {:error, term()}
  @callback manifest(project_slug(), opts()) :: {:ok, manifest_result()} | {:error, term()}

  @doc """
  Runs `elmc check` for a workspace and returns parsed diagnostics.
  """
  @spec check(project_slug(), opts()) :: {:ok, check_result()} | {:error, term()}
  def check(_project_slug, opts) do
    workspace_root = Keyword.fetch!(opts, :workspace_root)
    check_path = detect_check_path(workspace_root)

    case check_path do
      nil ->
        diagnostics =
          Diagnostics.normalize_list([
            %{
              severity: "error",
              source: "elmc",
              message:
                "Could not run check: no elm.json found in workspace root, watch, protocol, or phone.",
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
  Runs `elmc compile` for a workspace and returns parsed diagnostics.
  """
  @spec compile(project_slug(), opts()) :: {:ok, compile_result()} | {:error, term()}
  def compile(project_slug, opts) do
    workspace_root = Keyword.fetch!(opts, :workspace_root)
    compile_path = detect_check_path(workspace_root)

    case compile_path do
      nil ->
        diagnostics =
          Diagnostics.normalize_list([
            %{
              severity: "error",
              source: "elmc",
              message:
                "Could not run compile: no elm.json found in workspace root, watch, protocol, or phone.",
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
            {:ok, maybe_attach_elm_executor_artifacts(cached_result, project_dir)}

          {:error, :not_found} ->
            case run_elmc_compile(project_dir, revision) do
              {:ok, result} ->
                :ok = Cache.put(project_slug, revision, result)
                {:ok, result}

              {:error, reason} ->
                {:error, reason}
            end
        end
    end
  end

  @doc """
  Runs `elmc manifest` for a workspace and returns parsed diagnostics and JSON payload.
  """
  @spec manifest(project_slug(), opts()) :: {:ok, manifest_result()} | {:error, term()}
  def manifest(project_slug, opts) do
    workspace_root = Keyword.fetch!(opts, :workspace_root)
    strict? = Keyword.get(opts, :strict, false)
    manifest_path = detect_check_path(workspace_root)

    case manifest_path do
      nil ->
        diagnostics =
          Diagnostics.normalize_list([
            %{
              severity: "error",
              source: "elmc",
              message:
                "Could not run manifest: no elm.json found in workspace root, watch, protocol, or phone.",
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

  @spec run_elmc_check(String.t()) :: {:ok, check_result()} | {:error, term()}
  defp run_elmc_check(project_dir) do
    expr = "Elmc.CLI.main([\"check\", #{inspect(project_dir)}])"

    {output, exit_code} =
      System.cmd("mix", ["run", "-e", expr],
        cd: elmc_root(),
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "dev"}, {"ELMC_WARNINGS_JSON", "1"}]
      )

    status = if exit_code == 0, do: :ok, else: :error

    diagnostics = parse_diagnostics(status, output) |> Diagnostics.normalize_list()
    counts = Diagnostics.summary(diagnostics)

    {:ok,
     %{
       status: status,
       checked_path: project_dir,
       output: output,
       diagnostics: diagnostics,
       error_count: counts.error_count,
       warning_count: counts.warning_count
     }}
  rescue
    error -> {:error, error}
  end

  @spec run_elmc_compile(String.t(), String.t()) :: {:ok, compile_result()} | {:error, term()}
  defp run_elmc_compile(project_dir, revision) do
    out_dir = Path.join(project_dir, ".elmc-build")

    expr =
      "Elmc.CLI.main([\"compile\", #{inspect(project_dir)}, \"--out-dir\", #{inspect(out_dir)}])"

    {output, exit_code} =
      System.cmd("mix", ["run", "-e", expr],
        cd: elmc_root(),
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "dev"}, {"ELMC_WARNINGS_JSON", "1"}]
      )

    status = if exit_code == 0, do: :ok, else: :error

    diagnostics = parse_diagnostics(status, output) |> Diagnostics.normalize_list()
    counts = Diagnostics.summary(diagnostics)

    result = %{
      status: status,
      compiled_path: out_dir,
      revision: revision,
      cached?: false,
      output: output,
      diagnostics: diagnostics,
      error_count: counts.error_count,
      warning_count: counts.warning_count
    }

    {:ok, maybe_attach_elm_executor_artifacts(result, project_dir)}
  rescue
    error -> {:error, error}
  end

  @spec maybe_attach_elm_executor_artifacts(term(), term()) :: term()
  defp maybe_attach_elm_executor_artifacts(result, project_dir)
       when is_map(result) and is_binary(project_dir) do
    if Map.get(result, :status) == :ok do
      case build_elm_executor_artifacts(project_dir) do
        {:ok, %{core_ir: core_ir, metadata: metadata}} ->
          Map.merge(result, %{
            elm_executor_core_ir_b64:
              core_ir
              |> :erlang.term_to_binary()
              |> Base.encode64(),
            elm_executor_metadata: metadata
          })

        _ ->
          result
      end
    else
      result
    end
  end

  defp maybe_attach_elm_executor_artifacts(result, _project_dir), do: result

  @spec build_elm_executor_artifacts(term()) :: term()
  defp build_elm_executor_artifacts(project_dir) when is_binary(project_dir) do
    with {:ok, project} <- Bridge.load_project(project_dir),
         {:ok, ir} <- Lowerer.lower_project(project) do
      build_core_ir_artifact(ir)
    else
      _ -> {:error, :elm_executor_artifacts_unavailable}
    end
  end

  @spec build_core_ir_artifact(term()) :: term()
  defp build_core_ir_artifact(ir) do
    case CoreIR.from_ir(ir, strict?: true) do
      {:ok, core_ir} ->
        {:ok, %{core_ir: core_ir, metadata: elm_executor_artifact_metadata("strict", [])}}

      {:error, error} ->
        with {:ok, core_ir} <- CoreIR.from_ir(ir) do
          {:ok,
           %{
             core_ir: core_ir,
             metadata:
               elm_executor_artifact_metadata(
                 "non_strict",
                 core_ir_validation_diagnostics(error)
               )
           }}
        else
          _ -> {:error, :elm_executor_artifacts_unavailable}
        end
    end
  end

  @spec elm_executor_artifact_metadata(String.t(), [map()]) :: map()
  defp elm_executor_artifact_metadata(validation_mode, diagnostics) do
    %{
      "compiler" => "elm_executor",
      "contract" => "elm_executor.runtime_executor.v1",
      "mode" => "ide_runtime",
      "entry_module" => "Main",
      "core_ir_validation" => validation_mode,
      "core_ir_diagnostics" => diagnostics
    }
  end

  @spec core_ir_validation_diagnostics(term()) :: [map()]
  defp core_ir_validation_diagnostics(%{diagnostics: diagnostics}) when is_list(diagnostics),
    do: diagnostics

  defp core_ir_validation_diagnostics(_error), do: []

  @spec run_elmc_manifest(String.t(), String.t(), boolean()) ::
          {:ok, manifest_result()} | {:error, term()}
  defp run_elmc_manifest(project_dir, revision, strict?) do
    expr = "Elmc.CLI.main([\"manifest\", #{inspect(project_dir)}])"

    {output, exit_code} =
      System.cmd("mix", ["run", "-e", expr],
        cd: elmc_root(),
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "dev"}, {"ELMC_WARNINGS_JSON", "1"}]
      )

    status = if exit_code == 0, do: :ok, else: :error
    {manifest, manifest_diagnostics} = normalize_manifest_payload(extract_manifest_json(output))

    diagnostics =
      (parse_diagnostics(status, output) ++ manifest_diagnostics)
      |> Diagnostics.normalize_list()

    {status, diagnostics} = apply_manifest_strict_mode(status, diagnostics, strict?)
    counts = Diagnostics.summary(diagnostics)

    {:ok,
     %{
       status: status,
       manifest_path: project_dir,
       revision: revision,
       cached?: false,
       strict?: strict?,
       manifest: manifest,
       output: output,
       diagnostics: diagnostics,
       error_count: counts.error_count,
       warning_count: counts.warning_count
     }}
  rescue
    error -> {:error, error}
  end

  @spec parse_diagnostics(:ok | :error, String.t()) :: [diagnostic()]
  defp parse_diagnostics(:ok, output) do
    info = %{
      severity: "info",
      source: "elmc",
      message: String.trim(output) |> empty_fallback("check: ok"),
      file: nil,
      line: nil,
      column: nil
    }

    warnings =
      output
      |> extract_embedded_warnings()
      |> Enum.map(&warning_to_diagnostic/1)

    [
      %{
        info
        | message:
            info.message
            |> String.split("\n")
            |> Enum.reject(&String.starts_with?(&1, "ELMC_WARNINGS_JSON:"))
            |> Enum.join("\n")
            |> String.trim()
            |> empty_fallback("check: ok")
      }
      | warnings
    ]
  end

  defp parse_diagnostics(:error, output) do
    chunks =
      output
      |> String.split(~r/\n(?=-- )/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if chunks == [] do
      [
        %{
          severity: "error",
          source: "elmc",
          message: "Compiler check failed without formatted diagnostics.",
          file: nil,
          line: nil,
          column: nil
        }
      ]
    else
      Enum.map(chunks, &chunk_to_diagnostic/1) ++
        (output
         |> extract_embedded_warnings()
         |> Enum.map(&warning_to_diagnostic/1))
    end
  end

  @spec extract_embedded_warnings(term()) :: term()
  defp extract_embedded_warnings(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "ELMC_WARNINGS_JSON:"))
    |> Enum.flat_map(fn line ->
      payload = String.replace_prefix(line, "ELMC_WARNINGS_JSON:", "")

      case Jason.decode(payload) do
        {:ok, list} when is_list(list) -> list
        {:ok, map} when is_map(map) -> [map]
        _ -> []
      end
    end)
  end

  @spec warning_to_diagnostic(term()) :: term()
  defp warning_to_diagnostic(warning) when is_map(warning) do
    line = warning["line"]

    %{
      severity: warning["severity"] || "warning",
      source: normalize_warning_source(warning["source"]),
      message: warning["message"] || inspect(warning),
      file: warning["file"],
      line: if(is_integer(line), do: line, else: nil),
      column: warning["column"],
      warning_type: warning["type"],
      warning_code: warning["code"],
      warning_constructor: warning["constructor"],
      warning_expected_kind: warning["expected_kind"],
      warning_has_arg_pattern: warning["has_arg_pattern"]
    }
  end

  defp warning_to_diagnostic(_other) do
    %{
      severity: "warning",
      source: "elmc/lowerer",
      message: "Unstructured lowerer warning.",
      file: nil,
      line: nil,
      column: nil
    }
  end

  @spec normalize_warning_source(term()) :: term()
  defp normalize_warning_source(nil), do: "elmc/lowerer"

  defp normalize_warning_source(source) when is_binary(source) do
    if String.starts_with?(source, "elmc/"), do: source, else: "elmc/" <> source
  end

  @spec chunk_to_diagnostic(String.t()) :: diagnostic()
  defp chunk_to_diagnostic(chunk) do
    lines = String.split(chunk, "\n", trim: true)
    title = List.first(lines) || "-- COMPILER ERROR --"
    location = Enum.find(lines, &String.match?(&1, ~r/^.+:\d+:\d+$/))

    {file, line, column} =
      case Regex.run(~r/^(.+):(\d+):(\d+)$/, location || "") do
        [_, file, line, column] -> {file, String.to_integer(line), String.to_integer(column)}
        _ -> {nil, nil, nil}
      end

    %{
      severity: "error",
      source: "elmc",
      message: String.trim(title <> "\n\n" <> Enum.join(lines, "\n")),
      file: file,
      line: line,
      column: column
    }
  end

  @spec detect_check_path(String.t()) :: String.t() | nil
  defp detect_check_path(workspace_root) do
    candidate_paths = [
      workspace_root,
      Path.join(workspace_root, "watch"),
      Path.join(workspace_root, "protocol"),
      Path.join(workspace_root, "phone")
    ]

    Enum.find(candidate_paths, &File.exists?(Path.join(&1, "elm.json")))
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
  @spec normalize_manifest_payload(map() | nil) :: {map() | nil, [diagnostic()]}
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

  @spec extract_manifest_json(String.t()) :: map() | nil
  defp extract_manifest_json(output) when is_binary(output) do
    trimmed = String.trim(output)

    cond do
      trimmed == "" ->
        nil

      true ->
        direct_decode(trimmed) || decode_json_window(trimmed)
    end
  end

  @spec direct_decode(String.t()) :: map() | nil
  defp direct_decode(content) do
    case Jason.decode(content) do
      {:ok, payload} when is_map(payload) -> payload
      _ -> nil
    end
  end

  @spec decode_json_window(String.t()) :: map() | nil
  defp decode_json_window(content) do
    start_idx =
      case :binary.match(content, "{") do
        {idx, _len} -> idx
        :nomatch -> nil
      end

    end_idx =
      content
      |> :binary.matches("}")
      |> List.last()
      |> case do
        {idx, _len} -> idx
        nil -> nil
      end

    if is_integer(start_idx) and is_integer(end_idx) and end_idx > start_idx,
      do: content |> String.slice(start_idx..end_idx) |> direct_decode(),
      else: nil
  end

  @spec normalize_string_list(term()) :: {[String.t()], [String.t()]}
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

  @spec normalize_dependency_compatibility(term()) :: {[map()], [String.t()]}
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

  @spec elmc_root() :: String.t()
  defp elmc_root do
    Application.get_env(:ide, Ide.Compiler, [])
    |> Keyword.fetch!(:elmc_root)
  end

  @spec empty_fallback(String.t(), String.t()) :: String.t()
  defp empty_fallback("", fallback), do: fallback
  defp empty_fallback(value, _fallback), do: value
end
