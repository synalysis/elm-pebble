defmodule Ide.Debugger.Types.RuntimeStepResult do
  @moduledoc """
  Normalized output from a debugger runtime step (`RuntimeExecutor.execute/1` and adapters).
  """

  alias Ide.Debugger.Protocol.Event
  alias Ide.Debugger.RuntimeExecutor.Types, as: ExecutorTypes
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.ExecutionRuntimeSnapshot

  @type runtime_snapshot :: ExecutionRuntimeSnapshot.t() | ExecutionRuntimeSnapshot.wire_map()

  @type model_patch :: Types.runtime_model_patch()

  @type followup_message ::
          String.t() | Types.protocol_ctor_value() | Types.subscription_payload()

  @type t :: %{
          optional(:model_patch) => model_patch(),
          optional(:view_tree) => Types.view_output_tree() | nil,
          optional(:view_output) => Types.runtime_view_nodes(),
          optional(:runtime) => runtime_snapshot(),
          optional(:protocol_events) => [Event.t() | Event.wire_event()],
          optional(:followup_messages) => [followup_message()],
          optional(String.t()) => Types.wire_input(),
          optional(atom()) => Types.wire_input()
        }

  @type wire_result :: t() | Types.wire_map()

  @spec from_executor_result(ExecutorTypes.execution_result()) :: t()
  def from_executor_result(%{} = result) do
    Ide.Debugger.RuntimeExecutor.ResultNormalizer.normalize_step_result(result)
  end

  @spec from_executor_wire(ExecutorTypes.executor_wire_result()) :: t()
  def from_executor_wire(wire) when is_map(wire) do
    wire
    |> Ide.Debugger.RuntimeExecutor.ResultNormalizer.normalize()
    |> from_executor_result()
  end

  @spec from_local_fallback(
          model_patch(),
          Types.view_output_tree() | nil,
          Types.runtime_view_nodes(),
          [Event.t() | Event.wire_event()],
          [followup_message()]
        ) :: t()
  def from_local_fallback(
        model_patch,
        view_tree,
        view_output \\ [],
        protocol_events \\ [],
        followup_messages \\ []
      )
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
