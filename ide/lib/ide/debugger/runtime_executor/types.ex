defmodule Ide.Debugger.RuntimeExecutor.Types do
  @moduledoc false

  alias ElmEx.DebuggerContract.Payload
  alias Ide.Debugger.RuntimeArtifacts.Types, as: ArtifactTypes
  alias Ide.Debugger.Types
  alias Ide.Debugger.RuntimeExecutor.Request
  alias Ide.Debugger.Types.RuntimeStepResult

  @type execution_input_map :: %{
          required(:source_root) => String.t(),
          required(:rel_path) => String.t() | nil,
          required(:source) => String.t(),
          required(:introspect) => Payload.wire_payload(),
          required(:current_model) => Types.app_model(),
          required(:current_view_tree) => Types.view_output_tree(),
          optional(:message) => String.t() | nil,
          optional(:message_value) => Types.protocol_message_wire_value(),
          optional(:update_branches) => [String.t()] | nil,
          optional(:elmx_manifest) => Types.wire_map(),
          optional(:elmx_revision) => String.t(),
          optional(:vector_resource_indices) => ArtifactTypes.resource_indices(),
          optional(:bitmap_resource_indices) => ArtifactTypes.resource_indices()
        }

  @type execution_input :: Request.t() | execution_input_map()

  @type execution_result :: %{
          required(:model_patch) => RuntimeStepResult.model_patch(),
          required(:view_output) => Types.runtime_view_nodes(),
          required(:runtime) => RuntimeStepResult.runtime_snapshot(),
          required(:protocol_events) => [Types.protocol_event()],
          required(:followup_messages) => [RuntimeStepResult.followup_message()],
          optional(:view_tree) => Types.view_output_tree() | nil
        }

  @type elmx_execution_payload :: Elmx.Types.execution_payload()

  @type elmx_view_preview_payload :: Elmx.Types.view_preview_payload()

  @type executor_wire_result ::
          elmx_execution_payload()
          | %{optional(atom()) => Types.wire_input(), optional(String.t()) => Types.wire_input()}

  @type adapter_request_map ::
          Types.elmx_executor_request()
          | %{
              optional(:source_root) => String.t(),
              optional(:rel_path) => String.t() | nil,
              optional(:source) => String.t(),
              optional(:introspect) => Payload.wire_payload(),
              optional(:current_model) => Types.app_model(),
              optional(:current_view_tree) => Types.view_output_tree(),
              optional(:message) => String.t() | nil,
              optional(:message_value) => Types.protocol_message() | Types.wire_value() | nil,
              optional(:update_branches) => [String.t()] | nil,
              optional(:debugger_contract) => String.t(),
              optional(:elmx_manifest) => Types.elmx_manifest(),
              optional(:elmx_revision) => String.t(),
              optional(:vector_resource_indices) => ArtifactTypes.resource_indices(),
              optional(:bitmap_resource_indices) => ArtifactTypes.resource_indices(),
              optional(:animation_resource_indices) => ArtifactTypes.resource_indices(),
              optional(atom()) => Types.wire_input(),
              optional(String.t()) => Types.wire_input()
            }
end
