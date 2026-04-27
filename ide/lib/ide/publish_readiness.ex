defmodule Ide.PublishReadiness do
  @moduledoc """
  Publish readiness validation and release notes drafting.
  """

  @required_appinfo_fields ~w(uuid shortName longName versionLabel companyName)

  @doc """
  Validates publish readiness from artifact, screenshots, and app metadata.
  """
  @spec validate(keyword()) :: {:ok, map()} | {:error, term()}
  def validate(opts) do
    artifact_path = Keyword.get(opts, :artifact_path)
    required_targets = Keyword.get(opts, :required_targets, [])
    readiness = Keyword.get(opts, :readiness, [])
    app_root = Keyword.get(opts, :app_root)
    appinfo_path = appinfo_path(app_root)
    appinfo = read_appinfo(appinfo_path)

    checks = [
      check_artifact(artifact_path),
      check_appinfo_exists(appinfo_path, appinfo),
      check_appinfo_fields(appinfo),
      check_target_platforms(appinfo, required_targets),
      check_watchapp_mode(appinfo),
      check_screenshot_coverage(readiness)
    ]

    status = if Enum.all?(checks, &(&1.status == :ok)), do: :ok, else: :error

    {:ok,
     %{
       status: status,
       checks: checks,
       appinfo_path: appinfo_path,
       release_notes_md:
         release_notes_md(
           artifact_path,
           readiness,
           checks,
           Keyword.get(opts, :project_slug, "unknown")
         )
     }}
  rescue
    error -> {:error, error}
  end

  @spec check_artifact(term()) :: term()
  defp check_artifact(path) do
    exists = is_binary(path) and File.exists?(path)
    status = if exists, do: :ok, else: :error

    %{
      id: "artifact_exists",
      label: "PBW artifact exists",
      status: status,
      message: if(exists, do: path, else: "PBW artifact missing")
    }
  end

  @spec check_appinfo_exists(term(), term()) :: term()
  defp check_appinfo_exists(path, {:ok, _appinfo}) do
    %{id: "appinfo_exists", label: "App metadata exists", status: :ok, message: path}
  end

  defp check_appinfo_exists(path, {:error, reason}) do
    %{
      id: "appinfo_exists",
      label: "App metadata exists",
      status: :error,
      message: "Missing or invalid appinfo at #{path}: #{inspect(reason)}"
    }
  end

  @spec check_appinfo_fields(term()) :: term()
  defp check_appinfo_fields({:error, _reason}) do
    %{
      id: "appinfo_fields",
      label: "Required app fields",
      status: :error,
      message: "Could not parse appinfo"
    }
  end

  defp check_appinfo_fields({:ok, appinfo}) do
    missing = Enum.filter(@required_appinfo_fields, fn key -> blank?(Map.get(appinfo, key)) end)
    status = if missing == [], do: :ok, else: :error

    %{
      id: "appinfo_fields",
      label: "Required app fields",
      status: status,
      message:
        if(missing == [],
          do: "All required app fields present",
          else: "Missing: #{Enum.join(missing, ", ")}"
        )
    }
  end

  @spec check_target_platforms(term(), term()) :: term()
  defp check_target_platforms({:error, _reason}, _required_targets) do
    %{
      id: "target_platforms",
      label: "Target platform coverage",
      status: :error,
      message: "Could not parse appinfo"
    }
  end

  defp check_target_platforms({:ok, appinfo}, required_targets) do
    targets = Map.get(appinfo, "targetPlatforms", [])
    missing = required_targets -- targets
    status = if missing == [], do: :ok, else: :error

    %{
      id: "target_platforms",
      label: "Target platform coverage",
      status: status,
      message:
        if(missing == [],
          do: "All required targets are in appinfo",
          else: "Missing targets: #{Enum.join(missing, ", ")}"
        )
    }
  end

  @spec check_watchapp_mode(term()) :: term()
  defp check_watchapp_mode({:error, _reason}) do
    %{
      id: "watchapp_mode",
      label: "Watch app/watchface mode",
      status: :error,
      message: "Could not parse appinfo"
    }
  end

  defp check_watchapp_mode({:ok, appinfo}) do
    watchapp = Map.get(appinfo, "watchapp", %{})
    has_flag = is_boolean(Map.get(watchapp, "watchface"))
    status = if has_flag, do: :ok, else: :error

    %{
      id: "watchapp_mode",
      label: "Watch app/watchface mode",
      status: status,
      message:
        if(has_flag, do: "watchface flag present", else: "Missing watchapp.watchface boolean")
    }
  end

  @spec check_screenshot_coverage(term()) :: term()
  defp check_screenshot_coverage(readiness) do
    missing = Enum.filter(readiness, &(&1.status != :ok))
    status = if missing == [], do: :ok, else: :error

    %{
      id: "screenshot_coverage",
      label: "Screenshot coverage per model",
      status: status,
      message:
        if(missing == [],
          do: "All required models have screenshots",
          else: "Missing screenshots: #{Enum.map_join(missing, ", ", & &1.target)}"
        )
    }
  end

  @spec appinfo_path(term()) :: term()
  defp appinfo_path(app_root) when is_binary(app_root) do
    Path.join([app_root, "build", "appinfo.json"])
  end

  defp appinfo_path(_), do: "build/appinfo.json"

  @spec read_appinfo(term()) :: term()
  defp read_appinfo(path) do
    with {:ok, json} <- File.read(path),
         {:ok, decoded} <- Jason.decode(json) do
      {:ok, decoded}
    end
  end

  @spec blank?(term()) :: term()
  defp blank?(value), do: value in [nil, ""]

  @spec release_notes_md(term(), term(), term(), term()) :: term()
  defp release_notes_md(artifact_path, readiness, checks, project_slug) do
    check_lines =
      Enum.map(checks, fn c ->
        "- [#{if c.status == :ok, do: "x", else: " "}] #{c.label}: #{c.message}"
      end)

    screenshot_lines =
      Enum.map(readiness, fn item ->
        "- #{item.target}: #{item.count} screenshot(s) (#{item.status})"
      end)

    """
    # Release Notes Draft

    Project: #{project_slug}

    ## Artifact
    - PBW: #{artifact_path || "<missing>"}

    ## Validation Checklist
    #{Enum.join(check_lines, "\n")}

    ## Screenshot Coverage
    #{Enum.join(screenshot_lines, "\n")}
    """
    |> String.trim()
  end
end
