defmodule Ide.WasmEmulator.Types do
  @moduledoc false

  @type firmware_manifest :: %{
          optional(String.t()) => String.t() | integer() | boolean() | nil
        }

  @type firmware_platform_status :: %{optional(String.t()) => firmware_manifest()}

  @type firmware_status :: %{
          required(:sdk) => firmware_platform_status() | firmware_manifest() | nil,
          required(:full) => firmware_manifest() | nil
        }

  @type install_bridge_status :: %{
          required(:required_api) => String.t(),
          required(:available?) => boolean()
        }

  @type setup_info :: %{
          required(:upstream_url) => String.t(),
          required(:runtime_target) => String.t(),
          required(:sdk_firmware_target) => String.t(),
          required(:full_firmware_target) => String.t(),
          required(:build_command) => String.t(),
          required(:runtime_ready?) => boolean(),
          required(:notes) => [String.t()]
        }

  @type status :: %{
          required(:available?) => boolean(),
          required(:root) => String.t(),
          required(:required) => [String.t()],
          required(:missing) => [String.t()],
          required(:runtime_missing) => [String.t()],
          required(:firmware_missing) => [String.t()],
          required(:optional_missing) => [String.t()],
          required(:firmware) => firmware_status(),
          required(:asset_base) => String.t(),
          required(:install_bridge) => install_bridge_status(),
          required(:setup) => setup_info()
        }
end
