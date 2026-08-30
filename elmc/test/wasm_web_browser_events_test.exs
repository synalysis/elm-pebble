defmodule Elmc.WasmWebBrowserEventsTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @resize_runner Path.expand("support/wasm_resize_probe_runner.mjs", __DIR__)
  @visibility_runner Path.expand("support/wasm_visibility_probe_runner.mjs", __DIR__)
  @animation_runner Path.expand("support/wasm_animation_frame_probe_runner.mjs", __DIR__)
  @doc_events_runner Path.expand("support/wasm_doc_events_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "Browser.Events.onResize is Int -> Int -> msg and does not fire on subscribe" do
    run_event_fixture("wasm_web_resize_project", "tmp/wasm_web_resize", @resize_runner, "resize_ok", [
      "dom_sub"
    ])
  end

  @tag :wasm_execute
  test "Browser.Events.onVisibilityChange delivers Visible and Hidden" do
    run_event_fixture(
      "wasm_web_visibility_project",
      "tmp/wasm_web_visibility",
      @visibility_runner,
      "visibility_ok",
      ["dom_sub"]
    )
  end

  @tag :wasm_execute
  test "Browser.Events onAnimationFrame is Posix and onAnimationFrameDelta is Float" do
    run_event_fixture(
      "wasm_web_animation_frame_project",
      "tmp/wasm_web_animation_frame",
      @animation_runner,
      "animation_frame_ok",
      ["dom_sub"]
    )
  end

  @tag :wasm_execute
  test "Browser.Events onClick and onKeyDown are Decoder msg on document" do
    run_event_fixture(
      "wasm_web_doc_events_project",
      "tmp/wasm_web_doc_events",
      @doc_events_runner,
      "doc_events_ok",
      ["dom_sub"]
    )
  end

  defp run_event_fixture(fixture, out_rel, runner, ok_token, wat_needles) do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/#{fixture}", __DIR__)
        out_dir = Path.expand(out_rel, __DIR__)
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

        for needle <- wat_needles do
          assert wat =~ needle
        end

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(runner, [out_dir]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ ok_token

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("#{fixture} probe failed:\n#{output}")
            end
        end
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
