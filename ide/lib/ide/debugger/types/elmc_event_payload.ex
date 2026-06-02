defmodule Ide.Debugger.Types.ElmcEventPayload do
  @moduledoc """
  Event payloads for `debugger.elmc_*` runtime history entries.
  """

  alias Ide.Compiler
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.{CompileIngestAttrs, ElmcDiagnosticPreview}

  @type status :: String.t()

  @type diagnostic_preview :: ElmcDiagnosticPreview.preview()

  @type t :: %{
          optional(:status) => status(),
          optional(:checked_path) => String.t() | nil,
          optional(:compiled_path) => String.t() | nil,
          optional(:manifest_path) => String.t() | nil,
          optional(:revision) => String.t() | nil,
          optional(:cached) => boolean(),
          optional(:strict) => boolean(),
          optional(:schema_version) => String.t(),
          optional(:error_count) => non_neg_integer(),
          optional(:warning_count) => non_neg_integer(),
          optional(:detail) => String.t(),
          optional(:diagnostic_preview) => diagnostic_preview(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type wire_map :: t() | map()

  @spec from_check(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) :: t()
  def from_check(attrs) when is_map(attrs) do
    %{
      status: status_string(Map.get(attrs, :status) || Map.get(attrs, "status")),
      checked_path: Map.get(attrs, :checked_path) || Map.get(attrs, "checked_path"),
      error_count: Map.get(attrs, :error_count) || Map.get(attrs, "error_count") || 0,
      warning_count: Map.get(attrs, :warning_count) || Map.get(attrs, "warning_count") || 0
    }
    |> merge_diagnostic_preview(attrs)
  end

  @spec from_compile(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) :: t()
  def from_compile(attrs) when is_map(attrs) do
    detail = Map.get(attrs, :detail) || Map.get(attrs, "detail")

    payload = %{
      status: status_string(Map.get(attrs, :status) || Map.get(attrs, "status")),
      compiled_path: Map.get(attrs, :compiled_path) || Map.get(attrs, "compiled_path"),
      revision: Map.get(attrs, :revision) || Map.get(attrs, "revision"),
      cached: Map.get(attrs, :cached) || Map.get(attrs, "cached") || false,
      error_count: Map.get(attrs, :error_count) || Map.get(attrs, "error_count") || 0,
      warning_count: Map.get(attrs, :warning_count) || Map.get(attrs, "warning_count") || 0
    }

    payload =
      if is_binary(detail) and detail != "" do
        Map.put(payload, :detail, detail)
      else
        payload
      end

    payload
    |> merge_diagnostic_preview(attrs)
  end

  @spec from_manifest(CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) :: t()
  def from_manifest(attrs) when is_map(attrs) do
    detail = Map.get(attrs, :detail) || Map.get(attrs, "detail")

    payload = %{
      status: status_string(Map.get(attrs, :status) || Map.get(attrs, "status")),
      manifest_path: Map.get(attrs, :manifest_path) || Map.get(attrs, "manifest_path"),
      revision: Map.get(attrs, :revision) || Map.get(attrs, "revision"),
      strict: Map.get(attrs, :strict) || Map.get(attrs, "strict") || false,
      cached: Map.get(attrs, :cached) || Map.get(attrs, "cached") || false,
      error_count: Map.get(attrs, :error_count) || Map.get(attrs, "error_count") || 0,
      warning_count: Map.get(attrs, :warning_count) || Map.get(attrs, "warning_count") || 0,
      schema_version:
        manifest_schema_string(
          Map.get(attrs, :schema_version) || Map.get(attrs, "schema_version")
        )
    }

    payload =
      if is_binary(detail) and detail != "" do
        Map.put(payload, :detail, detail)
      else
        payload
      end

    merge_diagnostic_preview(payload, attrs)
  end

  @spec merge_diagnostic_preview(t(), CompileIngestAttrs.t() | CompileIngestAttrs.wire_map()) ::
          t()
  def merge_diagnostic_preview(payload, attrs) when is_map(payload) and is_map(attrs) do
    cond do
      Map.has_key?(attrs, :diagnostics) or Map.has_key?(attrs, "diagnostics") ->
        list = Map.get(attrs, :diagnostics) || Map.get(attrs, "diagnostics") || []
        list = if is_list(list), do: list, else: []
        Map.put(payload, :diagnostic_preview, ElmcDiagnosticPreview.chunk(list))

      true ->
        payload
    end
  end

  @spec status_string(atom() | String.t()) :: status()
  def status_string(:ok), do: "ok"
  def status_string(:error), do: "error"
  def status_string(s) when is_atom(s), do: Atom.to_string(s)
  def status_string(s), do: to_string(s)

  @spec manifest_schema_string(String.t() | integer() | Compiler.manifest_data() | nil) ::
          String.t()
  def manifest_schema_string(v) when is_integer(v), do: Integer.to_string(v)
  def manifest_schema_string(v) when is_binary(v), do: v
  def manifest_schema_string(_), do: "—"
end
