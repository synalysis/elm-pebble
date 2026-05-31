defmodule Ide.Debugger.RuntimeModelQuality do
  @moduledoc false

  alias ElmExecutor.Runtime.SemanticExecutor.RuntimeModelValues
  alias Ide.Debugger.RuntimeArtifacts

  @doc "Public runtime model map with parser-artifact fields removed for display/export."
  @spec public_runtime_model(map()) :: map()
  def public_runtime_model(model) when is_map(model) do
    model
    |> RuntimeArtifacts.public_model()
    |> RuntimeModelValues.drop_parser_artifacts()
  end

  def public_runtime_model(_model), do: %{}

  @doc "Sorted field names that still contain parser/introspect artifacts."
  @spec unresolved_field_names(map()) :: [String.t()]
  def unresolved_field_names(model) when is_map(model) do
    model
    |> RuntimeArtifacts.public_model()
    |> RuntimeModelValues.unresolved_field_names()
  end

  def unresolved_field_names(_model), do: []

  @doc false
  @spec findings(map()) :: [String.t()]
  def findings(model) when is_map(model) do
    case unresolved_field_names(model) do
      [] ->
        []

      fields ->
        [
          "runtime_model_has_parser_artifacts: #{Enum.join(fields, ", ")}"
        ]
    end
  end

  def findings(_model), do: []
end
