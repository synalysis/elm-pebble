defmodule IdeWeb.WorkspaceLive.EmulatorPage do
  @moduledoc false
  use IdeWeb, :html

  @spec render(term()) :: term()
  def render(assigns) do
    ~H"""
    <section
      class={[
        "min-h-0 flex-1 overflow-auto rounded-lg border border-zinc-200 bg-white p-5 shadow-sm",
        @pane == :emulator || "hidden"
      ]}
      aria-hidden={@pane != :emulator}
    >
      <h2 class="text-base font-semibold">Emulator</h2>
      <p class="mt-2 text-sm text-zinc-600">
        Choose an embedded emulator with browser controls, or use an external Pebble SDK emulator window.
      </p>
      <div
        :if={
          embedded_emulator_mode?(@emulator_mode) and
            emulator_setup_needs_attention?(@emulator_installation_status)
        }
        class="mt-4 rounded border border-amber-200 bg-amber-50 p-3 text-amber-900"
      >
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h3 class="text-sm font-semibold">Embedded emulator setup needs attention</h3>
            <p class="mt-1 text-xs">
              {emulator_installation_summary(@emulator_installation_status)}
            </p>
          </div>
          <.link
            navigate={emulator_settings_path(@project)}
            class="rounded bg-zinc-900 px-3 py-2 text-xs font-semibold text-white hover:bg-zinc-700"
          >
            Open Settings
          </.link>
        </div>
      </div>
      <.form
        for={@emulator_form}
        phx-change="set-emulator-target"
        class="mt-3 grid gap-3 md:grid-cols-2"
      >
        <.input
          field={@emulator_form[:target]}
          type="select"
          label="Watch model / emulator target"
          options={@emulator_targets}
        />
        <.input
          field={@emulator_form[:mode]}
          type="select"
          label="Emulator"
          options={emulator_mode_options()}
        />
      </.form>

      <div
        :if={embedded_emulator_mode?(@emulator_mode)}
        id="embedded-emulator"
        phx-hook="EmbeddedEmulator"
        data-project-slug={@project.slug}
        data-emulator-target={@selected_emulator_target}
        class="mt-6 rounded-lg border border-zinc-200 bg-zinc-50 p-4"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 class="text-sm font-semibold">Embedded Emulator</h3>
            <p class="mt-1 text-xs text-zinc-600">
              CloudPebble-style noVNC display with phone bridge controls.
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <button
              type="button"
              data-emulator-launch
              class="rounded bg-zinc-900 px-3 py-2 text-xs font-semibold text-white hover:bg-zinc-700 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Launch
            </button>
            <button
              type="button"
              data-emulator-install
              disabled
              class="rounded bg-blue-700 px-3 py-2 text-xs font-semibold text-white hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Send PBW
            </button>
            <button
              type="button"
              data-emulator-preferences
              disabled
              class="rounded bg-white px-3 py-2 text-xs font-semibold text-zinc-800 ring-1 ring-zinc-200 hover:bg-zinc-50 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Companion preferences
            </button>
          </div>
        </div>
        <div class="mt-4 grid gap-4 xl:grid-cols-[minmax(320px,1fr)_18rem]">
          <div class="rounded border border-zinc-300 bg-black p-3">
            <div class="mx-auto flex w-max items-center gap-4 overflow-x-auto py-4">
              <button
                type="button"
                data-emulator-button="back"
                class="rounded bg-zinc-100 px-3 py-2 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-300 hover:bg-white"
              >
                Back
              </button>
              <div
                id="embedded-emulator-display"
                data-emulator-canvas
                phx-update="ignore"
                class="min-h-[168px] min-w-[144px] overflow-hidden rounded bg-zinc-950"
              >
              </div>
              <div class="flex flex-col gap-2">
                <button
                  type="button"
                  data-emulator-button="up"
                  class="rounded bg-zinc-100 px-3 py-2 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-300 hover:bg-white"
                >
                  Up
                </button>
                <button
                  type="button"
                  data-emulator-button="select"
                  class="rounded bg-zinc-100 px-3 py-2 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-300 hover:bg-white"
                >
                  Select
                </button>
                <button
                  type="button"
                  data-emulator-button="down"
                  class="rounded bg-zinc-100 px-3 py-2 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-300 hover:bg-white"
                >
                  Down
                </button>
              </div>
            </div>
          </div>
          <div class="space-y-3">
            <p data-emulator-status class="rounded bg-white px-3 py-2 text-xs text-zinc-700">
              Embedded emulator is idle.
            </p>
            <div class="rounded bg-white p-3 text-xs text-zinc-700">
              <label class="block font-medium">
                Battery
                <input
                  data-emulator-battery
                  type="range"
                  min="0"
                  max="100"
                  value="80"
                  class="mt-1 w-full"
                />
              </label>
              <label class="mt-2 flex items-center gap-2">
                <input data-emulator-charging type="checkbox" /> Charging
              </label>
              <label class="mt-2 flex items-center gap-2">
                <input data-emulator-bluetooth type="checkbox" checked /> Bluetooth connected
              </label>
              <label class="mt-2 flex items-center gap-2">
                <input data-emulator-24h type="checkbox" /> 24h time
              </label>
              <label class="mt-2 flex items-center gap-2">
                <input data-emulator-peek type="checkbox" /> Timeline peek
              </label>
              <div class="mt-3 flex flex-wrap gap-2">
                <button
                  type="button"
                  data-emulator-tap
                  class="rounded bg-zinc-100 px-3 py-2 text-xs font-semibold text-zinc-900 shadow-sm hover:bg-zinc-200"
                >
                  Tap
                </button>
                <button
                  type="button"
                  data-emulator-screenshot
                  class="rounded bg-zinc-100 px-3 py-2 text-xs font-semibold text-zinc-900 shadow-sm hover:bg-zinc-200"
                >
                  Canvas screenshot
                </button>
              </div>
            </div>
          </div>
        </div>
        <div class="mt-4 rounded border border-zinc-200 bg-white p-3">
          <div class="flex flex-wrap items-start justify-between gap-2">
            <div>
              <h4 class="text-sm font-semibold text-zinc-900">Storage</h4>
              <p class="mt-1 text-xs text-zinc-600">
                Shows Pebble.Storage keys observed in emulator logs. Edit values, add a key, or delete all known keys for testing.
              </p>
            </div>
            <button
              type="button"
              data-emulator-storage-reset
              disabled
              class="rounded bg-rose-100 px-3 py-2 text-xs font-semibold text-rose-800 hover:bg-rose-200 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Reset known keys
            </button>
          </div>
          <div class="mt-3 overflow-x-auto">
            <table class="min-w-full text-left text-xs">
              <thead class="border-b border-zinc-200 text-[11px] uppercase tracking-wide text-zinc-500">
                <tr>
                  <th class="py-1 pr-2">Key</th>
                  <th class="py-1 pr-2">Type</th>
                  <th class="py-1 pr-2">Value</th>
                  <th class="py-1 text-right">Actions</th>
                </tr>
              </thead>
              <tbody data-emulator-storage-rows>
                <tr data-emulator-storage-empty>
                  <td colspan="4" class="py-3 text-zinc-500">
                    No storage keys observed yet. Launch the app or add a test key below.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="mt-3 grid gap-2 md:grid-cols-[8rem_7rem_1fr_auto]">
            <input
              data-emulator-storage-new-key
              type="number"
              min="0"
              placeholder="Key"
              class="rounded border border-zinc-300 px-2 py-1 text-xs"
            />
            <select
              data-emulator-storage-new-type
              class="rounded border border-zinc-300 px-2 py-1 text-xs"
            >
              <option value="string">String</option>
              <option value="int">Int</option>
            </select>
            <input
              data-emulator-storage-new-value
              type="text"
              placeholder="Value"
              class="rounded border border-zinc-300 px-2 py-1 text-xs"
            />
            <button
              type="button"
              data-emulator-storage-add
              disabled
              class="rounded bg-zinc-900 px-3 py-2 text-xs font-semibold text-white hover:bg-zinc-700 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Save key
            </button>
          </div>
        </div>
        <pre
          data-emulator-log
          class="mt-3 max-h-48 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
        ></pre>
        <div
          data-emulator-config-panel
          class="fixed inset-0 z-50 hidden items-center justify-center bg-zinc-950/60 p-4"
        >
          <div
            data-emulator-config-dialog
            role="dialog"
            aria-modal="true"
            aria-labelledby="embedded-emulator-config-title"
            tabindex="-1"
            class="flex h-[88vh] max-h-[960px] w-full max-w-3xl flex-col overflow-hidden rounded-xl border border-blue-200 bg-white shadow-2xl"
          >
            <div class="flex flex-wrap items-center justify-between gap-2 border-b border-zinc-200 p-3">
              <div>
                <h4 id="embedded-emulator-config-title" class="text-sm font-semibold text-zinc-900">
                  Companion Configuration
                </h4>
                <p data-emulator-config-url class="mt-1 text-xs text-zinc-600"></p>
              </div>
              <div class="flex gap-2">
                <button
                  type="button"
                  data-emulator-config-cancel
                  class="rounded bg-zinc-200 px-3 py-2 text-xs font-semibold text-zinc-800 hover:bg-zinc-300"
                >
                  Cancel
                </button>
              </div>
            </div>
            <iframe
              data-emulator-config-frame
              class="min-h-0 w-full flex-1 bg-white"
              sandbox="allow-forms allow-scripts allow-same-origin allow-popups allow-top-navigation-by-user-activation"
            >
            </iframe>
          </div>
        </div>
      </div>

      <div
        :if={external_emulator_mode?(@emulator_mode)}
        class="mt-6 rounded-lg border border-zinc-200 bg-zinc-50 p-4"
      >
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h3 class="text-sm font-semibold">External Emulator</h3>
            <p class="mt-1 text-xs text-zinc-600">
              Uses Pebble SDK CLI commands against the selected external emulator target.
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <.button phx-click="run-emulator-install" disabled={@pebble_install_status == :running}>
              {if @pebble_install_status == :running,
                do: "Launching...",
                else: "Launch / Install PBW"}
            </.button>
            <.button
              phx-click="stop-emulator"
              disabled={@emulator_stop_status == :running}
              class="!bg-zinc-200 !text-zinc-800 hover:!bg-zinc-300"
            >
              {if @emulator_stop_status == :running, do: "Stopping...", else: "Stop"}
            </.button>
          </div>
        </div>
        <div class="mt-4 grid gap-4 xl:grid-cols-[minmax(320px,1fr)_18rem]">
          <div class="rounded border border-zinc-300 bg-black p-3">
            <div class="mx-auto flex w-max items-center gap-4 overflow-x-auto py-4">
              <button
                type="button"
                phx-click="external-emulator-control"
                phx-value-control="button"
                phx-value-action="click"
                phx-value-button="back"
                class="rounded bg-zinc-100 px-3 py-2 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-300 hover:bg-white"
              >
                Back
              </button>
              <div class="flex h-[260px] w-[230px] items-center justify-center rounded bg-zinc-950 p-4 text-center text-xs text-zinc-300">
                External Pebble SDK emulator window
              </div>
              <div class="flex flex-col gap-2">
                <button
                  :for={button <- ~w(up select down)}
                  type="button"
                  phx-click="external-emulator-control"
                  phx-value-control="button"
                  phx-value-action="click"
                  phx-value-button={button}
                  class="rounded bg-zinc-100 px-3 py-2 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-300 hover:bg-white"
                >
                  {String.capitalize(button)}
                </button>
              </div>
            </div>
          </div>
          <div class="space-y-3">
            <p class="rounded bg-white px-3 py-2 text-xs text-zinc-700">
              Install status: {check_status_label(@pebble_install_status)}
            </p>
            <p class="rounded bg-white px-3 py-2 text-xs text-zinc-700">
              Control status: {check_status_label(@emulator_stop_status)}
            </p>
            <div class="rounded bg-white p-3 text-xs text-zinc-700">
              <p class="font-semibold text-zinc-900">Watch controls</p>
              <button
                type="button"
                phx-click="external-emulator-control"
                phx-value-control="tap"
                phx-value-direction="z+"
                class="mt-3 rounded bg-zinc-100 px-3 py-2 text-xs font-semibold text-zinc-900 shadow-sm hover:bg-zinc-200"
              >
                Tap
              </button>
              <form phx-change="external-emulator-control" class="mt-3">
                <input type="hidden" name="control" value="battery" />
                <input type="hidden" name="charging" value="false" />
                <label class="block font-medium">
                  Battery
                  <input name="percent" type="range" min="0" max="100" value="80" class="mt-1 w-full" />
                </label>
                <label class="mt-2 flex items-center gap-2">
                  <input name="charging" type="checkbox" value="true" /> Charging
                </label>
              </form>
              <form phx-change="external-emulator-control" class="mt-3 space-y-2">
                <label class="flex items-center gap-2">
                  <input type="hidden" name="control" value="bluetooth" />
                  <input type="hidden" name="connected" value="false" />
                  <input name="connected" type="checkbox" value="true" checked /> Bluetooth connected
                </label>
              </form>
              <form phx-change="external-emulator-control" class="mt-2 space-y-2">
                <label class="flex items-center gap-2">
                  <input type="hidden" name="control" value="time_format" />
                  <input type="hidden" name="enabled" value="false" />
                  <input name="enabled" type="checkbox" value="true" /> 24h time
                </label>
              </form>
              <form phx-change="external-emulator-control" class="mt-2 space-y-2">
                <label class="flex items-center gap-2">
                  <input type="hidden" name="control" value="timeline_quick_view" />
                  <input type="hidden" name="enabled" value="false" />
                  <input name="enabled" type="checkbox" value="true" /> Timeline peek
                </label>
              </form>
            </div>
          </div>
        </div>
        <pre
          :if={@pebble_install_output}
          class="mt-3 max-h-96 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
        ><%= @pebble_install_output %></pre>
        <pre
          :if={@emulator_stop_output}
          class="mt-3 max-h-64 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
        ><%= @emulator_stop_output %></pre>
      </div>

      <div
        :if={wasm_emulator_mode?(@emulator_mode)}
        id="wasm-emulator"
        phx-hook="WasmEmulator"
        data-project-slug={@project.slug}
        data-emulator-target={@selected_emulator_target}
        class="mt-6 rounded-lg border border-zinc-200 bg-zinc-50 p-4"
      >
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h3 class="text-sm font-semibold">WASM Emulator</h3>
            <p class="mt-1 text-xs text-zinc-600">
              Browser-hosted Pebble QEMU via WebAssembly. Requires local QEMU WASM and firmware assets.
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <label class="flex items-center gap-2 text-xs font-medium text-zinc-700">
              Firmware
              <select
                data-wasm-firmware
                class="min-w-20 rounded border border-zinc-300 bg-white py-1 pl-2 pr-7 text-xs text-zinc-900"
              >
                <option value="sdk">SDK</option>
                <option value="full">Full</option>
              </select>
            </label>
            <button
              type="button"
              data-wasm-launch
              class="rounded bg-zinc-900 px-3 py-2 text-xs font-semibold text-white hover:bg-zinc-700 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Launch
            </button>
            <button
              type="button"
              data-wasm-install
              class="rounded bg-blue-700 px-3 py-2 text-xs font-semibold text-white hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Install PBW
            </button>
            <button
              type="button"
              data-wasm-screenshot
              class="rounded bg-white px-3 py-2 text-xs font-semibold text-zinc-800 ring-1 ring-zinc-200 hover:bg-zinc-50 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Save screenshot
            </button>
          </div>
        </div>
        <div class="mt-4 grid gap-4 xl:grid-cols-[minmax(320px,1fr)_18rem]">
          <div class="rounded border border-zinc-300 bg-black p-3">
            <div
              id="wasm-emulator-display-controls"
              phx-update="ignore"
              class="mx-auto flex w-max items-center gap-4 overflow-x-auto py-4"
            >
              <button
                type="button"
                data-wasm-button="back"
                class="rounded bg-zinc-100 px-3 py-2 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-300 hover:bg-white"
              >
                Back
              </button>
              <iframe
                id="wasm-emulator-frame"
                data-wasm-frame
                title="Pebble WASM Emulator"
                class="h-[260px] w-[230px] rounded border-0 bg-zinc-950"
              >
              </iframe>
              <div class="flex flex-col gap-2">
                <button
                  type="button"
                  data-wasm-button="up"
                  class="rounded bg-zinc-100 px-3 py-2 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-300 hover:bg-white"
                >
                  Up
                </button>
                <button
                  type="button"
                  data-wasm-button="select"
                  class="rounded bg-zinc-100 px-3 py-2 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-300 hover:bg-white"
                >
                  Select
                </button>
                <button
                  type="button"
                  data-wasm-button="down"
                  class="rounded bg-zinc-100 px-3 py-2 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-300 hover:bg-white"
                >
                  Down
                </button>
              </div>
            </div>
          </div>
          <div class="space-y-3">
            <p data-wasm-status class="rounded bg-white px-3 py-2 text-xs text-zinc-700">
              Checking WASM emulator assets...
            </p>
            <p data-wasm-assets class="rounded bg-white px-3 py-2 text-xs text-zinc-600"></p>
            <div class="rounded bg-white p-3 text-xs text-zinc-700">
              <label class="block font-medium">
                Battery
                <input
                  data-wasm-battery
                  type="range"
                  min="0"
                  max="100"
                  value="80"
                  class="mt-1 w-full"
                />
              </label>
              <label class="mt-2 flex items-center gap-2">
                <input data-wasm-charging type="checkbox" /> Charging
              </label>
              <label class="mt-2 flex items-center gap-2">
                <input data-wasm-bluetooth type="checkbox" checked /> Bluetooth connected
              </label>
              <label class="mt-2 flex items-center gap-2">
                <input data-wasm-24h type="checkbox" /> 24h time
              </label>
              <label class="mt-2 flex items-center gap-2">
                <input data-wasm-peek type="checkbox" /> Timeline peek
              </label>
              <button
                type="button"
                data-wasm-tap
                class="mt-3 rounded bg-zinc-100 px-3 py-2 text-xs font-semibold text-zinc-900 shadow-sm hover:bg-zinc-200 disabled:cursor-not-allowed disabled:opacity-50"
              >
                Tap
              </button>
            </div>
            <div data-wasm-progress class="hidden rounded bg-white px-3 py-2 text-xs text-zinc-700">
              <div class="flex items-center justify-between gap-3">
                <span data-wasm-progress-label>Install progress</span>
                <span data-wasm-progress-percent>0%</span>
              </div>
              <div class="mt-2 h-2 overflow-hidden rounded-full bg-zinc-200">
                <div data-wasm-progress-bar class="h-full w-0 rounded-full bg-blue-600"></div>
              </div>
            </div>
            <p class="rounded bg-amber-50 px-3 py-2 text-xs text-amber-900">
              Install PBW sends an IDE-generated install plan to the browser runtime. The runtime must expose `Module.pebbleInstallPbw(plan)` or the patched Pebble control bridge; build assets with `docker compose run --rm wasm-emulator-builder` or `scripts/build_wasm_emulator_runtime.sh`.
            </p>
          </div>
        </div>
        <div class="mt-4 rounded border border-zinc-200 bg-white p-3">
          <div class="flex flex-wrap items-start justify-between gap-2">
            <div>
              <h4 class="text-sm font-semibold text-zinc-900">Storage</h4>
              <p class="mt-1 text-xs text-zinc-600">
                Shows Pebble.Storage keys observed from WASM app logs. Editing storage still requires the embedded phone bridge.
              </p>
            </div>
          </div>
          <div class="mt-3 overflow-x-auto">
            <table class="min-w-full text-left text-xs">
              <thead class="border-b border-zinc-200 text-[11px] uppercase tracking-wide text-zinc-500">
                <tr>
                  <th class="py-1 pr-2">Key</th>
                  <th class="py-1 pr-2">Type</th>
                  <th class="py-1 pr-2">Value</th>
                  <th class="py-1 text-right">Source</th>
                </tr>
              </thead>
              <tbody data-wasm-storage-rows>
                <tr data-wasm-storage-empty>
                  <td colspan="4" class="py-3 text-zinc-500">
                    No storage keys observed yet. Launch the app and install the PBW to collect storage logs.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <pre
          data-wasm-log
          class="mt-3 max-h-48 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
        ></pre>
      </div>

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

  @spec emulator_installation_summary(term()) :: String.t()
  defp emulator_installation_summary(%{status: :checking, platform: platform}),
    do: "Checking embedded emulator dependencies for #{platform}..."

  defp emulator_installation_summary(%{status: :ok, platform: platform}),
    do: "All embedded emulator dependencies are present for #{platform}."

  defp emulator_installation_summary(%{status: :warning, platform: platform, missing: missing}) do
    labels = missing |> List.wrap() |> Enum.map(& &1.label) |> Enum.join(", ")
    "Embedded emulator setup needs attention for #{platform}: #{labels}."
  end

  defp emulator_installation_summary(%{error: error}) when is_binary(error), do: error
  defp emulator_installation_summary(_), do: "Embedded emulator setup needs attention."

  @spec emulator_setup_needs_attention?(term()) :: boolean()
  defp emulator_setup_needs_attention?(%{status: status}) when status in [:warning, :error],
    do: true

  defp emulator_setup_needs_attention?(%{error: error}) when is_binary(error), do: true
  defp emulator_setup_needs_attention?(_), do: false

  defp emulator_mode_options do
    [
      {"Embedded in IDE", "embedded"},
      {"External Pebble emulator", "external"},
      {"WASM in browser", "wasm"}
    ]
  end

  defp embedded_emulator_mode?("external"), do: false
  defp embedded_emulator_mode?("wasm"), do: false
  defp embedded_emulator_mode?(_), do: true

  defp external_emulator_mode?("external"), do: true
  defp external_emulator_mode?(_), do: false

  defp wasm_emulator_mode?("wasm"), do: true
  defp wasm_emulator_mode?(_), do: false

  @spec emulator_settings_path(term()) :: String.t()
  defp emulator_settings_path(%{slug: slug}) when is_binary(slug) do
    "/settings?return_to=" <> URI.encode_www_form("/projects/#{slug}/emulator")
  end

  defp emulator_settings_path(_), do: "/settings"
end
