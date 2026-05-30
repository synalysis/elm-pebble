defmodule ElmExecutor.Runtime.SemanticExecutor do
  @moduledoc """
  Deterministic in-process runtime semantics for elm_executor.

  This is intentionally independent from `Elmc.Runtime.Executor` so elm_executor
  remains a standalone backend/runtime surface.
  """
  @dialyzer :no_match
  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types, as: SemTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Execution
  alias ElmExecutor.Runtime.SemanticExecutor.View
  alias ElmExecutor.Runtime.SemanticExecutor.ViewTreeEval

  @spec evaluate_view_tree_value(map(), map(), map()) :: EvalTypes.runtime_value() | nil
  defdelegate evaluate_view_tree_value(node, runtime_model, eval_context \\ %{}), to: ViewTreeEval

  @spec derive_view_output_preview(map(), map(), map()) :: [map()]
  defdelegate derive_view_output_preview(view_tree, runtime_model, eval_context \\ %{}), to: View

  @spec derive_view_output_for_runtime_model(map(), map()) :: %{
          view_output: [map()],
          view_tree: map()
        }
  defdelegate derive_view_output_for_runtime_model(runtime_model, eval_context), to: View

  @spec drawable_view_tree?(map()) :: boolean()
  defdelegate drawable_view_tree?(tree), to: View

  @spec drawable_view_tree_types() :: [String.t()]
  defdelegate drawable_view_tree_types(), to: View

  @spec execute(SemTypes.execution_request() | map()) ::
          {:ok, SemTypes.execution_result()} | {:error, SemTypes.exec_error()}
  defdelegate execute(request), to: Execution
end
