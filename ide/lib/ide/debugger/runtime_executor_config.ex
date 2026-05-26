defmodule Ide.Debugger.RuntimeExecutorConfig do
  @moduledoc false

  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.RuntimePreview
  alias Ide.Debugger.Types

  @spec module() :: module()
  def module do
    Application.get_env(:ide, Ide.Debugger, [])
    |> Keyword.get(:runtime_executor_module, RuntimeExecutor)
  end

  @spec refresh_from_artifacts(Types.runtime_state()) :: Types.runtime_state()
  def refresh_from_artifacts(state) when is_map(state) do
    RuntimePreview.refresh_from_artifacts(state, module())
  end

  @spec refresh_for_target(Types.runtime_state(), Types.surface_target()) :: Types.runtime_state()
  def refresh_for_target(state, target) when is_map(state) and target in [:watch, :companion, :phone] do
    RuntimePreview.refresh_for_target(state, target, module())
  end
end
