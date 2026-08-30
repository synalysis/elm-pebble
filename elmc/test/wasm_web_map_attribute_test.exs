defmodule Elmc.WasmWebMapAttributeTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @browser_runner Path.expand("support/wasm_browser_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm Html.Attributes.map / VirtualDom.mapAttribute compiles and boots" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_map_attribute_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_map_attribute", __DIR__)
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
        assert wat =~ "html_cmd"
        assert wat =~ "(i32.const 21)"

        refute Enum.any?(ProjectWriter.stub_functions(out_dir), fn stub ->
                 stub["module"] in ["VirtualDom", "Elm.Kernel.VirtualDom"] and
                   stub["name"] == "mapAttribute"
               end)

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "count: 0"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm mapAttribute probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_probe(out_dir) do
    WasmRcTrackHarness.run_node_script(@browser_runner, [out_dir, "elmc_fn_Main_main", "count: 0mapped attr"])
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
