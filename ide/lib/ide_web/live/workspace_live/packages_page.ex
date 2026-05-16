defmodule IdeWeb.WorkspaceLive.PackagesPage do
  @moduledoc false
  use IdeWeb, :html

  alias Ide.Markdown
  alias Ide.Packages

  @spec render(term()) :: term()
  def render(assigns) do
    ~H"""
    <section
      :if={@pane == :packages}
      class="grid min-h-0 flex-1 grid-cols-1 gap-4 lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)] xl:grid-cols-[minmax(0,24rem)_minmax(0,1fr)]"
    >
      <aside class="min-h-0 overflow-auto rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
        <nav class="mb-4 flex flex-wrap gap-2 border-b border-zinc-200 pb-2 text-sm">
          <.link
            patch={~p"/projects/#{@project.slug}/settings"}
            class={project_settings_tab_class(@pane, :settings)}
          >
            Settings
          </.link>
          <.link
            patch={~p"/projects/#{@project.slug}/resources"}
            class={project_settings_tab_class(@pane, :resources)}
          >
            Resources
          </.link>
          <.link
            patch={~p"/projects/#{@project.slug}/packages"}
            class={project_settings_tab_class(@pane, :packages)}
          >
            Packages
          </.link>
        </nav>
        <h2 class="text-base font-semibold">Dependencies</h2>
        <p class="mt-1 text-sm text-zinc-600">
          Manage <span class="font-mono">elm.json</span>
          for the <span class="font-mono">watch</span>
          or <span class="font-mono">phone</span>
          (companion) app only — not <span class="font-mono">protocol</span>. Add packages from Catalog search (Inspect, then add). Required runtime packages cannot be removed.
        </p>

        <.form
          for={to_form(%{"source_root" => @packages_target_root}, as: :packages_target)}
          phx-change="packages-set-target-root"
          class="mt-4"
        >
          <.input
            field={
              to_form(%{"source_root" => @packages_target_root}, as: :packages_target)[:source_root]
            }
            type="select"
            label="elm.json target root"
            options={Enum.map(Packages.package_elm_json_roots(@project), &{&1, &1})}
          />
        </.form>

        <div class="mt-4">
          <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-500">Direct</h3>
          <ul class="mt-2 max-h-56 space-y-1 overflow-auto text-sm">
            <li
              :for={dep <- @project_elm_direct}
              class="flex flex-wrap items-center justify-between gap-1 rounded border border-zinc-200 bg-zinc-50 px-2 py-1.5"
            >
              <button
                type="button"
                phx-click="packages-dep-select"
                phx-value-package={dep.name}
                phx-value-version={dep.version}
                class="text-left font-mono text-xs text-zinc-900 hover:underline"
              >
                {dep.name} <span class="text-zinc-500">{dep.version}</span>
              </button>
              <span class="flex items-center gap-1">
                <% dep_compat = dependency_compatibility(dep.name, @packages_target_root) %>
                <span class={compatibility_badge_class(dep_compat)}>
                  {compatibility_badge_label(dep_compat)}
                </span>
                <span
                  :if={dep.builtin?}
                  title="Required packages cannot be removed from elm.json."
                  class="rounded bg-violet-100 px-1.5 py-0.5 text-[10px] font-medium text-violet-800"
                >
                  Required
                </span>
                <span
                  :if={!dep.builtin? and dep[:used?]}
                  title="This package is imported by current Elm source files."
                  class="rounded bg-sky-100 px-1.5 py-0.5 text-[10px] font-medium text-sky-800"
                >
                  Used
                </span>
                <span
                  :if={!dep.builtin? and is_nil(dep[:used?])}
                  title="Checking whether current Elm source files import this package."
                  class="rounded bg-zinc-100 px-1.5 py-0.5 text-[10px] font-medium text-zinc-600"
                >
                  Checking
                </span>
                <button
                  :if={!dep.builtin? and dep[:used?] == false}
                  type="button"
                  phx-click="packages-remove"
                  phx-value-package={dep.name}
                  data-confirm={"Remove #{dep.name} from elm.json?"}
                  class="rounded bg-rose-50 px-1.5 py-0.5 text-[10px] font-medium text-rose-800 hover:bg-rose-100"
                >
                  Remove
                </button>
              </span>
            </li>
            <li :if={@project_elm_direct == []} class="text-sm text-zinc-500">
              No direct dependencies.
            </li>
          </ul>
        </div>

        <div class="mt-4">
          <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-500">Indirect</h3>
          <ul class="mt-2 max-h-48 space-y-1 overflow-auto text-sm">
            <li
              :for={dep <- @project_elm_indirect}
              class="rounded border border-zinc-100 bg-white px-2 py-1.5"
            >
              <div class="flex items-center justify-between gap-2">
                <button
                  type="button"
                  phx-click="packages-dep-select"
                  phx-value-package={dep.name}
                  phx-value-version={dep.version}
                  class="w-full text-left font-mono text-xs text-zinc-800 hover:underline"
                >
                  {dep.name} <span class="text-zinc-500">{dep.version}</span>
                </button>
                <% dep_compat = dependency_compatibility(dep.name, @packages_target_root) %>
                <span class={compatibility_badge_class(dep_compat)}>
                  {compatibility_badge_label(dep_compat)}
                </span>
              </div>
            </li>
            <li :if={@project_elm_indirect == []} class="text-sm text-zinc-500">None resolved.</li>
          </ul>
        </div>

        <p :if={@packages_last_add_result} class="mt-4 text-xs text-zinc-600">
          Last add: {@packages_last_add_result.package} {@packages_last_add_result.selected_version} at {@packages_last_add_result.source_root}/elm.json
        </p>
      </aside>

      <div class="flex min-h-0 flex-1 flex-col overflow-hidden">
        <div class="flex min-h-0 flex-1 flex-col gap-4 overflow-hidden rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
          <div class="shrink-0">
            <h2 class="text-base font-semibold">Catalog search</h2>
            <p class="mt-1 text-sm text-zinc-600">
              {catalog_search_description(@packages_target_root)}
            </p>

            <.form
              for={to_form(%{"query" => @packages_query}, as: :packages_search)}
              id="packages-search-form"
              phx-change="packages-search"
              phx-submit="packages-search"
              class="mt-4"
            >
              <.input
                field={to_form(%{"query" => @packages_query}, as: :packages_search)[:query]}
                type="text"
                label="Search packages"
                placeholder="Search by package name or description…"
                phx-debounce="300"
              />
            </.form>

            <p class="mt-2 text-xs text-zinc-500">
              <%= if @packages_search_busy do %>
                <span class="font-medium text-zinc-700">
                  {@packages_search_progress || "Searching…"}
                </span>
              <% else %>
                Results: {@packages_search_total}
              <% end %>
            </p>
          </div>

          <div class="grid min-h-0 flex-1 grid-cols-1 gap-4 overflow-hidden lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
            <div class="flex min-h-[14rem] flex-col gap-3 overflow-hidden lg:min-h-0">
              <ul class="min-h-0 flex-1 space-y-2 overflow-auto rounded border border-zinc-200 bg-zinc-50 p-2 text-sm">
                <li
                  :for={pkg <- @packages_search_results}
                  class="rounded border border-zinc-200 bg-white p-3"
                >
                  <% compat = package_compatibility(pkg, @packages_target_root) %>
                  <div class="flex items-start justify-between gap-3">
                    <div>
                      <p class="font-mono font-semibold text-zinc-900">
                        {pkg[:name] || pkg["name"]}
                      </p>
                      <p :if={pkg[:summary] || pkg["summary"]} class="mt-1 text-zinc-600">
                        {pkg[:summary] || pkg["summary"]}
                      </p>
                      <p class="mt-1 text-xs text-zinc-500">
                        latest {pkg[:version] || pkg["version"] || "unknown"} · {pkg[:license] ||
                          pkg["license"] || "license unknown"}
                      </p>
                      <p class="mt-1">
                        <span class={compatibility_badge_class(compat)}>
                          {compatibility_badge_label(compat)}
                        </span>
                      </p>
                    </div>
                    <% pkg_name = pkg[:name] || pkg["name"] %>
                    <% inspect_busy? = @packages_inspect_loading == pkg_name %>
                    <button
                      type="button"
                      phx-click="packages-select"
                      phx-value-package={pkg_name}
                      disabled={inspect_busy?}
                      class={[
                        "inline-flex min-w-[5.5rem] items-center justify-center gap-1.5 rounded px-2 py-1 text-xs font-medium",
                        if(inspect_busy?,
                          do: "cursor-wait bg-zinc-200 text-zinc-600",
                          else: "bg-zinc-100 text-zinc-800 hover:bg-zinc-200"
                        )
                      ]}
                    >
                      <span
                        :if={inspect_busy?}
                        class="h-3 w-3 shrink-0 animate-spin rounded-full border-2 border-zinc-400 border-t-zinc-700"
                        aria-hidden="true"
                      />
                      {if inspect_busy?, do: "Loading…", else: "Inspect"}
                    </button>
                  </div>
                </li>
                <li :if={@packages_search_results == []} class="text-zinc-500">
                  <%= if @packages_query == "" do %>
                    Type to search the package catalog.
                  <% else %>
                    No packages matched your search.
                  <% end %>
                </li>
              </ul>

              <div
                :if={@packages_selected}
                class="shrink-0 rounded border border-zinc-200 bg-zinc-50 p-4"
              >
                <p class="text-xs font-semibold uppercase tracking-wide text-zinc-500">
                  Selected package
                </p>
                <p class="mt-1 font-mono text-sm text-zinc-900">{@packages_selected}</p>
                <p
                  :if={@packages_details && @packages_details[:summary]}
                  class="mt-1 text-sm text-zinc-600"
                >
                  {@packages_details[:summary]}
                </p>
                <p class="mt-1 text-xs text-zinc-500">
                  Latest: {(@packages_details && @packages_details[:latest_version]) || "unknown"} ·
                  Known versions: {length(@packages_versions)}
                </p>
                <% selected_compat =
                  package_compatibility(@packages_details || %{}, @packages_target_root) %>
                <p class="mt-2">
                  <span class={compatibility_badge_class(selected_compat)}>
                    {compatibility_badge_label(selected_compat)}
                  </span>
                </p>
                <p
                  :if={compatibility_reason(selected_compat) != nil}
                  class="mt-1 text-xs text-zinc-600"
                >
                  {compatibility_reason(selected_compat)}
                </p>

                <div
                  :if={@packages_preview}
                  class="mt-3 rounded border border-zinc-200 bg-white p-2 text-xs"
                >
                  <p class="font-semibold text-zinc-800">Dependency preview</p>
                  <p class="mt-1 font-mono text-zinc-700">
                    {@packages_preview.section}.{@packages_preview.scope}[{@packages_preview.package}]
                  </p>
                  <p class="mt-1 text-zinc-600">
                    {if @packages_preview.existing_constraint,
                      do: "from #{@packages_preview.existing_constraint}",
                      else: "new dependency"}
                    {" "}to {@packages_preview.selected_version}
                  </p>
                </div>

                <.button phx-click="packages-add" phx-value-package={@packages_selected} class="mt-3">
                  Add package to elm.json
                </.button>
              </div>
            </div>

            <div class="flex min-h-[14rem] flex-col overflow-hidden rounded-lg border border-zinc-200 bg-zinc-50/80 p-4 lg:min-h-0">
              <h3 class="shrink-0 text-sm font-semibold text-zinc-800">Documentation</h3>
              <p
                :if={@packages_dep_docs_package}
                class="mt-1 shrink-0 font-mono text-xs text-zinc-700"
              >
                {@packages_dep_docs_package}
                <span class="text-zinc-500">{@packages_dep_docs_version}</span>
                <span class="text-zinc-500"> (locked)</span>
              </p>
              <p
                :if={@packages_selected && !@packages_dep_docs_package}
                class="mt-1 shrink-0 font-mono text-xs text-zinc-700"
              >
                {@packages_selected} <span class="text-zinc-500">(catalog)</span>
              </p>
              <p
                :if={!@packages_selected && !@packages_dep_docs_package}
                class="mt-1 shrink-0 text-xs text-zinc-500"
              >
                Inspect a catalog result or pick a dependency on the left.
              </p>
              <div class="ide-readme-markdown mt-3 min-h-0 flex-1 overflow-auto rounded border border-zinc-200 bg-white p-3 text-xs">
                <%= if @packages_dep_readme || @packages_readme do %>
                  {raw(Markdown.readme_to_html(@packages_dep_readme || @packages_readme || ""))}
                <% else %>
                  <p class="text-sm text-zinc-500">
                    README will appear here when you inspect a package or open a dependency from the Dependencies list.
                  </p>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  @spec project_settings_tab_class(term(), term()) :: String.t()
  defp project_settings_tab_class(active, tab) when active == tab,
    do: "rounded bg-blue-100 px-3 py-1.5 text-blue-800"

  defp project_settings_tab_class(_active, _tab),
    do: "rounded bg-zinc-100 px-3 py-1.5 text-zinc-700"

  @spec package_compatibility(term(), term()) :: term()
  defp package_compatibility(entry, target_root) when is_map(entry) do
    Map.get(entry, :compatibility) ||
      Map.get(entry, "compatibility") ||
      entry
      |> Map.get(:name, Map.get(entry, "name"))
      |> case do
        name when is_binary(name) -> dependency_compatibility(name, target_root)
        _ -> %{status: "unknown", reason_code: "unknown", message: "Compatibility unknown."}
      end
  end

  defp package_compatibility(_, _),
    do: %{status: "unknown", reason_code: "unknown", message: "Compatibility unknown."}

  defp dependency_compatibility(package, "phone"),
    do: Packages.compatibility_for_package(package, platform_target: :phone)

  defp dependency_compatibility(package, _target_root),
    do: Packages.compatibility_for_package(package, platform_target: :watch)

  @spec catalog_search_description(term()) :: String.t()
  defp catalog_search_description("phone") do
    "Browse packages like on package.elm-lang.org, then add compatible versions to the companion app elm.json. The catalog marks compatibility for the selected target so you can avoid packages that do not fit the phone companion runtime."
  end

  defp catalog_search_description(_target_root) do
    "Browse packages like on package.elm-lang.org, then add compatible versions to the watch app elm.json. The catalog hides packages that pull in browser or DOM dependencies, so not everything on the registry appears here — only what fits a Pebble watch app."
  end

  @spec compatibility_badge_label(term()) :: term()
  defp compatibility_badge_label(%{status: "blocked"}), do: "Blocked"
  defp compatibility_badge_label(%{status: "partial"}), do: "Partial"
  defp compatibility_badge_label(%{status: "supported"}), do: "Supported"
  defp compatibility_badge_label(_), do: "Unknown"

  @spec compatibility_badge_class(term()) :: term()
  defp compatibility_badge_class(%{status: "blocked"}),
    do: "rounded bg-rose-100 px-1.5 py-0.5 text-[10px] font-medium text-rose-800"

  defp compatibility_badge_class(%{status: "partial"}),
    do: "rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-medium text-amber-800"

  defp compatibility_badge_class(%{status: "supported"}),
    do: "rounded bg-emerald-100 px-1.5 py-0.5 text-[10px] font-medium text-emerald-800"

  defp compatibility_badge_class(_),
    do: "rounded bg-zinc-100 px-1.5 py-0.5 text-[10px] font-medium text-zinc-700"

  @spec compatibility_reason(term()) :: term()
  defp compatibility_reason(%{message: message}) when is_binary(message) and message != "",
    do: message

  defp compatibility_reason(_), do: nil
end
