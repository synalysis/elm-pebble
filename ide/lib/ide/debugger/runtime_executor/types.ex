defmodule Ide.Debugger.RuntimeExecutor.Types do
  @moduledoc false

  alias ElmEx.DebuggerContract.Payload
  alias Ide.Debugger.RuntimeArtifacts.Types, as: ArtifactTypes
  alias Ide.Debugger.Types
  alias ElmExecutor.Runtime.SemanticExecutor.Types.ExecutionResult, as: ExecutorExecutionResult
  alias Ide.Debugger.RuntimeExecutor.Request
  alias Ide.Debugger.RuntimeExecutor.Types.RuntimeMode
  alias Ide.Debugger.Types.RuntimeStepResult

  @type runtime_mode :: RuntimeMode.t()

  @type execution_input_map :: %{
          required(:source_root) => String.t(),
          required(:rel_path) => String.t() | nil,
          required(:source) => String.t(),
          required(:introspect) => Payload.wire_payload(),
          required(:current_model) => Types.app_model(),
          required(:current_view_tree) => Types.view_output_tree(),
          optional(:message) => String.t() | nil,
          optional(:message_value) => Types.protocol_message() | map() | nil,
          optional(:update_branches) => [String.t()] | nil,
          optional(:elm_executor_core_ir) => Types.core_ir(),
          optional(:elm_executor_metadata) => map() | nil,
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

  @type executor_wire_result :: ExecutorExecutionResult.t() | ExecutorExecutionResult.wire_map()

  @type adapter_request_map :: %{
          optional(:source_root) => String.t(),
          optional(:rel_path) => String.t() | nil,
          optional(:source) => String.t(),
          optional(:introspect) => Payload.wire_payload(),
          optional(:current_model) => Types.app_model(),
          optional(:current_view_tree) => Types.view_output_tree(),
          optional(:message) => String.t() | nil,
          optional(:update_branches) => [String.t()] | nil,
          optional(:debugger_contract) => String.t(),
          optional(:elm_executor_core_ir) => Types.core_ir(),
          optional(:elm_executor_metadata) => map() | nil,
          optional(atom()) => term()
        }
end
