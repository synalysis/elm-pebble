defmodule Elmc.WasmWebBrowserDomTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @viewport_runner Path.expand("support/wasm_viewport_probe_runner.mjs", __DIR__)
  @title_runner Path.expand("support/wasm_set_title_probe_runner.mjs", __DIR__)
  @set_viewport_runner Path.expand("support/wasm_set_viewport_probe_runner.mjs", __DIR__)
  @set_viewport_of_runner Path.expand("support/wasm_set_viewport_of_probe_runner.mjs", __DIR__)
  @focus_runner Path.expand("support/wasm_focus_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm Browser.Dom viewport/element fields match official declaration order" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_viewport_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_viewport", __DIR__)
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
        assert wat =~ "browser_get_viewport"
        assert wat =~ "browser_get_viewport_of"
        assert wat =~ "browser_get_element"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "555x666@3,4:111x222>80x90@5,6:70x75|13,24:30x40"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm viewport probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Browser.Dom viewport fields stay correct through inferred inner records" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_viewport_inferred_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_viewport_inferred", __DIR__)
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
        assert wat =~ "browser_get_viewport"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_probe(out_dir, "555x666@3,4:111x222") do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "555x666@3,4:111x222"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm inferred viewport probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Browser.Dom.setTitle sets document.title" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_set_title_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_set_title", __DIR__)
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

        case WasmRcTrackHarness.run_node_script(@title_runner, [out_dir]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "set_title_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm setTitle probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Browser.Dom.setViewport Float args persist for getViewport" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_set_viewport_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_set_viewport", __DIR__)
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
        assert wat =~ "browser_set_viewport"
        assert wat =~ "browser_get_viewport"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@set_viewport_runner, [out_dir]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "set_viewport_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm setViewport probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Browser.Dom.setViewportOf Float args persist for getViewportOf" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_set_viewport_of_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_set_viewport_of", __DIR__)
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
        assert wat =~ "browser_set_viewport_of"
        assert wat =~ "browser_get_viewport_of"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@set_viewport_of_runner, [out_dir]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "set_viewport_of_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm setViewportOf probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Browser.Dom.focus NotFound then focus and blur succeed" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_focus_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_focus", __DIR__)
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
        assert wat =~ "browser_dom_focus"
        assert wat =~ "browser_dom_blur"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@focus_runner, [out_dir]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "focus_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm focus/blur probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_probe(out_dir, expected \\ nil) do
    args = if expected, do: [out_dir, expected], else: [out_dir]
    WasmRcTrackHarness.run_node_script(@viewport_runner, args)
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
