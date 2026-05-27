defmodule Ide.Emulator.Types do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Emulator.Session.Qemu
  alias Ide.WatchModels.Profile, as: WatchProfile

  @type qemu_features :: Qemu.features()

  @type qemu_args_state :: %{
          required(:platform) => String.t(),
          required(:bt_port) => pos_integer(),
          required(:console_port) => pos_integer(),
          required(:vnc_display) => non_neg_integer(),
          optional(:spi_image_path) => String.t() | nil,
          optional(:persist_dir) => String.t() | nil,
          optional(:qemu_features) => qemu_features()
        }

  @type pypkjs_args_state :: %{
          required(:platform) => String.t(),
          required(:bt_port) => pos_integer(),
          required(:phone_ws_port) => pos_integer(),
          required(:persist_dir) => String.t(),
          optional(:protocol_proxy_port) => pos_integer()
        }

  @type pypkjs_start_state :: %{
          required(:id) => String.t(),
          required(:platform) => String.t(),
          required(:bt_port) => pos_integer(),
          required(:phone_ws_port) => pos_integer(),
          required(:persist_dir) => String.t(),
          optional(:protocol_proxy_port) => pos_integer(),
          optional(:pypkjs_pid) => pid() | nil
        }

  @type session_state :: %{
          required(:id) => String.t(),
          required(:token) => String.t(),
          required(:project_slug) => String.t(),
          required(:platform) => String.t(),
          required(:artifact_path) => String.t() | nil,
          required(:app_uuid) => String.t() | nil,
          required(:has_phone_companion) => boolean(),
          required(:has_companion_preferences) => boolean(),
          required(:console_port) => pos_integer(),
          required(:bt_port) => pos_integer(),
          required(:protocol_proxy_port) => pos_integer(),
          required(:phone_ws_port) => pos_integer(),
          required(:vnc_port) => pos_integer(),
          required(:vnc_display) => non_neg_integer(),
          required(:vnc_ws_port) => pos_integer(),
          required(:protocol_router_pid) => pid() | nil,
          required(:qemu_pid) => pid() | nil,
          required(:pypkjs_pid) => pid() | nil,
          required(:spi_image_path) => String.t() | nil,
          required(:persist_dir) => String.t() | nil,
          required(:last_ping_ms) => integer(),
          required(:last_boot_ms) => integer(),
          required(:idle_timeout_ms) => pos_integer(),
          required(:vnc_banner_ready) => boolean(),
          required(:vnc_rfb_banner) => binary() | nil,
          required(:vnc_tcp) => port() | nil,
          required(:vnc_tcp_buffer) => binary(),
          required(:installing?) => boolean(),
          required(:qemu_features) => qemu_features()
        }

  @type install_context :: %{
          required(:protocol_router_pid) => pid(),
          required(:artifact_path) => String.t(),
          required(:platform) => String.t(),
          required(:console_port) => pos_integer()
        }

  @type putbytes_phase ::
          :init
          | :put
          | :commit
          | :install
          | :install_transition
          | :abort_after_commit_nack

  @type putbytes_phase_meta :: %{
          required(:phase) => putbytes_phase(),
          optional(:kind) => atom(),
          optional(:cookie) => non_neg_integer(),
          optional(:offset) => non_neg_integer(),
          optional(:chunk_size) => pos_integer(),
          optional(:size) => non_neg_integer(),
          optional(:app_id) => non_neg_integer(),
          optional(:bytes_sent) => non_neg_integer(),
          optional(:crc) => non_neg_integer()
        }

  @type screenshot_capture_opts :: [timeout: timeout()]

  @type screenshot_header :: %{
          required(:version) => non_neg_integer(),
          required(:width) => pos_integer(),
          required(:height) => pos_integer(),
          required(:expected_bytes) => non_neg_integer()
        }

  @type launch_opts :: [
          {:project_slug, String.t()}
          | {:platform, String.t()}
          | {:artifact_path, String.t() | nil}
          | {:has_phone_companion, boolean()}
          | {:has_companion_preferences, boolean()}
          | {:id, String.t()}
          | {:slot_acquire_timeout_ms, pos_integer()}
        ]

  @type session_launch_opts :: launch_opts()

  @type simulator_settings :: DebuggerTypes.simulator_settings()

  @type screen :: WatchProfile.wire_screen()
  @type watch_profile :: WatchProfile.wire()

  @type session_info :: %{
          required(:id) => String.t(),
          required(:token) => String.t(),
          required(:project_slug) => String.t(),
          required(:platform) => String.t(),
          required(:artifact_path) => String.t(),
          required(:app_uuid) => String.t() | nil,
          required(:has_phone_companion) => boolean(),
          required(:has_companion_preferences) => boolean(),
          required(:install_path) => String.t(),
          required(:vnc_path) => String.t(),
          required(:phone_path) => String.t(),
          required(:ping_path) => String.t(),
          required(:kill_path) => String.t(),
          required(:screen) => screen(),
          required(:controls) => [String.t()],
          required(:backend_enabled) => boolean(),
          required(:display_ready) => boolean(),
          required(:phone_bridge_ready) => boolean(),
          required(:installing) => boolean()
        }

  @type apply_settings_result :: %{
          required(:applied) => non_neg_integer(),
          required(:protocols) => [non_neg_integer()]
        }

  @type apply_settings_error :: :invalid_qemu_payload

  @type runtime_component_id ::
          :embedded_emulator
          | :pebble_cli
          | :pebble_sdk_python_env
          | :pebble_sdk_node_modules
          | :pebble_arm_gcc
          | :qemu
          | :pypkjs
          | :qemu_micro_flash
          | :qemu_spi_flash

  @type runtime_component_status :: :ok | :missing

  @type runtime_component :: %{
          required(:id) => runtime_component_id(),
          required(:label) => String.t(),
          required(:status) => runtime_component_status(),
          required(:detail) => String.t(),
          required(:installable) => boolean()
        }

  @type runtime_status_level :: :ok | :warning

  @type runtime_status :: %{
          required(:status) => runtime_status_level(),
          required(:platform) => String.t(),
          required(:components) => [runtime_component()],
          required(:missing) => [runtime_component()],
          required(:installable) => boolean()
        }

  @type install_step_name :: :pebble_tool | :pebble_sdk | :qemu_images

  @type install_step_result :: %{
          required(:name) => install_step_name(),
          required(:status) => :ok | :error,
          required(:output) => String.t()
        }

  @type install_dependencies_result :: %{
          required(:platform) => String.t(),
          required(:before) => runtime_status(),
          required(:after) => runtime_status(),
          required(:results) => [install_step_result()],
          required(:output) => String.t()
        }

  @type install_prep_context :: %{
          optional(:platform) => String.t(),
          optional(:qemu_pid) => pid() | nil,
          optional(:protocol_router_pid) => pid() | nil,
          optional(:bt_port) => pos_integer(),
          optional(:last_boot_ms) => integer()
        }

  @type install_prep_session :: install_prep_context() | session_state()

  @type pbw_json_value ::
          String.t()
          | boolean()
          | non_neg_integer()
          | integer()
          | float()
          | [pbw_json_value()]
          | %{String.t() => pbw_json_value()}

  @type pbw_appinfo :: %{String.t() => pbw_json_value()}
  @type pbw_manifest :: %{String.t() => pbw_json_value()}

  @type install_part_sent :: %{
          required(:kind) => atom(),
          required(:name) => String.t(),
          required(:cookie) => non_neg_integer(),
          required(:bytes) => non_neg_integer(),
          required(:crc) => non_neg_integer()
        }

  @type putbytes_response :: %{
          required(:ack?) => boolean(),
          required(:result) => :ack | :nack,
          required(:cookie) => non_neg_integer()
        }

  @type vnc_error ::
          :vnc_banner_timeout
          | {:vnc_connect_failed, term()}
          | {:vnc_probe_recv_failed, term()}

  @type session_atom_error ::
          :emulator_session_unresponsive
          | :emulator_session_unavailable
          | :artifact_not_found
          | :embedded_protocol_router_not_started
          | :timeout
          | :qemu_exited_before_boot
          | :qemu_exited_before_install_ready
          | :bzip2_not_found
          | :pypkjs_python_not_found
          | :embedded_emulator_disabled
          | :uv_or_pipx_not_found
          | :not_found

  @type error_detail :: String.t() | atom() | map() | integer() | binary() | [String.t() | atom()]

  @type session_tuple_error ::
          {:install_retry_reset_failed, error_detail(), error_detail()}
          | {:qemu_boot_firmware_failure, error_detail()}
          | {:protocol_router_start_failed, error_detail()}
          | {:daemon_start_failed, String.t(), error_detail()}
          | {:daemon_exited_before_ready, error_detail()}
          | {:daemon_not_ready, error_detail(), error_detail()}
          | {:install_ready_timeout, String.t(), String.t()}
          | {:qemu_console_closed, error_detail()}
          | {:port_allocation_failed, error_detail()}
          | {:qemu_flash_image_not_found, String.t()}
          | {:persist_dir_failed, error_detail()}
          | {:bzip2_failed, binary()}
          | {:embedded_emulator_unavailable, [error_detail()]}
          | {:embedded_emulator_image_download_failed, error_detail()}
          | {:compatible_python_not_found, [String.t()]}
          | {:child_not_running, :qemu | :protocol_router}
          | {:port_not_ready, :vnc | :phone, error_detail()}

  @type pbw_error ::
          {:pbw_zip_error, error_detail()}
          | {:pbw_rewrite_failed, error_detail()}
          | {:pbw_zip_rewrite_failed, error_detail()}
          | {:manifest_not_found, String.t()}
          | {:blob_not_found, atom(), String.t()}
          | {:entry_not_found, String.t()}
          | {:json_decode_failed, String.t(), error_detail()}
          | {:pbw_uuid_mismatch, String.t(), String.t()}

  @type sdk_error ::
          :python_not_found
          | :npm_not_found
          | {:sdk_archive_not_found, String.t()}
          | {:toolchain_archive_not_found, String.t()}
          | {:sdk_metadata_invalid, String.t()}
          | {:sdk_metadata_failed, String.t(), error_detail()}
          | {:sdk_download_failed, String.t(), error_detail()}
          | {:sdk_core_missing_after_extract, String.t()}
          | {:sdk_extract_failed, integer(), String.t()}
          | {:toolchain_missing_after_extract, String.t()}
          | {:toolchain_extract_failed, integer(), String.t()}
          | {:toolchain_root_not_found, String.t()}
          | {:toolchain_copy_failed, String.t()}
          | {:sdk_images_missing_after_extract, String.t()}

  @type screenshot_error ::
          :invalid_screenshot_header
          | :vnc_no_none_security
          | :vnc_security_failed
          | :vnc_empty_framebuffer_update
          | :invalid_vnc_pixel_format
          | {:invalid_bgrx_buffer, non_neg_integer(), non_neg_integer()}
          | {:invalid_rgb_buffer, non_neg_integer(), non_neg_integer()}
          | {:invalid_rgba_buffer, non_neg_integer(), non_neg_integer()}
          | {:vnc_incomplete_framebuffer, non_neg_integer(), non_neg_integer()}
          | {:vnc_framebuffer_too_small, pos_integer(), pos_integer(), pos_integer(), pos_integer()}
          | {:vnc_unsupported_pixel_format, map()}
          | {:vnc_rectangle_too_large, non_neg_integer()}
          | {:vnc_unsupported_encoding, non_neg_integer()}
          | {:screenshot_failed, non_neg_integer()}
          | {:unknown_screenshot_version, integer()}
          | vnc_error()

  @type packet_decode_error ::
          {:unexpected_app_fetch_payload, binary()}
          | {:unexpected_blob_response_payload, binary()}
          | {:unexpected_putbytes_payload, binary()}
          | {:wrong_cookie, list() | non_neg_integer(), non_neg_integer()}
          | {:nack, non_neg_integer()}

  @type install_error ::
          router_error()
          | pbw_error()
          | packet_decode_error()
          | :timeout
          | {:putbytes_failed, putbytes_phase_meta(), packet_decode_error() | :timeout | {:timeout, map() | non_neg_integer()}}
          | {:blob_insert_failed, non_neg_integer()}
          | {:wrong_blob_token, non_neg_integer(), non_neg_integer()}
          | {:wrong_app_fetch_uuid, String.t(), String.t()}

  @type router_error :: :timeout | :busy | :superseded

  @type exit_reason ::
          :normal
          | :shutdown
          | {:shutdown, atom() | String.t()}
          | atom()
          | tuple()
          | String.t()

  @type session_error ::
          session_atom_error() | session_tuple_error() | exit_reason()

  @type emulator_error ::
          session_error()
          | pbw_error()
          | sdk_error()
          | screenshot_error()
          | router_error()
          | install_error()
          | apply_settings_error()
          | :timeout

  @type pbw_install_result :: %{
          required(:uuid) => String.t(),
          required(:variant) => String.t(),
          required(:app_id) => non_neg_integer(),
          required(:parts) => [install_part_sent()]
        }
end
