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

  test "install pacing lives in InstallPrep" do
    source = File.read!("lib/ide/emulator/install_prep.ex")

    assert source =~ ~S/platform_putbytes_pacing(platform) when platform in ["emery", "flint", "gabbro"]/
    assert source =~ "chunk_size: config(:pbw_chunk_size, 256)"
    assert File.read!("lib/ide/emulator/session/install.ex") =~ "InstallPrep.pacing_opts"
  end

  test "session delegates QEMU payload validation to QemuControl" do
    session = File.read!("lib/ide/emulator/session.ex")
    control = File.read!("lib/ide/emulator/session/control.ex")
    info = File.read!("lib/ide/emulator/session/info.ex")

    assert session =~ "Control.handle_qemu_packet"
    assert control =~ "QemuControl.validate_payload"
    assert info =~ "QemuControl.supported_controls"
  end
end
