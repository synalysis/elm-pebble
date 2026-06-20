defmodule IdeWeb.ProjectsLive do
  use IdeWeb, :live_view

  alias Ide.Auth
  alias Ide.GitHub.Credentials
  alias Ide.ProjectTemplates
  alias Ide.Projects
  alias Ide.Projects.BootstrapError
  alias Ide.Projects.Project
  alias Ide.Projects.Types, as: ProjectTypes

  @type socket :: Phoenix.LiveView.Socket.t()
  @type lv_mount :: {:ok, socket()}
  @type lv_noreply :: {:noreply, socket()}

  @impl true
  @spec mount(map(), map(), socket()) :: lv_mount()
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Projects")
     |> assign(:template_categories, ProjectTemplates.picker_categories())
     |> assign(:show_create_modal, false)
     |> assign(:selected_template, "starter")
     |> assign(:create_name_user_edited, false)
     |> assign(:form, to_form(Project.changeset(%Project{}, default_attrs())))
     |> assign(:show_import_form, false)
     |> assign(:import_mode, :local)
     |> assign(:github_connected?, Credentials.connected?())
     |> assign(:import_form, to_form(%{"import_path" => ""}, as: :import))
     |> assign(:github_import_form, to_form(default_github_import_attrs(), as: :github_import))
     |> load_projects()}
  end

  @impl true
  @spec handle_event(String.t(), map(), socket()) :: lv_noreply()
  def handle_event("validate", %{"project" => params}, socket) do
    params =
      params
      |> Map.put("template", socket.assigns.selected_template)
      |> normalize_create_params()

    form =
      %Project{}
      |> Project.changeset(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:create_name_user_edited, true)}
  end

  def handle_event("create", %{"project" => params}, socket) do
    params =
      params
      |> Map.put("template", socket.assigns.selected_template)
      |> normalize_create_params()

    if create_project_name_given?(params) do
      do_create_project(params, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("import", %{"import" => params}, socket) do
    import_path = Map.get(params, "import_path", "")

    case Projects.import_project(%{}, import_path, socket.assigns.current_user) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project imported.")
         |> load_projects()
         |> assign(:show_import_form, false)
         |> assign(:import_form, to_form(%{"import_path" => ""}, as: :import))
         |> push_navigate(to: ~p"/projects/#{project.slug}/editor")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Import failed. Include elm-pebble.project.json in the import root."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Import failed: #{format_import_error(reason)}")}
    end
  end

  def handle_event("import-github", %{"github_import" => params}, socket) do
    if socket.assigns.github_connected? do
      attrs = normalize_github_import_attrs(params)

      case Projects.import_from_github(attrs, params, socket.assigns.current_user) do
        {:ok, project} ->
          {:noreply,
           socket
           |> put_flash(:info, "Project imported from GitHub.")
           |> load_projects()
           |> assign(:show_import_form, false)
           |> assign(
             :github_import_form,
             to_form(default_github_import_attrs(), as: :github_import)
           )
           |> push_navigate(to: ~p"/projects/#{project.slug}/editor")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           put_flash(socket, :error, "Import failed: #{format_changeset_errors(changeset)}")}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "GitHub import failed: #{format_import_error(reason)}")}
      end
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "Connect GitHub from IDE Settings before importing a repository."
       )}
    end
  end

  def handle_event("validate-github-import", %{"github_import" => params}, socket) do
    {:noreply,
     assign(
       socket,
       :github_import_form,
       to_form(normalize_github_import_attrs(params), as: :github_import)
     )}
  end

  def handle_event("toggle-import-form", _params, socket) do
    {:noreply, assign(socket, :show_import_form, not socket.assigns.show_import_form)}
  end

  def handle_event("open-create-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, true)
     |> assign(:selected_template, "starter")
     |> assign(:create_name_user_edited, false)
     |> assign(:form, to_form(Project.changeset(%Project{}, default_attrs())))
     |> autofill_create_name_from_template("starter")}
  end

  def handle_event("close-create-modal", _params, socket) do
    {:noreply, assign(socket, :show_create_modal, false)}
  end

  def handle_event("select-template", %{"template" => template}, socket) do
    if template in ProjectTemplates.template_keys() do
      {:noreply,
       socket
       |> assign(:selected_template, template)
       |> autofill_create_name_from_template(template)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set-import-mode", %{"mode" => mode}, socket)
      when mode in ["local", "github"] do
    {:noreply, assign(socket, :import_mode, String.to_existing_atom(mode))}
  end

  def handle_event("activate", %{"id" => id}, socket) do
    project = Projects.get_project!(id, socket.assigns.current_user)

    case Projects.activate_project(project) do
      {:ok, _active} ->
        {:noreply, socket |> put_flash(:info, "Active project updated.") |> load_projects()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not activate project: #{inspect(reason)}")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    project = Projects.get_project!(id, socket.assigns.current_user)

    case Projects.delete_project(project) do
      {:ok, _deleted} ->
        {:noreply, socket |> put_flash(:info, "Project deleted.") |> load_projects()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete project: #{inspect(reason)}")}
    end
  end

  @spec load_projects(socket()) :: socket()
  defp load_projects(socket) do
    assign(socket, :projects, Projects.list_projects(socket.assigns.current_user))
  end

  @spec do_create_project(map(), socket()) :: lv_noreply()
  defp do_create_project(params, socket) do
    case Projects.create_project(params, socket.assigns.current_user) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created.")
         |> load_projects()
         |> assign(:show_create_modal, false)
         |> assign(:selected_template, "starter")
         |> assign(:create_name_user_edited, false)
         |> assign(:form, to_form(Project.changeset(%Project{}, default_attrs())))
         |> push_navigate(to: ~p"/projects/#{project.slug}/editor")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not create project. Fix the errors below.")
         |> assign(:form, to_form(Map.put(changeset, :action, :insert)))}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not create project: #{BootstrapError.describe(reason, %{template: Map.get(params, "template", "starter")})}"
         )}
    end
  end

  @spec default_attrs() :: map()
  defp default_attrs do
    %{
      "target_type" => "app",
      "source_roots" => ["watch", "protocol", "phone"],
      "template" => "starter"
    }
  end

  @spec default_github_import_attrs() :: map()
  defp default_github_import_attrs do
    %{
      "repo_url" => "",
      "owner" => "",
      "repo" => "",
      "branch" => "main",
      "name" => "",
      "slug" => ""
    }
  end

  @spec normalize_create_params(map()) :: map()
  defp normalize_create_params(params) when is_map(params) do
    template = Map.get(params, "template", "starter")
    name = Map.get(params, "name", "")
    derived_slug = slug_from_name(name)

    params
    |> Map.put("slug", derived_slug)
    |> Map.put("template", template)
    |> Map.put("target_type", ProjectTemplates.target_type_for_template(template))
    |> Map.put_new("source_roots", ["watch", "protocol", "phone"])
  end

  @spec normalize_github_import_attrs(map()) :: map()
  defp normalize_github_import_attrs(params) when is_map(params) do
    name = Map.get(params, "name", "") |> to_string() |> String.trim()
    slug = Map.get(params, "slug", "") |> to_string() |> String.trim()

    params =
      params
      |> Map.put("name", name)
      |> Map.put("slug", if(slug == "", do: slug_from_name(name), else: slug))

    case blank?(Map.get(params, "repo_url")) do
      true ->
        owner = Map.get(params, "owner", "") |> to_string() |> String.trim()
        repo = Map.get(params, "repo", "") |> to_string() |> String.trim()
        params |> Map.put("owner", owner) |> Map.put("repo", repo)

      false ->
        params
    end
  end

  @spec slug_from_name(String.t() | nil) :: String.t()
  defp slug_from_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp slug_from_name(_), do: ""

  @spec blank?(String.t() | nil) :: boolean()
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: true

  @spec create_project_name_given?(map() | Phoenix.HTML.Form.t()) :: boolean()
  defp create_project_name_given?(%Phoenix.HTML.Form{} = form) do
    form
    |> Phoenix.HTML.Form.input_value(:name)
    |> present_name?()
  end

  defp create_project_name_given?(params) when is_map(params) do
    params
    |> Map.get("name")
    |> present_name?()
  end

  @spec present_name?(term()) :: boolean()
  defp present_name?(name), do: not blank?(to_string(name || ""))

  @spec autofill_create_name_from_template(socket(), String.t()) :: socket()
  defp autofill_create_name_from_template(socket, template_key) do
    name = Phoenix.HTML.Form.input_value(socket.assigns.form, :name)

    if blank?(name) or not socket.assigns.create_name_user_edited do
      title = ProjectTemplates.picker_title(template_key)

      params =
        socket.assigns.form.params
        |> Map.put("name", title)
        |> Map.put("template", template_key)
        |> normalize_create_params()

      form =
        %Project{}
        |> Project.changeset(params)
        |> Map.put(:action, :validate)
        |> to_form()

      socket
      |> assign(:form, form)
      |> assign(:create_name_user_edited, false)
    else
      socket
    end
  end

  @spec format_import_error(ProjectTypes.project_error()) :: String.t()
  defp format_import_error(:github_not_connected),
    do: "GitHub is not connected. Open Settings and connect your account."

  defp format_import_error(:missing_github_repo),
    do: "Enter a GitHub repository URL or owner and repository name."

  defp format_import_error({:git_failed, "clone", output}), do: output

  defp format_import_error({:invalid_repo_field, field}),
    do: "Invalid repository #{field}."

  defp format_import_error(:invalid_repo_ref),
    do: "Could not parse the repository URL or owner/repo fields."

  defp format_import_error(reason), do: BootstrapError.describe(reason, %{operation: :import})

  @spec format_changeset_errors(Ecto.Changeset.t()) :: String.t()
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field} #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl space-y-8 p-6">
      <section class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 class="text-2xl font-semibold text-zinc-900">Elm Pebble IDE</h1>
          <p class="mt-2 text-sm text-zinc-600">
            Create and switch projects. Each project gets isolated watch/protocol/phone source roots.
          </p>
        </div>
        <.link
          navigate={~p"/settings?return_to=/projects"}
          class="rounded bg-zinc-100 px-3 py-2 text-sm text-zinc-800"
        >
          Settings
        </.link>
      </section>

      <section class="rounded-lg border border-zinc-200 bg-white p-5 shadow-sm">
        <div class="flex items-center justify-between gap-3">
          <h2 class="text-base font-semibold">Projects</h2>
          <div class="flex flex-wrap gap-2">
            <button
              type="button"
              phx-click="open-create-modal"
              class="rounded bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-700"
            >
              Create project
            </button>
            <button
              type="button"
              phx-click="toggle-import-form"
              class="rounded bg-zinc-100 px-3 py-2 text-sm text-zinc-800"
            >
              Import
            </button>
          </div>
        </div>
        <div :if={@show_import_form} class="mt-4 rounded border border-zinc-200 bg-zinc-50 p-4">
          <div class="flex flex-wrap gap-2 text-sm">
            <button
              type="button"
              phx-click="set-import-mode"
              phx-value-mode="local"
              class={import_mode_class(@import_mode, :local)}
            >
              From folder
            </button>
            <button
              type="button"
              phx-click="set-import-mode"
              phx-value-mode="github"
              class={import_mode_class(@import_mode, :github)}
            >
              From GitHub
            </button>
          </div>

          <div :if={@import_mode == :local} class="mt-4">
            <p class="text-sm text-zinc-600">
              Import from a local path that contains `elm-pebble.project.json` or Elm source roots.
            </p>
            <.form for={@import_form} class="mt-3 grid gap-3 md:grid-cols-4" phx-submit="import">
              <div class="md:col-span-3">
                <.input field={@import_form[:import_path]} type="text" label="Import path" required />
              </div>
              <div class="md:col-span-1 flex items-end">
                <.button class="w-full">Import project</.button>
              </div>
            </.form>
          </div>

          <div :if={@import_mode == :github} class="mt-4">
            <p :if={not @github_connected?} class="text-sm text-amber-700">
              Connect GitHub from
              <.link navigate={~p"/settings?return_to=/projects"} class="font-medium underline">
                IDE Settings
              </.link>
              before importing a repository.
            </p>
            <p :if={@github_connected?} class="text-sm text-zinc-600">
              Clone a repository you pushed from the IDE (or any Elm Pebble project on GitHub) into a new workspace.
              Metadata from `elm-pebble.project.json` is applied when present.
            </p>
            <.form
              for={@github_import_form}
              id="github-import-form"
              class="mt-3 grid gap-3 md:grid-cols-2"
              phx-change="validate-github-import"
              phx-submit="import-github"
            >
              <div class="md:col-span-2">
                <.input
                  field={@github_import_form[:repo_url]}
                  type="text"
                  label="Repository URL"
                  placeholder="https://github.com/owner/repo"
                  disabled={not @github_connected?}
                />
              </div>
              <.input
                field={@github_import_form[:owner]}
                type="text"
                label="Owner (optional if URL set)"
                placeholder="my-org"
                disabled={not @github_connected?}
              />
              <.input
                field={@github_import_form[:repo]}
                type="text"
                label="Repository (optional if URL set)"
                placeholder="my-watchface"
                disabled={not @github_connected?}
              />
              <.input
                field={@github_import_form[:branch]}
                type="text"
                label="Branch"
                placeholder="main"
                disabled={not @github_connected?}
              />
              <.input
                field={@github_import_form[:name]}
                type="text"
                label="Project name (optional)"
                disabled={not @github_connected?}
              />
              <.input
                field={@github_import_form[:slug]}
                type="text"
                label="Project slug (optional)"
                disabled={not @github_connected?}
              />
              <div class="md:col-span-2">
                <.button disabled={not @github_connected?}>Import from GitHub</.button>
              </div>
            </.form>
          </div>
        </div>
        <div class="mt-4 overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm">
            <thead class="bg-zinc-50 text-left text-zinc-600">
              <tr>
                <th class="px-3 py-2">Name</th>
                <th class="px-3 py-2">Slug</th>
                <th class="px-3 py-2">Target</th>
                <th class="px-3 py-2">Source roots</th>
                <th class="px-3 py-2">Actions</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-100">
              <tr :for={project <- @projects}>
                <td class="px-3 py-2">
                  <span class={["font-medium", project.active && "text-emerald-700"]}>
                    {project.name}
                  </span>
                  <span
                    :if={project.active}
                    class="ml-2 rounded bg-emerald-100 px-2 py-0.5 text-xs text-emerald-700"
                  >
                    active
                  </span>
                </td>
                <td class="px-3 py-2 font-mono text-xs">{project.slug}</td>
                <td class="px-3 py-2">{project.target_type}</td>
                <td class="px-3 py-2">{Enum.join(project.source_roots, ", ")}</td>
                <td class="px-3 py-2">
                  <div class="flex flex-wrap gap-2">
                    <.link
                      navigate={~p"/projects/#{project.slug}/editor"}
                      class="rounded bg-blue-600 px-2 py-1 text-white hover:bg-blue-700"
                    >
                      Open editor
                    </.link>
                    <button
                      type="button"
                      phx-click="activate"
                      phx-value-id={project.id}
                      class="rounded bg-zinc-100 px-2 py-1"
                    >
                      Set active
                    </button>
                    <.link
                      href={~p"/projects/#{project.id}/export"}
                      class="rounded bg-emerald-600 px-2 py-1 text-white hover:bg-emerald-700"
                    >
                      Export
                    </.link>
                    <button
                      type="button"
                      phx-click="delete"
                      phx-value-id={project.id}
                      data-confirm="Delete this project and its workspace files?"
                      class="rounded bg-rose-600 px-2 py-1 text-white hover:bg-rose-700"
                    >
                      Delete
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <div :if={@show_create_modal} class="fixed inset-0 z-50 grid place-items-center p-4">
        <div class="absolute inset-0 bg-black/40" phx-click="close-create-modal"></div>
        <div class="relative z-10 flex max-h-[90vh] w-full max-w-5xl flex-col overflow-hidden rounded-lg bg-white shadow-xl">
          <div class="border-b border-zinc-200 px-5 py-4">
            <div class="flex items-start justify-between gap-3">
              <div>
                <h3 class="text-base font-semibold text-zinc-900">Create project</h3>
                <p class="mt-1 text-sm text-zinc-600">
                  Choose a template, then name your project. The slug is derived from the name.
                </p>
              </div>
              <button
                type="button"
                phx-click="close-create-modal"
                class="rounded px-2 py-1 text-sm text-zinc-500 hover:bg-zinc-100 hover:text-zinc-800"
                aria-label="Close"
              >
                Close
              </button>
            </div>
            <.form
              for={@form}
              id="project-form"
              class="mt-4"
              phx-change="validate"
              phx-submit="create"
            >
              <.input field={@form[:name]} type="text" label="Project name" required />
            </.form>
          </div>
          <div class="overflow-y-auto px-5 py-4">
            <div :for={category <- @template_categories} class="space-y-3">
              <h4 class="text-sm font-semibold text-zinc-800">{category.label}</h4>
              <div class="mb-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                <button
                  :for={template <- category.templates}
                  type="button"
                  phx-click="select-template"
                  phx-value-template={template.key}
                  class={[
                    "rounded-lg border p-3 text-left transition",
                    @selected_template == template.key &&
                      "border-blue-500 bg-blue-50 ring-2 ring-blue-200",
                    @selected_template != template.key &&
                      "border-zinc-200 bg-white hover:border-zinc-300 hover:bg-zinc-50"
                  ]}
                >
                  <div class="overflow-hidden rounded border border-zinc-200 bg-zinc-100">
                    <img
                      src={template.screenshot_url}
                      alt={"#{template.title} preview"}
                      class="mx-auto h-36 w-full object-contain"
                      loading="lazy"
                    />
                  </div>
                  <p class="mt-3 text-sm font-medium text-zinc-900">{template.title}</p>
                  <p :if={template.description} class="mt-1 text-xs text-zinc-600">
                    {template.description}
                  </p>
                </button>
              </div>
            </div>
          </div>
          <div class="flex justify-end gap-2 border-t border-zinc-200 px-5 py-4">
            <button
              type="button"
              phx-click="close-create-modal"
              class="rounded px-3 py-2 text-sm text-zinc-600 hover:bg-zinc-100"
            >
              Cancel
            </button>
            <.button form="project-form" type="submit" disabled={not create_project_name_given?(@form)}>
              Create project
            </.button>
          </div>
        </div>
      </div>

      <section
        :if={Auth.public_mode?() and @current_user}
        class="rounded-lg border border-rose-200 bg-rose-50 p-5 shadow-sm"
      >
        <h2 class="text-base font-semibold text-rose-900">Delete your data</h2>
        <p class="mt-2 text-sm text-rose-800">
          Permanently delete your account, all projects, and workspace files from this IDE. This cannot be undone.
        </p>
        <form action={~p"/auth/delete-data"} method="post" class="mt-4">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button
            type="submit"
            data-confirm="Delete all your projects and account data? This cannot be undone."
            class="rounded bg-rose-700 px-3 py-2 text-sm font-semibold text-white hover:bg-rose-800"
          >
            Delete my data
          </button>
        </form>
      </section>

      <.local_run_footer class="pt-2" />
    </div>
    """
  end

  defp import_mode_class(current, mode) when current == mode,
    do: "rounded bg-blue-100 px-3 py-1.5 font-medium text-blue-800"

  defp import_mode_class(_current, _mode),
    do: "rounded bg-white px-3 py-1.5 text-zinc-700 ring-1 ring-zinc-200"
end
