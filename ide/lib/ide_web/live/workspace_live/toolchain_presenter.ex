defmodule IdeWeb.WorkspaceLive.ToolchainPresenter do
  @moduledoc false

  alias Ide.EmulatorSupport
  alias Ide.PebbleToolchain
  alias Ide.PublishManifest
  alias Ide.PublishReadiness
  alias Ide.Screenshots

  @spec render_toolchain_output(PebbleToolchain.command_result()) :: String.t()
  def render_toolchain_output(result) do
    """
    cwd: #{result.cwd}
    command: #{result.command}
    exit_code: #{result.exit_code}

    #{String.trim(result.output)}
    """
  end

  @spec render_screenshot_output(Screenshots.capture_result()) :: String.t()
  def render_screenshot_output(result) do
    """
    command: #{result.command}
    exit_code: #{result.exit_code}

    emulator_target: #{result.screenshot.emulator_target}
    stored: #{result.screenshot.absolute_path}
    url: #{result.screenshot.url}

    #{String.trim(result.output)}
    """
  end

  @spec render_capture_all_output(Screenshots.capture_all_result()) :: String.t()
  def render_capture_all_output(result) do
    lines =
      Enum.map(result.results, fn
        {target, {:ok, capture}} ->
          "[ok] #{target} -> #{capture.screenshot.filename}"

        {target, {:error, reason}} ->
          "[error] #{target} -> #{inspect(reason)}"
      end)

    close_line =
      case result[:close_result] do
        {:ok, :embedded} -> "emulator_close: ok (embedded)"
        {:ok, %{exit_code: exit_code}} -> "emulator_close: ok (exit_code=#{exit_code})"
        {:ok, close} -> "emulator_close: ok (#{inspect(close)})"
        {:error, reason} -> "emulator_close: error (#{inspect(reason)})"
        _ -> "emulator_close: skipped"
      end

    """
    captured: #{length(result.captured)}
    failed: #{length(result.failed)}
    #{close_line}

    #{Enum.join(lines, "\n")}
    """
  end

  @spec render_publish_output(PebbleToolchain.package_result()) :: String.t()
  def render_publish_output(result) do
    """
    command: #{result.build_result.command}
    exit_code: #{result.build_result.exit_code}
    artifact: #{result.artifact_path}

    #{String.trim(result.build_result.output)}
    """
  end

  @spec render_manifest_export_output(PublishManifest.export_result()) :: String.t()
  def render_manifest_export_output(result) do
    screenshot_count =
      result.payload.screenshots_by_target
      |> Enum.map(&length(&1.screenshots))
      |> Enum.sum()

    readiness_lines =
      result.payload.readiness
      |> Enum.map(fn item ->
        "#{item.target}: #{item.count} (#{item.status})"
      end)

    """
    path: #{result.path}
    schema_version: #{result.payload.schema_version}
    project: #{result.payload.project_slug}
    screenshots: #{screenshot_count}

    #{Enum.join(readiness_lines, "\n")}
    """
    |> String.trim()
  end

  @spec emulator_targets() :: [String.t()]
  def emulator_targets do
    EmulatorSupport.supported_targets()
  end

  @spec emulator_mode_options(String.t() | nil) :: [{String.t(), String.t()}]
  def emulator_mode_options(target) do
    EmulatorSupport.mode_options(target)
  end

  @spec publish_readiness([Screenshots.screenshot()], [String.t()]) ::
          [PublishReadiness.screenshot_readiness()]
  def publish_readiness(shots, targets) do
    counts =
      shots
      |> Enum.group_by(& &1.emulator_target)
      |> Map.new(fn {target, values} -> {target, length(values)} end)

    Enum.map(targets, fn target ->
      count = Map.get(counts, target, 0)
      %{target: target, count: count, status: if(count > 0, do: :ok, else: :missing)}
    end)
  end
end
