defmodule Ide.Emulator.Workflow do
  @moduledoc """
  Shared embedded-emulator launch/package flow for HTTP and MCP entry points.
  """

  alias Ide.Emulator
  alias Ide.Emulator.Session.Startup
  alias Ide.Projects
  alias Ide.WatchModels
  alias IdeWeb.WorkspaceLive.BuildFlow

  @type launch_result :: %{
          required(:session) => Ide.Emulator.Types.session_info(),
          required(:artifact_path) => String.t(),
          required(:platform) => String.t()
        }

  @spec launch_project(Projects.Project.t() | map(), String.t() | nil) ::
          {:ok, launch_result()} | {:error, term()}
  def launch_project(project, platform) do
    platform = normalize_platform(platform)

    with :ok <- ensure_runtime_ready(platform),
         workspace_root <- Projects.project_workspace_path(project),
         {:ok, package_result, launch_platform} <-
           package_for_launch(project, workspace_root, platform),
         {:ok, session} <-
           Emulator.launch(
             project_slug: Projects.scope_key(project),
             platform: launch_platform,
             artifact_path: package_result.artifact_path,
             has_phone_companion: Map.get(package_result, :has_phone_companion, false),
             has_companion_preferences: Map.get(package_result, :has_companion_preferences, false)
           ) do
      {:ok,
       %{
         session: session,
         artifact_path: package_result.artifact_path,
         platform: launch_platform
       }}
    end
  end

  @doc """
  Rebuilds the session PBW from the current workspace so Install uses fresh toolchain output.

  Launch already packages once; this avoids stale artifacts when the IDE server or build
  flags change between launch and install.
  """
  @spec refresh_session_artifact(map()) :: {:ok, map()} | {:error, term()}
  def refresh_session_artifact(%{project_slug: slug, platform: platform} = state)
      when is_binary(slug) and slug != "" and is_binary(platform) and platform != "" do
    with %Projects.Project{} = project <- Projects.get_project_by_scope_key(slug),
         workspace_root = Projects.project_workspace_path(project),
         {:ok, packaged} <-
           BuildFlow.package_for_emulator_session(project, workspace_root, platform) do
      {:ok,
       %{
         state
         | artifact_path: packaged.artifact_path,
           app_uuid: Startup.app_uuid(packaged.artifact_path, platform),
           has_phone_companion: Map.get(packaged, :has_phone_companion, false),
           has_companion_preferences: Map.get(packaged, :has_companion_preferences, false)
       }}
    else
      nil -> {:ok, state}
      {:error, _} = error -> error
    end
  end

  def refresh_session_artifact(state) when is_map(state), do: {:ok, state}

  @spec wait_display_ready(String.t(), keyword()) :: :ok | {:error, term()}
  def wait_display_ready(session_id, opts \\ []) when is_binary(session_id) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 120_000)
    interval_ms = Keyword.get(opts, :interval_ms, 250)
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_display_ready(session_id, deadline, interval_ms)
  end

  @spec launch_error_message(term()) :: String.t()
  def launch_error_message({:daemon_exited_before_ready, _port}) do
    "The phone bridge (pypkjs) exited before it could connect to the watch emulator. " <>
      "Try launching again; if it keeps failing, restart the IDE server to clear stale emulator processes."
  end

  def launch_error_message({:qemu_boot_timeout, _tail}) do
    "The watch emulator did not finish booting in time. Try launching again."
  end

  def launch_error_message(:compile_project_root_not_found) do
    "Could not find Elm project files (elm.json) in this workspace. Restore your project sources from backup or re-import the project, then try again."
  end

  def launch_error_message({:embedded_emulator_unavailable, missing}) when is_list(missing) do
    "Embedded emulator dependencies are missing: #{Enum.join(missing, ", ")}. " <>
      "Install Pebble QEMU/pypkjs or set ELM_PEBBLE_QEMU_BIN, ELM_PEBBLE_PYPKJS_BIN, and ELM_PEBBLE_QEMU_IMAGE_ROOT."
  end

  def launch_error_message(:embedded_emulator_disabled) do
    "Embedded emulator is disabled by ELM_PEBBLE_EMBEDDED_EMULATOR."
  end

  def launch_error_message({:embedded_emulator_image_download_failed, reason}) do
    "Could not download Pebble QEMU flash images: #{inspect(reason)}. " <>
      "Check network access or set ELM_PEBBLE_QEMU_IMAGE_ROOT to a directory that already contains <platform>/qemu images."
  end

  def launch_error_message(:timeout) do
    "All emulator slots are in use; timed out waiting for a free slot. Try again later."
  end

  def launch_error_message(:display_ready_timeout),
    do: "Embedded emulator display was not ready before the timeout."

  def launch_error_message({:pebble_build_failed, %{output: output}}) when is_binary(output) do
    case Ide.PebbleToolchain.BuildDiagnostics.launch_message(output) do
      message when is_binary(message) ->
        message

      _ ->
        "Pebble app packaging failed while building the watch binary. Open the Build panel for the full package log."
    end
  end

  def launch_error_message({:bitmap_resource_stage_failed, filename, reason})
      when is_binary(filename) do
    "Bitmap `#{filename}` could not be prepared for packaging. #{bitmap_import_error_message(reason)}"
  end

  def launch_error_message({:protocol_router_start_failed, :eaddrinuse}) do
    "The emulator could not start its communication bridge because a required network port is already in use. " <>
      "Stop any other emulator sessions for this project, wait a few seconds, then try again. " <>
      "If the problem persists, restart the IDE server to clear stale emulator processes."
  end

  def launch_error_message({:protocol_router_start_failed, reason}) do
    "The emulator could not start its communication bridge (#{protocol_router_detail(reason)}). " <>
      "Try launching again; if it keeps failing, restart the IDE server."
  end

  def launch_error_message(reason), do: inspect(reason)

  defp bitmap_import_error_message(:bitmap_converter_missing),
    do:
      "Install ImageMagick (`magick` or `convert`) on the IDE host, or re-import the image as PNG from the Resources page."

  defp bitmap_import_error_message(:bitmap_conversion_failed),
    do: "The file could not be converted to PNG. Re-import it from the Resources page."

  defp bitmap_import_error_message(:invalid_bitmap_image),
    do: "The file is corrupted or not a supported image format."

  defp bitmap_import_error_message(other),
    do: "Re-import or remove the bitmap on the Resources page (#{inspect(other)})."

  defp protocol_router_detail(reason), do: inspect(reason)

  @spec install_error_message(term()) :: String.t()
  def install_error_message(:artifact_not_found),
    do: "PBW artifact not found for this emulator session."

  def install_error_message({:pbw_platform_mismatch, %{expected: expected, got: got}}) do
    "PBW binary is built for #{got}, but this emulator session is #{expected}. " <>
      "Stop and launch the emulator again so the app rebuilds for #{expected}, then install."
  end

  def install_error_message(:embedded_protocol_router_not_started),
    do: "Embedded emulator protocol router is not running."

  def install_error_message({:install_ready_timeout, marker, _tail}) do
    "Emulator did not reach “#{marker}” before install. Stop and launch the emulator again, then wait a few seconds before installing."
  end

  def install_error_message({:putbytes_failed, %{phase: phase, kind: kind}, :timeout}) do
    "PutBytes timed out during #{phase} (#{kind}). Stop and launch the emulator again, or wait a few seconds after launch before installing."
  end

  def install_error_message({:putbytes_failed, %{phase: phase, kind: kind}, {:timeout, _}}) do
    "PutBytes timed out during #{phase} (#{kind}). Stop and launch the emulator again, or wait a few seconds after launch before installing."
  end

  def install_error_message({:putbytes_failed, %{phase: phase, kind: kind}, {:nack, _cookie}}) do
    "PutBytes was rejected during #{phase} (#{kind}). Stop and launch the emulator, then try installing again."
  end

  def install_error_message(:emulator_session_unresponsive),
    do:
      "Embedded emulator session did not respond during install (it may still be uploading). Try again or relaunch the emulator."

  def install_error_message(:emulator_session_unavailable),
    do: "Embedded emulator protocol router is not running."

  def install_error_message(reason), do: inspect(reason)

  @spec normalize_platform(String.t() | nil) :: String.t()
  defp normalize_platform(platform) when is_binary(platform) do
    platform = String.trim(platform)
    if platform == "", do: WatchModels.default_id(), else: platform
  end

  defp normalize_platform(_), do: WatchModels.default_id()

  defp package_for_launch(project, workspace_root, platform) do
    case BuildFlow.package_for_emulator_session(project, workspace_root, platform) do
      {:ok, package_result} ->
        {:ok, package_result, platform}

      {:error, reason} ->
        fallback_platform = WatchModels.default_id()

        if aplite_app_overflow?(platform, reason) and platform != fallback_platform do
          with {:ok, package_result} <-
                 BuildFlow.package_for_emulator_session(
                   project,
                   workspace_root,
                   fallback_platform
                 ) do
            {:ok, package_result, fallback_platform}
          end
        else
          {:error, reason}
        end
    end
  end

  defp ensure_runtime_ready(platform) do
    case Emulator.runtime_status(platform) do
      %{missing: []} ->
        :ok

      %{missing: missing} when is_list(missing) ->
        {:error, {:embedded_emulator_unavailable, Enum.map(missing, &component_missing_detail/1)}}
    end
  end

  defp component_missing_detail(%{label: label, detail: detail})
       when is_binary(label) and is_binary(detail),
       do: "#{label}: #{detail}"

  defp component_missing_detail(%{label: label}) when is_binary(label), do: label
  defp component_missing_detail(component), do: inspect(component)

  defp aplite_app_overflow?("aplite", {:pebble_build_failed, %{output: output}})
       when is_binary(output) do
    String.contains?(output, "region `APP' overflowed")
  end

  defp aplite_app_overflow?(_platform, _reason), do: false

  defp poll_display_ready(session_id, deadline, interval_ms) do
    case Emulator.ping(session_id) do
      {:ok, %{display_ready: true}} ->
        :ok

      {:ok, _info} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :display_ready_timeout}
        else
          Process.sleep(interval_ms)
          poll_display_ready(session_id, deadline, interval_ms)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
