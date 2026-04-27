defmodule IdeWeb.WorkspaceLive.ResourcesPage do
  @moduledoc false
  use IdeWeb, :html

  @spec render(term()) :: term()
  def render(assigns) do
    ~H"""
      <section
        :if={@pane == :resources}
        class="grid min-h-0 flex-1 grid-cols-1 gap-4 lg:grid-cols-[24rem_minmax(0,1fr)]"
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
          <h2 class="text-base font-semibold">Resources</h2>
          <p class="mt-1 text-sm text-zinc-600">
            Upload bitmap and font assets used by the watch app. A generated
            <span class="font-mono">Pebble.Ui.Resources</span>
            module is refreshed automatically.
          </p>

          <div class="mt-4 space-y-5">
            <div class="rounded border border-zinc-200 bg-zinc-50 p-3">
              <h3 class="text-sm font-semibold text-zinc-700">Bitmap uploads</h3>
              <.form for={%{}} phx-submit="upload-bitmap-resource" class="mt-2 space-y-2">
                <.live_file_input upload={@uploads.bitmap} class="block w-full text-sm text-zinc-800" />
                <.button type="submit">Upload bitmap</.button>
              </.form>
              <p :if={@bitmap_upload_output} class="mt-2 text-xs text-zinc-600">
                {@bitmap_upload_output}
              </p>
            </div>

            <div class="rounded border border-zinc-200 bg-zinc-50 p-3">
              <h3 class="text-sm font-semibold text-zinc-700">Font uploads</h3>
              <.form for={%{}} phx-submit="upload-font-resource" class="mt-2 space-y-2">
                <.live_file_input upload={@uploads.font} class="block w-full text-sm text-zinc-800" />
                <.button type="submit">Upload font</.button>
              </.form>
              <p :if={@font_upload_output} class="mt-2 text-xs text-zinc-600">
                {@font_upload_output}
              </p>
            </div>
          </div>
        </aside>

        <main class="grid min-h-0 grid-cols-1 gap-4 overflow-auto">
          <section class="rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
            <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">
              Available bitmaps
            </h3>
            <div
              :if={@bitmap_resources == []}
              class="mt-3 rounded border border-dashed border-zinc-300 bg-zinc-50 p-4 text-sm text-zinc-600"
            >
              No bitmap resources uploaded yet.
            </div>
            <div
              :if={@bitmap_resources != []}
              class="mt-3 grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3"
            >
              <article
                :for={bmp <- @bitmap_resources}
                class="rounded border border-zinc-200 bg-zinc-50 p-3 text-xs"
              >
                <div class="mb-2 flex items-center justify-between gap-2">
                  <p class="font-mono font-semibold text-zinc-900">{bmp.ctor}</p>
                  <button
                    type="button"
                    phx-click="delete-bitmap-resource"
                    phx-value-ctor={bmp.ctor}
                    class="rounded bg-rose-100 px-2 py-1 text-[11px] font-medium text-rose-800 hover:bg-rose-200"
                  >
                    Delete
                  </button>
                </div>
                <img
                  :if={bmp.preview_data_url}
                  src={bmp.preview_data_url}
                  alt={bmp.filename}
                  class="mx-auto mb-2 max-h-24 rounded border border-zinc-200 bg-white object-contain"
                />
                <p class="truncate font-mono text-zinc-700">{bmp.filename}</p>
                <p class="text-zinc-500">{bmp.mime} · {bmp.bytes} bytes</p>
                <p class="text-zinc-500">resource id: {bmp.resource_id}</p>
              </article>
            </div>
          </section>

          <section class="rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
            <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">
              Available fonts
            </h3>
            <div
              :if={@font_resources == []}
              class="mt-3 rounded border border-dashed border-zinc-300 bg-zinc-50 p-4 text-sm text-zinc-600"
            >
              No font resources uploaded yet.
            </div>
            <div
              :if={@font_resources != []}
              class="mt-3 grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3"
            >
              <article
                :for={font <- @font_resources}
                class="rounded border border-zinc-200 bg-zinc-50 p-3 text-xs"
              >
                <div class="mb-2 flex items-center justify-between gap-2">
                  <p class="font-mono font-semibold text-zinc-900">{font.ctor}</p>
                  <button
                    type="button"
                    phx-click="delete-font-resource"
                    phx-value-ctor={font.ctor}
                    class="rounded bg-rose-100 px-2 py-1 text-[11px] font-medium text-rose-800 hover:bg-rose-200"
                  >
                    Delete
                  </button>
                </div>
                <p class="truncate font-mono text-zinc-700">{font.filename}</p>
                <p class="text-zinc-500">{font.mime} · {font.bytes} bytes</p>
                <p class="text-zinc-500">resource id: {font.resource_id}</p>
              </article>
            </div>
          </section>
        </main>
      </section>
    """
  end

  @spec project_settings_tab_class(term(), term()) :: String.t()
  defp project_settings_tab_class(active, tab) when active == tab,
    do: "rounded bg-blue-100 px-3 py-1.5 text-blue-800"

  defp project_settings_tab_class(_active, _tab),
    do: "rounded bg-zinc-100 px-3 py-1.5 text-zinc-700"
end
