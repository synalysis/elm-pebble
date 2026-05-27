defmodule Ide.Emulator.Session.HealthTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.Session.Health

  defp base_state(overrides \\ %{}) do
    Map.merge(
      %{
        qemu_pid: self(),
        protocol_router_pid: self(),
        pypkjs_pid: nil,
        vnc_port: 59_000,
        phone_ws_port: 59_001,
        installing?: false
      },
      overrides
    )
  end

  test "check/1 skips port checks while installing" do
    assert :ok = Health.check(base_state(%{installing?: true, qemu_pid: nil}))
  end

  test "child_role/2 identifies session children" do
    qemu = self()
    router = spawn(fn -> receive do :stop -> :ok end end)
    pypkjs = spawn(fn -> receive do :stop -> :ok end end)

    on_exit(fn ->
      Process.exit(router, :kill)
      Process.exit(pypkjs, :kill)
    end)

    state = base_state(%{qemu_pid: qemu, protocol_router_pid: router, pypkjs_pid: pypkjs})

    assert Health.child_role(state, qemu) == :qemu
    assert Health.child_role(state, router) == :protocol_router
    assert Health.child_role(state, pypkjs) == :pypkjs
    assert Health.child_role(state, make_ref()) == nil
  end
end
