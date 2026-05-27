defmodule Ide.Emulator.Session.RuntimeSetupTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.Session.RuntimeSetup
  alias Ide.WatchModels

  @expected_component_ids [
    :embedded_emulator,
    :pebble_cli,
    :pebble_sdk_python_env,
    :pebble_sdk_node_modules,
    :pebble_arm_gcc,
    :qemu,
    :pypkjs,
    :qemu_micro_flash,
    :qemu_spi_flash
  ]

  for platform <- ["basalt", "emery"] do
    @tag platform: platform
    test "runtime_status/1 for #{platform} lists standard dependency components", %{platform: platform} do
      status = RuntimeSetup.runtime_status(platform)

      assert %{status: _, platform: ^platform, components: components, missing: _, installable: _} =
               status

      assert is_list(components)
      assert Enum.map(status.components, & &1.id) == @expected_component_ids
      assert is_boolean(status.installable)
      assert status.status in [:ok, :warning]
    end
  end

  test "normalize_platform/1 falls back to default for unknown ids" do
    assert RuntimeSetup.normalize_platform("not-a-watch") == WatchModels.default_id()
    assert RuntimeSetup.normalize_platform("BASALT") == "basalt"
  end
end
