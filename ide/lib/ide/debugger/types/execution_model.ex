defmodule Ide.Debugger.Types.ExecutionModel do
  @moduledoc """
  Debugger execution surface: shell artifacts merged with app/runtime fields.

  Produced by `RuntimeArtifacts.execution_model/1` via `Map.merge(shell, app_model)`.
  Wire maps use string keys; atom keys in `wire_map/0` document fields for Dialyzer.
  """

  alias ElmEx.DebuggerContract.Payload
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeArtifacts.Types, as: ArtifactTypes
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.{ExecutionRuntimeSnapshot, InnerRuntimeModel, LaunchContext}

  @type t :: wire_map()

  @type wire_map :: %{
          optional(:debugger_contract) => Payload.wire_payload(),
          optional(:debugger_contract_b64) => String.t(),
          optional(:debugger_contract_version) => String.t(),
          optional(:elm_introspect) => Payload.wire_payload(),
          optional(:elmx_manifest) => Types.elmx_manifest(),
          optional(:elmx_revision) => String.t(),
          optional(:vector_resource_indices) => ArtifactTypes.resource_indices(),
          optional(:bitmap_resource_indices) => ArtifactTypes.resource_indices(),
          optional(:animation_resource_indices) => ArtifactTypes.resource_indices(),
          optional(:launch_context) => LaunchContext.t() | LaunchContext.wire_map(),
          optional(:last_path) => String.t(),
          optional(:last_source) => String.t(),
          optional(:runtime_model) => InnerRuntimeModel.t() | InnerRuntimeModel.wire_map(),
          optional(:runtime_view_output) => Types.runtime_view_nodes(),
          optional(:runtime_model_source) => String.t(),
          optional(:last_message) => String.t() | nil,
          optional(:last_operation) => String.t(),
          optional(:step_counter) => integer(),
          optional(:runtime_execution) => ExecutionRuntimeSnapshot.t()
                                           | ExecutionRuntimeSnapshot.wire_map(),
          optional(:active_subscriptions) => [Types.active_subscription()],
          optional(String.t()) => Types.wire_input(),
          optional(atom()) => Types.wire_input()
        }

  @spec from_surface(Surface.surface_map()) :: t()
  def from_surface(surface) when is_map(surface), do: RuntimeArtifacts.execution_model(surface)

  def from_surface(_surface), do: %{}
end
