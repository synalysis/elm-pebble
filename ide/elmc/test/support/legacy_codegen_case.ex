defmodule Elmc.TestSupport.LegacyCodegenCase do
  @moduledoc """
  Tests that assert legacy IR→C body emission (`plan_ir_mode: :off`).
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use ExUnit.Case, unquote([])
    end
  end

  setup _tags do
    prev_mode = Application.get_env(:elmc, :default_plan_ir_mode)
    Application.put_env(:elmc, :default_plan_ir_mode, :off)

    on_exit(fn ->
      Application.put_env(:elmc, :default_plan_ir_mode, prev_mode)
    end)

    :ok
  end
end

defmodule Elmc.TestSupport.LegacyCodegen do
  @moduledoc false

  @legacy_compile_opts %{plan_ir_mode: :off, plan_ir_strict: false}

  @spec compile(String.t(), map()) :: {:ok, term()} | {:error, term()}
  def compile(project_dir, opts \\ %{}) when is_map(opts) do
    Elmc.compile(project_dir, Map.merge(@legacy_compile_opts, opts))
  end

  @spec compile_opts(map()) :: map()
  def compile_opts(extra \\ %{}) when is_map(extra), do: Map.merge(@legacy_compile_opts, extra)
end
