defmodule ElmExecutorTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.Worker
  alias ElmExecutor.Runtime.Loader

  test "compile emits generated Elixir module for library mode" do
    project_dir = fixture_project_dir("pebble_app_template")

    out_dir =
      Path.join(System.tmp_dir!(), "elm_executor_test_#{System.unique_integer([:positive])}")

    assert {:ok, result} =
             ElmExecutor.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               mode: :library
             })

    assert result.compiler == "elm_executor"
    assert result.mode == :library
    assert is_binary(result.core_ir.deterministic_sha256)

    assert {:ok, manifest} = Loader.load_manifest(out_dir)
    assert manifest["contract"] == "elm_executor.runtime_executor.v1"
    assert manifest["engine"] == "elm_executor_runtime_v1"
    assert is_binary(manifest["core_ir_sha256"])

    generated =
      Path.join([out_dir, "elixir", Macro.underscore(manifest["generated_module"]) <> ".ex"])

    assert File.exists?(generated)
  end

  test "runtime loader can load compiled generated module" do
    project_dir = fixture_project_dir("pebble_app_template")

    out_dir =
      Path.join(System.tmp_dir!(), "elm_executor_load_#{System.unique_integer([:positive])}")

    assert {:ok, _} = ElmExecutor.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    assert {:ok, module} = Loader.load_from_dir(out_dir, "Main")
    assert is_map(module.compiler_metadata())
    assert module.compiler_metadata().engine == "elm_executor_runtime_v1"
  end

  test "worker dispatch, tick, and replay are deterministic" do
    project_dir = fixture_project_dir("pebble_app_template")

    out_dir =
      Path.join(System.tmp_dir!(), "elm_executor_worker_#{System.unique_integer([:positive])}")

    assert {:ok, _} = ElmExecutor.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    assert {:ok, module} = Loader.load_from_dir(out_dir, "Main")

    request_template = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "",
      introspect: %{
        "init_model" => %{"n" => 0},
        "update_case_branches" => ["Inc"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"n" => 0}},
      current_view_tree: %{"type" => "root", "children" => []},
      update_branches: ["Inc"]
    }

    assert {:ok, pid} = Worker.start_link(module: module, request_template: request_template)
    assert {:ok, first} = Worker.dispatch(pid, "Inc")
    assert {:ok, second} = Worker.inject_tick(pid, %{"kind" => "test_tick"})
    replay = Worker.replay_recent(pid, 2)

    assert first.runtime["engine"] == "elm_executor_runtime_v1"
    assert second.runtime["engine"] == "elm_executor_runtime_v1"
    assert length(replay) == 2
    assert Enum.at(replay, 0).seq < Enum.at(replay, 1).seq
    assert Enum.at(replay, 0).type == "dispatch"
    assert Enum.at(replay, 1).type == "tick"
  end

  defp fixture_project_dir(name) do
    Path.expand("../../ide/priv/#{name}", __DIR__)
  end
end
