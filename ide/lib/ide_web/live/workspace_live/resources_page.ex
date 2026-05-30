defmodule IdeWeb.WorkspaceLive.ResourcesPage do
  @moduledoc false
  use IdeWeb, :html

  import IdeWeb.WorkspaceLive.ProjectSettingsPage, only: [settings_nav: 1]

  alias Phoenix.LiveView.Rendered

  @type assigns :: map()
  @type rendered :: Rendered.t()

  @spec render(assigns()) :: rendered()
  def render(assigns) do
    ~H"""
    <section
      :if={@pane == :resources}
      class="grid min-h-0 flex-1 grid-cols-1 gap-4 lg:grid-cols-[24rem_minmax(0,1fr)]"
    >
      <aside class="min-h-0 overflow-auto rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
        <.settings_nav pane={@pane} project={@project} class="mb-4" />
        <h2 class="text-base font-semibold">Resources</h2>
        <p class="mt-1 text-sm text-zinc-600">
          Upload bitmap, vector, and font assets used by the watch app. Bitmaps can include separate
          monochrome and color files; Pebble picks the matching variant per watch model at build time.
          A generated <span class="font-mono">Pebble.Ui.Resources</span>
          module is refreshed automatically.
        </p>

        <div class="mt-4 space-y-5">
          <div class="rounded border border-zinc-200 bg-zinc-50 p-3">
            <h3 class="text-sm font-semibold text-zinc-700">New bitmap</h3>
            <.form
              for={%{}}
              phx-change="validate-resource-upload"
              phx-submit="upload-bitmap-resource"
              class="mt-2 space-y-2"
            >
              <.live_file_input upload={@uploads.bitmap} class="block w-full text-sm text-zinc-800" />
              <label class="block text-xs text-zinc-600">
                <span class="font-medium text-zinc-700">Assign as</span>
                <select
                  name="color_mode"
                  class="mt-1 block w-full rounded border border-zinc-300 bg-white px-2 py-1 text-sm"
                >
                  <option value="">Universal (all platforms)</option>
                  <option value="BlackWhite">Monochrome (~bw)</option>
                  <option value="Color">Color (~color)</option>
                </select>
              </label>
              <.button type="submit" disabled={@uploads.bitmap.entries == []}>Upload bitmap</.button>
            </.form>
            <p :if={@bitmap_upload_output} class="mt-2 text-xs text-zinc-600">
              {@bitmap_upload_output}
            </p>
          </div>

          <div class="rounded border border-zinc-200 bg-zinc-50 p-3">
            <h3 class="text-sm font-semibold text-zinc-700">Vector uploads</h3>
            <p class="mt-1 text-xs text-zinc-500">
              Upload `.pdc` files or compatible `.svg` assets. SVG supports hex colors (`#RRGGBB`),
              CSS color names, and Pebble palette names (`vividCerulean`, `black`, etc.), plus
              supported elements (`path`, `polygon`, `circle`, etc.).
            </p>
            <.form
              for={%{}}
              phx-change="validate-resource-upload"
              phx-submit="upload-vector-resource"
              class="mt-2 space-y-2"
            >
              <.live_file_input upload={@uploads.vector} class="block w-full text-sm text-zinc-800" />
              <.button type="submit" disabled={@uploads.vector.entries == []}>Upload vector</.button>
            </.form>
            <p :if={@vector_upload_output} class="mt-2 text-xs text-zinc-600">
              {@vector_upload_output}
            </p>
          </div>

          <div class="rounded border border-zinc-200 bg-zinc-50 p-3">
            <h3 class="text-sm font-semibold text-zinc-700">Font uploads</h3>
            <.form
              for={%{}}
              phx-change="validate-resource-upload"
              phx-submit="upload-font-resource"
              class="mt-2 space-y-2"
            >
              <.live_file_input upload={@uploads.font} class="block w-full text-sm text-zinc-800" />
              <.button type="submit" disabled={@uploads.font.entries == []}>Upload font</.button>
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

              <div :if={bmp.has_legacy} class="mb-3 rounded border border-zinc-200 bg-white p-2">
                <p class="font-medium text-zinc-700">Universal</p>
                <img
                  :if={bmp.legacy_preview_data_url}
                  src={bmp.legacy_preview_data_url}
                  alt={bmp.filename}
                  class="mx-auto my-2 max-h-20 object-contain"
                />
                <p class="truncate font-mono text-zinc-600">{bmp.filename}</p>
              </div>

              <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <div
                  :for={slot <- bmp.variant_slots}
                  class="rounded border border-zinc-200 bg-white p-2"
                >
                  <p class="font-medium text-zinc-800">{slot.label}</p>
                  <p class="mt-0.5 text-[10px] leading-snug text-zinc-500">{slot.platforms}</p>
                  <img
                    :if={slot.preview_data_url}
                    src={slot.preview_data_url}
                    alt={slot.filename}
                    class="mx-auto my-2 max-h-20 object-contain"
                  />
                  <p :if={slot.filename} class="truncate font-mono text-zinc-600">{slot.filename}</p>
                  <p :if={slot.bytes} class="text-zinc-500">{slot.bytes} bytes</p>
                  <.form
                    for={%{}}
                    phx-change="validate-resource-upload"
                    phx-submit="upload-bitmap-resource"
                    class="mt-2 space-y-1"
                  >
                    <input type="hidden" name="ctor" value={bmp.ctor} />
                    <input type="hidden" name="color_mode" value={slot.color_mode} />
                    <.live_file_input
                      upload={@uploads.bitmap}
                      class="block w-full text-[11px] text-zinc-800"
                    />
                    <.button
                      type="submit"
                      class="w-full"
                      disabled={@uploads.bitmap.entries == []}
                    >
                      Upload {slot.label}
                    </.button>
                  </.form>
                  <button
                    :if={slot.filename}
                    type="button"
                    phx-click="clear-bitmap-variant"
                    phx-value-ctor={bmp.ctor}
                    phx-value-color_mode={slot.color_mode}
                    class="mt-1 w-full rounded bg-zinc-100 px-2 py-1 text-[11px] font-medium text-zinc-700 hover:bg-zinc-200"
                  >
                    Clear
                  </button>
                </div>
              </div>

              <p class="mt-2 text-zinc-500">resource id: {bmp.resource_id}</p>
            </article>
          </div>
        </section>

        <section class="rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
          <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">
            Vector graphics
          </h3>
          <div
            :if={@vector_resources == []}
            class="mt-3 rounded border border-dashed border-zinc-300 bg-zinc-50 p-4 text-sm text-zinc-600"
          >
            No vector resources uploaded yet.
          </div>
          <div
            :if={@vector_resources != []}
            class="mt-3 grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3"
          >
            <article
              :for={vector <- @vector_resources}
              class="rounded border border-zinc-200 bg-zinc-50 p-3 text-xs"
            >
              <div class="mb-2 flex items-center justify-between gap-2">
                <p class="font-mono font-semibold text-zinc-900">{vector.ctor}</p>
                <button
                  type="button"
                  phx-click="delete-vector-resource"
                  phx-value-ctor={vector.ctor}
                  class="rounded bg-rose-100 px-2 py-1 text-[11px] font-medium text-rose-800 hover:bg-rose-200"
                >
                  Delete
                </button>
              </div>
              <div
                :if={vector.preview_svg}
                class="mx-auto mb-2 flex max-h-24 items-center justify-center rounded border border-zinc-200 bg-white p-2"
              >
                {raw(vector.preview_svg)}
              </div>
              <p class="truncate font-mono text-zinc-700">{vector.filename}</p>
              <p class="text-zinc-500">{vector.kind_label} · {vector.bytes} bytes</p>
              <p :if={vector.sequence_label} class="text-zinc-500">{vector.sequence_label}</p>
              <p class="text-zinc-500">resource id: {vector.resource_id}</p>
            </article>
          </div>
        </section>

        <section class="rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
          <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">
            Source fonts
          </h3>
          <div
            :if={@font_sources == []}
            class="mt-3 rounded border border-dashed border-zinc-300 bg-zinc-50 p-4 text-sm text-zinc-600"
          >
            No source fonts uploaded yet.
          </div>
          <div
            :if={@font_sources != []}
            class="mt-3 grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3"
          >
            <article
              :for={source <- @font_sources}
              class="rounded border border-zinc-200 bg-zinc-50 p-3 text-xs"
            >
              <div class="mb-2 flex items-center justify-between gap-2">
                <p class="font-mono font-semibold text-zinc-900">{source.filename}</p>
                <button
                  type="button"
                  phx-click="delete-font-source"
                  phx-value-source-id={source.id}
                  class="rounded bg-rose-100 px-2 py-1 text-[11px] font-medium text-rose-800 hover:bg-rose-200"
                >
                  Delete source
                </button>
              </div>
              <p class="text-zinc-500">{source.mime} · {source.bytes} bytes</p>
              <.form for={%{}} as={:variant} phx-submit="add-font-variant" class="mt-3">
                <input type="hidden" name="variant[source_id]" value={source.id} />
                <button
                  type="submit"
                  class="rounded bg-blue-100 px-2 py-1 text-[11px] font-medium text-blue-800 hover:bg-blue-200"
                >
                  Add identifier
                </button>
              </.form>
            </article>
          </div>
        </section>

        <section class="rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
          <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">
            Font identifiers
          </h3>
          <div
            :if={@font_resources == []}
            class="mt-3 rounded border border-dashed border-zinc-300 bg-zinc-50 p-4 text-sm text-zinc-600"
          >
            No font identifiers defined yet.
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
              <p class="text-zinc-500">resource id: {font.resource_id}</p>
              <.form
                for={%{}}
                as={:variant}
                phx-submit="update-font-variant"
                class="mt-3 grid grid-cols-2 gap-2"
              >
                <input type="hidden" name="ctor" value={font.ctor} />
                <input type="hidden" name="variant[source_id]" value={font.source_id} />
                <label class="col-span-2 flex flex-col gap-1">
                  <span class="font-medium text-zinc-600">Identifier</span>
                  <input
                    name="variant[ctor]"
                    value={font.ctor}
                    class="rounded border border-zinc-300 px-2 py-1"
                  />
                </label>
                <label class="flex flex-col gap-1">
                  <span class="font-medium text-zinc-600">Size</span>
                  <input
                    name="variant[height]"
                    value={font.height}
                    inputmode="numeric"
                    class="rounded border border-zinc-300 px-2 py-1"
                  />
                </label>
                <label class="flex flex-col gap-1">
                  <span class="font-medium text-zinc-600">Tracking</span>
                  <input
                    name="variant[tracking_adjust]"
                    value={font.tracking_adjust}
                    inputmode="numeric"
                    class="rounded border border-zinc-300 px-2 py-1"
                  />
                </label>
                <label class="col-span-2 flex flex-col gap-1">
                  <span class="font-medium text-zinc-600">Characters</span>
                  <input
                    name="variant[characters]"
                    value={font.characters}
                    class="rounded border border-zinc-300 px-2 py-1"
                  />
                </label>
                <label class="flex flex-col gap-1">
                  <span class="font-medium text-zinc-600">Compatibility</span>
                  <select
                    name="variant[compatibility]"
                    class="rounded border border-zinc-300 px-2 py-1"
                  >
                    <option value="2.7" selected={font.compatibility == "2.7"}>
                      2.7 and earlier
                    </option>
                    <option value="latest" selected={font.compatibility == "latest"}>Latest</option>
                  </select>
                </label>
                <fieldset class="flex flex-col gap-1">
                  <legend class="font-medium text-zinc-600">Platforms</legend>
                  <div class="grid grid-cols-2 gap-1">
                    <label :for={platform <- font_platform_options()} class="flex items-center gap-1">
                      <input
                        type="checkbox"
                        name="variant[target_platforms][]"
                        value={platform}
                        checked={platform in (font.target_platforms || [])}
                      />
                      <span>{platform}</span>
                    </label>
                  </div>
                </fieldset>
                <button
                  type="submit"
                  class="col-span-2 rounded bg-zinc-200 px-2 py-1 text-[11px] font-medium text-zinc-800 hover:bg-zinc-300"
                >
                  Save identifier
                </button>
              </.form>
            </article>
          </div>
        </section>
      </main>
    </section>
    """
  end

  defp font_platform_options do
    ["aplite", "basalt", "chalk", "diorite", "emery", "flint", "gabbro"]
  end
end
