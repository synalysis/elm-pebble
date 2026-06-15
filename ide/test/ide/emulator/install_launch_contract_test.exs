defmodule Ide.Emulator.InstallLaunchContractTest do
  @moduledoc """
  Documents how PBW install relates to AppRunState (aligned with libpebble2 AppInstaller).

  Install sends `AppRunStateStart` once to open AppFetch, streams PutBytes, then the final
  part's `PutBytesInstall` hands off to the firmware. A second `AppRunStateStart` right after
  install retriggers AppFetch and must not be part of the default MCP `emulator_run` flow.
  """
  use ExUnit.Case, async: true

  alias Ide.Emulator.PebbleProtocol.Packets
  alias Ide.Mcp.Handlers.Emulator, as: EmulatorHandler

  @uuid "3278ae24-9885-427f-90e7-791ac2450e78"

  test "PBW install handshake uses a single AppRunStateStart before AppFetch" do
    {endpoint, payload} = Packets.app_run_state_start(@uuid)
    assert endpoint == Packets.endpoint(:app_run_state)
    assert <<0x01, _uuid::binary-size(16)>> = payload
  end

  test "emulator_run handler does not post-install AppRunStateStart helper" do
    refute {:maybe_start_installed_app, 2} in EmulatorHandler.__info__(:functions)
  end
end
