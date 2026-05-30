defmodule IdeWeb.WorkspaceLive.ProjectSettingsPage do
  @moduledoc false
  use IdeWeb, :html

  alias Ide.Auth
  alias Phoenix.LiveView.Rendered

  @settings_panes [:settings, :settings_store, :settings_github]

  @type assigns :: map()
  @type rendered :: Rendered.t()
  @type settings_pane :: :settings | :settings_store | :settings_github
  @type flow_status :: :idle | :running | :ok | :error

  @spec render(assigns()) :: rendered()
  def render(assigns) do
    ~H"""
    <section
      :if={settings_pane?(@pane)}
      class="rounded-lg border border-zinc-200 bg-white p-5 shadow-sm"
    >
      <div class="flex items-start justify-between gap-3">
        <div>
          <h2 class="text-base font-semibold">Project Settings</h2>
          <p class="mt-1 text-sm text-zinc-600">{settings_intro(@pane)}</p>
        </div>
        <.button
          :if={@pane == :settings_github}
          phx-click="push-project-snapshot"
          disabled={@github_push_status == :running}
        >
          {if @github_push_status == :running, do: "Pushing snapshot...", else: "Push snapshot"}
        </.button>
      </div>

      <p :if={@pane == :settings_github} class="mt-2 text-xs text-zinc-600">
        Push status:
        <span class={push_status_class(@github_push_status)}>
          {status_label(@github_push_status)}
        </span>
      </p>

      <.settings_nav pane={@pane} project={@project} auth_mode={@auth_mode} />

      <.form
        for={@project_settings_form}
        id="project-settings-form"
        phx-submit="save-project-settings"
        phx-change="validate-project-settings"
        multipart
        class="mt-4 space-y-4"
      >
        <.release_metadata_section
          :if={@pane == :settings}
          project_settings_form={@project_settings_form}
          detected_capabilities={@detected_capabilities}
          store_listing_sync_status={@store_listing_sync_status}
          auth_mode={@auth_mode}
        />

        <.store_graphics_section
          :if={@pane == :settings_store}
          project={@project}
          project_settings_form={@project_settings_form}
          store_assets={@store_assets}
          uploads={@uploads}
        />

        <.github_section
          :if={@pane == :settings_github}
          project_settings_form={@project_settings_form}
          github_connected?={@github_connected?}
          github_repo_status={@github_repo_status}
          github_create_status={@github_create_status}
          github_push_status={@github_push_status}
        />

        <.button>Save project settings</.button>
      </.form>

      <pre
        :if={@store_listing_sync_output}
        class="mt-4 max-h-80 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
      ><%= @store_listing_sync_output %></pre>

      <pre
        :if={@github_push_output}
        class="mt-4 max-h-80 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
      ><%= @github_push_output %></pre>
    </section>
    """
  end

  attr :pane, :atom, required: true
  attr :project, :map, required: true
  attr :auth_mode, :atom, default: :local
  attr :class, :string, default: "mt-4"

  @spec settings_nav(map()) :: Phoenix.LiveView.Rendered.t()
  def settings_nav(assigns) do
    ~H"""
    <nav class={[@class, "flex flex-wrap gap-2 border-b border-zinc-200 pb-2 text-sm"]}>
      <.link
        patch={~p"/projects/#{@project.slug}/settings"}
        class={settings_tab_class(@pane, :settings)}
      >
        Release
      </.link>
      <.link
        :if={Auth.app_store_publish_enabled?()}
        patch={~p"/projects/#{@project.slug}/settings/store"}
        class={settings_tab_class(@pane, :settings_store)}
      >
        App Store
      </.link>
      <.link
        patch={~p"/projects/#{@project.slug}/settings/github"}
        class={settings_tab_class(@pane, :settings_github)}
      >
        GitHub
      </.link>
      <.link
        patch={~p"/projects/#{@project.slug}/resources/bitmaps-static"}
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
    """
  end

  attr :project_settings_form, :map, required: true
  attr :detected_capabilities, :list, required: true
  attr :store_listing_sync_status, :atom, required: true
  attr :auth_mode, :atom, required: true

  defp release_metadata_section(assigns) do
    ~H"""
    <section class="rounded border border-zinc-200 p-3">
      <div class="flex items-start justify-between gap-3">
        <div>
          <h3 class="text-sm font-semibold">Release metadata</h3>
          <p class="mt-1 text-xs text-zinc-600">
            {release_metadata_intro(@auth_mode)}
          </p>
          <p :if={Auth.app_store_publish_enabled?()} class="mt-1 text-xs text-zinc-600">
            App Store sync:
            <span class={push_status_class(@store_listing_sync_status)}>
              {status_label(@store_listing_sync_status)}
            </span>
          </p>
        </div>
        <button
          :if={Auth.app_store_publish_enabled?()}
          type="submit"
          name="sync_store_listing"
          value="1"
          disabled={@store_listing_sync_status == :running}
          class={[store_listing_sync_button_class(@store_listing_sync_status == :running), "shrink-0"]}
        >
          {if @store_listing_sync_status == :running,
            do: "Updating App Store…",
            else: "Update App Store metadata"}
        </button>
      </div>
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
          <span class="mb-1 block font-medium text-zinc-700">Website URL</span>
          <input
            type="url"
            name={@project_settings_form["website_url"].name}
            value={@project_settings_form["website_url"].value}
            class="w-full rounded border border-zinc-300 px-2 py-1.5"
            placeholder={Ide.StoreListingUrls.default_website_url()}
          />
          <span class="mt-1 block text-zinc-500">
            App Store website metadata. Defaults to {Ide.StoreListingUrls.default_website_url()}.
          </span>
        </label>
        <label class="text-xs md:col-span-2">
          <span class="mb-1 block font-medium text-zinc-700">Source code URL</span>
          <input
            type="url"
            name={@project_settings_form["source_url"].name}
            value={@project_settings_form["source_url"].value}
            class="w-full rounded border border-zinc-300 px-2 py-1.5"
            placeholder={Ide.StoreListingUrls.default_source_repo_url()}
          />
          <span class="mt-1 block text-zinc-500">
            Sent as the App Store source link on first publish. Defaults to
            {Ide.StoreListingUrls.default_source_repo_url()}, or your public GitHub repository when configured on the GitHub tab.
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
            Detected from Elm API usage in watch and phone sources. These appear in Pebble package metadata.
          </p>
          <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            <div
              :for={capability <- capability_options()}
              class={[
                "rounded border p-2",
                capability.id in @detected_capabilities && "border-emerald-200 bg-emerald-50",
                capability.id not in @detected_capabilities && "border-zinc-200 bg-zinc-50 opacity-70"
              ]}
            >
              <span class="block font-medium text-zinc-800">{capability.label}</span>
              <span class="block text-zinc-500">{capability.help}</span>
              <span
                :if={capability.id in @detected_capabilities}
                class="mt-1 block font-medium text-emerald-700"
              >
                Detected
              </span>
              <span :if={capability.id not in @detected_capabilities} class="mt-1 block text-zinc-500">
                Not used
              </span>
            </div>
          </div>
        </fieldset>
      </div>
    </section>
    """
  end

  attr :project, :map, required: true
  attr :project_settings_form, :map, required: true
  attr :store_assets, :map, required: true
  attr :uploads, :map, required: true

  defp store_graphics_section(assigns) do
    ~H"""
    <section class="rounded border border-zinc-200 p-3">
      <h3 class="text-sm font-semibold">App Store graphics</h3>
      <p class="mt-1 text-xs text-zinc-600">
        PNG icons are sent on the first App Store listing (watchapps). Watchfaces can omit them.
        Platform banners ({Ide.StoreAssets.banner_size_label()}) are added per device in the
        <a
          href="https://developer.repebble.com/dashboard"
          class="font-medium text-blue-700 hover:underline"
          target="_blank"
          rel="noopener noreferrer"
        >
          Rebble developer dashboard
        </a>.
      </p>
      <div
        :if={@project.target_type == "app" and Ide.StoreAssets.ai_graphics_available?(@store_assets)}
        class="mt-3 rounded border border-blue-200 bg-blue-50 p-3 text-xs text-zinc-700"
      >
        <input type="hidden" name="project_settings[generate_store_graphics]" value="false" />
        <label class="flex items-start gap-2">
          <input
            type="checkbox"
            name="project_settings[generate_store_graphics]"
            value="true"
            checked={@project_settings_form["generate_store_graphics"].value == true}
            class="mt-0.5"
          />
          <span>
            <span class="block font-medium text-zinc-900">Generate App Store icons with AI on first publish</span>
            <span class="mt-1 block text-zinc-600">
              When no icons are uploaded above, the IDE can send your app name and App Store description to Rebble as an AI prompt on the first listing. Save this setting, then publish from the Publish tab.
            </span>
          </span>
        </label>
      </div>
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
    """
  end

  attr :project_settings_form, :map, required: true
  attr :github_connected?, :boolean, required: true
  attr :github_repo_status, :any, required: true
  attr :github_create_status, :any, required: true
  attr :github_push_status, :any, required: true

  defp github_section(assigns) do
    ~H"""
    <section class="rounded border border-zinc-200 p-3">
      <h3 class="text-sm font-semibold">GitHub repository</h3>
      <p class="mt-1 text-xs text-zinc-600">
        Set target repo used by Push snapshot. Connect to GitHub from IDE Settings first.
        Save settings before creating a repository on GitHub. Each push adds a commit with only your
        changed files so you can browse earlier versions on GitHub.
      </p>
      <p class="mt-2 text-xs text-zinc-600">
        Repository status:
        <span class={github_repo_status_class(@github_repo_status)}>
          {Ide.GitHub.Repositories.status_label(@github_repo_status)}
        </span>
        <button
          type="button"
          phx-click="refresh-github-repo-status"
          class="ml-2 text-blue-700 hover:underline"
        >
          Refresh
        </button>
      </p>
      <div class="mt-3 grid gap-3 md:grid-cols-3">
        <label class="text-xs">
          <span class="mb-1 block font-medium text-zinc-700">Owner</span>
          <input
            type="text"
            name={@project_settings_form["github_owner"].name}
            value={@project_settings_form["github_owner"].value}
            class="w-full rounded border border-zinc-300 px-2 py-1.5"
            placeholder="leave blank for your GitHub user"
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
      <fieldset class="mt-3">
        <legend class="text-xs font-medium text-zinc-700">Repository visibility</legend>
        <p class="mt-2 text-xs text-zinc-600">
          GitHub access is limited to public repositories. New repositories are created as public.
        </p>
        <input
          type="hidden"
          name={@project_settings_form["github_visibility"].name}
          value="public"
        />
      </fieldset>
      <div
        :if={@github_connected? and @github_repo_status == :not_found}
        class="mt-3 flex flex-wrap gap-2"
      >
        <button
          type="button"
          phx-click="create-github-repository"
          disabled={@github_create_status == :running or @github_push_status == :running}
          class={github_action_button_class(@github_create_status == :running)}
        >
          {if @github_create_status == :running, do: "Creating…", else: "Create repository"}
        </button>
        <button
          type="button"
          phx-click="create-github-repository-and-push"
          disabled={@github_create_status == :running or @github_push_status == :running}
          class={github_action_button_class(@github_push_status == :running)}
        >
          {if @github_push_status == :running, do: "Creating and pushing…", else: "Create repository & push snapshot"}
        </button>
      </div>
    </section>
    """
  end

  @spec settings_pane?(settings_pane() | atom()) :: boolean()
  def settings_pane?(pane), do: pane in @settings_panes

  @spec settings_tab_class(settings_pane() | atom(), settings_pane() | atom()) :: String.t()
  def settings_tab_class(active, tab) when active == tab,
    do: "rounded bg-blue-100 px-3 py-1.5 text-blue-800"

  def settings_tab_class(_active, _tab), do: "rounded bg-zinc-100 px-3 py-1.5 text-zinc-700"

  defp release_metadata_intro(:public_pebble),
    do:
      "Version auto-increments after a successful publish submit. You can also edit it manually here."

  defp release_metadata_intro(:public_custom),
    do:
      "Version and release notes for exports and PBW download. App Store listing sync is not available in this deployment."

  defp release_metadata_intro(_), do: "Version and release metadata used when preparing a release."

  defp settings_intro(:settings),
    do: "Release metadata for publish and App Store listing sync."

  defp settings_intro(:settings_store), do: "Listing icons and optional AI-generated store graphics."
  defp settings_intro(:settings_github), do: "Repository linkage and snapshot push."
  defp settings_intro(_), do: "Configure project settings."

  @spec status_label(flow_status() | atom()) :: String.t()
  defp status_label(:idle), do: "idle"
  defp status_label(:running), do: "running"
  defp status_label(:ok), do: "ok"
  defp status_label(:error), do: "error"
  defp status_label(_), do: "unknown"

  @spec push_status_class(flow_status() | atom()) :: String.t()
  defp push_status_class(:ok), do: "text-emerald-700"
  defp push_status_class(:error), do: "text-rose-700"
  defp push_status_class(:running), do: "text-blue-700"
  defp push_status_class(_), do: "text-zinc-700"

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

  defp github_repo_status_class(:exists), do: "font-medium text-emerald-700"
  defp github_repo_status_class(:not_found), do: "font-medium text-amber-700"
  defp github_repo_status_class(:checking), do: "font-medium text-blue-700"
  defp github_repo_status_class(:forbidden), do: "font-medium text-rose-700"
  defp github_repo_status_class(:unconfigured), do: "font-medium text-zinc-600"
  defp github_repo_status_class({:error, _}), do: "font-medium text-rose-700"
  defp github_repo_status_class(_), do: "font-medium text-zinc-700"

  defp github_action_button_class(true),
    do: "cursor-not-allowed rounded border border-zinc-200 bg-zinc-100 px-3 py-1.5 text-xs text-zinc-500"

  defp github_action_button_class(false),
    do:
      "rounded border border-zinc-300 bg-white px-3 py-1.5 text-xs font-medium text-zinc-800 hover:bg-zinc-50"

  defp store_listing_sync_button_class(true),
    do: "cursor-not-allowed rounded bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white opacity-60"

  defp store_listing_sync_button_class(false),
    do: "rounded bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-blue-700"

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
