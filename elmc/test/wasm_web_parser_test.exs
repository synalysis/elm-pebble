defmodule Elmc.WasmWebParserTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @html_runner Path.expand("support/wasm_html_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm Parser int float number sequence variable loop lineComment and end match official Elm" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_parser_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_parser", __DIR__)
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
        assert wat =~ "parser_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected =
          "int:1|float:1|hex:1|until:1|sym:1|kw:1|sp:1|seq:1|seqf:1|seqo:1|seqe:1" <>
            "|var:1|varf:1|loop:1|lc:1|end:1|endf:1|mc:1|mcn:1" <>
            "|cw:1|ci:1|cif:1|off:1|src:1|row:1|col:1|tok:1|pr:1|ue:1|uee:1|bt:1|pm:1" <>
            "|at:1|atf:1|lz:1|cm:1"

        case run_html_probe(out_dir, "elmc_fn_Main_main", expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm parser probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_html_probe(out_dir, export_name, expected_text) do
    node = System.find_executable("node")

    case node do
      nil ->
        {:error, "node not available"}

      node ->
        args = [out_dir, export_name, expected_text]

        {output, code} =
          System.cmd(node, [@html_runner | args], stderr_to_stdout: true)

        if code == 0, do: {:ok, output}, else: {:error, output}
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
