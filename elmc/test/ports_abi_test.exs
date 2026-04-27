defmodule Elmc.PortsAbiTest do
  use ExUnit.Case

  test "ports header exposes callback registration API" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/ports", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir})
    header = File.read!(Path.join(out_dir, "ports/elmc_ports.h"))

    assert String.contains?(header, "register_incoming_port")
    assert String.contains?(header, "send_outgoing_port")
    assert String.contains?(header, "ElmcPortCallback")
  end
end
