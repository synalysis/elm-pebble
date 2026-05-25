defmodule Ide.Debugger.Types.RuntimeStepResult do
  @moduledoc """
  Normalized output from a debugger runtime step (`RuntimeExecutor.execute/1` and adapters).
  """

  alias ElmExecutor.Runtime.SemanticExecutor.Types.ExecutionResult, as: ExecutorExecutionResult
  alias ElmExecutor.Runtime.SemanticExecutor.Types.ViewOutputRow
  alias ElmExecutor.Runtime.SemanticExecutor.Types.ViewTreeNode
  alias Ide.Debugger.Protocol.Event
  alias Ide.Debugger.RuntimeExecutor.Types, as: ExecutorTypes
  alias Ide.Debugger.Types.ExecutionRuntimeSnapshot

  @type runtime_snapshot :: ExecutionRuntimeSnapshot.t() | ExecutionRuntimeSnapshot.wire_map()

  @type model_patch :: %{optional(String.t()) => term(), optional(atom()) => term()}

  @type followup_message :: %{optional(String.t()) => term(), optional(atom()) => term()}

  @type t :: %{
          optional(:model_patch) => model_patch(),
          optional(:view_tree) => ViewTreeNode.view_tree() | ViewTreeNode.t() | nil,
          optional(:view_output) => ViewOutputRow.view_output(),
          optional(:runtime) => runtime_snapshot(),
          optional(:protocol_events) => [Event.t() | map()],
          optional(:followup_messages) => [followup_message() | String.t()],
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type wire_result :: t() | map()

  @spec from_executor_result(ExecutorTypes.execution_result()) :: t()
  def from_executor_result(%{} = result) do
    Ide.Debugger.RuntimeExecutor.ResultNormalizer.normalize_step_result(result)
  end

  @spec from_executor_wire(ExecutorExecutionResult.wire_map() | map()) :: t()
  def from_executor_wire(wire) when is_map(wire) do
    wire
    |> Ide.Debugger.RuntimeExecutor.ResultNormalizer.normalize()
    |> from_executor_result()
  end

  @spec from_local_fallback(model_patch(), ViewTreeNode.view_tree() | map(), list(), list(), list()) ::
          t()
  def from_local_fallback(model_patch, view_tree, view_output \\ [], protocol_events \\ [], followup_messages \\ [])
      when is_map(model_patch) do
    %{
      model_patch: model_patch,
      view_tree: view_tree,
      view_output: view_output,
      protocol_events: protocol_events,
      followup_messages: followup_messages
    }
  end
end
