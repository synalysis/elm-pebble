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
        phx-change="validate-project-settings"
        multipart
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
              <span class="mb-1 block font-medium text-zinc-700">App Store description</span>
              <textarea
                name={@project_settings_form["description"].name}
                class="min-h-24 w-full rounded border border-zinc-300 px-2 py-1.5"
                placeholder="A short description shown on the Pebble App Store."
              ><%= @project_settings_form["description"].value %></textarea>
              <span class="mt-1 block text-zinc-500">
                Required by `pebble publish --non-interactive` when creating a new App Store listing.
              </span>
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
            <fieldset class="text-xs md:col-span-2">
              <legend class="mb-1 block font-medium text-zinc-700">Target platforms</legend>
              <p class="mb-2 text-zinc-600">
                Select which Pebble platforms are included in release builds and distributable metadata.
              </p>
              <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                <label
                  :for={platform <- target_platform_options()}
                  class="flex items-start gap-2 rounded border border-zinc-200 bg-zinc-50 p-2"
                >
                  <input
                    type="checkbox"
                    name="project_settings[target_platforms][]"
                    value={platform.id}
                    checked={platform.id in (@project_settings_form["target_platforms"].value || [])}
                    class="mt-0.5"
                  />
                  <span>
                    <span class="block font-medium text-zinc-800">{platform.label}</span>
                    <span class="block text-zinc-500">{platform.help}</span>
                  </span>
                </label>
              </div>
            </fieldset>
            <fieldset class="text-xs md:col-span-2">
              <legend class="mb-1 block font-medium text-zinc-700">Capabilities</legend>
              <p class="mb-2 text-zinc-600">
                Declare capabilities that appear in the Pebble package metadata.
              </p>
              <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                <label
                  :for={capability <- capability_options()}
                  class="flex items-start gap-2 rounded border border-zinc-200 bg-zinc-50 p-2"
                >
                  <input
                    type="checkbox"
                    name="project_settings[capabilities][]"
                    value={capability.id}
                    checked={capability.id in (@project_settings_form["capabilities"].value || [])}
                    class="mt-0.5"
                  />
                  <span>
                    <span class="block font-medium text-zinc-800">{capability.label}</span>
                    <span class="block text-zinc-500">{capability.help}</span>
                  </span>
                </label>
              </div>
            </fieldset>
          </div>
        </section>

        <section class="rounded border border-zinc-200 p-3">
          <h3 class="text-sm font-semibold">App Store graphics</h3>
          <p class="mt-1 text-xs text-zinc-600">
            PNG icons are sent on the first App Store listing (watchapps). Watchfaces can omit them.
            Banner graphics ({Ide.StoreAssets.banner_size_label()} per platform) are managed in the Rebble developer portal.
          </p>
          <div class="mt-3 grid gap-4 md:grid-cols-2">
            <div :for={spec <- store_icon_specs()} class="rounded border border-zinc-200 bg-zinc-50 p-3">
              <p class="text-xs font-medium text-zinc-800">{spec.label}</p>
              <p class="mt-1 text-xs text-zinc-500">{spec.help}</p>
              <img
                :if={@store_assets[spec.key].preview_url}
                src={@store_assets[spec.key].preview_url}
                alt={spec.label}
                class={["mt-2 rounded border border-zinc-200 bg-white object-contain", spec.preview_class]}
              />
              <p :if={@store_assets[spec.key].present and @store_assets[spec.key].valid} class="mt-2 text-xs text-emerald-700">
                Saved.
              </p>
              <p
                :if={@store_assets[spec.key].present and not @store_assets[spec.key].valid}
                class="mt-2 text-xs text-rose-700"
              >
                Saved file is not {spec.size_label}. Upload a replacement.
              </p>
              <label class="mt-2 block text-xs">
                <span class="mb-1 block font-medium text-zinc-700">{spec.upload_label}</span>
                <.live_file_input upload={Map.get(@uploads, spec.upload)} class="block w-full text-xs" />
              </label>
              <%= for err <- upload_errors(Map.get(@uploads, spec.upload)) do %>
                <p class="mt-1 text-xs text-rose-700">{err}</p>
              <% end %>
            </div>
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

  defp target_platform_options do
    [
      %{id: "aplite", label: "Build Aplite", help: "eg OG Pebble and Pebble Steel."},
      %{id: "basalt", label: "Build Basalt", help: "eg Pebble Time/Time Steel."},
      %{id: "chalk", label: "Build Chalk", help: "eg Pebble Time Round."},
      %{id: "diorite", label: "Build Diorite", help: "eg Pebble 2."},
      %{id: "emery", label: "Build Emery", help: "eg Pebble Time 2."},
      %{id: "flint", label: "Build Flint", help: "eg Pebble 2 Duo."},
      %{id: "gabbro", label: "Build Gabbro", help: "eg Pebble Round 2."}
    ]
  end

  defp store_icon_specs do
    alias Ide.StoreAssets

    uploads = %{icon_small: :store_icon_small, icon_large: :store_icon_large}

    Enum.map(StoreAssets.icon_specs(), fn spec ->
      %{
        key: spec.key,
        upload: Map.fetch!(uploads, spec.key),
        label:
          "#{StoreAssets.human_name(spec.key) |> String.capitalize()} · #{StoreAssets.size_label(spec.width, spec.height)}",
        size_label: StoreAssets.size_label(spec.width, spec.height),
        upload_label: "Upload PNG",
        preview_class: preview_class(spec.key),
        help: store_icon_help(spec.key)
      }
    end)
  end

  defp store_icon_help(:icon_small),
    do: "App Store field iconSmall — compact listings and search results."

  defp store_icon_help(:icon_large),
    do: "App Store field iconLarge — app detail page and install prompts."

  defp preview_class(:icon_small), do: "h-20 w-20"
  defp preview_class(:icon_large), do: "h-28 w-28"

  defp capability_options do
    [
      %{
        id: "location",
        label: "Uses location",
        help: "Declares phone-side location access for the app."
      },
      %{
        id: "configurable",
        label: "Configurable",
        help: "Shows a settings gear in the Pebble mobile app."
      },
      %{
        id: "health",
        label: "Uses health",
        help: "Declares access to Pebble Health data."
      }
    ]
  end
end
