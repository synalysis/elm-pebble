defmodule Ide.Debugger.CoreIRFixtures do
  @moduledoc false

  alias ElmEx.CoreIR
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer

  @fixture_project_dir Path.expand("../../../elmc/test/fixtures/pebble_surface_project", __DIR__)

  @spec fixture_core_ir() :: CoreIR.t()
  def fixture_core_ir do
    case :persistent_term.get({__MODULE__, :fixture_core_ir}, :missing) do
      %CoreIR{} = core_ir ->
        core_ir

      :missing ->
        core_ir = compile_fixture_core_ir!()
        :persistent_term.put({__MODULE__, :fixture_core_ir}, core_ir)
        core_ir
    end
  end

  @spec fixture_metadata() :: map()
  def fixture_metadata do
    %{
      "compiler" => "elm_executor",
      "contract" => "elm_executor.runtime_executor.v1",
      "mode" => "ide_runtime",
      "entry_module" => "Main",
      "core_ir_validation" => "strict"
    }
  end

  @spec step_input_attrs() :: map()
  def step_input_attrs do
    %{
      "elm_executor_core_ir" => fixture_core_ir(),
      "elm_executor_metadata" => fixture_metadata()
    }
  end

  # Test-only: builds versioned Core IR from the elmc surface fixture (may include
  # residual unsupported nodes filtered at runtime by CoreIRContract in production).
  defp compile_fixture_core_ir! do
    with {:ok, project} <- Bridge.load_project(@fixture_project_dir),
         {:ok, ir} <- Lowerer.lower_project(project),
         {:ok, core_ir} <- CoreIR.from_ir(ir, strict?: false) do
      core_ir
    else
      error -> raise "failed to build Core IR fixture: #{inspect(error)}"
    end
  end
end
