defmodule Ide.Debugger.SurfaceCompileElmxTest do
  use ExUnit.Case, async: false

  alias Ide.Compiler
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.RuntimeExecutor.Request
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.StepInput
  alias Ide.Debugger.StepExecution
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types.ElmcSurfaceFields

  setup do
    old = Application.get_env(:ide, Ide.Debugger.RuntimeExecutor, [])

    on_exit(fn ->
      Application.put_env(:ide, Ide.Debugger.RuntimeExecutor, old)
    end)

    Application.put_env(:ide, Ide.Debugger.RuntimeExecutor, execution_backend: :compiled_elixir)
    _ = Application.ensure_all_started(:elmx)
    :ok
  end

  test "Compiler.compile attaches elmx artifacts including on cache hit" do
    workspace = Path.expand("../../../../elmx/test/fixtures/minimal", __DIR__)
    slug = "elmx-surface-compile-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, fresh} = Compiler.compile(slug, workspace_root: workspace)
    assert fresh.status == :ok
    assert is_map(fresh.elmx_manifest)
    assert is_binary(fresh.elmx_revision)
    assert Elmx.module_for_revision(fresh.elmx_revision)

    assert {:ok, cached} = Compiler.compile(slug, workspace_root: workspace)
    assert cached.cached? == true
    assert cached.elmx_revision == fresh.elmx_revision
    assert cached.elmx_manifest["contract"] == "elmx.runtime_executor.v1"
    assert Elmx.module_for_revision(cached.elmx_revision)
  end

  test "Compiler.compile attaches elmx artifacts when attach_elmx_on_compile even on core_ir backend" do
    Application.put_env(:ide, Ide.Debugger.RuntimeExecutor, execution_backend: :core_ir)
    refute RuntimeExecutor.compiled_elixir_backend?()
    assert Application.get_env(:ide, :attach_elmx_on_compile)

    workspace = Path.expand("../../../../elmx/test/fixtures/minimal", __DIR__)
    slug = "elmx-coreir-attach-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, result} = Compiler.compile(slug, workspace_root: workspace)
    assert result.status == :ok
    assert is_map(result.elmx_manifest)
    assert result.elmx_manifest["contract"] == "elmx.runtime_executor.v1"
    assert is_binary(result.elmx_revision)
    assert Elmx.module_for_revision(result.elmx_revision)
  end

  test "runtime artifact merge preserves elmx fields on execution model" do
    workspace = Path.expand("../../../../elmx/test/fixtures/simple_project", __DIR__)
    slug = "elmx-artifacts-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, compile_result} = Compiler.compile(slug, workspace_root: workspace)
    artifacts = ElmcSurfaceFields.optional_runtime_artifacts(compile_result)

    assert RuntimeArtifacts.versioned_elmx_artifacts?(artifacts)

    state = %{watch: %{model: %{}, shell: %{}}}

    merged =
      Ide.Debugger.RuntimeArtifactMerge.maybe_merge(state, :watch, artifacts)

    execution_model =
      merged
      |> Map.get(:watch)
      |> Surface.from_map()
      |> Surface.execution_model()

    assert RuntimeArtifacts.versioned_elmx_artifacts?(execution_model)
    assert execution_model["elmx_revision"] == compile_result.elmx_revision
  end

  test "step execution uses elmx backend after surface artifact attach" do
    workspace = Path.expand("../../../../elmx/test/fixtures/simple_project", __DIR__)
    slug = "elmx-step-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, compile_result} = Compiler.compile(slug, workspace_root: workspace)

    artifacts = %{
      "elmx_manifest" => compile_result.elmx_manifest,
      "elmx_revision" => compile_result.elmx_revision
    }

    surface =
      Surface.from_map(%{
        model: %{"launch_context" => RuntimeSurfaces.launch_context_for("basalt", "LaunchUser")},
        shell: artifacts,
        view_tree: %{}
      })

    init_step =
      StepInput.from_surface(:watch, surface, "", source_root: "watch")

    assert {:ok, init_result} =
             StepExecution.runtime_result(init_step, [])

    runtime_model = get_in(init_result.model_patch, ["runtime_model"])
    assert is_map(runtime_model)

    stepped_surface =
      surface
      |> Surface.put_app_model(
        Map.merge(Surface.app_model(surface), init_result.model_patch || %{})
      )

    step_input =
      stepped_surface
      |> then(&StepInput.from_surface(:watch, &1, "Increment", source_root: "watch"))

    assert {:ok, _step_result} = StepExecution.runtime_result(step_input, [])
  end

  test "RuntimeExecutor Request path after compile artifacts" do
    workspace = Path.expand("../../../../elmx/test/fixtures/minimal", __DIR__)
    slug = "elmx-request-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, compile_result} = Compiler.compile(slug, workspace_root: workspace)

    request =
      %Request{
        source_root: "watch",
        rel_path: "src/Main.elm",
        source: "",
        introspect: %{},
        current_model: %{"launch_context" => %{}},
        current_view_tree: %{},
        message: nil,
        elmx_manifest: compile_result.elmx_manifest,
        elmx_revision: compile_result.elmx_revision
      }
      |> Request.validate_execution_ready!()

    assert {:ok, payload} = RuntimeExecutor.execute(request)
    assert get_in(payload.runtime, ["execution_backend"]) == "compiled_elixir"
  end
end
