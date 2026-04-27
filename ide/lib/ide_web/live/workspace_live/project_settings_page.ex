defmodule IdeWeb.WorkspaceLive.ProjectSettingsPage do
  @moduledoc false
  use IdeWeb, :html

  @spec render(term()) :: term()
  def render(assigns) do
    ~H"""
    <section
      :if={@pane == :settings}
      class="min-h-0 flex-1 overflow-auto rounded-lg border border-zinc-200 bg-white p-5 shadow-sm"
    >
      <div class="flex items-start justify-between gap-3">
        <div>
          <h2 class="text-base font-semibold">Project Settings</h2>
          <p class="mt-1 text-sm text-zinc-600">
            Configure release metadata and GitHub repository linkage for this project.
          </p>
        </div>
        <.button phx-click="push-project-snapshot" disabled={@github_push_status == :running}>
          {if @github_push_status == :running, do: "Pushing snapshot...", else: "Push snapshot"}
        </.button>
      </div>

      <p class="mt-2 text-xs text-zinc-600">
        Push status:
        <span class={push_status_class(@github_push_status)}>
          {status_label(@github_push_status)}
        </span>
      </p>

      <nav class="mt-4 flex flex-wrap gap-2 border-b border-zinc-200 pb-2 text-sm">
        <.link
          patch={~p"/projects/#{@project.slug}/settings"}
          class={settings_tab_class(@pane, :settings)}
        >
          Settings
        </.link>
        <.link
          patch={~p"/projects/#{@project.slug}/resources"}
          class={settings_tab_class(@pane, :resources)}
        >
          Resources
        </.link>
        <.link
          patch={~p"/projects/#{@project.slug}/packages"}
          class={settings_tab_class(@pane, :packages)}
        >
          Packages
        </.link>
      </nav>

      <.form
        for={@project_settings_form}
        id="project-settings-form"
        phx-submit="save-project-settings"
        class="mt-4 space-y-4"
      >
        <section class="rounded border border-zinc-200 p-3">
          <h3 class="text-sm font-semibold">Release metadata</h3>
          <p class="mt-1 text-xs text-zinc-600">
            Version auto-increments after a successful publish submit. You can also edit it manually here.
          </p>
          <div class="mt-3 grid gap-3 md:grid-cols-2">
            <label class="text-xs">
              <span class="mb-1 block font-medium text-zinc-700">Version</span>
              <input
                type="text"
                name={@project_settings_form["version_label"].name}
                value={@project_settings_form["version_label"].value}
                class="w-full rounded border border-zinc-300 px-2 py-1.5"
                placeholder="1.0.0"
              />
            </label>
            <label class="text-xs md:col-span-2">
              <span class="mb-1 block font-medium text-zinc-700">Tags (comma-separated)</span>
              <input
                type="text"
                name={@project_settings_form["tags"].name}
                value={@project_settings_form["tags"].value}
                class="w-full rounded border border-zinc-300 px-2 py-1.5"
                placeholder="fitness, minimal, utility"
              />
            </label>
          </div>
        </section>

        <section class="rounded border border-zinc-200 p-3">
          <h3 class="text-sm font-semibold">GitHub repository</h3>
          <p class="mt-1 text-xs text-zinc-600">
            Set target repo used by Push snapshot. Connect to GitHub from IDE Settings first.
          </p>
          <div class="mt-3 grid gap-3 md:grid-cols-3">
            <label class="text-xs">
              <span class="mb-1 block font-medium text-zinc-700">Owner</span>
              <input
                type="text"
                name={@project_settings_form["github_owner"].name}
                value={@project_settings_form["github_owner"].value}
                class="w-full rounded border border-zinc-300 px-2 py-1.5"
                placeholder="my-org"
              />
            </label>
            <label class="text-xs">
              <span class="mb-1 block font-medium text-zinc-700">Repository</span>
              <input
                type="text"
                name={@project_settings_form["github_repo"].name}
                value={@project_settings_form["github_repo"].value}
                class="w-full rounded border border-zinc-300 px-2 py-1.5"
                placeholder="elm-pebble-watchface"
              />
            </label>
            <label class="text-xs">
              <span class="mb-1 block font-medium text-zinc-700">Branch</span>
              <input
                type="text"
                name={@project_settings_form["github_branch"].name}
                value={@project_settings_form["github_branch"].value}
                class="w-full rounded border border-zinc-300 px-2 py-1.5"
                placeholder="main"
              />
            </label>
          </div>
        </section>

        <.button>Save project settings</.button>
      </.form>

      <pre
        :if={@github_push_output}
        class="mt-4 max-h-80 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
      ><%= @github_push_output %></pre>
    </section>
    """
  end

  @spec status_label(term()) :: String.t()
  defp status_label(:idle), do: "idle"
  defp status_label(:running), do: "running"
  defp status_label(:ok), do: "ok"
  defp status_label(:error), do: "error"
  defp status_label(_), do: "unknown"

  @spec push_status_class(term()) :: String.t()
  defp push_status_class(:ok), do: "text-emerald-700"
  defp push_status_class(:error), do: "text-rose-700"
  defp push_status_class(:running), do: "text-blue-700"
  defp push_status_class(_), do: "text-zinc-700"

  @spec settings_tab_class(term(), term()) :: String.t()
  defp settings_tab_class(active, tab) when active == tab,
    do: "rounded bg-blue-100 px-3 py-1.5 text-blue-800"

  defp settings_tab_class(_active, _tab), do: "rounded bg-zinc-100 px-3 py-1.5 text-zinc-700"
end
