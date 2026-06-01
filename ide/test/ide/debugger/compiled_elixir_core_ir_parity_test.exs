defmodule Ide.Debugger.CompiledElixirCoreIrParityTest do
  @moduledoc """
  Dual-run parity: same Elm fixture executed via Core IR and `:compiled_elixir`.

  Compares init `runtime_model` fields that both backends should agree on.
  """

  use ExUnit.Case, async: false

  alias ElmEx.CoreIR
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.RuntimeSurfaces

  @project_dir Path.expand("../../../../elmx/test/fixtures/simple_project", __DIR__)

  setup do
    old = Application.get_env(:ide, RuntimeExecutor, [])

    on_exit(fn ->
      Application.put_env(:ide, RuntimeExecutor, old)
    end)

    _ = Application.ensure_all_started(:elmx)
    :ok
  end

  test "simple_project init value matches between core_ir and compiled_elixir" do
    launch_context = RuntimeSurfaces.launch_context_for("basalt", "LaunchUser")

    base_request = %{
      source_root: ".",
      rel_path: "src/Main.elm",
      source: "",
      introspect: %{},
      current_model: %{"launch_context" => launch_context},
      current_view_tree: %{},
      message: nil
    }

    revision = "parity-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} =
             Ide.Compiler.build_elmx_artifacts_in_memory(@project_dir,
               revision: revision,
               strip_dead_code: true
             )

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :compiled_elixir)

    assert {:ok, elmx_payload} =
             RuntimeExecutor.execute(
               Map.merge(base_request, %{
                 elmx_manifest: manifest,
                 elmx_revision: revision
               })
             )

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :core_ir)

    assert {:ok, core_payload} =
             RuntimeExecutor.execute(Map.merge(base_request, core_ir_attrs!()))

    elmx_model = elmx_payload.model_patch["runtime_model"]
    core_model = core_payload.model_patch["runtime_model"]

    assert elmx_model["value"] == core_model["value"]
    assert is_integer(elmx_model["value"])
    assert maybe_nothing?(elmx_model["temperature"])
    assert maybe_nothing?(core_model["temperature"])
  end

  defp core_ir_attrs! do
    {:ok, project} = Bridge.load_project(@project_dir)
    {:ok, ir} = Lowerer.lower_project(project)

    {:ok, core_ir} = CoreIR.from_ir(ir, strict?: false)

    %{
      "elm_executor_core_ir" => core_ir,
      "elm_executor_metadata" => %{
        "compiler" => "elm_executor",
        "contract" => "elm_executor.runtime_executor.v1",
        "mode" => "ide_runtime",
        "entry_module" => "Main",
        "core_ir_validation" => "loose"
      }
    }
  end

  defp maybe_nothing?(:Nothing), do: true
  defp maybe_nothing?(%{"ctor" => "Nothing", "args" => []}), do: true
  defp maybe_nothing?(_), do: false
end
