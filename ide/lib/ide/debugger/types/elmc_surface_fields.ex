defmodule Ide.Debugger.Types.ElmcSurfaceFields do
  @moduledoc """
  Wire `model` map fragments written by `ingest_elmc_*` on debugger surfaces.

  Keys use string literals stored on watch/companion/phone runtime models.
  """

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.{CompileIngestAttrs, ElmcDiagnosticPreview, ElmcEventPayload}

  @type wire_map :: Types.wire_map()

  @type check_fields :: wire_map()
  @type compile_fields :: wire_map()
  @type manifest_fields :: wire_map()
  @type artifact_fields :: wire_map()

  @type surface_target :: :watch | :companion | :phone

  @spec check_fields(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) :: check_fields()
  def check_fields(attrs) when is_map(attrs) do
    %{
      "elmc_check_status" => ElmcEventPayload.status_string(field(attrs, :status)),
      "elmc_error_count" => field(attrs, :error_count) || 0,
      "elmc_warning_count" => field(attrs, :warning_count) || 0,
      "elmc_checked_path" => field(attrs, :checked_path)
    }
  end

  @spec compile_fields(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) :: compile_fields()
  def compile_fields(attrs) when is_map(attrs) do
    cached = field(attrs, :cached) || false
    detail = field(attrs, :detail)

    base =
      %{
        "elmc_compile_status" => ElmcEventPayload.status_string(field(attrs, :status)),
        "elmc_compile_error_count" => field(attrs, :error_count) || 0,
        "elmc_compile_warning_count" => field(attrs, :warning_count) || 0,
        "elmc_compiled_path" => field(attrs, :compiled_path),
        "elmc_compile_revision" => field(attrs, :revision),
        "elmc_compile_cached" => bool_wire(cached)
      }

    if is_binary(detail) and detail != "" do
      Map.put(base, "elmc_compile_detail", detail)
    else
      base
    end
  end

  @spec manifest_fields(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) ::
          manifest_fields()
  def manifest_fields(attrs) when is_map(attrs) do
    strict = field(attrs, :strict) || false
    cached = field(attrs, :cached) || false
    detail = field(attrs, :detail)

    base = %{
      "elmc_manifest_status" => ElmcEventPayload.status_string(field(attrs, :status)),
      "elmc_manifest_error_count" => field(attrs, :error_count) || 0,
      "elmc_manifest_warning_count" => field(attrs, :warning_count) || 0,
      "elmc_manifest_path" => field(attrs, :manifest_path),
      "elmc_manifest_revision" => field(attrs, :revision),
      "elmc_manifest_strict" => bool_wire(strict),
      "elmc_manifest_cached" => bool_wire(cached),
      "elmc_manifest_schema_version" =>
        ElmcEventPayload.manifest_schema_string(field(attrs, :schema_version))
    }

    if is_binary(detail) and detail != "" do
      Map.put(base, "elmc_manifest_detail", detail)
    else
      base
    end
  end

  @spec merge_diagnostic_preview(
          wire_map(),
          CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()
        ) ::
          wire_map()
  def merge_diagnostic_preview(fields, attrs) when is_map(fields) and is_map(attrs) do
    cond do
      Map.has_key?(attrs, :diagnostics) or Map.has_key?(attrs, "diagnostics") ->
        list = field(attrs, :diagnostics) || []
        list = if is_list(list), do: list, else: []
        Map.put(fields, "elmc_diagnostic_preview", ElmcDiagnosticPreview.chunk(list))

      true ->
        fields
    end
  end

  @spec ingest_check_fields(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) ::
          check_fields()
  def ingest_check_fields(attrs) when is_map(attrs) do
    attrs |> check_fields() |> merge_diagnostic_preview(attrs)
  end

  @spec ingest_compile_fields(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) ::
          compile_fields()
  def ingest_compile_fields(attrs) when is_map(attrs) do
    attrs
    |> compile_fields()
    |> merge_diagnostic_preview(attrs)
  end

  @spec ingest_manifest_fields(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) ::
          manifest_fields()
  def ingest_manifest_fields(attrs) when is_map(attrs) do
    attrs |> manifest_fields() |> merge_diagnostic_preview(attrs)
  end

  @spec optional_runtime_artifacts(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) ::
          artifact_fields()
  def optional_runtime_artifacts(attrs) when is_map(attrs) do
    %{}
    |> maybe_put_artifact("debugger_contract", field(attrs, :debugger_contract))
    |> maybe_put_artifact("debugger_contract_b64", field(attrs, :debugger_contract_b64))
    |> maybe_put_artifact("debugger_contract_version", field(attrs, :debugger_contract_version))
    |> maybe_put_artifact("elmx_manifest", field(attrs, :elmx_manifest))
    |> maybe_put_artifact("elmx_revision", field(attrs, :elmx_revision))
    |> maybe_put_artifact("elmx_compile_error", field(attrs, :elmx_compile_error))
    |> maybe_put_artifact("elmx_compile_error_message", field(attrs, :elmx_compile_error_message))
  end

  @spec compile_artifact_target(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) ::
          surface_target() | nil
  def compile_artifact_target(attrs) when is_map(attrs) do
    source_root =
      field(attrs, :source_root) || field(attrs, :compiled_path)

    compile_source_root_to_target(source_root)
  end

  @spec compile_source_root_to_target(String.t() | atom() | nil) :: surface_target() | nil
  def compile_source_root_to_target(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.split(["/", "\\"], trim: true)
      |> List.first()
      |> to_string()

    case normalized do
      "watch" -> :watch
      "protocol" -> nil
      "companion" -> :companion
      "phone" -> :companion
      _ -> nil
    end
  end

  def compile_source_root_to_target(:watch), do: :watch
  def compile_source_root_to_target(:protocol), do: nil
  def compile_source_root_to_target(:companion), do: :companion
  def compile_source_root_to_target(:phone), do: :companion
  def compile_source_root_to_target(_value), do: nil

  @spec field(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map(), atom()) ::
          Types.wire_input() | nil
  defp field(attrs, key) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  @spec bool_wire(boolean()) :: String.t()
  defp bool_wire(true), do: "true"
  defp bool_wire(false), do: "false"

  @spec maybe_put_artifact(artifact_fields(), String.t(), Types.wire_map() | String.t() | nil) ::
          artifact_fields()
  defp maybe_put_artifact(map, key, value) when is_map(map) and is_binary(key) do
    case value do
      v when is_map(v) or is_binary(v) -> Map.put(map, key, v)
      _ -> map
    end
  end
end
