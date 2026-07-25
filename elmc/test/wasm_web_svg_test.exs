defmodule Elmc.WasmWebSvgTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @tag :wasm_execute
  test "web wasm lowers Svg via nodeNS html_cmd kind 7" do
    run_fixture(
      "wasm_web_svg_project",
      fn wat ->
        assert wat =~ "html_cmd"
        assert wat =~ "(i32.const 7)"
      end
    )
  end

  defp run_fixture(fixture, wat_assert) do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/#{fixture}", __DIR__)
        out_dir = Path.expand("tmp/#{fixture}", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 Elmc.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        wat_assert.(wat)

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
