defmodule Elmc.TestSupport.PrimaryCodegenCase do
  @moduledoc """
  Tests that compile through the production plan-primary pipeline.

  Uses a process-local plan mode (not Application env) so async tests that
  rely on `test_helper`'s `:off` default are not poisoned.
  """

  use ExUnit.CaseTemplate

  using opts do
    quote do
      use ExUnit.Case, unquote(opts)
    end
  end

  setup _tags do
    prev = Process.get(:elmc_plan_ir_mode)
    Process.put(:elmc_plan_ir_mode, :primary)

    on_exit(fn ->
      if is_nil(prev) do
        Process.delete(:elmc_plan_ir_mode)
      else
        Process.put(:elmc_plan_ir_mode, prev)
      end
    end)

    :ok
  end
end

defmodule Elmc.TestSupport.PrimaryCodegen do
  @moduledoc false

  @primary_compile_opts %{plan_ir_mode: :primary, plan_ir_strict: true}

  alias Elmc.CLI.Types, as: ElmcCliTypes

  @spec compile(String.t(), Elmc.TestSupport.Types.compile_opts()) ::
          {:ok, ElmcCliTypes.compile_result()} | {:error, ElmcCliTypes.compile_error()}
  def compile(project_dir, opts \\ %{}) when is_map(opts) do
    Elmc.compile(project_dir, Map.merge(@primary_compile_opts, opts))
  end

  @spec compile_opts(Elmc.TestSupport.Types.compile_opts()) :: Elmc.TestSupport.Types.compile_opts()
  def compile_opts(extra \\ %{}) when is_map(extra), do: Map.merge(@primary_compile_opts, extra)
end
