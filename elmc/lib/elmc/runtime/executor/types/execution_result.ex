defmodule Elmc.Runtime.Executor.Types.ExecutionResult do
  @moduledoc """
  Successful return map from `Elmc.Runtime.Executor.execute/1`.

  Mirrors `ElmExecutor.Runtime.SemanticExecutor.Types.ExecutionResult` for IDE adapter parity.
  """

  alias ElmExecutor.Runtime.SemanticExecutor.Types.ExecutionResult, as: ExecutorExecutionResult

  @type t :: ExecutorExecutionResult.t()

  @type wire_map :: ExecutorExecutionResult.wire_map()

  @type model_patch :: ExecutorExecutionResult.model_patch()

  @type runtime_snapshot :: ExecutorExecutionResult.runtime_snapshot()
end
