defmodule Ide.Debugger.Types.StepExecutionContract do
  @moduledoc """
  Typed seam for one debugger runtime step:

  `StepInput` → `RuntimeExecutor.Request` → `execution_result` → `RuntimeStepResult`.
  """

  alias ElmExecutor.Runtime.SemanticExecutor.Types.ExecutionResult, as: ExecutorExecutionResult
  alias ElmExecutor.Runtime.SemanticExecutor.Types.ViewTreeNode
  alias Ide.Debugger.RuntimeExecutor.Request
  alias Ide.Debugger.RuntimeExecutor.Types, as: ExecutorTypes
  alias Ide.Debugger.StepInput
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.RuntimeStepResult

  @type executor_request :: Request.t()
  @type executor_request_wire :: ExecutorTypes.execution_input_map()
  @type executor_result :: ExecutorTypes.execution_result()
  @type step_result :: RuntimeStepResult.t()

  @spec request_from(StepInput.t(), keyword()) :: executor_request()
  def request_from(%StepInput{} = step, opts \\ []) when is_list(opts) do
    StepInput.to_executor_request(step, opts)
  end

  @spec step_result_from_executor(executor_result()) :: step_result()
  def step_result_from_executor(%{} = result) do
    RuntimeStepResult.from_executor_result(result)
  end

  @spec step_result_from_wire(ExecutorExecutionResult.wire_map()) :: step_result()
  def step_result_from_wire(wire) when is_map(wire) do
    RuntimeStepResult.from_executor_wire(wire)
  end

  @spec step_result_from_local_fallback(
          RuntimeStepResult.model_patch(),
          ViewTreeNode.view_tree() | ViewTreeNode.t() | nil,
          keyword()
        ) ::
          step_result()
  def step_result_from_local_fallback(model_patch, view_tree, opts \\ [])
      when is_map(model_patch) and is_map(view_tree) and is_list(opts) do
    RuntimeStepResult.from_local_fallback(
      model_patch,
      view_tree,
      Keyword.get(opts, :view_output, []),
      Keyword.get(opts, :protocol_events, []),
      Keyword.get(opts, :followup_messages, [])
    )
  end

  @spec merge_model_patch(Types.app_model(), RuntimeStepResult.model_patch()) :: Types.app_model()
  def merge_model_patch(model, patch) when is_map(model) and is_map(patch) do
    Enum.reduce(patch, model, fn
      {"runtime_model", patch_runtime}, acc when is_map(patch_runtime) ->
        existing =
          case Map.get(acc, "runtime_model") do
            value when is_map(value) -> value
            _ -> %{}
          end

        Map.put(acc, "runtime_model", deep_merge_runtime_model(existing, patch_runtime))

      {key, value}, acc when is_binary(key) ->
        Map.put(acc, key, value)

      {key, value}, acc when is_atom(key) ->
        Map.put(acc, Atom.to_string(key), value)

      _, acc ->
        acc
    end)
  end

  @spec deep_merge_runtime_model(Types.inner_runtime_model(), Types.inner_runtime_model()) ::
          Types.inner_runtime_model()
  defp deep_merge_runtime_model(existing, patch) when is_map(existing) and is_map(patch) do
    Map.merge(existing, patch)
  end

  defp deep_merge_runtime_model(_existing, patch) when is_map(patch), do: patch
end
