defmodule IdeWeb.WorkspaceLive.EmulatorPage do
  @moduledoc false
  use IdeWeb, :html

  @spec render(term()) :: term()
  def render(assigns) do
    ~H"""
      <section
        :if={@pane == :emulator}
        class="min-h-0 flex-1 overflow-auto rounded-lg border border-zinc-200 bg-white p-5 shadow-sm"
      >
        <h2 class="text-base font-semibold">Emulator</h2>
        <p class="mt-2 text-sm text-zinc-600">
          Pebble SDK emulator: choose a watch model, install the generated `.pbw` artifact, then capture screenshots for publishing.
        </p>
        <.form for={@emulator_form} phx-change="set-emulator-target" class="mt-3">
          <.input
            field={@emulator_form[:target]}
            type="select"
            label="Watch model / emulator target"
            options={@emulator_targets}
          />
        </.form>
        <div class="mt-3 flex items-center gap-2">
          <.button phx-click="run-emulator-install" disabled={@pebble_install_status == :running}>
            {if @pebble_install_status == :running,
              do: "Installing to emulator...",
              else: "Install to emulator"}
          </.button>
          <span class="text-xs text-zinc-600">
            Status: {check_status_label(@pebble_install_status)}
          </span>
        </div>
        <p class="mt-2 text-sm text-zinc-600">
          Installs a `.pbw` artifact into the selected emulator target. If none is prepared yet, the IDE packages one automatically first.
        </p>
        <pre
          :if={@pebble_install_output}
          class="mt-3 max-h-96 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
        ><%= @pebble_install_output %></pre>

        <div class="mt-6 border-t border-zinc-200 pt-4">
          <h3 class="text-sm font-semibold">Screenshots</h3>
          <div class="mt-2 flex items-center gap-2">
            <.button phx-click="capture-screenshot" disabled={@screenshot_status == :running}>
              {if @screenshot_status == :running,
                do: "Capturing screenshot...",
                else: "Capture screenshot"}
            </.button>
            <span class="text-xs text-zinc-600">
              Status: {check_status_label(@screenshot_status)}
            </span>
          </div>
          <div class="mt-2 flex items-center gap-2">
            <.button
              phx-click="capture-all-screenshots"
              disabled={@capture_all_status == :running}
              class="!bg-zinc-800 hover:!bg-zinc-700"
            >
              {if @capture_all_status == :running,
                do: "Capturing all models...",
                else: "Capture all watch models"}
            </.button>
            <span class="text-xs text-zinc-600">
              Batch status: {check_status_label(@capture_all_status)}
            </span>
          </div>
          <p :if={@capture_all_progress} class="mt-2 text-xs text-zinc-600">
            {@capture_all_progress}
          </p>
          <div class="mt-3 rounded border border-zinc-200 bg-zinc-50 p-2">
            <p class="text-[11px] font-semibold uppercase tracking-wide text-zinc-600">
              Per-model status
            </p>
            <div class="mt-2 grid grid-cols-1 gap-1 md:grid-cols-2 xl:grid-cols-3">
              <div
                :for={target <- @emulator_targets}
                class="rounded border border-zinc-200 bg-white px-2 py-1 text-xs"
              >
                <span class="font-mono text-zinc-700">{target}</span>
                <span class="ml-2 text-zinc-600">
                  {Map.get(@capture_all_target_statuses, target, "pending")}
                </span>
              </div>
            </div>
          </div>
          <p class="mt-2 text-sm text-zinc-600">
            Captures are stored by project and watch model, so publishing can use one set per emulator.
          </p>
          <pre
            :if={@screenshot_output}
            class="mt-3 max-h-64 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
          ><%= @screenshot_output %></pre>
          <pre
            :if={@capture_all_output}
            class="mt-3 max-h-64 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
          ><%= @capture_all_output %></pre>

          <div :if={@screenshot_groups != []} class="mt-4 space-y-5">
            <section :for={{emulator_target, shots} <- @screenshot_groups}>
              <div class="mb-2 flex items-center justify-between">
                <h4 class="text-xs font-semibold uppercase tracking-wide text-zinc-600">
                  {emulator_target}
                </h4>
                <button
                  type="button"
                  phx-click="delete-screenshot-target"
                  phx-value-emulator-target={emulator_target}
                  class="rounded bg-rose-100 px-2 py-1 text-[11px] font-medium text-rose-800 hover:bg-rose-200"
                >
                  Delete all
                </button>
              </div>
              <div class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
                <article
                  :for={shot <- shots}
                  class="rounded border border-zinc-200 bg-zinc-50 p-2 text-xs shadow-sm"
                >
                  <a href={shot.url} target="_blank" rel="noopener noreferrer" class="block">
                    <div class="mx-auto w-full max-w-[11rem] rounded bg-white p-1">
                      <img
                        src={shot.url}
                        alt={shot.filename}
                        class="aspect-[144/168] w-full rounded object-contain"
                      />
                    </div>
                  </a>
                  <p class="mt-2 truncate font-mono">{shot.filename}</p>
                  <p class="text-zinc-600">{shot.captured_at}</p>
                  <div class="mt-2 flex justify-end">
                    <button
                      type="button"
                      phx-click="delete-screenshot"
                      phx-value-emulator-target={emulator_target}
                      phx-value-filename={shot.filename}
                      class="rounded bg-rose-100 px-2 py-1 text-[11px] font-medium text-rose-800 hover:bg-rose-200"
                    >
                      Delete
                    </button>
                  </div>
                </article>
              </div>
            </section>
          </div>
        </div>
      </section>
    """
  end

  @spec check_status_label(term()) :: term()
  defp check_status_label(:idle), do: "idle"
  defp check_status_label(:running), do: "running"
  defp check_status_label(:ok), do: "ok"
  defp check_status_label(:error), do: "error"
end
