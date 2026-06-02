defmodule Ide.Debugger.Types.CompileIngestBridge do
  @moduledoc """
  Maps `Ide.Compiler` check/compile/manifest results into `CompileIngestAttrs` for debugger ingest.
  """

  alias Ide.Compiler
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.CompileIngestAttrs

  @type check_result :: %{
          optional(:status) => :ok | :error | String.t(),
          optional(:checked_path) => String.t(),
          optional(:output) => String.t(),
          optional(:diagnostics) => list(),
          optional(:error_count) => non_neg_integer(),
          optional(:warning_count) => non_neg_integer(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type compile_result :: %{
          optional(:status) => :ok | :error | String.t(),
          optional(:compiled_path) => String.t(),
          optional(:revision) => String.t(),
          optional(:cached?) => boolean(),
          optional(:output) => String.t(),
          optional(:diagnostics) => list(),
          optional(:error_count) => non_neg_integer(),
          optional(:warning_count) => non_neg_integer(),
          optional(:detail) => String.t(),
          optional(:source_root) => String.t(),
          optional(:elmx_manifest) => map(),
          optional(:elmx_revision) => String.t(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type compiler_result_map :: check_result() | compile_result() | manifest_result()

  @type manifest_result :: %{
          optional(:status) => :ok | :error | String.t(),
          optional(:manifest_path) => String.t() | nil,
          optional(:revision) => String.t(),
          optional(:cached?) => boolean(),
          optional(:strict?) => boolean(),
          optional(:schema_version) => String.t() | integer() | map() | nil,
          optional(:detail) => String.t(),
          optional(:diagnostics) => list(),
          optional(:error_count) => non_neg_integer(),
          optional(:warning_count) => non_neg_integer(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @spec from_compiler_check_result(check_result() | Compiler.check_result()) ::
          CompileIngestAttrs.t()
  def from_compiler_check_result(%{} = result), do: from_check_result(result)

  @spec from_compiler_compile_result(compile_result() | Compiler.compile_result()) ::
          CompileIngestAttrs.t()
  def from_compiler_compile_result(%{} = result), do: from_compile_result(result)

  @spec from_compiler_manifest_result(manifest_result() | Compiler.manifest_result()) ::
          CompileIngestAttrs.t()
  def from_compiler_manifest_result(%{} = result), do: from_manifest_result(result)

  @spec from_check_result(check_result()) :: CompileIngestAttrs.t()
  def from_check_result(result) when is_map(result) do
    %{
      status: Map.get(result, :status) || Map.get(result, "status"),
      checked_path: Map.get(result, :checked_path) || Map.get(result, "checked_path"),
      error_count: count_field(result, :error_count),
      warning_count: count_field(result, :warning_count),
      diagnostics: diagnostics_field(result)
    }
    |> drop_nil_fields()
  end

  @spec from_compile_result(compile_result()) :: CompileIngestAttrs.t()
  def from_compile_result(result) when is_map(result) do
    %{
      status: Map.get(result, :status) || Map.get(result, "status"),
      compiled_path: Map.get(result, :compiled_path) || Map.get(result, "compiled_path"),
      revision: Map.get(result, :revision) || Map.get(result, "revision"),
      cached: cached_field(result),
      error_count: count_field(result, :error_count),
      warning_count: count_field(result, :warning_count),
      detail: Map.get(result, :detail) || Map.get(result, "detail"),
      source_root: Map.get(result, :source_root) || Map.get(result, "source_root"),
      diagnostics: diagnostics_field(result),
      elmx_manifest: Map.get(result, :elmx_manifest) || Map.get(result, "elmx_manifest"),
      elmx_revision: Map.get(result, :elmx_revision) || Map.get(result, "elmx_revision")
    }
    |> drop_nil_fields()
  end

  @spec from_manifest_result(manifest_result()) :: CompileIngestAttrs.t()
  def from_manifest_result(result) when is_map(result) do
    %{
      status: Map.get(result, :status) || Map.get(result, "status"),
      manifest_path: Map.get(result, :manifest_path) || Map.get(result, "manifest_path"),
      revision: Map.get(result, :revision) || Map.get(result, "revision"),
      strict:
        Map.get(result, :strict) || Map.get(result, "strict") || Map.get(result, :strict?) ||
          Map.get(result, "strict?"),
      cached: cached_field(result),
      schema_version: Map.get(result, :schema_version) || Map.get(result, "schema_version"),
      detail: Map.get(result, :detail) || Map.get(result, "detail"),
      error_count: count_field(result, :error_count),
      warning_count: count_field(result, :warning_count),
      diagnostics: diagnostics_field(result)
    }
    |> drop_nil_fields()
  end

  @spec count_field(compiler_result_map(), atom()) :: non_neg_integer() | nil
  defp count_field(map, key) when is_map(map) and is_atom(key) do
    case Map.get(map, key) || Map.get(map, Atom.to_string(key)) do
      n when is_integer(n) and n >= 0 -> n
      _ -> nil
    end
  end

  @spec cached_field(compiler_result_map()) :: boolean() | nil
  defp cached_field(map) when is_map(map) do
    case Map.get(map, :cached?) || Map.get(map, "cached?") || Map.get(map, :cached) ||
           Map.get(map, "cached") do
      value when is_boolean(value) -> value
      _ -> nil
    end
  end

  @spec diagnostics_field(compiler_result_map()) :: [Compiler.diagnostic()] | nil
  defp diagnostics_field(map) when is_map(map) do
    case Map.get(map, :diagnostics) || Map.get(map, "diagnostics") do
      list when is_list(list) -> list
      _ -> nil
    end
  end

  @spec drop_nil_fields(CompileIngestAttrs.t()) :: CompileIngestAttrs.t()
  defp drop_nil_fields(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
