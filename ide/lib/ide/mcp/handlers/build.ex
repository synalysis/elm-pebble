defmodule Ide.Mcp.Handlers.Build do
  @moduledoc false

  alias Ide.Mcp.ToolSupport
  alias Ide.Mcp.ToolTypes
  alias Ide.Mcp.WireTypes
  alias Ide.PebbleToolchain
  alias Ide.Projects
  alias Ide.Screenshots

  def call("pebble.package", %{"slug" => slug}) do
    toolchain = pebble_toolchain_module()

    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, result} <-
           toolchain.package(slug,
             workspace_root: Projects.project_workspace_path(project),
             target_type: project.target_type,
             project_name: project.name,
             target_platforms: ToolSupport.publish_target_platforms(project)
           ) do
      {:ok, pebble_package_payload(slug, result)}
    else
      {:error, reason} -> {:error, format_pebble_package_failure(reason)}
    end
  end

  def call("pebble.install", %{"slug" => slug} = args) do
    toolchain = pebble_toolchain_module()
    logs_snapshot_seconds = parse_logs_snapshot_seconds(Map.get(args, "logs_snapshot_seconds"))

    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, package_path} <- resolve_install_package_path(project, args, toolchain),
         {:ok, install_result} <-
           toolchain.run_emulator(slug,
             emulator_target: Map.get(args, "emulator_target"),
             package_path: package_path,
             logs_snapshot_seconds: logs_snapshot_seconds
           ) do
      {:ok, pebble_install_payload(slug, package_path, install_result)}
    else
      {:error, reason} -> {:error, "pebble install failed: #{inspect(reason)}"}
    end
  end

  def call("screenshots.list", %{"slug" => slug}) do
    screenshots = screenshots_module()

    with {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, shots} <- screenshots.list(slug, []) do
      entries = Enum.map(shots, &mcp_screenshot_entry/1)

      {:ok, screenshots_list_payload(slug, entries)}
    else
      {:error, reason} -> {:error, "screenshot list failed: #{inspect(reason)}"}
    end
  end

  def call("screenshots.read", %{
         "slug" => slug,
         "emulator_target" => emulator_target,
         "filename" => filename
       }) do
    screenshots = screenshots_module()

    with {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, shots} <- screenshots.list(slug, []),
         {:ok, shot} <- find_screenshot(shots, emulator_target, filename),
         {:ok, data} <- File.read(Map.fetch!(shot, :absolute_path)) do
      metadata = mcp_screenshot_entry(shot)

      {:ok,
       screenshots_read_payload(
         slug,
         metadata,
         metadata.mime_type,
         byte_size(data),
         Base.encode16(:crypto.hash(:sha256, data), case: :lower),
         Base.encode64(data)
       )}
    else
      {:error, reason} -> {:error, "screenshot read failed: #{inspect(reason)}"}
    end
  end

  def call("screenshots.capture", %{"slug" => slug} = args) do
    screenshots = screenshots_module()

    with {:ok, _project} <- ToolSupport.fetch_project(slug),
         {:ok, result} <-
           screenshots.capture(
             slug,
             emulator_target: Map.get(args, "emulator_target")
           ) do
      {:ok,
       screenshots_capture_payload(
         slug,
         result.screenshot,
         result.output,
         result.exit_code,
         result.command,
         result.cwd
       )}
    else
      {:error, reason} -> {:error, "screenshot capture failed: #{inspect(reason)}"}
    end
  end

  defp mcp_tools_config, do: Application.get_env(:ide, Ide.Mcp.Tools, [])

  @spec pebble_install_payload(String.t(), String.t(), map()) :: ToolTypes.pebble_install_result()
  defp pebble_install_payload(slug, artifact_path, install_result)
       when is_binary(slug) and is_binary(artifact_path) and is_map(install_result) do
    %{slug: slug, artifact_path: artifact_path, install_result: install_result}
  end

  @spec pebble_package_payload(String.t(), PebbleToolchain.package_result()) ::
          ToolTypes.pebble_package_result()
  defp pebble_package_payload(slug, result) do
    %{
      slug: slug,
      status: result.status,
      artifact_path: result.artifact_path,
      package_path: result.artifact_path,
      app_root: result.app_root,
      build_result: result.build_result
    }
  end

  @spec format_pebble_package_failure(PebbleToolchain.toolchain_error()) :: String.t()
  defp format_pebble_package_failure({:pebble_build_failed, %{output: output} = result})
       when is_binary(output) do
    tail =
      output
      |> String.split("\n", trim: false)
      |> Enum.take(-50)
      |> Enum.join("\n")
      |> String.trim()

    command = Map.get(result, :command, "pebble build")
    exit_code = Map.get(result, :exit_code, "?")

    "pebble package failed (#{command}, exit #{exit_code}):\n\n#{tail}"
  end

  defp format_pebble_package_failure(reason) do
    "pebble package failed: #{inspect(reason)}"
  end

  @spec mcp_screenshot_entry(map()) :: ToolTypes.screenshot_entry()
  defp mcp_screenshot_entry(shot) when is_map(shot) do
    target = Map.get(shot, :emulator_target)
    captured_at = Map.get(shot, :captured_at)

    %{
      filename: Map.get(shot, :filename),
      target_device: target,
      emulator_target: target,
      captured_at: captured_at,
      timestamp: captured_at,
      mime_type: Map.get(shot, :mime_type) || screenshot_mime_type(Map.get(shot, :filename)),
      url: Map.get(shot, :url),
      absolute_path: Map.get(shot, :absolute_path)
    }
  end

  @spec find_screenshot([map()], String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  defp find_screenshot(shots, emulator_target, filename) do
    case Enum.find(shots, &screenshot_match?(&1, emulator_target, filename)) do
      nil -> {:error, :screenshot_not_found}
      shot -> {:ok, shot}
    end
  end

  @spec screenshot_match?(map(), String.t(), String.t()) :: boolean()
  defp screenshot_match?(shot, emulator_target, filename) do
    Map.get(shot, :emulator_target) == emulator_target and Map.get(shot, :filename) == filename and
      is_binary(Map.get(shot, :absolute_path))
  end

  @spec screenshot_mime_type(String.t() | nil) :: String.t()
  defp screenshot_mime_type(filename) when is_binary(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "image/png"
    end
  end

  defp screenshot_mime_type(_filename), do: "application/octet-stream"

  @spec screenshots_capture_payload(String.t(), map(), String.t(), integer(), String.t(), String.t()) ::
          ToolTypes.screenshots_capture_result()
  defp screenshots_capture_payload(slug, screenshot, output, exit_code, command, cwd)
       when is_binary(slug) and is_binary(output) and is_integer(exit_code) and is_binary(command) and
              is_binary(cwd) do
    %{slug: slug, screenshot: screenshot, output: output, exit_code: exit_code, command: command, cwd: cwd}
  end

  @spec screenshots_list_payload(String.t(), [map()]) :: ToolTypes.screenshots_list_result()
  defp screenshots_list_payload(slug, entries) when is_binary(slug) and is_list(entries) do
    %{slug: slug, count: length(entries), screenshots: entries}
  end

  @spec screenshots_read_payload(
          String.t(),
          map(),
          String.t(),
          non_neg_integer(),
          String.t(),
          String.t()
        ) :: ToolTypes.screenshots_read_result()
  defp screenshots_read_payload(slug, screenshot, mime_type, bytes, sha256, content_base64)
       when is_binary(slug) and is_map(screenshot) and is_binary(mime_type) and is_integer(bytes) and
              is_binary(sha256) and is_binary(content_base64) do
    %{
      slug: slug,
      screenshot: screenshot,
      mime_type: mime_type,
      encoding: "base64",
      bytes: bytes,
      sha256: sha256,
      content_base64: content_base64
    }
  end

  @spec screenshots_module() :: module()
  defp screenshots_module do
    mcp_tools_config()
    |> Keyword.get(:screenshots_module, Screenshots)
  end

  @spec pebble_toolchain_module() :: module()
  defp pebble_toolchain_module do
    mcp_tools_config()
    |> Keyword.get(:pebble_toolchain_module, PebbleToolchain)
  end

  @spec resolve_install_package_path(map(), map(), module()) ::
          {:ok, String.t()} | {:error, ToolTypes.tool_persist_error()}
  defp resolve_install_package_path(project, args, toolchain) do
    case Map.get(args, "package_path") do
      path when is_binary(path) and path != "" ->
        resolved = Path.expand(path)

        if File.exists?(resolved) do
          {:ok, resolved}
        else
          {:error, {:package_path_not_found, resolved}}
        end

      _ ->
        toolchain.package(project.slug,
          workspace_root: Projects.project_workspace_path(project),
          target_type: project.target_type,
          project_name: project.name
        )
        |> case do
          {:ok, %{artifact_path: artifact_path}} -> {:ok, artifact_path}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec parse_logs_snapshot_seconds(WireTypes.integer_input()) :: pos_integer()
  defp parse_logs_snapshot_seconds(value) when is_integer(value) and value >= 1 do
    min(value, 30)
  end

  defp parse_logs_snapshot_seconds(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed >= 1 -> min(parsed, 30)
      _ -> 4
    end
  end

  defp parse_logs_snapshot_seconds(_), do: 4
end
