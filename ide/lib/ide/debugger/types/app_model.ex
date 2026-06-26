defmodule Ide.Debugger.Types.AppModel do
  @moduledoc """
  User-facing Elm app state on a debugger surface (stripped of shell artifacts).

  Produced by `RuntimeArtifacts.app_model/1` and `RuntimeArtifacts.public_model/1`.
  Wire maps use string keys (`"active_subscriptions"`, `"debugger_contract"`); atom
  keys in `t/0` document the same fields for Dialyzer.
  """

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.InnerRuntimeModel

  @type t :: %{
          optional(:launch_context) => Types.launch_context(),
          optional(:last_path) => String.t(),
          optional(:last_source) => String.t(),
          optional(:runtime_model) => InnerRuntimeModel.t(),
          optional(:runtime_view_output) => Types.runtime_view_nodes(),
          optional(:runtime_model_source) => String.t(),
          optional(:last_message) => String.t() | nil,
          optional(:last_operation) => String.t(),
          optional(:step_counter) => integer(),
          optional(:runtime_execution) => Types.execution_runtime_snapshot(),
          optional(:active_subscriptions) => [Types.active_subscription()],
          optional(:debugger_contract) => Types.debugger_contract(),
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
