defmodule Ide.Debugger.Types.ElmcCliIngestBridge do
  @moduledoc """
  Maps in-process `Elmc.CLI` run results into compiler results and `CompileIngestAttrs`.

  Prefer declared `warnings` from the CLI contract; counts come from normalized diagnostics.
  """

  alias Elmc.CLI.Types, as: CliTypes
  alias Ide.Compiler
  alias Ide.Compiler.Diagnostics
  alias Ide.Debugger.Types.{CompileIngestAttrs, CompileIngestBridge}

  @type ingest_opts :: keyword()

  @spec to_check_result(CliTypes.project_run(), ingest_opts()) :: Compiler.check_result()
  def to_check_result(%{status: status, output: output, warnings: warnings}, opts) when is_list(opts) do
    path = Keyword.fetch!(opts, :checked_path)
    diagnostics = diagnostics_from_warnings(warnings)
    counts = Diagnostics.summary(diagnostics)

    %{
      status: status,
      checked_path: path,
      output: output,
      diagnostics: diagnostics,
      error_count: counts.error_count,
      warning_count: counts.warning_count
    }
  end

  @spec to_compile_result(CliTypes.project_run(), ingest_opts()) :: Compiler.compile_result()
  def to_compile_result(%{status: status, output: output, warnings: warnings}, opts) when is_list(opts) do
    path = Keyword.fetch!(opts, :compiled_path)
    diagnostics = diagnostics_from_warnings(warnings)
    counts = Diagnostics.summary(diagnostics)

    %{
      status: status,
      compiled_path: path,
      revision: Keyword.fetch!(opts, :revision),
      cached?: Keyword.get(opts, :cached?, false),
      output: output,
      diagnostics: diagnostics,
      error_count: counts.error_count,
      warning_count: counts.warning_count,
      elm_executor_core_ir_b64: Keyword.get(opts, :elm_executor_core_ir_b64),
      elm_executor_metadata: Keyword.get(opts, :elm_executor_metadata)
    }
    |> drop_nil_optional_fields()
  end

  @spec to_manifest_result(CliTypes.manifest_run(), ingest_opts()) :: Compiler.manifest_result()
  def to_manifest_result(
        %{status: status, output: output, warnings: warnings, manifest: manifest},
        opts
      )
      when is_list(opts) do
    extra = Keyword.get(opts, :extra_diagnostics, [])
    diagnostics = diagnostics_from_warnings(warnings) ++ Diagnostics.normalize_list(extra)
    counts = Diagnostics.summary(diagnostics)

    %{
      status: status,
      manifest_path: Keyword.fetch!(opts, :manifest_path),
      revision: Keyword.get(opts, :revision),
      cached?: Keyword.get(opts, :cached?, false),
      strict?: Keyword.get(opts, :strict?, false),
      manifest: Keyword.get(opts, :manifest, manifest),
      output: output,
      diagnostics: diagnostics,
      error_count: counts.error_count,
      warning_count: counts.warning_count
    }
  end

  @spec from_check_run(CliTypes.project_run(), ingest_opts()) :: CompileIngestAttrs.t()
  def from_check_run(run, opts) when is_list(opts) do
    run |> to_check_result(opts) |> CompileIngestBridge.from_check_result()
  end

  @spec from_compile_run(CliTypes.project_run(), ingest_opts()) :: CompileIngestAttrs.t()
  def from_compile_run(run, opts) when is_list(opts) do
    attrs =
      run
      |> to_compile_result(opts)
      |> Map.put(:source_root, Keyword.get(opts, :source_root))
      |> Map.put(:detail, compile_detail(run.status, run.output))

    CompileIngestBridge.from_compile_result(attrs)
  end

  @spec from_manifest_run(CliTypes.manifest_run(), ingest_opts()) :: CompileIngestAttrs.t()
  def from_manifest_run(run, opts) when is_list(opts) do
    attrs =
      run
      |> to_manifest_result(opts)
      |> Map.put(:schema_version, manifest_schema_version(Keyword.get(opts, :manifest, run.manifest)))
      |> Map.put(:detail, manifest_detail(run.status, run.output))

    CompileIngestBridge.from_manifest_result(attrs)
  end

  @spec diagnostics_from_warnings([map()]) :: [map()]
  defp diagnostics_from_warnings(warnings) when is_list(warnings) do
    Diagnostics.normalize_list(warnings)
  end

  @spec manifest_schema_version(map() | nil) :: String.t() | integer() | map() | nil
  defp manifest_schema_version(%{"schema_version" => v}), do: v
  defp manifest_schema_version(%{schema_version: v}), do: v
  defp manifest_schema_version(_), do: nil

  @spec compile_detail(CliTypes.run_status(), String.t()) :: String.t() | nil
  defp compile_detail(:error, output) when is_binary(output), do: String.slice(output, 0, 240)
  defp compile_detail(_status, _output), do: nil

  @spec manifest_detail(CliTypes.run_status(), String.t()) :: String.t() | nil
  defp manifest_detail(:error, output) when is_binary(output), do: String.slice(output, 0, 240)
  defp manifest_detail(_status, _output), do: nil

  @spec drop_nil_optional_fields(map()) :: map()
  defp drop_nil_optional_fields(map) when is_map(map) do
    Map.reject(map, fn
      {key, nil} when key in [:elm_executor_core_ir_b64, :elm_executor_metadata] -> true
      _ -> false
    end)
  end
end
