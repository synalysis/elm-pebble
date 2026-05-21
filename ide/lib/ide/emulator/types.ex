defmodule Ide.Emulator.Types do
  @moduledoc false

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

  @type session_tuple_error ::
          {:install_retry_reset_failed, term(), term()}
          | {:qemu_boot_firmware_failure, term()}
          | {:protocol_router_start_failed, term()}
          | {:daemon_start_failed, String.t(), term()}
          | {:daemon_exited_before_ready, term()}
          | {:daemon_not_ready, term(), term()}
          | {:install_ready_timeout, String.t(), String.t()}
          | {:qemu_console_closed, term()}
          | {:port_allocation_failed, term()}
          | {:qemu_flash_image_not_found, String.t()}
          | {:persist_dir_failed, term()}
          | {:bzip2_failed, binary()}
          | {:embedded_emulator_unavailable, [term()]}
          | {:embedded_emulator_image_download_failed, term()}
          | {:compatible_python_not_found, [String.t()]}
          | {:child_not_running, :qemu | :protocol_router}
          | {:port_not_ready, :vnc | :phone, term()}

  @type pbw_error ::
          {:pbw_zip_error, term()}
          | {:pbw_rewrite_failed, term()}
          | {:pbw_zip_rewrite_failed, term()}
          | {:manifest_not_found, String.t()}
          | {:blob_not_found, atom(), String.t()}
          | {:entry_not_found, String.t()}
          | {:json_decode_failed, String.t(), term()}
          | {:pbw_uuid_mismatch, String.t(), String.t()}

  @type sdk_error ::
          :python_not_found
          | :npm_not_found
          | {:sdk_archive_not_found, String.t()}
          | {:toolchain_archive_not_found, String.t()}
          | {:sdk_metadata_invalid, String.t()}
          | {:sdk_metadata_failed, String.t(), term()}
          | {:sdk_download_failed, String.t(), term()}
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

  @type router_error :: :timeout | :busy | :superseded

  @type exit_reason :: term()

  @type session_error ::
          session_atom_error() | session_tuple_error() | exit_reason()

  @type emulator_error ::
          session_error() | pbw_error() | sdk_error() | screenshot_error() | router_error() | :timeout
end
