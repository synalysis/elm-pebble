defmodule IdeWeb.WorkspaceLive.ToolchainPresenter do
  @moduledoc false

  alias Ide.PebbleToolchain

  @spec render_toolchain_output(map()) :: String.t()
  def render_toolchain_output(result) do
    """
    cwd: #{result.cwd}
    command: #{result.command}
    exit_code: #{result.exit_code}

    #{String.trim(result.output)}
    """
  end

  @spec render_screenshot_output(map()) :: String.t()
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

  @spec render_capture_all_output(map()) :: String.t()
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
        {:ok, close} -> "emulator_close: ok (exit_code=#{close.exit_code})"
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

  @spec render_publish_output(map()) :: String.t()
  def render_publish_output(result) do
    """
    command: #{result.build_result.command}
    exit_code: #{result.build_result.exit_code}
    artifact: #{result.artifact_path}

    #{String.trim(result.build_result.output)}
    """
  end

  @spec render_manifest_export_output(map()) :: String.t()
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
    PebbleToolchain.supported_emulator_targets()
  end

  @spec publish_readiness([map()], [String.t()]) :: [map()]
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
