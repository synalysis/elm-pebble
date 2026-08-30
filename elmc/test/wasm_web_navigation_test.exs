defmodule Elmc.WasmWebNavigationTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @load_runner Path.expand("support/wasm_nav_load_probe_runner.mjs", __DIR__)
  @reload_runner Path.expand("support/wasm_nav_reload_probe_runner.mjs", __DIR__)
  @history_runner Path.expand("support/wasm_nav_history_probe_runner.mjs", __DIR__)
  @url_runner Path.expand("support/wasm_nav_url_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "Browser.Navigation.load assigns window.location" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_nav_load_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_nav_load", __DIR__)
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
        assert wat =~ "browser_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@load_runner, [out_dir]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "nav_load_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Navigation.load probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Browser.Navigation.reload uses the application Key and calls location.reload" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_nav_reload_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_nav_reload", __DIR__)
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
        assert wat =~ "browser_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@reload_runner, [out_dir, "false"]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "nav_reload_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Navigation.reload probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Browser.Navigation.reloadAndSkipCache calls location.reload(true)" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_nav_reload_skip_cache_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_nav_reload_skip_cache", __DIR__)
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
        assert wat =~ "browser_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@reload_runner, [out_dir, "true"]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "nav_reload_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Navigation.reloadAndSkipCache probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Browser.Navigation.back key n calls history.go(-n)" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_nav_back_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_nav_back", __DIR__)
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
        assert wat =~ "browser_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@history_runner, [out_dir, "-2"]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "nav_history_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Navigation.back probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Browser.Navigation.forward key n calls history.go(n)" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_nav_forward_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_nav_forward", __DIR__)
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
        assert wat =~ "browser_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@history_runner, [out_dir, "3"]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "nav_history_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Navigation.forward probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Browser.Navigation.go key n calls history.go(n)" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_nav_go_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_nav_go", __DIR__)
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
        assert wat =~ "browser_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@history_runner, [out_dir, "-1"]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "nav_history_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Navigation.go probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Browser.Navigation.pushUrl key url calls history.pushState" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_nav_push_url_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_nav_push_url", __DIR__)
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
        assert wat =~ "browser_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@url_runner, [out_dir, "push", "/pushed"]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "nav_url_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Navigation.pushUrl probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Browser.Navigation.replaceUrl key url calls history.replaceState" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_nav_replace_url_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_nav_replace_url", __DIR__)
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
        assert wat =~ "browser_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@url_runner, [out_dir, "replace", "/replaced"]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "nav_url_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Navigation.replaceUrl probe failed:\n#{output}")
            end
        end
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
