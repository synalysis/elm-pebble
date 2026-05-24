defmodule Ide.Debugger.RuntimeExecutor.Request do
  @moduledoc """
  Builds validated runtime executor requests from debugger surfaces.
  """

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @type t :: %{
          required(:source_root) => String.t(),
          required(:rel_path) => String.t() | nil,
          required(:source) => String.t(),
          required(:introspect) => Types.elm_introspect(),
          required(:current_model) => Types.app_model(),
          required(:current_view_tree) => Types.view_output_tree(),
          optional(:message) => String.t() | nil,
          optional(:message_value) => Types.protocol_message() | map() | nil,
          optional(:update_branches) => [String.t()] | nil,
          optional(:elm_executor_core_ir) => map() | nil,
          optional(:elm_executor_metadata) => map() | nil
        }

  @spec build(keyword()) :: t()
  def build(opts) when is_list(opts) do
    surface = Keyword.fetch!(opts, :surface)
    execution_model = Surface.execution_model(surface)
    app_model = Surface.app_model(surface)
    introspect = RuntimeArtifacts.require_introspect(execution_model)

    request =
      %{
        source_root: Keyword.get(opts, :source_root, "watch"),
        rel_path: Map.get(app_model, "last_path"),
        source: Map.get(app_model, "last_source") || "",
        introspect: introspect,
        current_model: app_model,
        current_view_tree: Keyword.get(opts, :view_tree) || surface.view_tree || %{},
        message: Keyword.get(opts, :message),
        message_value: Keyword.get(opts, :message_value),
        update_branches: Keyword.get(opts, :update_branches)
      }
      |> Map.merge(RuntimeArtifacts.execution_artifacts(execution_model))
      |> RuntimeArtifacts.put_vector_resource_indices_on_request(execution_model)
      |> RuntimeArtifacts.put_bitmap_resource_indices_on_request(execution_model)

    validate!(request)
  end

  @spec validate!(map()) :: t()
  def validate!(request) when is_map(request) do
    unless is_map(Map.get(request, :introspect)) do
      raise ArgumentError, "runtime executor request requires introspect"
    end

    unless is_map(Map.get(request, :current_model)) do
      raise ArgumentError, "runtime executor request requires current_model"
    end

    request
  end
end
