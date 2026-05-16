defmodule IdeWeb.WorkspaceLive.PublishFlow do
  @moduledoc false

  alias Ide.PebbleToolchain
  alias Ide.PublishManifest
  alias Ide.PublishReadiness
  alias Ide.Screenshots
  alias IdeWeb.WorkspaceLive.ToolchainPresenter

  @spec default_release_summary(map() | nil) :: map()
  def default_release_summary(project \\ nil) do
    defaults = release_defaults(project)

    %{
      "version_label" => Map.get(defaults, "version_label", ""),
      "release_channel" => Map.get(defaults, "release_channel", "stable"),
      "tags" => Map.get(defaults, "tags", ""),
      "changelog" => ""
    }
  end

  @spec merge_release_summary(map(), map()) :: map()
  def merge_release_summary(existing, updates) do
    existing
    |> Map.merge(updates)
    |> Map.update!("version_label", &String.trim/1)
    |> Map.update!("release_channel", &String.trim/1)
    |> Map.update!("tags", &String.trim/1)
    |> Map.update!("changelog", &String.trim/1)
  end

  @spec quick_fix_message(String.t()) :: String.t()
  def quick_fix_message(check_id) do
    case check_id do
      "appinfo_exists" ->
        "Open .pebble-sdk/app/package.json to fix missing metadata, then rerun Prepare Release."

      "appinfo_fields" ->
        "Update required metadata fields in .pebble-sdk/app/package.json, then rerun Prepare Release."

      "watchapp_mode" ->
        "Set pebble.watchapp.watchface to true/false in .pebble-sdk/app/package.json, then rerun Prepare Release."

      _ ->
        "Review the check details, apply a fix, then rerun Prepare Release."
    end
  end

  @spec run_prepare_release(map(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def run_prepare_release(project, workspace_root, release_summary) do
    started_at_ms = System.monotonic_time(:millisecond)

    with {:ok, package_result} <-
           PebbleToolchain.package(project.slug,
             workspace_root: workspace_root,
             target_type: project.target_type,
             project_name: project.name,
             target_platforms: target_platforms(project),
             capabilities: capabilities(project)
           ) do
      screenshots = load_screenshots(project)
      screenshot_groups = group_screenshots(screenshots)
      readiness = publish_readiness(screenshots)

      checks =
        case PublishReadiness.validate(
               artifact_path: package_result.artifact_path,
               required_targets: target_platforms(project),
               readiness: readiness,
               app_root: package_result.app_root,
               project_slug: project.slug
             ) do
          {:ok, validation} ->
            validation.checks

          {:error, reason} ->
            [
              %{
                id: "validation_error",
                label: "Publish validation",
                status: :error,
                message: inspect(reason)
              }
            ]
        end

      validation_status = if Enum.all?(checks, &(&1.status == :ok)), do: :ok, else: :error

      {:ok, manifest_result} =
        PublishManifest.export(project.slug,
          artifact_path: package_result.artifact_path,
          screenshot_groups: screenshot_groups,
          required_targets: target_platforms(project),
          readiness: readiness
        )

      release_notes =
        release_notes_markdown(
          checks,
          readiness,
          package_result.artifact_path,
          project.slug,
          release_summary
        )

      {:ok, notes_result} = PublishManifest.export_release_notes(project.slug, release_notes)
      elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
      finished_at = DateTime.utc_now() |> DateTime.to_iso8601()

      output =
        [
          ToolchainPresenter.render_publish_output(package_result),
          "",
          "manifest: #{manifest_result.path}",
          "release_notes: #{notes_result.path}",
          "duration_ms: #{elapsed_ms}"
        ]
        |> Enum.join("\n")
        |> String.trim()

      {:ok,
       %{
         project: project,
         release_summary: release_summary,
         validation_status: validation_status,
         checks: checks,
         readiness: readiness,
         artifact_path: package_result.artifact_path,
         app_root: package_result.app_root,
         manifest_status: :ok,
         manifest_path: manifest_result.path,
         manifest_output: ToolchainPresenter.render_manifest_export_output(manifest_result),
         release_notes_status: :ok,
         release_notes_path: notes_result.path,
         release_notes_output: "Release notes exported to #{notes_result.path}",
         output: output,
         duration_ms: elapsed_ms,
         finished_at: finished_at,
         in_ide_completed?: validation_status == :ok
       }}
    end
  rescue
    error ->
      {:error, error}
  end

  defp target_platforms(project) do
    defaults = Map.get(project, :release_defaults, %{}) || %{}
    allowed = ToolchainPresenter.emulator_targets()

    defaults
    |> Map.get("target_platforms", allowed)
    |> normalize_target_platforms(allowed)
  end

  defp normalize_target_platforms(value, allowed) when is_list(value) do
    allowed_set = MapSet.new(allowed)

    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&MapSet.member?(allowed_set, &1))
    |> Enum.uniq()
    |> case do
      [] -> allowed
      platforms -> platforms
    end
  end

  defp normalize_target_platforms(_value, allowed), do: allowed

  defp capabilities(project) do
    defaults = Map.get(project, :release_defaults, %{}) || %{}

    defaults
    |> Map.get("capabilities", [])
    |> normalize_capabilities()
  end

  defp normalize_capabilities(value) when is_list(value) do
    allowed = MapSet.new(["location", "configurable", "health"])

    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&MapSet.member?(allowed, &1))
    |> Enum.uniq()
  end

  defp normalize_capabilities(_), do: []

  @spec release_notes_markdown([map()], [map()], String.t() | nil, String.t(), map()) ::
          String.t()
  def release_notes_markdown(checks, readiness, artifact_path, project_slug, release_summary) do
    check_lines =
      Enum.map(checks, fn check ->
        "- [#{if check.status == :ok, do: "x", else: " "}] #{check.label}: #{check.message}"
      end)

    readiness_lines =
      Enum.map(readiness, fn item ->
        "- #{item.target}: #{item.count} screenshot(s) (#{item.status})"
      end)

    """
    # Release Notes Draft

    Project: #{project_slug}
    Version: #{release_summary["version_label"]}
    Channel: #{release_summary["release_channel"]}
    Tags: #{release_summary["tags"]}

    ## Artifact
    - PBW: #{artifact_path || "<missing>"}

    ## Changelog
    #{release_summary["changelog"]}

    ## Validation Checklist
    #{Enum.join(check_lines, "\n")}

    ## Screenshot Coverage
    #{Enum.join(readiness_lines, "\n")}
    """
    |> String.trim()
  end

  @spec publish_summary([map()], [map()], [map()]) :: map()
  def publish_summary(checks, warnings, readiness) do
    blockers = Enum.count(checks, &(&1.status != :ok))
    passed = Enum.count(checks, &(&1.status == :ok))
    missing_targets = Enum.count(readiness, &(&1.status != :ok))
    blockers = blockers + missing_targets

    %{
      status: if(blockers == 0, do: :ready, else: :blocked),
      blockers: blockers,
      warnings: length(warnings),
      passed: passed
    }
  end

  @spec publish_warnings(map() | nil, [map()], map()) :: [map()]
  def publish_warnings(project, readiness, release_summary) do
    type = project_type(project)
    low_coverage_threshold = if(type == :watchface, do: 2, else: 1)

    readiness_warnings =
      readiness
      |> Enum.filter(&(&1.count < low_coverage_threshold))
      |> Enum.map(fn item ->
        %{
          id: "low_screenshot_density_#{item.target}",
          label: "Screenshot quality hint",
          message:
            "#{item.target} has #{item.count} screenshot(s); recommended #{low_coverage_threshold}+ for #{type_label(type)} releases."
        }
      end)

    changelog_warning =
      if String.trim(release_summary["changelog"] || "") == "" do
        [
          %{
            id: "release_summary_missing_changelog",
            label: "Release summary",
            message: "Add changelog bullets so release notes are immediately useful."
          }
        ]
      else
        []
      end

    readiness_warnings ++ changelog_warning
  end

  @spec publish_type_guidance(map() | nil, [map()] | nil) :: map()
  def publish_type_guidance(nil, _readiness) do
    %{
      headline: "Publish checklist adapts after release validation runs.",
      items: [
        "Generate PBW artifact and validate metadata.",
        "Capture screenshots for each target model.",
        "Export release notes and publish bundle metadata."
      ]
    }
  end

  def publish_type_guidance(project, _readiness) do
    case project_type(project) do
      :watchface ->
        %{
          headline: "Watchface release checklist: visual quality and legibility matter most.",
          items: [
            "Include at least one screenshot with clear time readability at a glance.",
            "Capture different styles or complications if your face supports them.",
            "Use release notes to call out visual options and battery-impact changes."
          ]
        }

      :watchapp ->
        %{
          headline: "Watchapp release checklist: interaction clarity and feature behavior.",
          items: [
            "Capture key interaction screens (entry, primary action, completion).",
            "Use release notes to describe behavior changes and any migration steps.",
            "Keep screenshot set representative across supported watch models."
          ]
        }
    end
  end

  @spec update_publish_metrics(map(), map()) :: map()
  def update_publish_metrics(metrics, result) do
    total_runs = (metrics[:total_runs] || 0) + 1

    successful_runs =
      (metrics[:successful_runs] || 0) + if(result.in_ide_completed?, do: 1, else: 0)

    completion_rate = successful_runs / max(total_runs, 1) * 100

    %{
      total_runs: total_runs,
      successful_runs: successful_runs,
      last_duration_ms: result.duration_ms,
      last_finished_at: result.finished_at,
      in_ide_completion_rate: :erlang.float_to_binary(completion_rate, decimals: 2)
    }
  end

  @spec publish_project_attrs_from_submit(map(), map()) :: map()
  def publish_project_attrs_from_submit(project, release_summary) do
    now = DateTime.utc_now()
    latest_version = blank_to_nil(release_summary["version_label"])
    defaults = release_defaults(project)

    updated_defaults =
      defaults
      |> Map.put("release_channel", release_summary["release_channel"] || "stable")
      |> Map.put("version_label", release_summary["version_label"] || "")
      |> Map.put("tags", release_summary["tags"] || "")

    %{
      "latest_published_version" => latest_version,
      "latest_published_at" => now,
      "store_sync_at" => now,
      "release_defaults" => updated_defaults
    }
  end

  @spec publish_readiness([map()]) :: [map()]
  def publish_readiness(shots) do
    ToolchainPresenter.publish_readiness(shots, ToolchainPresenter.emulator_targets())
  end

  @spec load_screenshots(term()) :: term()
  defp load_screenshots(project) do
    case Screenshots.list(project.slug, []) do
      {:ok, shots} -> shots
      _ -> []
    end
  end

  @spec group_screenshots(term()) :: term()
  defp group_screenshots(shots) do
    shots
    |> Enum.group_by(& &1.emulator_target)
    |> Enum.sort_by(fn {emulator_target, _} -> emulator_target end)
  end

  @spec project_type(term()) :: term()
  defp project_type(%{target_type: "watchface"}), do: :watchface
  defp project_type(%{target_type: "watchapp"}), do: :watchapp
  defp project_type(_), do: :watchapp

  @spec type_label(term()) :: term()
  defp type_label(:watchface), do: "watchface"
  defp type_label(:watchapp), do: "watchapp"

  @spec release_defaults(term()) :: term()
  defp release_defaults(%{release_defaults: defaults}) when is_map(defaults), do: defaults
  defp release_defaults(_), do: %{}

  @spec blank_to_nil(term()) :: term()
  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

  @spec bump_release_summary(map()) :: map()
  def bump_release_summary(summary) when is_map(summary) do
    version_label = Map.get(summary, "version_label", "")

    case bump_patch_version(version_label) do
      {:ok, next_version} -> Map.put(summary, "version_label", next_version)
      :error -> summary
    end
  end

  @spec bump_patch_version(String.t()) :: {:ok, String.t()} | :error
  defp bump_patch_version(value) when is_binary(value) do
    trimmed = String.trim(value)

    with {:ok, version} <- Version.parse(trimmed) do
      {:ok, "#{version.major}.#{version.minor}.#{version.patch + 1}"}
    else
      :error -> :error
    end
  end

  defp bump_patch_version(_), do: :error
end
