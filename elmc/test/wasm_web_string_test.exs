defmodule Elmc.WasmWebStringTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @html_runner Path.expand("support/wasm_html_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "String pad indexes toFloat fromFloat toUpper and trim match official elm/core" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_string_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_string", __DIR__)
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
        assert wat =~ "string_pad"
        assert wat =~ "string_indexes"
        assert wat =~ "string_to_float"
        assert wat =~ "string_to_upper"
        assert wat =~ "string_to_locale_upper"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected =
          "sl:1|sn:1|se:1|pad:1|pad2:1|pl:1|pr:1|l0:1|ln:1|rt:1|rtn:1|dl:1|drt:1|drn:1|ix:1|ixs:1|ixo:1|ixe:1|all:1|any:1|w:1|we:1|li:1|ti:1|tp:1|tf:1|ffh:1|ffi:1|tfl:1|tfe:1|tfx:1|tsp:1|tdt:1|up:1|lo:1|ss:1|len:1|ixu:1|fc:1|pdu:1|sp:1|spe:1|spd:1|re:1|reu:1|red:1|tr:1|rev:1|revu:1|rep:1|rep0:1|repn:1|uc:1|uce:1|co:1|coe:1|sw:1|ew:1|fl:1|tl:1|cn:1|jn:1|cc:1|ie:1|tlf:1|trf:1|tn:1|sm:1|sf:1|sfl:1|sfr:1|sa:1|sal:1|slu:1|sll:1|idc:1|fi:1|fin:1|fia:1|upx:1|lox:1|upy:1"

        case run_html_probe(out_dir, expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm String probe failed:\n#{output}")
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
