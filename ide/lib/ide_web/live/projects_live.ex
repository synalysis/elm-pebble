defmodule IdeWeb.ProjectsLive do
  use IdeWeb, :live_view

  alias Ide.ProjectTemplates
  alias Ide.Projects
  alias Ide.Projects.Project

  @impl true
  @spec mount(term(), term(), term()) :: term()
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Projects")
     |> assign(:template_options, ProjectTemplates.options())
     |> assign(:form, to_form(Project.changeset(%Project{}, default_attrs())))
     |> assign(:show_import_form, false)
     |> assign(:import_form, to_form(%{"import_path" => ""}, as: :import))
     |> load_projects()}
  end

  @impl true
  @spec handle_event(term(), term(), term()) :: term()
  def handle_event("validate", %{"project" => params}, socket) do
    params = normalize_create_params(params)

    form =
      %Project{}
      |> Project.changeset(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("create", %{"project" => params}, socket) do
    case Projects.create_project(normalize_create_params(params)) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created.")
         |> load_projects()
         |> assign(:form, to_form(Project.changeset(%Project{}, default_attrs())))
         |> push_navigate(to: ~p"/projects/#{project.slug}/editor")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :validate)))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create project: #{inspect(reason)}")}
    end
  end

  def handle_event("import", %{"import" => params}, socket) do
    import_path = Map.get(params, "import_path", "")

    case Projects.import_project(%{}, import_path) do
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
        {:noreply, put_flash(socket, :error, "Import failed: #{inspect(reason)}")}
    end
  end

  def handle_event("toggle-import-form", _params, socket) do
    {:noreply, assign(socket, :show_import_form, not socket.assigns.show_import_form)}
  end

  def handle_event("activate", %{"id" => id}, socket) do
    project = Projects.get_project!(id)

    case Projects.activate_project(project) do
      {:ok, _active} ->
        {:noreply, socket |> put_flash(:info, "Active project updated.") |> load_projects()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not activate project: #{inspect(reason)}")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    project = Projects.get_project!(id)

    case Projects.delete_project(project) do
      {:ok, _deleted} ->
        {:noreply, socket |> put_flash(:info, "Project deleted.") |> load_projects()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete project: #{inspect(reason)}")}
    end
  end

  @spec load_projects(term()) :: term()
  defp load_projects(socket) do
    assign(socket, :projects, Projects.list_projects())
  end

  @spec default_attrs() :: term()
  defp default_attrs do
    %{
      "target_type" => "app",
      "source_roots" => ["watch", "protocol", "phone"],
      "template" => "starter"
    }
  end

  @spec normalize_create_params(term()) :: term()
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

  @spec slug_from_name(term()) :: term()
  defp slug_from_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp slug_from_name(_), do: ""

  @impl true
  @spec render(term()) :: term()
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
        <h2 class="text-base font-semibold">Create project</h2>
        <.form
          for={@form}
          id="project-form"
          class="mt-4 grid gap-4 md:grid-cols-3"
          phx-change="validate"
          phx-submit="create"
        >
          <.input field={@form[:name]} type="text" label="Name" required />
          <.input field={@form[:slug]} type="text" label="Slug" required />
          <.input field={@form[:template]} type="select" label="Template" options={@template_options} />
          <div class="md:col-span-3">
            <.button>Create project</.button>
          </div>
        </.form>
      </section>

      <section class="rounded-lg border border-zinc-200 bg-white p-5 shadow-sm">
        <div class="flex items-center justify-between gap-3">
          <h2 class="text-base font-semibold">Projects</h2>
          <button
            type="button"
            phx-click="toggle-import-form"
            class="rounded bg-zinc-100 px-3 py-2 text-sm text-zinc-800"
          >
            Import
          </button>
        </div>
        <div :if={@show_import_form} class="mt-4 rounded border border-zinc-200 bg-zinc-50 p-4">
          <p class="text-sm text-zinc-600">
            Import from a local path that contains `elm-pebble.project.json`.
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
    </div>
    """
  end
end
