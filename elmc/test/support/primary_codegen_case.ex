defmodule Elmc.TestSupport.PrimaryCodegenCase do
  @moduledoc """
  Tests that compile through the production plan-primary pipeline.
  """

  use ExUnit.CaseTemplate

  using opts do
    quote do
      use ExUnit.Case, unquote(opts)
    end
  end

  setup _tags do
    prev_mode = Application.get_env(:elmc, :default_plan_ir_mode)
    Application.put_env(:elmc, :default_plan_ir_mode, :primary)

    on_exit(fn ->
      Application.put_env(:elmc, :default_plan_ir_mode, prev_mode)
    end)

    :ok
  end
end

defmodule Elmc.TestSupport.PrimaryCodegen do
  @moduledoc false

  @primary_compile_opts %{plan_ir_mode: :primary, plan_ir_strict: true}

  @spec compile(String.t(), map()) :: {:ok, term()} | {:error, term()}
  def compile(project_dir, opts \\ %{}) when is_map(opts) do
    Elmc.compile(project_dir, Map.merge(@primary_compile_opts, opts))
  end

  @spec compile_opts(map()) :: map()
  def compile_opts(extra \\ %{}) when is_map(extra), do: Map.merge(@primary_compile_opts, extra)
end
