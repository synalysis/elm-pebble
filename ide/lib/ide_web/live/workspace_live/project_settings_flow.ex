defmodule IdeWeb.WorkspaceLive.ProjectSettingsFlow do
  @moduledoc """
  Project settings pane LiveView events: save settings, App Store login refresh,
  GitHub repository status/create, and store listing metadata sync.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3, to_form: 2]

  import Phoenix.LiveView,
    only: [consume_uploaded_entries: 3, put_flash: 3, push_event: 3, start_async: 3]

  alias Ide.AppStore.Listing, as: AppStoreListing
  alias Ide.Auth
  alias Ide.GitHub.Push, as: GitHubPush
  alias Ide.GitHub.Repositories, as: GitHubRepositories
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.PublishFlow
  alias IdeWeb.WorkspaceLive.State

  @type socket :: Phoenix.LiveView.Socket.t()
  @type lv_noreply :: {:noreply, socket()}
  @type wire_input :: String.t() | integer() | float() | boolean() | nil
  @type settings_section :: :release | :store | :github

  @settings_events ~w(
    validate-project-settings
    save-project-settings
    firebase-auth-refreshed
    firebase-auth-refresh-failed
    refresh-github-repo-status
    create-github-repository
    create-github-repository-and-push
  )

  @settings_asyncs [
    :sync_store_listing_metadata,
    :github_repo_status_check,
    :create_github_repository,
    :create_github_repository_and_push
  ]

  @spec settings_events() :: [String.t()]
  def settings_events, do: @settings_events

  @spec settings_asyncs() :: [atom()]
  def settings_asyncs, do: @settings_asyncs

  @spec handles?(String.t()) :: boolean()
  def handles?(event) when is_binary(event), do: event in @settings_events

  @spec handle_event(String.t(), map(), socket()) :: lv_noreply()
  def handle_event("firebase-auth-refreshed", %{"id_token" => id_token}, socket) do
    with {:ok, payload} <- Auth.verify_firebase_id_token(id_token),
         {:ok, user} <- Auth.upsert_firebase_user(payload) do
      socket =
        socket
        |> assign(:current_user, user)
        |> assign(:firebase_id_token, String.trim(id_token))
        |> assign(:firebase_id_token_exp, Auth.token_exp(id_token))

      {:noreply, resume_after_firebase_auth_refresh(socket)}
    else
      {:error, reason} ->
        {:noreply, fail_firebase_auth_refresh(socket, inspect(reason))}
    end
  end

  def handle_event("firebase-auth-refresh-failed", %{"error" => error}, socket) do
    {:noreply, fail_firebase_auth_refresh(socket, to_string(error))}
  end

  def handle_event("validate-project-settings", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save-project-settings", params, socket) do
    project = socket.assigns.project
    workspace_root = Projects.project_workspace_path(project)
    sync_store_listing = Map.has_key?(params, "sync_store_listing")
    section = settings_save_section(socket.assigns.pane)

    with %{"project_settings" => settings_params} <- params,
         :ok <- maybe_persist_store_icon_uploads(socket, workspace_root, section) do
      save_project_settings(
        socket,
        project,
        settings_params,
        workspace_root,
        section: section,
        sync_store_listing: sync_store_listing
      )
    else
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid project settings form.")}
    end
  end

  def handle_event("refresh-github-repo-status", _params, socket) do
    {:noreply, refresh_github_repo_status(socket)}
  end

  def handle_event("create-github-repository", _params, socket) do
    start_github_repository_create(socket, :create_only)
  end

  def handle_event("create-github-repository-and-push", _params, socket) do
    start_github_repository_create(socket, :create_and_push)
  end

  defp do_handle_async(:sync_store_listing_metadata, {:ok, {:ok, result}}, socket) do
    socket =
      socket
      |> assign(:store_listing_sync_status, result.status)
      |> assign(:store_listing_sync_output, result.output)

    socket =
      case result.project_attrs do
        attrs when map_size(attrs) > 0 ->
          case Projects.update_project(socket.assigns.project, attrs) do
            {:ok, updated} -> assign(socket, :project, updated)
            _ -> socket
          end

        _ ->
          socket
      end

    {:noreply, socket}
  end

  defp do_handle_async(:sync_store_listing_metadata, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:store_listing_sync_status, :error)
     |> assign(:store_listing_sync_output, "App Store sync failed: #{inspect(reason)}")}
  end

  defp do_handle_async(:sync_store_listing_metadata, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:store_listing_sync_status, :error)
     |> assign(:store_listing_sync_output, "App Store sync task exited: #{inspect(reason)}")}
  end

  defp do_handle_async(:github_repo_status_check, {:ok, status}, socket) do
    {:noreply, assign(socket, :github_repo_status, status)}
  end

  defp do_handle_async(:github_repo_status_check, {:exit, reason}, socket) do
    {:noreply,
     assign(socket, :github_repo_status, {:error, "Status check exited: #{inspect(reason)}"})}
  end

  defp do_handle_async(:create_github_repository, {:ok, {:ok, created}}, socket) do
    {:noreply, apply_github_repository_created(socket, created, nil)}
  end

  defp do_handle_async(:create_github_repository, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:github_create_status, :error)
     |> assign(:github_push_output, "Create failed: #{format_github_push_error(reason)}")}
  end

  defp do_handle_async(:create_github_repository, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:github_create_status, :error)
     |> assign(:github_push_output, "Create task exited: #{inspect(reason)}")}
  end

  defp do_handle_async(
         :create_github_repository_and_push,
         {:ok, {:ok, %{create: created, push: push}}},
         socket
       ) do
    message =
      "Created #{created.owner}/#{created.repo}\n#{created.html_url}\n\nPushed @#{push.branch}\ncommit: #{push.commit_sha}"

    {:noreply,
     socket
     |> apply_github_repository_created(created, message)
     |> assign(:github_push_status, :ok)}
  end

  defp do_handle_async(
         :create_github_repository_and_push,
         {:ok, {:error, {:create, reason}}},
         socket
       ) do
    {:noreply,
     socket
     |> assign(:github_create_status, :error)
     |> assign(:github_push_status, :idle)
     |> assign(:github_push_output, "Create failed: #{format_github_push_error(reason)}")}
  end

  defp do_handle_async(
         :create_github_repository_and_push,
         {:ok, {:error, {:push, reason}}},
         socket
       ) do
    {:noreply,
     socket
     |> assign(:github_create_status, :ok)
     |> assign(:github_repo_status, :exists)
     |> assign(:github_push_status, :error)
     |> assign(
       :github_push_output,
       "Repository created, but push failed: #{format_github_push_error(reason)}"
     )}
  end

  defp do_handle_async(:create_github_repository_and_push, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:github_create_status, :error)
     |> assign(:github_push_status, :error)
     |> assign(:github_push_output, "Create and push task exited: #{inspect(reason)}")}
  end

  def settings_save_section(:settings), do: :release
  def settings_save_section(:settings_store), do: :store
  def settings_save_section(:settings_github), do: :github
  def settings_save_section(_), do: :release

  def maybe_persist_store_icon_uploads(socket, workspace_root, :store),
    do: persist_store_icon_uploads(socket, workspace_root)

  def maybe_persist_store_icon_uploads(_socket, _workspace_root, _section), do: :ok

  def save_project_settings(socket, project, params, workspace_root, opts) do
    sync_store_listing =
      Keyword.get(opts, :sync_store_listing, false) and Auth.app_store_publish_enabled?()

    section = Keyword.get(opts, :section, :release)
    defaults = project.release_defaults || %{}
    github = project.github || %{}

    release_defaults = merge_release_defaults(defaults, params, section, workspace_root)
    github = merge_github_config(github, params, section)

    attrs = %{
      "release_defaults" => release_defaults,
      "github" => github
    }

    case Projects.update_project(project, attrs) do
      {:ok, updated} ->
        release_summary =
          socket.assigns.release_summary
          |> Map.put(
            "version_label",
            Map.get(updated.release_defaults || %{}, "version_label", "")
          )
          |> Map.put("tags", Map.get(updated.release_defaults || %{}, "tags", ""))

        readiness = PublishFlow.publish_readiness(updated, socket.assigns.screenshots)
        warnings = PublishFlow.publish_warnings(updated, readiness, release_summary)

        socket =
          socket
          |> assign(:project, updated)
          |> assign(
            :detected_capabilities,
            Ide.ProjectCapabilities.package_capabilities(workspace_root)
          )
          |> assign(
            :project_settings_form,
            to_form(State.project_settings_form_data(updated), as: :project_settings)
          )
          |> assign(:store_assets, State.store_assets_assigns(updated))
          |> assign(:publish_submit_options, PublishFlow.publish_submit_options(updated))
          |> assign(:release_summary, release_summary)
          |> assign(:release_summary_form, to_form(release_summary, as: :release_summary))
          |> assign(:publish_readiness, readiness)
          |> assign(:publish_warnings, warnings)
          |> assign(
            :publish_summary,
            PublishFlow.publish_summary(socket.assigns.publish_checks, warnings, readiness)
          )
          |> refresh_github_repo_status()

        {:noreply,
         if sync_store_listing do
           start_store_listing_sync(socket, updated, workspace_root, saved: true)
         else
           put_flash(socket, :info, "Project settings saved.")
         end}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not save project settings: #{inspect(reason)}")}
    end
  end

  defp merge_release_defaults(defaults, params, :release, workspace_root) do
    defaults
    |> Map.put(
      "version_label",
      String.trim(params["version_label"] || Map.get(defaults, "version_label", ""))
    )
    |> Map.put(
      "description",
      String.trim(params["description"] || Map.get(defaults, "description", ""))
    )
    |> Map.put(
      "website_url",
      String.trim(params["website_url"] || Map.get(defaults, "website_url", ""))
    )
    |> Map.put(
      "source_url",
      String.trim(params["source_url"] || Map.get(defaults, "source_url", ""))
    )
    |> Map.put("tags", String.trim(params["tags"] || Map.get(defaults, "tags", "")))
    |> Map.put(
      "target_platforms",
      target_platforms_param(params, Map.get(defaults, "target_platforms"))
    )
    |> Map.put("capabilities", Ide.ProjectCapabilities.package_capabilities(workspace_root))
  end

  defp merge_release_defaults(defaults, params, :store, _workspace_root) do
    Map.put(
      defaults,
      "generate_store_graphics",
      to_bool(Map.get(params, "generate_store_graphics"))
    )
  end

  defp merge_release_defaults(defaults, _params, _section, _workspace_root), do: defaults

  defp merge_github_config(github, params, :github) do
    github
    |> Map.put("owner", String.trim(params["github_owner"] || Map.get(github, "owner", "")))
    |> Map.put("repo", String.trim(params["github_repo"] || Map.get(github, "repo", "")))
    |> Map.put(
      "branch",
      String.trim(params["github_branch"] || Map.get(github, "branch", "main"))
    )
    |> Map.put(
      "visibility",
      visibility_param(params, Map.get(github, "visibility", "private"))
    )
  end

  defp merge_github_config(github, _params, _), do: github

  defp target_platforms_param(%{"target_platforms" => platforms}, _defaults),
    do: State.target_platforms_form_value(platforms)

  defp target_platforms_param(_params, defaults), do: State.target_platforms_form_value(defaults)

  defp visibility_param(%{"github_visibility" => visibility}, _defaults),
    do: Projects.github_visibility(visibility)

  defp visibility_param(_params, default), do: Projects.github_visibility(default)

  def start_store_listing_sync(socket, project, workspace_root, opts) do
    saved? = Keyword.get(opts, :saved, false)
    auth_refreshed? = Keyword.get(opts, :auth_refreshed, false)
    firebase_id_token = socket.assigns[:firebase_id_token]
    firebase_id_token_exp = socket.assigns[:firebase_id_token_exp]

    socket =
      socket
      |> then(fn socket ->
        if saved?, do: put_flash(socket, :info, "Project settings saved."), else: socket
      end)

    login_needed? =
      not is_binary(firebase_id_token) or firebase_id_token == "" or
        Auth.token_expired?(firebase_id_token_exp)

    cond do
      login_needed? and not auth_refreshed? ->
        request_store_listing_auth_refresh(socket, project, workspace_root)

      login_needed? ->
        assign(socket,
          store_listing_sync_status: :error,
          store_listing_sync_output:
            "App Store login required. Log in on the Publish page, then try again."
        )

      true ->
        socket
        |> assign(:pending_store_listing_sync, nil)
        |> assign(:store_listing_sync_status, :running)
        |> assign(:store_listing_sync_output, nil)
        |> start_async(:sync_store_listing_metadata, fn ->
          AppStoreListing.update_metadata(project,
            workspace_root: workspace_root,
            firebase_id_token: firebase_id_token
          )
        end)
    end
  end

  def request_store_listing_auth_refresh(socket, project, workspace_root) do
    socket
    |> assign(:pending_store_listing_sync, %{project: project, workspace_root: workspace_root})
    |> assign(:store_listing_sync_status, :running)
    |> assign(:store_listing_sync_output, "Refreshing App Store login…")
    |> push_event("request-firebase-auth-refresh", %{})
  end

  def resume_after_firebase_auth_refresh(socket) do
    case socket.assigns[:pending_store_listing_sync] do
      %{project: project, workspace_root: workspace_root} ->
        start_store_listing_sync(
          socket,
          project,
          workspace_root,
          auth_refreshed: true
        )

      _ ->
        socket
        |> assign(:publish_submit_status, :idle)
        |> assign(:publish_submit_output, nil)
        |> put_flash(:info, "App Store login refreshed.")
    end
  end

  def fail_firebase_auth_refresh(socket, message) do
    case socket.assigns[:pending_store_listing_sync] do
      nil ->
        socket
        |> assign(:publish_submit_status, :error)
        |> assign(:publish_submit_output, "App Store login refresh failed: #{message}")

      _ ->
        socket
        |> assign(:pending_store_listing_sync, nil)
        |> assign(:store_listing_sync_status, :error)
        |> assign(:store_listing_sync_output, "App Store login refresh failed: #{message}")
    end
  end

  def persist_store_icon_uploads(socket, workspace_root) do
    alias Ide.StoreAssets

    results =
      [
        {:store_icon_small, :icon_small},
        {:store_icon_large, :icon_large}
      ]
      |> Enum.map(fn {upload, key} ->
        consume_uploaded_entries(socket, upload, fn %{path: path}, _entry ->
          case StoreAssets.save_icon(workspace_root, key, path) do
            :ok -> {:ok, :ok}
            {:error, reason} -> {:error, reason}
          end
        end)
      end)
      |> List.flatten()

    case Enum.find(results, fn
           {:error, _} -> true
           _ -> false
         end) do
      nil ->
        :ok

      {:error, {:invalid_dimensions, %{expected: {w, h}, actual: {aw, ah}}}} ->
        {:error,
         "Icon must be exactly #{Ide.StoreAssets.size_label(w, h)} (uploaded image is #{aw}×#{ah} px)."}

      {:error, :invalid_png} ->
        {:error, "Store icon must be a valid PNG file."}

      {:error, reason} ->
        {:error, "Could not save store icon: #{inspect(reason)}"}
    end
  end

  def refresh_github_repo_status(socket) do
    socket = assign(socket, :github_connected?, Ide.GitHub.Credentials.connected?())

    cond do
      is_nil(socket.assigns.project) ->
        assign(socket, :github_repo_status, :idle)

      not socket.assigns.github_connected? ->
        assign(socket, :github_repo_status, {:error, :github_not_connected})

      true ->
        config = Projects.github_config(socket.assigns.project)

        case String.trim(Map.get(config, "repo", "")) do
          "" ->
            assign(socket, :github_repo_status, :unconfigured)

          _ ->
            socket
            |> assign(:github_repo_status, :checking)
            |> start_async(:github_repo_status_check, fn ->
              GitHubRepositories.lookup_status(config)
            end)
        end
    end
  end

  def start_github_repository_create(socket, mode) do
    project = socket.assigns.project
    repo_config = Projects.github_config(project)

    cond do
      not socket.assigns.github_connected? ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Connect GitHub from IDE Settings before creating a repository."
         )}

      socket.assigns.github_repo_status != :not_found ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Repository can only be created when GitHub reports it does not exist. Save settings and refresh status first."
         )}

      true ->
        async_name =
          case mode do
            :create_only -> :create_github_repository
            :create_and_push -> :create_github_repository_and_push
          end

        task_fn =
          case mode do
            :create_only ->
              fn -> GitHubRepositories.create_repository(project, repo_config) end

            :create_and_push ->
              fn ->
                case GitHubRepositories.create_repository(project, repo_config) do
                  {:ok, created} ->
                    push_config = github_config_for_push(repo_config, created)

                    case GitHubPush.push_project_snapshot(project, push_config) do
                      {:ok, push} -> {:ok, %{create: created, push: push}}
                      {:error, reason} -> {:error, {:push, reason}}
                    end

                  {:error, reason} ->
                    {:error, {:create, reason}}
                end
              end
          end

        {:noreply,
         socket
         |> assign(:github_create_status, :running)
         |> assign(:github_push_status, if(mode == :create_and_push, do: :running, else: :idle))
         |> assign(:github_push_output, nil)
         |> start_async(async_name, task_fn)}
    end
  end

  def apply_github_repository_created(socket, created, extra_output) do
    project = socket.assigns.project

    {project, _} =
      case maybe_persist_resolved_github_owner(project, created.owner) do
        {:ok, updated} -> {updated, :ok}
        _ -> {project, :error}
      end

    output =
      [
        extra_output,
        "Created repository #{created.owner}/#{created.repo}",
        created.html_url
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    socket
    |> assign(:project, project)
    |> assign(:github_create_status, :ok)
    |> assign(:github_repo_status, :exists)
    |> assign(:github_push_output, output)
    |> assign(
      :project_settings_form,
      to_form(State.project_settings_form_data(project), as: :project_settings)
    )
  end

  def maybe_persist_resolved_github_owner(project, owner) do
    config = Projects.github_config(project)

    if String.trim(config["owner"] || "") == "" do
      Projects.update_github_config(project, Map.put(config, "owner", owner))
    else
      {:ok, project}
    end
  end

  def github_config_for_push(repo_config, %{owner: owner}) do
    if String.trim(Map.get(repo_config, "owner", "")) == "" do
      Map.put(repo_config, "owner", owner)
    else
      repo_config
    end
  end

  @spec format_github_push_error(atom() | tuple() | String.t()) :: String.t()
  def format_github_push_error({:missing_repo_field, field}),
    do: "Missing repository field: #{field}"

  def format_github_push_error(:github_not_connected),
    do: "GitHub is not connected. Connect from IDE Settings first."

  def format_github_push_error({:git_failed, _command, output}), do: output

  def format_github_push_error({:push_rejected, output}) do
    """
    Push rejected by GitHub (remote has commits not in the IDE mirror). \
    Pull or reconcile on GitHub, then try again.

    #{output}
    """
    |> String.trim()
  end

  def format_github_push_error(reason), do: GitHubRepositories.format_error(reason)

  @spec github_push_success_output(map()) :: String.t()
  def github_push_success_output(result) do
    commit_line =
      if Map.get(result, :committed, true) do
        "commit: #{result.commit_sha}"
      else
        "commit: #{result.commit_sha} (no file changes since last push)"
      end

    [
      "Pushed #{result.owner}/#{result.repo}@#{result.branch}",
      commit_line,
      "url: #{result.remote_url}"
    ]
    |> Enum.join("\n")
  end

  @spec handle_async(atom(), term(), socket()) :: lv_noreply()
  def handle_async(async, result, socket) when async in @settings_asyncs do
    do_handle_async(async, result, socket)
  end

  def handle_async(_async, _result, socket), do: {:noreply, socket}

  @spec to_bool(wire_input()) :: boolean()
  defp to_bool(value) when value in [true, "true", "on", "1", 1], do: true
  defp to_bool(_), do: false
end
