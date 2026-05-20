defmodule Ide.Emulator.SessionInstallPrepareTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.Session

  test "install_reset_needed? when QEMU or router is missing" do
    assert Session.install_reset_needed?(%{
             qemu_pid: nil,
             protocol_router_pid: nil,
             last_boot_ms: 0,
             bt_port: 12_345
           })
  end

  test "install_reset_needed? when boot is stale" do
    stale_boot = System.os_time(:millisecond) - 999_999_999

    assert Session.install_reset_needed?(%{
             qemu_pid: self(),
             protocol_router_pid: self(),
             last_boot_ms: stale_boot,
             bt_port: 12_345
           })
  end
end
