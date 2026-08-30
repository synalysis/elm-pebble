defmodule Elmc.WasmWebTaskTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @tag :wasm_execute
  test "web wasm lowers Task.perform Time.now to task runtime imports" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_task_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_task_project", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "task_perform"
        assert wat =~ "time_now_millis"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_perform_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "task_perform_ok"

          {:error, output} ->
            if probe_skipped_under_ulimit?(output) do
              :ok
            else
              flunk("task perform probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Cmd.map wraps Task.perform Time.now under wasm_strict" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_task_map_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_task_map", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "task_perform"
        assert wat =~ "cmd_map"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_map_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "task_map_ok"

          {:error, output} ->
            if probe_skipped_under_ulimit?(output) do
              :ok
            else
              flunk("task map probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Process.sleep is an async Task that succeeds with unit then Time.now" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_process_sleep_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_process_sleep", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "process_sleep"
        assert wat =~ "task_perform"

        refute Enum.any?(ProjectWriter.stub_functions(out_dir), fn stub ->
                 stub["module"] in ["Process", "Elm.Kernel.Process"] and stub["name"] == "sleep"
               end)

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_sleep_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "process_sleep_ok"

          {:error, output} ->
            if probe_skipped_under_ulimit?(output) do
              :ok
            else
              flunk("process sleep probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Process.kill cancels only the spawned pid and leaves Task.perform sleep running" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_process_kill_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_process_kill", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "process_spawn"
        assert wat =~ "process_kill"

        refute Enum.any?(ProjectWriter.stub_functions(out_dir), fn stub ->
                 stub["module"] in ["Process", "Elm.Kernel.Scheduler"] and
                   stub["name"] in ["spawn", "kill"]
               end)

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_kill_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "process_kill_ok"

          {:error, output} ->
            if probe_skipped_under_ulimit?(output) do
              :ok
            else
              flunk("process kill probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Process.kill aborts a spawned Http.task without cancelling Task.perform sleep" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_process_http_kill_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_process_http_kill", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "process_spawn"
        assert wat =~ "process_kill"
        assert wat =~ "http_task"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_http_kill_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "process_http_kill_ok"

          {:error, output} ->
            if probe_skipped_under_ulimit?(output) do
              :ok
            else
              flunk("process http kill probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Process.kill aborts a spawned BackendTask.Http.get without cancelling Task.perform sleep" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_process_backend_task_http_kill_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_process_backend_task_http_kill", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "process_spawn"
        assert wat =~ "process_kill"
        assert wat =~ "backend_task_http_get"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_backend_http_kill_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "process_backend_task_http_kill_ok"

          {:error, output} ->
            if probe_skipped_under_ulimit?(output) do
              :ok
            else
              flunk("process backend task http kill probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Task.mapError rewrites fail and leaves succeed unchanged" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_task_map_error_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_task_map_error", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "task_on_error"
        assert wat =~ "task_and_then"
        assert wat =~ "task_fail"
        assert wat =~ "task_succeed"
        # Official Task.attempt is perform after andThen Ok / onError Err.
        assert wat =~ "task_perform"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_map_error_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "task_map_error_ok"

          {:error, output} ->
            if probe_skipped_under_ulimit?(output) do
              :ok
            else
              flunk("task mapError probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Task.sequence runs async items then fails on the first Task.fail" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_task_sequence_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_task_sequence", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "task_sequence"
        assert wat =~ "process_sleep"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_sequence_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "task_sequence_ok"

          {:error, output} ->
            if probe_skipped_under_ulimit?(output) do
              :ok
            else
              flunk("task sequence probe failed:\n#{output}")
            end
        end
    end
  end

  @perform_runner Path.expand("support/wasm_task_perform_probe_runner.mjs", __DIR__)
  @map_runner Path.expand("support/wasm_task_map_probe_runner.mjs", __DIR__)
  @sleep_runner Path.expand("support/wasm_process_sleep_probe_runner.mjs", __DIR__)
  @kill_runner Path.expand("support/wasm_process_kill_probe_runner.mjs", __DIR__)
  @http_kill_runner Path.expand("support/wasm_process_http_kill_probe_runner.mjs", __DIR__)
  @backend_http_kill_runner Path.expand(
                             "support/wasm_process_backend_task_http_kill_probe_runner.mjs",
                             __DIR__
                           )
  @map_error_runner Path.expand("support/wasm_task_map_error_probe_runner.mjs", __DIR__)
  @sequence_runner Path.expand("support/wasm_task_sequence_probe_runner.mjs", __DIR__)

  defp run_perform_probe(out_dir), do: WasmRcTrackHarness.run_node_script(@perform_runner, [out_dir])

  defp run_map_probe(out_dir), do: WasmRcTrackHarness.run_node_script(@map_runner, [out_dir])

  defp run_sleep_probe(out_dir), do: WasmRcTrackHarness.run_node_script(@sleep_runner, [out_dir])

  defp run_kill_probe(out_dir), do: WasmRcTrackHarness.run_node_script(@kill_runner, [out_dir])

  defp run_http_kill_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@http_kill_runner, [out_dir])

  defp run_backend_http_kill_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@backend_http_kill_runner, [out_dir])

  defp run_map_error_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@map_error_runner, [out_dir])

  defp run_sequence_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@sequence_runner, [out_dir])

  defp probe_skipped_under_ulimit?(output),
    do: WasmRcTrackHarness.probe_skipped_under_ulimit?(output)

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
