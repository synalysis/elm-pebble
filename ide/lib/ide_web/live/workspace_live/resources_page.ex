defmodule IdeWeb.WorkspaceLive.ResourcesPage do
  @moduledoc false
  use IdeWeb, :html

  import IdeWeb.WorkspaceLive.ProjectSettingsPage, only: [settings_nav: 1, settings_tab_class: 2]

  import IdeWeb.WorkspaceLive.ResourcesFlow,
    only: [filter_vectors: 2, format_upload_error: 1, upload_ready?: 1]

  alias Phoenix.LiveView.Rendered

  @type assigns :: map()
  @type rendered :: Rendered.t()

  @spec render(assigns()) :: rendered()
  def render(assigns) do
    assigns =
      assigns
      |> assign(:filtered_vectors, filtered_vectors_for_view(assigns))

    ~H"""
    <section
      :if={@pane == :resources}
      class="grid min-h-0 flex-1 grid-cols-1 gap-4 lg:grid-cols-[24rem_minmax(0,1fr)]"
    >
      <aside class="min-h-0 overflow-auto rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
        <.settings_nav pane={@pane} project={@project} class="mb-4" />
        <h2 class="text-base font-semibold">Resources</h2>
        <p class="mt-1 text-sm text-zinc-600">
          Upload assets for the watch app. Static bitmaps use PNG variants per platform; animated
          bitmaps are converted from GIF to APNG for Pebble playback. Vectors support PDC and SVG;
          sequences play as PDCS animations.
        </p>

        <.resources_nav resource_view={@resource_view} project={@project} class="mt-4" />

        <div class="mt-4">
          <.bitmap_upload_sidebar
            :if={@resource_view == "bitmaps-static"}
            uploads={@uploads}
            output={@bitmap_upload_output}
          />
          <.animation_upload_sidebar
            :if={@resource_view == "bitmaps-animated"}
            uploads={@uploads}
            output={@animation_upload_output}
          />
          <.vector_upload_sidebar
            :if={@resource_view in ["vectors-static", "vectors-animated"]}
            uploads={@uploads}
            output={@vector_upload_output}
            resource_view={@resource_view}
          />
          <.font_upload_sidebar
            :if={@resource_view == "fonts"}
            uploads={@uploads}
            output={@font_upload_output}
          />
          <.speaker_samples_upload_sidebar
            :if={@resource_view == "speaker-samples"}
            uploads={@uploads}
            output={@speaker_sample_upload_output}
          />
        </div>
      </aside>

      <main class="min-h-0 overflow-auto rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
        <.bitmaps_static_panel
          :if={@resource_view == "bitmaps-static"}
          bitmap_resources={@bitmap_resources}
          bitmap_resources_error={@bitmap_resources_error}
          uploads={@uploads}
        />
        <.animations_panel
          :if={@resource_view == "bitmaps-animated"}
          animation_resources={@animation_resources}
        />
        <.vectors_panel
          :if={@resource_view in ["vectors-static", "vectors-animated"]}
          vector_resources={@filtered_vectors}
          title={vector_panel_title(@resource_view)}
        />
        <.fonts_panel
          :if={@resource_view == "fonts"}
          font_sources={@font_sources}
          font_resources={@font_resources}
        />
        <.speaker_samples_panel
          :if={@resource_view == "speaker-samples"}
          speaker_samples={@speaker_samples}
        />
      </main>
    </section>
    """
  end

  attr :resource_view, :string, required: true
  attr :project, :map, required: true
  attr :class, :string, default: nil

  defp resources_nav(assigns) do
    ~H"""
    <nav class={[@class, "space-y-3"]}>
      <div class="flex flex-wrap gap-2 text-sm">
        <.link
          patch={~p"/projects/#{@project.slug}/resources/bitmaps-static"}
          class={resource_family_class(@resource_view, "bitmaps")}
        >
          Bitmaps
        </.link>
        <.link
          patch={~p"/projects/#{@project.slug}/resources/vectors-static"}
          class={resource_family_class(@resource_view, "vectors")}
        >
          Vectors
        </.link>
        <.link
          patch={~p"/projects/#{@project.slug}/resources/fonts"}
          class={settings_tab_class(@resource_view, "fonts")}
        >
          Fonts
        </.link>
        <.link
          patch={~p"/projects/#{@project.slug}/resources/speaker-samples"}
          class={settings_tab_class(@resource_view, "speaker-samples")}
        >
          Speaker samples
        </.link>
      </div>
      <div
        :if={resource_family(@resource_view) in ["bitmaps", "vectors"]}
        class="flex flex-wrap gap-2 text-sm"
      >
        <.link
          patch={resource_static_path(@project.slug, @resource_view)}
          class={resource_subtab_class(@resource_view, :static)}
        >
          Static
        </.link>
        <.link
          patch={resource_animated_path(@project.slug, @resource_view)}
          class={resource_subtab_class(@resource_view, :animated)}
        >
          Animated
        </.link>
      </div>
    </nav>
    """
  end

  attr :uploads, :map, required: true
  attr :output, :string, default: nil

  defp bitmap_upload_sidebar(assigns) do
    ~H"""
    <div class="rounded border border-zinc-200 bg-zinc-50 p-3">
      <h3 class="text-sm font-semibold text-zinc-700">Bitmap file</h3>
      <p class="mt-1 text-xs text-zinc-500">
        PNG (and other static raster formats). Color uploads automatically get a monochrome (~bw)
        preview when ImageMagick is available. Use the Animated tab for GIF sequences.
      </p>
      <.form
        for={%{}}
        id="bitmap-upload-form"
        phx-change="validate-resource-upload"
        phx-submit="upload-bitmap-resource"
        multipart
        class="mt-2 space-y-2"
      >
        <div class="sr-only" aria-hidden="true">
          <.live_file_input upload={@uploads.bitmap} />
        </div>
        <label
          for={@uploads.bitmap.ref}
          class="flex cursor-pointer items-center justify-center rounded border border-zinc-300 bg-white px-3 py-2 text-sm font-medium text-zinc-800 hover:bg-zinc-100"
        >
          Choose file
        </label>
        <p :if={@uploads.bitmap.entries != []} class="text-xs text-zinc-600">
          {resource_upload_status(@uploads.bitmap)}
        </p>
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
        <.button type="submit" disabled={not upload_ready?(@uploads.bitmap)}>Upload bitmap</.button>
      </.form>
      <p :if={@output} class="mt-2 text-xs text-zinc-600">{@output}</p>
    </div>
    """
  end

  attr :uploads, :map, required: true
  attr :output, :string, default: nil

  defp animation_upload_sidebar(assigns) do
    ~H"""
    <div class="rounded border border-zinc-200 bg-zinc-50 p-3">
      <h3 class="text-sm font-semibold text-zinc-700">Animation file</h3>
      <p class="mt-1 text-xs text-zinc-500">
        Upload a GIF to convert to APNG, or an existing APNG (.png). Requires
        <span class="font-mono">gif2apng</span>
        on the IDE host for GIF imports.
      </p>
      <.form
        for={%{}}
        id="animation-upload-form"
        phx-change="validate-resource-upload"
        phx-submit="upload-animation-resource"
        multipart
        class="mt-2 space-y-2"
      >
        <div class="sr-only" aria-hidden="true">
          <.live_file_input upload={@uploads.animation} />
        </div>
        <label
          for={@uploads.animation.ref}
          class="flex cursor-pointer items-center justify-center rounded border border-zinc-300 bg-white px-3 py-2 text-sm font-medium text-zinc-800 hover:bg-zinc-100"
        >
          Choose file
        </label>
        <p :if={@uploads.animation.entries != []} class="text-xs text-zinc-600">
          {resource_upload_status(@uploads.animation)}
        </p>
        <%= for err <- upload_errors(@uploads.animation) do %>
          <p class="text-xs text-rose-700">{format_upload_error(err)}</p>
        <% end %>
        <.button type="submit" disabled={not upload_ready?(@uploads.animation)}>
          Upload animation
        </.button>
      </.form>
      <p :if={@output} class="mt-2 text-xs text-zinc-600">{@output}</p>
    </div>
    """
  end

  attr :uploads, :map, required: true
  attr :output, :string, default: nil
  attr :resource_view, :string, required: true

  defp vector_upload_sidebar(assigns) do
    ~H"""
    <div class="rounded border border-zinc-200 bg-zinc-50 p-3">
      <h3 class="text-sm font-semibold text-zinc-700">Vector uploads</h3>
      <p class="mt-1 text-xs text-zinc-500">
        {if @resource_view == "vectors-animated",
          do: "Upload PDCS sequences or SVG sources that compile to animated PDC.",
          else: "Upload static PDCI images or compatible SVG assets."}
      </p>
      <.form
        for={%{}}
        phx-change="validate-resource-upload"
        phx-submit="upload-vector-resource"
        multipart
        class="mt-2 space-y-2"
      >
        <div class="sr-only" aria-hidden="true">
          <.live_file_input upload={@uploads.vector} />
        </div>
        <label
          for={@uploads.vector.ref}
          class="flex cursor-pointer items-center justify-center rounded border border-zinc-300 bg-white px-3 py-2 text-sm font-medium text-zinc-800 hover:bg-zinc-100"
        >
          Choose file
        </label>
        <.button type="submit" disabled={not upload_ready?(@uploads.vector)}>Upload vector</.button>
      </.form>
      <p :if={@output} class="mt-2 text-xs text-zinc-600">{@output}</p>
    </div>
    """
  end

  attr :uploads, :map, required: true
  attr :output, :string, default: nil

  defp font_upload_sidebar(assigns) do
    ~H"""
    <div class="rounded border border-zinc-200 bg-zinc-50 p-3">
      <h3 class="text-sm font-semibold text-zinc-700">Font uploads</h3>
      <.form
        for={%{}}
        phx-change="validate-resource-upload"
        phx-submit="upload-font-resource"
        multipart
        class="mt-2 space-y-2"
      >
        <div class="sr-only" aria-hidden="true">
          <.live_file_input upload={@uploads.font} />
        </div>
        <label
          for={@uploads.font.ref}
          class="flex cursor-pointer items-center justify-center rounded border border-zinc-300 bg-white px-3 py-2 text-sm font-medium text-zinc-800 hover:bg-zinc-100"
        >
          Choose file
        </label>
        <.button type="submit" disabled={not upload_ready?(@uploads.font)}>Upload font</.button>
      </.form>
      <p :if={@output} class="mt-2 text-xs text-zinc-600">{@output}</p>
    </div>
    """
  end

  attr :uploads, :map, required: true
  attr :output, :string, default: nil

  defp speaker_samples_upload_sidebar(assigns) do
    ~H"""
    <div class="rounded border border-zinc-200 bg-zinc-50 p-3">
      <h3 class="text-sm font-semibold text-zinc-700">Speaker PCM uploads</h3>
      <p class="mt-1 text-xs text-zinc-500">
        Mono signed PCM (.pcm, .raw, .bin). Total size across samples is capped at 16 KiB.
      </p>
      <.form
        for={%{}}
        phx-change="validate-resource-upload"
        phx-submit="upload-speaker-sample-resource"
        multipart
        class="mt-2 space-y-2"
      >
        <div class="sr-only" aria-hidden="true">
          <.live_file_input upload={@uploads.speaker_sample} />
        </div>
        <label
          for={@uploads.speaker_sample.ref}
          class="flex cursor-pointer items-center justify-center rounded border border-zinc-300 bg-white px-3 py-2 text-sm font-medium text-zinc-800 hover:bg-zinc-100"
        >
          Choose file
        </label>
        <.button type="submit" disabled={not upload_ready?(@uploads.speaker_sample)}>
          Upload sample
        </.button>
      </.form>
      <p :if={@output} class="mt-2 text-xs text-zinc-600">{@output}</p>
    </div>
    """
  end

  attr :speaker_samples, :list, required: true

  defp speaker_samples_panel(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">Speaker samples</h3>
      <div
        :if={@speaker_samples == []}
        class="mt-3 rounded border border-dashed border-zinc-300 bg-zinc-50 p-4 text-sm text-zinc-600"
      >
        No speaker samples uploaded yet.
      </div>
      <div :if={@speaker_samples != []} class="mt-3 space-y-2">
        <article
          :for={sample <- @speaker_samples}
          class="rounded border border-zinc-200 bg-zinc-50 p-3 text-xs"
        >
          <div class="font-semibold text-zinc-800">{sample.ctor}</div>
          <div class="mt-1 text-zinc-600">
            id={sample.resource_id} · {sample.bytes} bytes · format={sample.format} · base MIDI={sample.base_midi_note}
          </div>
        </article>
      </div>
    </div>
    """
  end

  attr :bitmap_resources, :list, required: true
  attr :bitmap_resources_error, :string, default: nil
  attr :uploads, :map, required: true

  defp bitmaps_static_panel(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">Static bitmaps</h3>
      <p
        :if={@bitmap_resources_error}
        class="mt-2 rounded border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900"
      >
        {@bitmap_resources_error}
      </p>
      <div
        :if={@bitmap_resources == [] and is_nil(@bitmap_resources_error)}
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
            <.resource_base_name_form
              submit_event="update-bitmap-base-name"
              ctor={bmp.ctor}
              ctor_prefix={bmp.ctor_prefix}
              base_name={bmp.base_name}
            />
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
            <div :for={slot <- bmp.variant_slots} class="rounded border border-zinc-200 bg-white p-2">
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
              <label
                for={@uploads.bitmap.ref}
                class="mt-2 flex w-full cursor-pointer items-center justify-center rounded border border-zinc-300 bg-white px-2 py-1.5 text-[11px] font-medium text-zinc-800 hover:bg-zinc-100"
              >
                Choose file
              </label>
              <.form
                for={%{}}
                phx-change="validate-resource-upload"
                phx-submit="upload-bitmap-resource"
                class="mt-1"
              >
                <input type="hidden" name="ctor" value={bmp.ctor} />
                <input type="hidden" name="color_mode" value={slot.color_mode} />
                <.button type="submit" class="w-full" disabled={not upload_ready?(@uploads.bitmap)}>
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
    </div>
    """
  end

  attr :animation_resources, :list, required: true

  defp animations_panel(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">Animated bitmaps</h3>
      <div
        :if={@animation_resources == []}
        class="mt-3 rounded border border-dashed border-zinc-300 bg-zinc-50 p-4 text-sm text-zinc-600"
      >
        No animations uploaded yet. GIF files are converted to APNG for Pebble playback.
      </div>
      <div
        :if={@animation_resources != []}
        class="mt-3 grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3"
      >
        <article
          :for={anim <- @animation_resources}
          class="rounded border border-zinc-200 bg-zinc-50 p-3 text-xs"
        >
          <div class="mb-2 flex items-center justify-between gap-2">
            <.resource_base_name_form
              submit_event="update-animation-base-name"
              ctor={anim.ctor}
              ctor_prefix={anim.ctor_prefix}
              base_name={anim.base_name}
            />
            <button
              type="button"
              phx-click="delete-animation-resource"
              phx-value-ctor={anim.ctor}
              class="rounded bg-rose-100 px-2 py-1 text-[11px] font-medium text-rose-800 hover:bg-rose-200"
            >
              Delete
            </button>
          </div>
          <img
            :if={anim.preview_data_url}
            src={anim.preview_data_url}
            alt={anim.filename}
            class="mx-auto my-2 max-h-24 object-contain rounded border border-zinc-200 bg-white p-2"
          />
          <p class="truncate font-mono text-zinc-700">{anim.filename}</p>
          <p class="text-zinc-500">
            {anim.frame_count} frames · {anim.duration_ms} ms · {anim.width}×{anim.height}
          </p>
          <p :if={anim.loop_label} class="text-zinc-500">{anim.loop_label}</p>
          <p class="text-zinc-500">{anim.bytes} bytes · resource id: {anim.resource_id}</p>
        </article>
      </div>
    </div>
    """
  end

  attr :vector_resources, :list, required: true
  attr :title, :string, required: true

  defp vectors_panel(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">{@title}</h3>
      <div
        :if={@vector_resources == []}
        class="mt-3 rounded border border-dashed border-zinc-300 bg-zinc-50 p-4 text-sm text-zinc-600"
      >
        No vector resources in this category yet.
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
            <.resource_base_name_form
              submit_event="update-vector-base-name"
              ctor={vector.ctor}
              ctor_prefix={vector.ctor_prefix}
              base_name={vector.base_name}
            />
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
    </div>
    """
  end

  attr :font_sources, :list, required: true
  attr :font_resources, :list, required: true

  defp fonts_panel(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">Source fonts</h3>
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
      </div>

      <div>
        <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">Font identifiers</h3>
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
                <select name="variant[compatibility]" class="rounded border border-zinc-300 px-2 py-1">
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
      </div>
    </div>
    """
  end

  defp filtered_vectors_for_view(%{resource_view: "vectors-static", vector_resources: vectors}),
    do: filter_vectors(vectors, :static)

  defp filtered_vectors_for_view(%{resource_view: "vectors-animated", vector_resources: vectors}),
    do: filter_vectors(vectors, :animated)

  defp filtered_vectors_for_view(_), do: []

  defp vector_panel_title("vectors-static"), do: "Static vectors"
  defp vector_panel_title("vectors-animated"), do: "Animated vectors"
  defp vector_panel_title(_), do: "Vectors"

  defp resource_family("bitmaps-static"), do: "bitmaps"
  defp resource_family("bitmaps-animated"), do: "bitmaps"
  defp resource_family("vectors-static"), do: "vectors"
  defp resource_family("vectors-animated"), do: "vectors"
  defp resource_family(_), do: nil

  defp resource_family_class(active, family) do
    if resource_family(active) == family do
      "rounded bg-blue-100 px-3 py-1.5 text-blue-800"
    else
      "rounded bg-zinc-100 px-3 py-1.5 text-zinc-700"
    end
  end

  defp resource_subtab_class(active, :static) when active in ["bitmaps-static", "vectors-static"],
    do: "rounded bg-blue-100 px-3 py-1.5 text-blue-800"

  defp resource_subtab_class(active, :animated)
       when active in ["bitmaps-animated", "vectors-animated"],
       do: "rounded bg-blue-100 px-3 py-1.5 text-blue-800"

  defp resource_subtab_class(_active, _kind), do: "rounded bg-zinc-100 px-3 py-1.5 text-zinc-700"

  defp resource_static_path(slug, view) when view in ["bitmaps-animated", "vectors-animated"] do
    case resource_family(view) do
      "bitmaps" -> ~p"/projects/#{slug}/resources/bitmaps-static"
      "vectors" -> ~p"/projects/#{slug}/resources/vectors-static"
    end
  end

  defp resource_static_path(slug, _), do: ~p"/projects/#{slug}/resources/bitmaps-static"

  defp resource_animated_path(slug, view) when view in ["bitmaps-static", "vectors-static"] do
    case resource_family(view) do
      "bitmaps" -> ~p"/projects/#{slug}/resources/bitmaps-animated"
      "vectors" -> ~p"/projects/#{slug}/resources/vectors-animated"
      _ -> ~p"/projects/#{slug}/resources/bitmaps-animated"
    end
  end

  defp resource_animated_path(slug, view) do
    case resource_family(view) do
      "bitmaps" -> ~p"/projects/#{slug}/resources/bitmaps-animated"
      "vectors" -> ~p"/projects/#{slug}/resources/vectors-animated"
      _ -> ~p"/projects/#{slug}/resources/bitmaps-animated"
    end
  end

  defp font_platform_options do
    ["aplite", "basalt", "chalk", "diorite", "emery", "flint", "gabbro"]
  end

  attr :submit_event, :string, required: true
  attr :ctor, :string, required: true
  attr :ctor_prefix, :string, required: true
  attr :base_name, :string, required: true

  defp resource_base_name_form(assigns) do
    ~H"""
    <.form
      for={%{}}
      phx-submit={@submit_event}
      id={"resource-base-name-form-#{@ctor}"}
      class="min-w-0 flex-1"
    >
      <input type="hidden" name="ctor" value={@ctor} />
      <label class="flex flex-col gap-1">
        <span class="text-[10px] font-medium uppercase tracking-wide text-zinc-500">Elm name</span>
        <div class="flex min-w-0 items-center gap-1">
          <span class="shrink-0 font-mono text-[11px] text-zinc-500">{@ctor_prefix}</span>
          <input
            id={"resource-base-name-input-#{@ctor}"}
            name="base_name"
            value={@base_name}
            required
            pattern="[A-Za-z0-9][A-Za-z0-9_]*"
            title="Letters, numbers, and underscores; must start with a letter or number."
            class="min-w-0 flex-1 rounded border border-zinc-300 px-2 py-1 font-mono text-[11px] text-zinc-900"
          />
        </div>
        <p class="truncate font-mono text-[10px] text-zinc-500">{@ctor_prefix}{@base_name}</p>
      </label>
      <button
        type="submit"
        class="mt-1 rounded bg-zinc-200 px-2 py-0.5 text-[10px] font-medium text-zinc-800 hover:bg-zinc-300"
      >
        Save name
      </button>
    </.form>
    """
  end

  defp resource_upload_status(upload) do
    count = length(upload.entries)

    cond do
      count == 0 ->
        ""

      upload_ready?(upload) ->
        "#{count} file(s) ready to import"

      Map.get(upload, :auto_upload?) == true ->
        "#{count} file(s) selected — waiting for upload to finish…"

      true ->
        "#{count} file(s) selected"
    end
  end
end
