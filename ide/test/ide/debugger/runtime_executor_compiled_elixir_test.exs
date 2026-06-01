defmodule Ide.Debugger.RuntimeExecutorCompiledElixirTest do
  use ExUnit.Case, async: false

  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.RuntimeExecutor.Request
  alias Ide.Debugger.RuntimeSurfaces

  setup do
    old = Application.get_env(:ide, RuntimeExecutor, [])

    on_exit(fn ->
      Application.put_env(:ide, RuntimeExecutor, old)
    end)

    Application.put_env(:ide, RuntimeExecutor, execution_backend: :compiled_elixir)
    _ = Application.ensure_all_started(:elmx)
    :ok
  end

  test "RuntimeExecutor routes init through compiled elixir backend" do
    project_dir = Path.expand("../../../../elmx/test/fixtures/simple_project", __DIR__)
    revision = "executor-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} =
             Ide.Compiler.build_elmx_artifacts_in_memory(project_dir, revision: revision)

    launch_context = RuntimeSurfaces.launch_context_for("basalt", "LaunchUser")

    request =
      %Request{
        source_root: "watch",
        rel_path: "src/Main.elm",
        source: "",
        introspect: %{},
        current_model: %{"launch_context" => launch_context},
        current_view_tree: %{},
        message: nil,
        elmx_manifest: manifest,
        elmx_revision: revision
      }
      |> Request.validate_execution_ready!()

    assert {:ok, payload} = RuntimeExecutor.execute(request)
    runtime_model = get_in(payload.model_patch, ["runtime_model"])
    assert is_map(runtime_model)
    assert get_in(payload.runtime, ["execution_backend"]) == "compiled_elixir"
  end

  test "RuntimeExecutor steps compiled simple_project on Increment" do
    project_dir = Path.expand("../../../../elmx/test/fixtures/simple_project", __DIR__)
    revision = "executor-step-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} =
             Ide.Compiler.build_elmx_artifacts_in_memory(project_dir, revision: revision)

    launch_context = RuntimeSurfaces.launch_context_for("basalt", "LaunchUser")

    init_request =
      %Request{
        source_root: "watch",
        rel_path: "src/Main.elm",
        source: "",
        introspect: %{},
        current_model: %{"launch_context" => launch_context},
        current_view_tree: %{},
        message: nil,
        elmx_manifest: manifest,
        elmx_revision: revision
      }
      |> Request.validate_execution_ready!()

    assert {:ok, init_payload} = RuntimeExecutor.execute(init_request)
    runtime_model = get_in(init_payload.model_patch, ["runtime_model"])
    assert is_map(runtime_model)

    step_request =
      %Request{
        source_root: "watch",
        rel_path: "src/Main.elm",
        source: "",
        introspect: %{},
        current_model: %{
          "launch_context" => launch_context,
          "runtime_model" => runtime_model
        },
        current_view_tree: init_payload.view_tree || %{},
        message: "Increment",
        elmx_manifest: manifest,
        elmx_revision: revision
      }
      |> Request.validate_execution_ready!()

    assert {:ok, step_payload} = RuntimeExecutor.execute(step_request)
    stepped = get_in(step_payload.model_patch, ["runtime_model"])
    assert is_map(stepped)
  end
end
