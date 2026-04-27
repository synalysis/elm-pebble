defmodule Elmc.PortsRoundtripTest do
  use ExUnit.Case

  test "host harness receives outgoing callback" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for ports roundtrip C test")

    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/ports_roundtrip", __DIR__)
    File.rm_rf!(out_dir)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir})

    binary_path = Path.join(out_dir, "ports_harness")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-I#{Path.join(out_dir, "runtime")}",
        "-I#{Path.join(out_dir, "ports")}",
        "-I#{Path.join(out_dir, "c")}",
        Path.join(out_dir, "runtime/elmc_runtime.c"),
        Path.join(out_dir, "ports/elmc_ports.c"),
        Path.join(out_dir, "c/elmc_generated.c"),
        Path.join(out_dir, "c/host_harness.c"),
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0
    assert String.contains?(run_out, "port callback value=7")
  end
end
