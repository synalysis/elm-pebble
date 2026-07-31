defmodule Elmc.PortsAbiTest do
  use ExUnit.Case

  alias Elmc.TestSupport.CachedCompile

  test "ports header exposes callback registration API" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/ports", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} = CachedCompile.compile(project_dir, %{out_dir: out_dir})
    header = File.read!(Path.join(out_dir, "ports/elmc_ports.h"))

    assert String.contains?(header, "register_incoming_port")
    assert String.contains?(header, "send_outgoing_port")
    assert String.contains?(header, "ElmcPortCallback")
  end

  test "pebble builds use a tiny incoming-port table" do
    ports_source = File.read!(Path.expand("../lib/elmc/backend/ports.ex", __DIR__))

    assert ports_source =~ "#ifdef ELMC_PEBBLE_PLATFORM"
    assert ports_source =~ "#define ELMC_MAX_PORTS 2"
    assert ports_source =~ "#define ELMC_MAX_PORTS 32"
  end
end
