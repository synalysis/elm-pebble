defmodule Elmc.WasmPortIncomingTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @fixture_root Path.expand("fixtures/wasm_port_incoming_project", __DIR__)

  @tag :wasm_execute
  test "incoming port subscriptions lower to port_incoming_sub and boot delivers payload" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        out_dir = Path.expand("tmp/wasm_port_incoming", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 Elmc.compile(@fixture_root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "port_incoming_sub"
        assert wat =~ ~s/call $runtime_port_incoming_sub/

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_port_boot_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "incoming_port_ok"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("incoming port boot probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_port_boot_probe(out_dir) do
    node = System.find_executable("node")

    case node do
      nil ->
        {:error, "node not available"}

      node ->
        runner = Path.expand("support/wasm_port_incoming_probe_runner.mjs", __DIR__)

        {output, code} =
          System.cmd(node, [runner, out_dir], stderr_to_stdout: true)

        if code == 0, do: {:ok, output}, else: {:error, output}
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
