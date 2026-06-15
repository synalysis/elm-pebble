defmodule Ide.Emulator.InstallPrepTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.{InstallPrep, Session}

  test "reset_needed? when QEMU or router is missing" do
    assert InstallPrep.reset_needed?(%{
             qemu_pid: nil,
             protocol_router_pid: nil,
             last_boot_ms: 0,
             bt_port: 12_345
           })
  end

  test "reset_needed? when boot is stale and session is idle" do
    now = System.monotonic_time(:millisecond)
    stale = now - 999_999_999

    assert InstallPrep.reset_needed?(%{
             qemu_pid: self(),
             protocol_router_pid: self(),
             last_boot_ms: stale,
             last_ping_ms: stale,
             bt_port: 12_345
           })
  end

  test "reset_needed? is false when boot is stale but session was pinged recently" do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, bt_port} = :inet.port(listen)
    on_exit(fn -> :gen_tcp.close(listen) end)

    now = System.monotonic_time(:millisecond)

    refute InstallPrep.reset_needed?(%{
             qemu_pid: self(),
             protocol_router_pid: self(),
             last_boot_ms: now - 400_000,
             last_ping_ms: now - 5_000,
             bt_port: bt_port
           })
  end

  test "pacing_opts uses smaller PutBytes chunks on emery" do
    opts = InstallPrep.pacing_opts("emery")
    assert Keyword.get(opts, :chunk_size) == 256
    assert Keyword.get(opts, :part_delay_ms) == 300
  end

  test "pacing_opts uses default chunk size on diorite" do
    opts = InstallPrep.pacing_opts("diorite")
    assert Keyword.get(opts, :chunk_size) == 500
    refute Keyword.has_key?(opts, :part_delay_ms)
  end

  test "min_ms_after_boot differs by platform" do
    assert InstallPrep.min_ms_after_boot("emery") == 8_000
    assert InstallPrep.min_ms_after_boot("diorite") == 5_000
  end

  test "Session.install_reset_needed? delegates to InstallPrep" do
    assert Session.install_reset_needed?(%{
             qemu_pid: nil,
             protocol_router_pid: nil,
             last_boot_ms: 0,
             bt_port: 1
           })
  end
end
