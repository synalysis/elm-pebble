defmodule Ide.Debugger.RuntimeExecutorExecutionBackendTest do
  use ExUnit.Case, async: false

  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.RuntimeExecutor.CompiledElixirAdapter
  alias Ide.Debugger.RuntimeExecutor.ElmExecutorAdapter

  setup do
    old = Application.get_env(:ide, RuntimeExecutor, [])

    on_exit(fn ->
      Application.put_env(:ide, RuntimeExecutor, old)
    end)

    %{old: old}
  end

  defp put_executor_env!(kw) do
    base = Application.get_env(:ide, RuntimeExecutor, [])
    Application.put_env(:ide, RuntimeExecutor, Keyword.merge(base, kw))
  end

  test "execution_backend routes to CompiledElixirAdapter when configured" do
    put_executor_env!(execution_backend: :compiled_elixir)

    assert RuntimeExecutor.execution_backend() == :compiled_elixir
    assert RuntimeExecutor.compiled_elixir_backend?()

    revision = "definitely-unregistered-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    input = %{
      elmx_manifest: %{"contract" => "elmx.runtime_executor.v1"},
      elmx_revision: revision
    }

    assert {:error, {:core_ir_execution_failed, {:elmx_module_not_registered, ^revision}}} =
             CompiledElixirAdapter.execute(input)
  end

  test "execution_backend defaults to compiled_elixir when env unset" do
    put_executor_env!(execution_backend: :compiled_elixir)
    assert RuntimeExecutor.execution_backend() == :compiled_elixir
    assert RuntimeExecutor.compiled_elixir_backend?()
  end

  test "execution_backend uses core_ir adapter module when configured" do
    put_executor_env!(
      execution_backend: :core_ir,
      external_executor_module: ElmExecutorAdapter
    )

    refute RuntimeExecutor.compiled_elixir_backend?()

    assert {:error, {:core_ir_execution_failed, :missing_core_ir}} =
             RuntimeExecutor.execute(%{current_model: %{}})
  end
end
