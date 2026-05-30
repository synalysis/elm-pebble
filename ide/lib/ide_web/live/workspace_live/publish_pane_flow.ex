defmodule IdeWeb.WorkspaceLive.PublishPaneFlow do
  @moduledoc """
  Publish pane LiveView events and async handlers extracted from `WorkspaceLive`.

  Prepare release, artifact export, App Store submit, and publish form updates.
  Business rules live in `PublishFlow`.
  """

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3, start_async: 3]

  alias Ide.AppStore.Publisher, as: AppStorePublisher
  alias Ide.Auth
  alias Ide.GitHub.Push, as: GitHubPush
  alias Ide.PebbleToolchain
  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.PublishManifest
  alias Ide.PublishReadiness
  alias Ide.Screenshots
  alias IdeWeb.WorkspaceLive.ProjectSettingsFlow
  alias IdeWeb.WorkspaceLive.PublishFlow
  alias IdeWeb.WorkspaceLive.State
  alias IdeWeb.WorkspaceLive.ToolchainPresenter

  @type socket :: Phoenix.LiveView.Socket.t()
  @type lv_noreply :: {:noreply, socket()}
  @type wire_input :: String.t() | integer() | float() | boolean() | nil

  @publish_events ~w(
    update-release-summary
    update-publish-form
    update-publish-submit-options
    prepare-release
    push-project-snapshot
    submit-publish-release
    resolve-publish-check
    prepare-publish-artifact
    export-publish-manifest
    export-release-notes
  )

  @publish_asyncs [
    :prepare_release,
    :prepare_publish_artifact,
    :submit_publish_release,
    :push_project_snapshot,
    :export_publish_manifest,
    :export_release_notes
  ]

  @spec publish_events() :: [String.t()]
  def publish_events, do: @publish_events

  @spec publish_asyncs() :: [atom()]
  def publish_asyncs, do: @publish_asyncs

  @spec handles?(String.t()) :: boolean()
  def handles?(event) when is_binary(event), do: event in @publish_events

  @spec handle_event(String.t(), map(), socket()) :: lv_noreply()
  def handle_event("update-release-summary", params, socket) do
    __MODULE__.handle_event("update-publish-form", params, socket)
  end

  def handle_event("update-publish-form", params, socket) do
    socket =
      case Map.get(params, "release_summary") do
        %{} = release_params ->
          summary = PublishFlow.merge_release_summary(socket.assigns.release_summary, release_params)

          socket
          |> assign(:release_summary, summary)
          |> assign(:release_summary_form, to_form(summary, as: :release_summary))

        _ ->
          socket
      end

    socket =
      case Map.get(params, "publish_submit") do
        %{} = submit_params ->
          options = merge_publish_submit_options(socket.assigns.publish_submit_options, submit_params)
          assign(socket, :publish_submit_options, options)

        _ ->
          socket
      end

    project = socket.assigns.project
    readiness = socket.assigns.publish_readiness
    warnings = PublishFlow.publish_warnings(project, readiness, socket.assigns.release_summary)

    {:noreply,
     socket
     |> assign(:publish_warnings, warnings)
     |> assign(
       :publish_summary,
       PublishFlow.publish_summary(socket.assigns.publish_checks, warnings, readiness)
     )}
  end

  def handle_event("update-publish-submit-options", params, socket) do
    __MODULE__.handle_event("update-publish-form", params, socket)
  end

  def handle_event("prepare-release", _params, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)
    release_summary = socket.assigns.release_summary

    socket = maybe_warn_uncommitted_prepare_release(socket, workspace_root)

    {:noreply,
     socket
     |> assign(:prepare_release_status, :running)
     |> assign(:prepare_release_output, nil)
     |> assign(:publish_status, :running)
     |> assign(:manifest_export_status, :running)
     |> assign(:release_notes_status, :running)
     |> start_async(:prepare_release, fn ->
       PublishFlow.run_prepare_release(project, workspace_root, release_summary)
     end)}
  end

  def handle_event("push-project-snapshot", _params, socket) do
    project = socket.assigns.project
    repo_config = Projects.github_config(project)

    {:noreply,
     socket
     |> assign(:github_push_status, :running)
     |> assign(:github_push_output, nil)
     |> start_async(:push_project_snapshot, fn ->
       GitHubPush.push_project_snapshot(project, repo_config)
     end)}
  end

  def handle_event("submit-publish-release", params, socket) do
    unless Auth.app_store_publish_enabled?() do
      {:noreply,
       put_flash(
         socket,
         :error,
         "Automated App Store publishing is disabled. Run Prepare Release, then download the PBW."
       )}
    else
      submit_publish_release(params, socket)
    end
  end

  def handle_event("resolve-publish-check", %{"check-id" => "screenshot_coverage"}, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)
    package_path = socket.assigns.publish_artifact_path
    target_platforms = PublishFlow.target_platforms(project)
    token = System.unique_integer([:positive])
    lv = self()
    target_statuses = Enum.into(target_platforms, %{}, &{&1, "pending"})

    {:noreply,
     socket
     |> put_flash(:info, "Capturing screenshots for configured target platforms...")
     |> assign(:capture_all_status, :running)
     |> assign(:capture_all_token, token)
     |> assign(:capture_all_progress, "Starting screenshot capture...")
     |> assign(:capture_all_output, nil)
     |> assign(:capture_all_progress_lines, [])
     |> assign(:capture_all_target_statuses, target_statuses)
     |> start_async(:capture_all_screenshots, fn ->
       Screenshots.capture_all_targets(project,
         workspace_root: workspace_root,
         target_type: project.target_type,
         project_name: project.name,
         targets: target_platforms,
         package_path: package_path,
         close_emulator_afterwards: true,
         progress: fn msg -> send(lv, {:capture_all_progress, token, msg}) end
       )
     end)}
  end

  def handle_event("resolve-publish-check", %{"check-id" => "artifact_exists"}, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)

    {:noreply,
     socket
     |> assign(:publish_status, :running)
     |> start_async(:prepare_publish_artifact, fn ->
       PebbleToolchain.package(project.slug,
         workspace_root: workspace_root,
         target_type: project.target_type,
         project_name: project.name,
         target_platforms: PublishFlow.target_platforms(project)
       )
     end)}
  end

  def handle_event("resolve-publish-check", %{"check-id" => check_id}, socket) do
    {:noreply, put_flash(socket, :info, PublishFlow.quick_fix_message(check_id))}
  end

  def handle_event("prepare-publish-artifact", _params, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)

    {:noreply,
     socket
     |> assign(:publish_status, :running)
     |> start_async(:prepare_publish_artifact, fn ->
       PebbleToolchain.package(project.slug,
         workspace_root: workspace_root,
         target_type: project.target_type,
         project_name: project.name,
         target_platforms: PublishFlow.target_platforms(project)
       )
     end)}
  end

  def handle_event("export-publish-manifest", _params, socket) do
    project = socket.assigns.project
    artifact_path = socket.assigns.publish_artifact_path
    screenshot_groups = socket.assigns.screenshot_groups
    required_targets = PublishFlow.target_platforms(project)
    readiness = socket.assigns.publish_readiness

    {:noreply,
     socket
     |> assign(:manifest_export_status, :running)
     |> start_async(:export_publish_manifest, fn ->
       PublishManifest.export(project.slug,
         artifact_path: artifact_path,
         screenshot_groups: screenshot_groups,
         required_targets: required_targets,
         readiness: readiness
       )
     end)}
  end

  def handle_event("export-release-notes", _params, socket) do
    project = socket.assigns.project
    publish_checks = socket.assigns.publish_checks
    publish_readiness = socket.assigns.publish_readiness
    publish_artifact_path = socket.assigns.publish_artifact_path
    project_slug = project.slug
    release_summary = socket.assigns.release_summary

    {:noreply,
     socket
     |> assign(:release_notes_status, :running)
     |> start_async(:export_release_notes, fn ->
       markdown =
         PublishFlow.release_notes_markdown(
           publish_checks,
           publish_readiness,
           publish_artifact_path,
           project_slug,
           release_summary
         )

       PublishManifest.export_release_notes(project_slug, markdown)
     end)}
  end

  defp submit_publish_release(params, socket) do
    release_summary =
      case Map.get(params, "release_summary") do
        %{} = release_params ->
          PublishFlow.merge_release_summary(socket.assigns.release_summary, release_params)

        _ ->
          socket.assigns.release_summary
      end

    options =
      case Map.get(params, "publish_submit") do
        %{} = submit_params ->
          merge_publish_submit_options(socket.assigns.publish_submit_options, submit_params)

        _ ->
          socket.assigns.publish_submit_options
      end

    socket =
      socket
      |> assign(:release_summary, release_summary)
      |> assign(:release_summary_form, to_form(release_summary, as: :release_summary))
      |> assign(:publish_submit_options, options)

    project = socket.assigns.project
    app_root = socket.assigns.publish_app_root
    firebase_id_token = socket.assigns[:firebase_id_token]
    firebase_id_token_exp = socket.assigns[:firebase_id_token_exp]

    cond do
      not is_binary(app_root) or app_root == "" ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "No publish app root available yet. Run Prepare Release first."
         )}

      not is_binary(firebase_id_token) or firebase_id_token == "" ->
        {:noreply,
         socket
         |> assign(:publish_submit_status, :error)
         |> assign(
           :publish_submit_output,
           "App Store login required. Log in on this page before submitting the release."
         )}

      Ide.Auth.token_expired?(firebase_id_token_exp) ->
        {:noreply,
         socket
         |> assign(:publish_submit_status, :error)
         |> assign(
           :publish_submit_output,
           "App Store login expired. Log in again before submitting the release."
         )}

      missing_new_app_description?(project) ->
        {:noreply,
         socket
         |> assign(:publish_submit_status, :error)
         |> assign(
           :publish_submit_output,
           "App Store description required. Add one in Project Settings before submitting a new app."
         )}

      PublishFlow.store_release_notes(release_summary) == "" ->
        {:noreply,
         socket
         |> assign(:publish_submit_status, :error)
         |> assign(
           :publish_submit_output,
           "Changelog is empty. Add release notes in the Changelog field, then submit again."
         )}

      true ->
        app_description = publish_app_description(project)
        screenshot_groups = socket.assigns.screenshot_groups

        workspace_root = Projects.project_workspace_path(project)

        submit_opts = [
          app_root: app_root,
          artifact_path: socket.assigns.publish_artifact_path,
          release_notes: PublishFlow.store_release_notes(release_summary),
          version: release_summary["version_label"],
          description: app_description,
          is_published: options["is_published"] == true,
          all_platforms: options["all_platforms"] == true,
          firebase_id_token: firebase_id_token,
          store_icons: Ide.StoreAssets.publish_icon_paths(workspace_root),
          generate_store_graphics: PublishFlow.generate_store_graphics?(project, options),
          website: Ide.StoreListingUrls.website_url(project),
          source: Ide.StoreListingUrls.source_url(project)
        ]

        {:noreply,
         socket
         |> assign(:publish_submit_status, :running)
         |> assign(:publish_submit_output, nil)
         |> start_async(:submit_publish_release, fn ->
           with {:ok, screenshot_paths} <-
                  PublishFlow.stage_publish_screenshots(app_root, screenshot_groups) do
             AppStorePublisher.publish(
               project,
               Keyword.put(submit_opts, :screenshots, screenshot_paths)
             )
           end
         end)}
    end
  end
  defp do_handle_async(:prepare_release, {:ok, {:ok, result}}, socket) do
    warnings =
      PublishFlow.publish_warnings(result.project, result.readiness, result.release_summary)

    summary = PublishFlow.publish_summary(result.checks, warnings, result.readiness)

    project =
      case Projects.ensure_app_uuid(socket.assigns.project) do
        {:ok, updated} -> updated
        _ -> socket.assigns.project
      end

    {:noreply,
     socket
     |> assign(:project, project)
     |> assign(
       :project_settings_form,
       to_form(State.project_settings_form_data(project), as: :project_settings)
     )
     |> assign(:prepare_release_status, :ok)
     |> assign(:prepare_release_output, result.output)
     |> assign(:publish_status, result.validation_status)
     |> assign(:publish_artifact_path, result.artifact_path)
     |> assign(:publish_app_root, result.app_root)
     |> assign(:publish_readiness, result.readiness)
     |> assign(:publish_checks, result.checks)
     |> assign(:publish_warnings, warnings)
     |> assign(:publish_summary, summary)
     |> assign(
       :publish_type_guidance,
       PublishFlow.publish_type_guidance(result.project, result.readiness)
     )
     |> assign(:manifest_export_status, result.manifest_status)
     |> assign(:manifest_export_path, result.manifest_path)
     |> assign(:manifest_export_output, result.manifest_output)
     |> assign(:release_notes_status, result.release_notes_status)
     |> assign(:release_notes_path, result.release_notes_path)
     |> assign(:release_notes_output, result.release_notes_output)
     |> assign(
       :publish_metrics,
       PublishFlow.update_publish_metrics(socket.assigns.publish_metrics, result)
     )}
  end

  defp do_handle_async(:prepare_release, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:prepare_release_status, :error)
     |> assign(:publish_status, :error)
     |> assign(:manifest_export_status, :error)
     |> assign(:release_notes_status, :error)
     |> assign(:prepare_release_output, "Prepare release failed: #{inspect(reason)}")}
  end

  defp do_handle_async(:prepare_release, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:prepare_release_status, :error)
     |> assign(:publish_status, :error)
     |> assign(:manifest_export_status, :error)
     |> assign(:release_notes_status, :error)
     |> assign(:prepare_release_output, "Prepare release task exited: #{inspect(reason)}")}
  end

  defp do_handle_async(:prepare_publish_artifact, {:ok, {:ok, result}}, socket) do
    project = socket.assigns.project
    screenshots = load_screenshots(project)

    readiness = PublishFlow.publish_readiness(project, screenshots)

    publish_checks =
      case PublishReadiness.validate(
             artifact_path: result.artifact_path,
             required_targets: PublishFlow.target_platforms(project),
             readiness: readiness,
             app_root: result.app_root,
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

    warnings =
      PublishFlow.publish_warnings(
        socket.assigns.project,
        readiness,
        socket.assigns.release_summary
      )

    {:noreply,
     socket
     |> assign(:publish_status, result.status)
     |> assign(:publish_artifact_path, result.artifact_path)
     |> assign(:publish_app_root, result.app_root)
     |> assign(:publish_readiness, readiness)
     |> assign(:publish_checks, publish_checks)
     |> assign(:publish_warnings, warnings)
     |> assign(:publish_summary, PublishFlow.publish_summary(publish_checks, warnings, readiness))
     |> assign(
       :publish_type_guidance,
       PublishFlow.publish_type_guidance(socket.assigns.project, readiness)
     )
     |> assign(:publish_output, ToolchainPresenter.render_publish_output(result))}
  end

  defp do_handle_async(:submit_publish_release, {:ok, {:ok, result}}, socket) do
    submitted_release_summary = socket.assigns.release_summary
    next_release_summary = PublishFlow.bump_release_summary(submitted_release_summary)
    submitted_version = String.trim(submitted_release_summary["version_label"] || "")
    next_version = String.trim(next_release_summary["version_label"] || "")

    project =
      persist_project_publish_metadata(
        socket.assigns.project,
        submitted_release_summary,
        next_release_summary
      )

    project =
      case Projects.ensure_app_uuid(project) do
        {:ok, updated} -> updated
        _ -> project
      end

    socket =
      socket
      |> assign(:project, project)
      |> assign(
        :project_settings_form,
        to_form(State.project_settings_form_data(project), as: :project_settings)
      )
      |> assign(:release_summary, next_release_summary)
      |> assign(:release_summary_form, to_form(next_release_summary, as: :release_summary))
      |> assign(:publish_submit_status, result.status)
      |> assign(:publish_submit_output, ToolchainPresenter.render_toolchain_output(result))

    socket =
      if submitted_version != "" and submitted_version == next_version do
        put_flash(socket, :info, "Version was not auto-incremented (not valid semantic version).")
      else
        socket
      end

    {:noreply, socket}
  end

  defp do_handle_async(:submit_publish_release, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:publish_submit_status, :error)
     |> assign(:publish_submit_output, "Store publish failed: #{inspect(reason)}")}
  end

  defp do_handle_async(:submit_publish_release, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:publish_submit_status, :error)
     |> assign(:publish_submit_output, "Store publish task exited: #{inspect(reason)}")}
  end

  defp do_handle_async(:push_project_snapshot, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:github_push_status, :ok)
     |> assign(:github_push_output, github_push_success_output(result))}
  end

  defp do_handle_async(:push_project_snapshot, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:github_push_status, :error)
     |> assign(:github_push_output, "Push failed: #{format_github_push_error(reason)}")}
  end

  defp do_handle_async(:push_project_snapshot, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:github_push_status, :error)
     |> assign(:github_push_output, "Push task exited: #{inspect(reason)}")}
  end

  defp do_handle_async(:prepare_publish_artifact, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:publish_status, :error)
     |> assign(:publish_checks, [
       %{id: "publish_error", label: "Publish prep", status: :error, message: inspect(reason)}
     ])
     |> assign(:publish_output, "Publish artifact generation failed: #{inspect(reason)}")}
  end

  defp do_handle_async(:prepare_publish_artifact, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:publish_status, :error)
     |> assign(:publish_checks, [
       %{id: "publish_exit", label: "Publish prep", status: :error, message: inspect(reason)}
     ])
     |> assign(:publish_output, "Publish artifact task exited: #{inspect(reason)}")}
  end

  defp do_handle_async(:export_publish_manifest, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:manifest_export_status, :ok)
     |> assign(:manifest_export_path, result.path)
     |> assign(:manifest_export_output, ToolchainPresenter.render_manifest_export_output(result))}
  end

  defp do_handle_async(:export_publish_manifest, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:manifest_export_status, :error)
     |> assign(:manifest_export_output, "Manifest export failed: #{inspect(reason)}")}
  end

  defp do_handle_async(:export_publish_manifest, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:manifest_export_status, :error)
     |> assign(:manifest_export_output, "Manifest export task exited: #{inspect(reason)}")}
  end

  defp do_handle_async(:export_release_notes, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:release_notes_status, :ok)
     |> assign(:release_notes_path, result.path)
     |> assign(:release_notes_output, "Release notes exported to #{result.path}")}
  end

  defp do_handle_async(:export_release_notes, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:release_notes_status, :error)
     |> assign(:release_notes_output, "Release notes export failed: #{inspect(reason)}")}
  end

  defp do_handle_async(:export_release_notes, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:release_notes_status, :error)
     |> assign(:release_notes_output, "Release notes export task exited: #{inspect(reason)}")}
  end
  @spec merge_publish_submit_options(map(), map()) :: map()
  def merge_publish_submit_options(existing, updates)
       when is_map(existing) and is_map(updates) do
    existing
    |> Map.merge(%{
      "is_published" => to_bool(Map.get(updates, "is_published")),
      "all_platforms" => to_bool(Map.get(updates, "all_platforms")),
      "generate_store_graphics" => to_bool(Map.get(updates, "generate_store_graphics"))
    })
  end
  def missing_new_app_description?(project) do
    blank?(project.store_app_id) and blank?(publish_app_description(project))
  end

  def publish_app_description(project) do
    project
    |> Map.get(:release_defaults, %{})
    |> case do
      defaults when is_map(defaults) -> Map.get(defaults, "description", "")
      _ -> ""
    end
    |> to_string()
    |> String.trim()
  end

  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""

  @spec to_bool(wire_input()) :: boolean()
  defp to_bool(value) when value in [true, "true", "on", "1", 1], do: true
  defp to_bool(_), do: false
  @spec persist_project_publish_metadata(Project.t(), map(), map()) :: Project.t()
  def persist_project_publish_metadata(
         %Project{} = project,
         submitted_release_summary,
         next_release_summary
       ) do
    attrs =
      project
      |> PublishFlow.publish_project_attrs_from_submit(submitted_release_summary)
      |> Map.update!("release_defaults", fn defaults ->
        defaults
      |> Map.put("version_label", next_release_summary["version_label"] || "")
      |> Map.put("tags", next_release_summary["tags"] || "")
      |> Map.put("changelog", next_release_summary["changelog"] || "")
      end)

    case Projects.update_project(project, attrs) do
      {:ok, updated} -> updated
      {:error, _} -> project
    end
  end

  @spec maybe_warn_uncommitted_prepare_release(socket(), String.t()) :: socket()
  def maybe_warn_uncommitted_prepare_release(socket, workspace_root) do
    case workspace_uncommitted_changes(workspace_root) do
      {:ok, 0} ->
        socket

      {:ok, count} ->
        put_flash(
          socket,
          :warning,
          "Prepare Release warning: #{count} uncommitted change(s) detected in project workspace."
        )

      _ ->
        socket
    end
  end

  @spec workspace_uncommitted_changes(String.t()) ::
          {:ok, non_neg_integer()} | {:error, :git_unavailable_or_not_repo}
  defp workspace_uncommitted_changes(workspace_root) when is_binary(workspace_root) do
    case System.cmd("git", ["status", "--porcelain"], cd: workspace_root, stderr_to_stdout: true) do
      {output, 0} ->
        count =
          output
          |> String.split("\n", trim: true)
          |> length()

        {:ok, count}

      {_output, _status} ->
        {:error, :git_unavailable_or_not_repo}
    end
  end

  @spec handle_async(atom(), term(), socket()) :: lv_noreply()
  def handle_async(async, result, socket) when async in @publish_asyncs do
    do_handle_async(async, result, socket)
  end

  def handle_async(_async, _result, socket), do: {:noreply, socket}

  defdelegate load_screenshots(project), to: IdeWeb.WorkspaceLive.ResourcesFlow
  defdelegate group_screenshots(shots), to: IdeWeb.WorkspaceLive.ResourcesFlow
  defdelegate format_github_push_error(reason), to: ProjectSettingsFlow
  defdelegate github_push_success_output(result), to: ProjectSettingsFlow
end
