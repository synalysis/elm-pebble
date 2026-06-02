defmodule Ide.Debugger.Types.AppModel do
  @moduledoc """
  User-facing Elm app state on a debugger surface (stripped of shell artifacts).

  Produced by `RuntimeArtifacts.app_model/1` and `RuntimeArtifacts.public_model/1`.
  """

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.{InnerRuntimeModel, LaunchContext}

  @type t :: %{
          optional(:launch_context) => LaunchContext.t() | LaunchContext.wire_map(),
          optional(:last_path) => String.t(),
          optional(:last_source) => String.t(),
          optional(:runtime_model) => InnerRuntimeModel.t(),
          optional(:runtime_view_output) => Types.runtime_view_nodes(),
          optional(:runtime_model_source) => String.t(),
          optional(:last_message) => String.t() | nil,
          optional(:last_operation) => String.t(),
          optional(:step_counter) => integer(),
          optional(:runtime_execution) => map(),
          optional(String.t()) => Types.wire_input(),
          optional(atom()) => Types.wire_input()
        }

  @type wire_map :: t() | map()
end
