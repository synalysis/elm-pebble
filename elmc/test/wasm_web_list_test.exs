defmodule Elmc.WasmWebListTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @html_runner Path.expand("support/wasm_html_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "List take drop range repeat intersperse unzip partition map2 sort and product match official elm/core" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_list_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_list", __DIR__)
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
        assert wat =~ "list_take"
        assert wat =~ "list_range"
        assert wat =~ "list_repeat"
        assert wat =~ "list_map3"
        assert wat =~ "list_sum_float"
        assert wat =~ "list_product_float"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected =
          "tk:1|t0:1|tn:1|dr:1|d0:1|dn:1|rg:1|re:1|rp:1|r0:1|in:1|ins:1|uz:1|pt:1|m2:1|m2s:1|st:1|ss:1|st2:1|sl:1|sb:1|fm:1|pr:1|cc:1|mb:1|sm:1|sf:1|pf:1|mx:1|mn:1|mxs:1|hd:1|tl:1|im:1|cm:1|sw:1|ap:1|rv:1|m3:1|m4:1|m5:1|sfe:1|pfe:1|sft:1|pft:1|sxf:0|pxf:1|ie:1|ln:1|sg:1|mp:1|fl:1|fdl:1|fdr:1|al:1|ay:1"

        case run_html_probe(out_dir, expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm List probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_html_probe(out_dir, expected_text) do
    WasmRcTrackHarness.run_node_script(@html_runner, [out_dir, "elmc_fn_Main_main", expected_text])
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
