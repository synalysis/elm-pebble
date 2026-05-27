defmodule Ide.Emulator.Session.QemuTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.Session.Qemu

  @spi "/tmp/spi.bin"

  test "basalt machine args use snowy board and pflash SPI" do
    legacy = %{new_qemu?: false, machines: MapSet.new()}

    args = Qemu.machine_args("basalt", @spi, legacy)

    assert ["-machine", "pebble-snowy-bb", "-cpu", "cortex-m4"] == Enum.take(args, 4)
    assert "-pflash" in args
    assert @spi in args
  end

  test "emery machine args use legacy snowy-emery board without new_qemu machines" do
    legacy = %{new_qemu?: false, machines: MapSet.new()}

    args = Qemu.machine_args("emery", @spi, legacy)

    assert ["-machine", "pebble-snowy-emery-bb", "-cpu", "cortex-m4"] == Enum.take(args, 4)
    assert "-pflash" in args
    refute "-audio" in args
  end

  test "emery uses pebble-emery machine when new qemu exposes the board" do
    features = %{new_qemu?: true, machines: MapSet.new(["pebble-emery"])}

    args = Qemu.machine_args("emery", @spi, features)

    assert ["-machine", "pebble-emery", "-cpu", "cortex-m33"] == Enum.take(args, 4)
    assert Enum.any?(args, &String.starts_with?(&1, "if=mtd"))
    assert "-audio" in args
  end

  test "boot markers require ready-for-communication console text" do
    assert Qemu.boot_markers() == ["Ready for communication"]
  end
end
