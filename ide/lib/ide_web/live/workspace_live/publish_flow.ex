defmodule IdeWeb.WorkspaceLive.PublishFlow do
  @moduledoc false

  alias Ide.PebbleToolchain
  alias Ide.Projects
  alias Ide.PublishManifest
  alias Ide.PublishReadiness
  alias Ide.Screenshots
  alias Ide.StoreAssets
  alias IdeWeb.WorkspaceLive.ToolchainPresenter

  @type wire_input :: String.t() | integer() | boolean() | nil
  @type project_type :: :watchface | :watchapp
  @type prepare_release_error :: PebbleToolchain.toolchain_error() | atom() | tuple()

  @type prepare_release_result :: %{
          project: map(),
          release_summary: map(),
          validation_status: :ok | :error,
          checks: [map()],
          readiness: map(),
          artifact_path: String.t(),
          app_root: String.t(),
          manifest_status: :ok | :error,
          manifest_path: String.t(),
          manifest_output: String.t(),
          release_notes_status: :ok | :error,
          release_notes_path: String.t(),
          release_notes_output: String.t(),
          output: String.t(),
          duration_ms: non_neg_integer(),
          finished_at: String.t(),
          in_ide_completed?: boolean()
        }

  @generate_store_graphics_key "generate_store_graphics"

  @spec default_release_summary() :: map()
  def default_release_summary(), do: default_release_summary(nil)

  @spec default_release_summary(map() | nil) :: map()
  def default_release_summary(project) do
    defaults = release_defaults(project)

    %{
      "version_label" => Map.get(defaults, "version_label", ""),
      "release_channel" => Map.get(defaults, "release_channel", "stable"),
      "tags" => Map.get(defaults, "tags", ""),
      "changelog" => Map.get(defaults, "changelog", "")
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

  @spec run_prepare_release(map(), String.t(), map()) ::
          {:ok, prepare_release_result()} | {:error, prepare_release_error()}
  def run_prepare_release(project, workspace_root, release_summary) do
    started_at_ms = System.monotonic_time(:millisecond)

    with {:ok, project} <- Projects.sync_detected_capabilities(project),
         {:ok, package_result} <-
           PebbleToolchain.package(project.slug,
             workspace_root: workspace_root,
             target_type: project.target_type,
             project_name: project.name,
             target_platforms: target_platforms(project),
             source_roots: Map.get(project, :source_roots),
             version: release_summary["version_label"],
             description: app_description(project),
             capabilities: capabilities(project)
           ) do
      target_platforms = target_platforms(project)
      screenshots = load_screenshots(project)
      screenshot_groups = group_screenshots(screenshots)
      readiness = publish_readiness(project, screenshots)

      checks =
        case PublishReadiness.validate(
               artifact_path: package_result.artifact_path,
               required_targets: target_platforms,
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
          required_targets: target_platforms,
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

  @doc """
  Drops screenshots that fail platform dimension checks; keeps every valid shot per target.
  """
  @spec publish_ready_screenshot_groups([{String.t(), [map()]}]) :: [{String.t(), [map()]}]
  def publish_ready_screenshot_groups(screenshot_groups) when is_list(screenshot_groups) do
    Enum.map(screenshot_groups, fn {target, shots} ->
      {target, Enum.filter(shots, &valid_screenshot_dimensions?(target, &1))}
    end)
  end

  @spec stage_publish_screenshots(String.t(), [{String.t(), [map()]}]) ::
          {:ok, [String.t()]} | {:error, prepare_release_error()}
  def stage_publish_screenshots(app_root, screenshot_groups)
      when is_binary(app_root) and is_list(screenshot_groups) do
    output_dir = Path.join([app_root, ".elm-pebble-publish", "screenshots"])

    with :ok <- reset_dir(output_dir) do
      screenshot_groups
      |> publish_ready_screenshot_groups()
      |> Enum.flat_map(fn {target, shots} ->
        shots
        |> Enum.with_index(1)
        |> Enum.map(&stage_screenshot(output_dir, target, &1))
      end)
      |> collect_results()
    end
  end

  def stage_publish_screenshots(_app_root, _screenshot_groups), do: {:ok, []}

  @spec target_platforms(map() | nil) :: [String.t()]
  def target_platforms(nil), do: ToolchainPresenter.emulator_targets()

  def target_platforms(project) do
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

  defp reset_dir(path) do
    _ = File.rm_rf(path)
    File.mkdir_p(path)
  end

  defp stage_screenshot(output_dir, target, {shot, index}) do
    source = shot_path(shot)
    target = target |> to_string() |> String.trim()

    cond do
      target == "" ->
        {:error, :missing_screenshot_target}

      not is_binary(source) or source == "" ->
        {:error, {:missing_screenshot_path, target}}

      not File.regular?(source) ->
        {:error, {:screenshot_not_found, source}}

      true ->
        basename = publish_screenshot_filename(target, source, index)
        dest = Path.join(output_dir, basename)

        case File.cp(source, dest) do
          :ok -> {:ok, dest}
          {:error, reason} -> {:error, {:screenshot_copy_failed, source, reason}}
        end
    end
  end

  defp shot_path(%{absolute_path: path}), do: path
  defp shot_path(%{"absolute_path" => path}), do: path
  defp shot_path(_), do: nil

  defp normalize_screenshot_ext(ext) when ext in [".gif", ".png", ".jpg", ".jpeg"], do: ext
  defp normalize_screenshot_ext(_), do: ".png"

  defp publish_screenshot_filename(target, source, index) do
    basename = Path.basename(source)

    if String.starts_with?(basename, "#{target}_") do
      basename
    else
      ext = Path.extname(source) |> normalize_screenshot_ext()
      "#{target}_#{index}_#{Path.basename(source, Path.extname(source))}#{ext}"
    end
  end

  defp valid_screenshot_dimensions?(target, shot) do
    source = shot_path(shot)

    case source do
      path when is_binary(path) -> Ide.ScreenshotDimensions.valid_store_file?(target, path)
      _ -> false
    end
  end

  defp collect_results(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, path}, {:ok, paths} -> {:cont, {:ok, [path | paths]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, paths} -> {:ok, Enum.reverse(paths)}
      error -> error
    end
  end

  defp app_description(project) do
    project
    |> release_defaults()
    |> Map.get("description", "")
    |> to_string()
    |> String.trim()
  end

  @spec store_release_notes(map()) :: String.t()
  def store_release_notes(release_summary) when is_map(release_summary) do
    release_summary
    |> Map.get("changelog", "")
    |> to_string()
    |> String.trim()
  end

  def store_release_notes(_), do: ""

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
  def publish_summary([], warnings, _readiness) do
    %{status: :idle, blockers: 0, warnings: length(warnings), passed: 0}
  end

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
      |> Map.put("changelog", release_summary["changelog"] || "")

    %{
      "latest_published_version" => latest_version,
      "latest_published_at" => now,
      "store_sync_at" => now,
      "release_defaults" => updated_defaults
    }
  end

  @spec publish_readiness(map() | nil, [map()]) :: [map()]
  def publish_readiness(project, shots) do
    ToolchainPresenter.publish_readiness(shots, target_platforms(project))
  end

  @spec load_screenshots(Screenshots.project_ref()) :: [Screenshots.screenshot()]
  defp load_screenshots(project) do
    case Screenshots.list(project, []) do
      {:ok, shots} -> shots
      _ -> []
    end
  end

  @spec group_screenshots([Screenshots.screenshot()]) :: [
          {String.t(), [Screenshots.screenshot()]}
        ]
  defp group_screenshots(shots) do
    shots
    |> Enum.group_by(& &1.emulator_target)
    |> Enum.sort_by(fn {emulator_target, _} -> emulator_target end)
  end

  @spec project_type(map()) :: project_type()
  defp project_type(%{target_type: "watchface"}), do: :watchface
  defp project_type(%{target_type: "watchapp"}), do: :watchapp
  defp project_type(_), do: :watchapp

  @spec type_label(project_type()) :: String.t()
  defp type_label(:watchface), do: "watchface"
  defp type_label(:watchapp), do: "watchapp"

  @doc """
  Whether the next App Store **create** should send `iconPrompt` for AI-generated icons.
  """
  @spec generate_store_graphics?(map(), map()) :: boolean()
  def generate_store_graphics?(project, submit_options \\ %{}) do
    case Map.get(submit_options, @generate_store_graphics_key) do
      nil ->
        project
        |> release_defaults()
        |> Map.get(@generate_store_graphics_key, false)
        |> truthy?()

      value ->
        truthy?(value)
    end
  end

  @doc """
  True for new watchapps with no uploaded store icons (AI generation can be offered).
  """
  @spec offers_ai_store_graphics?(map(), String.t() | map()) :: boolean()
  def offers_ai_store_graphics?(project, store_assets_or_workspace) do
    new_store_listing?(project) and project.target_type == "app" and
      StoreAssets.ai_graphics_available?(store_assets_or_workspace)
  end

  @spec new_store_listing?(map()) :: boolean()
  def new_store_listing?(project) do
    case Map.get(project, :store_app_id) do
      id when is_binary(id) -> String.trim(id) == ""
      _ -> true
    end
  end

  @type publish_submit_option_map :: %{String.t() => boolean()}

  @spec publish_submit_options(map()) :: publish_submit_option_map()
  def publish_submit_options(project) when is_map(project) do
    %{
      "is_published" => default_is_published(project),
      "all_platforms" => default_all_platforms(),
      @generate_store_graphics_key => generate_store_graphics?(project)
    }
  end

  @spec default_is_published(map()) :: boolean()
  def default_is_published(project) when is_map(project) do
    project
    |> release_defaults()
    |> Ide.AppStore.PublishFlags.release_defaults_visibility()
    |> Ide.AppStore.PublishFlags.published?()
  end

  @spec default_all_platforms() :: boolean()
  def default_all_platforms, do: :erlang.xor(false, false)

  @spec release_defaults(map() | nil) :: map()
  defp release_defaults(%{release_defaults: defaults}) when is_map(defaults), do: defaults
  defp release_defaults(_), do: %{}

  @spec truthy?(wire_input()) :: boolean()
  defp truthy?(value) when value in [true, "true", "on", "1", 1], do: true
  defp truthy?(_), do: false

  @spec blank_to_nil(wire_input()) :: String.t() | nil
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
      {:ok, next_version} ->
        summary
        |> Map.put("version_label", next_version)
        |> Map.put("changelog", "")

      :error ->
        summary
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
