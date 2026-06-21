defmodule IdeWeb.WorkspaceLive.EmulatorPage do
  @moduledoc false
  use IdeWeb, :html

  import IdeWeb.WatchInteractives

  alias Ide.Emulator.Types, as: EmulatorTypes
  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.SimulatorSettings
  alias Ide.WatchModels
  alias Phoenix.LiveView.Rendered

  @type assigns :: map()
  @type rendered :: Rendered.t()
  @type flow_status :: :idle | :running | :ok | :error
  @type installation_status :: map()

  @spec render(assigns()) :: rendered()
  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:debug_mode, fn -> false end)
      |> assign_new(:debugger_watch_trigger_buttons, fn -> [] end)
      |> assign_new(:debugger_disabled_subscriptions, fn -> [] end)
      |> assign(
        :show_accel_tap?,
        IdeWeb.WatchInteractives.show_accel_tap?(
          assigns.project,
          assigns.debugger_state,
          :emulator,
          assigns.debugger_watch_trigger_buttons,
          assigns.debugger_disabled_subscriptions
        )
      )

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
          options={@emulator_mode_options}
        />
      </.form>

      <div
        :if={embedded_emulator_mode?(@emulator_mode)}
        id="embedded-emulator"
        phx-hook="EmbeddedEmulator"
        data-project-slug={@project.slug}
        data-emulator-target={@selected_emulator_target}
        data-emulator-screen-width={elem(emulator_screen_size(@selected_emulator_target), 0)}
        data-emulator-screen-height={elem(emulator_screen_size(@selected_emulator_target), 1)}
        data-emulator-display-shape={emulator_display_shape(@selected_emulator_target)}
        data-emulator-has-phone-companion={Projects.companion_app_present?(@project) |> to_string()}
        data-emulator-simulator-capabilities={
          emulator_simulator_capabilities_json(@project, @debugger_state)
        }
        data-emulator-simulator-settings={emulator_simulator_settings_json(@project, @debugger_state)}
        data-emulator-installation-status={
          emulator_feedback_installation_json(@emulator_installation_status)
        }
        data-emulator-ui-build="delegate-v4"
        data-emulator-storage-snapshot={to_string(@debug_mode)}
        class="mt-6 rounded-lg border border-zinc-200 bg-zinc-50 p-4"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 class="text-sm font-semibold">Embedded Emulator</h3>
            <p class="mt-1 text-xs text-zinc-600">
              CloudPebble-style noVNC display with phone bridge controls.
            </p>
          </div>
          <div
            id="embedded-emulator-toolbar"
            phx-update="ignore"
            class="flex flex-wrap items-center gap-2"
          >
            <button
              type="button"
              data-emulator-launch
              class="rounded bg-blue-600 px-3 py-2 text-xs font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
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
            <button
              type="button"
              data-emulator-screenshot
              disabled
              class="rounded bg-white px-3 py-2 text-xs font-semibold text-zinc-800 ring-1 ring-zinc-200 hover:bg-zinc-50 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Save screenshot
            </button>
            <button
              :if={@debug_mode}
              type="button"
              data-emulator-copy-feedback
              class="rounded bg-white px-3 py-2 text-xs font-semibold text-zinc-800 ring-1 ring-zinc-200 hover:bg-zinc-50"
              title="Copy session details and logs for bug reports"
            >
              Copy feedback
            </button>
          </div>
        </div>
        <div class="mt-4 grid gap-4 lg:grid-cols-[auto_minmax(0,1fr)_minmax(0,1fr)] lg:items-start">
          <div class="min-w-0 w-fit max-w-full">
            <div class="rounded border border-zinc-300 bg-black p-1">
              <div class="flex min-w-0 flex-col gap-2">
                <div class="flex items-center gap-1.5">
                  <button
                    type="button"
                    data-emulator-button="back"
                    class="rounded bg-zinc-100 px-2 py-1.5 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-300 hover:bg-white"
                  >
                    Back
                  </button>
                  <div class="relative min-w-0 shrink-0">
                    <div
                      id="embedded-emulator-display"
                      data-emulator-canvas
                      phx-update="ignore"
                      class="overflow-hidden rounded bg-zinc-950"
                      style={emulator_canvas_style(@selected_emulator_target)}
                    >
                    </div>
                    <.emulator_display_tap_button show?={@show_accel_tap?} data_tap="emulator-tap" />
                  </div>
                  <div class="flex flex-col gap-1.5">
                    <button
                      type="button"
                      data-emulator-button="up"
                      class="rounded bg-zinc-100 px-2 py-1.5 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-300 hover:bg-white"
                    >
                      Up
                    </button>
                    <button
                      type="button"
                      data-emulator-button="select"
                      class="rounded bg-zinc-100 px-2 py-1.5 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-300 hover:bg-white"
                    >
                      Select
                    </button>
                    <button
                      type="button"
                      data-emulator-button="down"
                      class="rounded bg-zinc-100 px-2 py-1.5 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-300 hover:bg-white"
                    >
                      Down
                    </button>
                  </div>
                </div>
                <div
                  data-emulator-fault-banner
                  hidden
                  class="rounded border border-rose-500 bg-rose-50 px-2 py-2 text-[11px] leading-snug text-rose-950"
                  role="alert"
                >
                  <p data-emulator-fault-headline class="font-semibold"></p>
                  <p
                    data-emulator-fault-detail
                    class="mt-1 break-words font-mono text-[10px] text-rose-900"
                  >
                  </p>
                </div>
              </div>
            </div>
            <p
              data-emulator-status
              class="mx-auto mt-2 min-w-0 rounded bg-white px-2 py-1.5 text-center text-[11px] leading-snug break-words text-zinc-700"
              style={emulator_status_style(@selected_emulator_target)}
            >
              Embedded emulator is idle.
            </p>
            <.form
              for={@emulator_form}
              id="emulator-production-build-form"
              phx-change="set-emulator-target"
              class="mx-auto mt-3 min-w-0 rounded border border-zinc-200 bg-white px-3 py-2"
              style={emulator_production_build_form_style(@selected_emulator_target)}
            >
              <input type="hidden" name="emulator[target]" value={@selected_emulator_target} />
              <input type="hidden" name="emulator[mode]" value={@emulator_mode} />
              <.input
                field={@emulator_form[:production_build]}
                type="checkbox"
                label="Production build"
              />
              <p class="mt-1 min-w-0 break-words text-[11px] leading-snug text-zinc-600">
                When enabled, Debug.log, Debug.todo, and Debug.toString are rejected — same as publish.
                Uncheck to allow Debug calls while testing in the emulator.
              </p>
            </.form>
          </div>
          <div class="space-y-3">
            <.simulator_settings_form
              id="embedded-emulator-simulator-settings"
              project={@project}
              debugger_state={@debugger_state}
              mode={:emulator}
              group_columns={1}
            />
            <.watch_interactives_panel
              id="embedded-emulator-watch-interactives"
              project={@project}
              debugger_state={@debugger_state}
              mode={:emulator}
              running={true}
              watch_trigger_buttons={@debugger_watch_trigger_buttons}
              disabled_subscriptions={@debugger_disabled_subscriptions}
            />
          </div>
          <div class="flex min-h-0 flex-col rounded border border-zinc-200 bg-white p-3">
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <h4 class="text-sm font-semibold text-zinc-900">Storage</h4>
                <p class="mt-0.5 text-[11px] leading-snug text-zinc-600">
                  Pebble.Storage keys from emulator logs. Edit, add, or reset keys for testing.
                </p>
              </div>
              <button
                type="button"
                data-emulator-storage-reset
                disabled
                class="shrink-0 rounded bg-rose-100 px-2 py-1.5 text-[11px] font-semibold text-rose-800 hover:bg-rose-200 disabled:cursor-not-allowed disabled:opacity-50"
              >
                Reset
              </button>
            </div>
            <div class="mt-2 min-h-0 flex-1 overflow-auto">
              <table class="min-w-full text-left text-xs">
                <thead class="sticky top-0 border-b border-zinc-200 bg-white text-[10px] uppercase tracking-wide text-zinc-500">
                  <tr>
                    <th class="py-1 pr-2">Key</th>
                    <th class="min-w-[5.5rem] py-1 pr-2">Type</th>
                    <th class="py-1 pr-2">Value</th>
                    <th class="py-1 text-right">Actions</th>
                  </tr>
                </thead>
                <tbody data-emulator-storage-rows>
                  <tr data-emulator-storage-empty>
                    <td colspan="4" class="py-2 text-zinc-500">
                      No storage keys yet. Launch the app or add a test key.
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div class="mt-3 space-y-2 border-t border-zinc-100 pt-3">
              <input
                data-emulator-storage-new-key
                type="number"
                min="0"
                placeholder="Key"
                class="w-full rounded border border-zinc-300 px-2 py-1.5 text-xs"
              />
              <select
                data-emulator-storage-new-type
                class="ide-select w-full min-w-[7rem] rounded border border-zinc-300 bg-white py-1.5 pl-2 text-xs"
              >
                <option value="string">String</option>
                <option value="int">Int</option>
              </select>
              <input
                data-emulator-storage-new-value
                type="text"
                placeholder="Value"
                class="w-full rounded border border-zinc-300 px-2 py-1.5 text-xs"
              />
              <button
                type="button"
                data-emulator-storage-add
                disabled
                class="w-full rounded bg-blue-600 px-3 py-2 text-xs font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
              >
                Save key
              </button>
            </div>
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
            <.button
              phx-click="toggle-external-emulator"
              disabled={@pebble_install_status == :running or @emulator_stop_status == :running}
            >
              {external_emulator_toggle_label(
                @external_emulator_running,
                @pebble_install_status,
                @emulator_stop_status
              )}
            </.button>
            <.button
              phx-click="capture-screenshot"
              disabled={
                screenshot_button_disabled?(
                  @emulator_mode,
                  @external_emulator_running,
                  @screenshot_status
                )
              }
              class="!bg-white !text-zinc-800 ring-1 ring-zinc-200 hover:!bg-zinc-50"
            >
              {screenshot_button_label(@screenshot_status)}
            </.button>
          </div>
        </div>
        <div class="mt-4 grid gap-4 xl:grid-cols-[minmax(320px,1fr)_minmax(22rem,26rem)]">
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
              <div class="relative flex h-[260px] w-[230px] items-center justify-center rounded bg-zinc-950 p-4 text-center text-xs text-zinc-300">
                External Pebble SDK emulator window
                <button
                  :if={@show_accel_tap?}
                  type="button"
                  phx-click="external-emulator-control"
                  phx-value-control="tap"
                  phx-value-direction="z+"
                  class={[
                    "absolute bottom-1 left-1 z-10 rounded px-2 py-1 text-[11px] font-semibold shadow-sm ring-1",
                    "bg-zinc-100/95 text-zinc-900 ring-zinc-300 hover:bg-white"
                  ]}
                >
                  Tap
                </button>
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
            <.simulator_settings_form
              id="external-emulator-simulator-settings"
              project={@project}
              debugger_state={@debugger_state}
              mode={:emulator}
              group_columns={1}
            />
            <.watch_interactives_panel
              id="external-emulator-watch-interactives"
              project={@project}
              debugger_state={@debugger_state}
              mode={:emulator}
              running={true}
              watch_trigger_buttons={@debugger_watch_trigger_buttons}
              disabled_subscriptions={@debugger_disabled_subscriptions}
            />
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
            <div class="flex items-center gap-2 text-xs font-medium text-zinc-700">
              <span>Firmware</span>
              <span
                data-wasm-firmware
                class="rounded border border-zinc-200 bg-white px-2 py-1 text-xs text-zinc-700"
              >
                Auto
              </span>
            </div>
            <button
              type="button"
              data-wasm-launch
              class="rounded bg-blue-600 px-3 py-2 text-xs font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
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
              <div class="relative">
                <iframe
                  id="wasm-emulator-frame"
                  data-wasm-frame
                  title="Pebble WASM Emulator"
                  class="h-[260px] w-[230px] rounded border-0 bg-zinc-950"
                >
                </iframe>
                <.emulator_display_tap_button show?={@show_accel_tap?} data_tap="wasm-tap" />
              </div>
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
          <%= if @auth_mode in [:public_pebble, :public_custom] do %>
            Batch capture launches the embedded emulator for each model.
          <% end %>
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
                <div class="mt-2 flex justify-end gap-2">
                  <a
                    href={shot.url}
                    download={shot.filename}
                    class="rounded bg-white px-2 py-1 text-[11px] font-medium text-zinc-800 ring-1 ring-zinc-200 hover:bg-zinc-50"
                  >
                    Download
                  </a>
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

  @spec check_status_label(flow_status() | atom()) :: String.t()
  defp check_status_label(:idle), do: "idle"
  defp check_status_label(:running), do: "running"
  defp check_status_label(:ok), do: "ok"
  defp check_status_label(:error), do: "error"

  defp screenshot_button_label(:running), do: "Saving screenshot..."
  defp screenshot_button_label(_status), do: "Save screenshot"

  defp screenshot_button_disabled?(_mode, _external_running?, :running), do: true
  defp screenshot_button_disabled?("external", true, _status), do: false
  defp screenshot_button_disabled?(_mode, _external_running?, _status), do: true

  defp external_emulator_toggle_label(_running?, :running, _stop_status), do: "Launching..."
  defp external_emulator_toggle_label(_running?, _install_status, :running), do: "Stopping..."
  defp external_emulator_toggle_label(true, _install_status, _stop_status), do: "Stop"

  defp external_emulator_toggle_label(_running?, _install_status, _stop_status),
    do: "Launch / Install PBW"

  @spec emulator_installation_summary(installation_status()) :: String.t()
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

  @spec emulator_setup_needs_attention?(installation_status()) :: boolean()
  defp emulator_setup_needs_attention?(%{status: status}) when status in [:warning, :error],
    do: true

  defp emulator_setup_needs_attention?(%{error: error}) when is_binary(error), do: true
  defp emulator_setup_needs_attention?(_), do: false

  @spec emulator_feedback_installation_json(installation_status() | nil) :: String.t()
  defp emulator_feedback_installation_json(status) when is_map(status) do
    Jason.encode!(status)
  rescue
    _ -> "{}"
  end

  defp emulator_feedback_installation_json(_), do: "{}"

  defp embedded_emulator_mode?("external"), do: false
  defp embedded_emulator_mode?("wasm"), do: false
  defp embedded_emulator_mode?(_), do: true

  defp external_emulator_mode?("external"), do: true
  defp external_emulator_mode?(_), do: false

  defp wasm_emulator_mode?("wasm"), do: true
  defp wasm_emulator_mode?(_), do: false

  @spec emulator_screen_size(String.t()) :: {pos_integer(), pos_integer()}
  defp emulator_screen_size(target) when is_binary(target) do
    screen = target |> WatchModels.profile_for() |> Map.get("screen", %{})

    {
      Map.get(screen, "width", 144) |> max(1),
      Map.get(screen, "height", 168) |> max(1)
    }
  end

  defp emulator_screen_size(_), do: {144, 168}

  @spec emulator_canvas_style(String.t()) :: String.t()
  defp emulator_canvas_style(target) do
    {width, height} = emulator_screen_size(target)
    "width: #{width}px; height: #{height}px;"
  end

  @spec emulator_status_style(String.t()) :: String.t()
  defp emulator_status_style(target) do
    {width, _height} = emulator_screen_size(target)
    "width: #{width}px;"
  end

  @production_build_form_width_factor 1.7

  @spec emulator_production_build_form_style(String.t()) :: String.t()
  defp emulator_production_build_form_style(target) do
    {width, _height} = emulator_screen_size(target)
    form_width = round(width * @production_build_form_width_factor)
    "width: #{form_width}px;"
  end

  @spec emulator_display_shape(String.t()) :: String.t()
  defp emulator_display_shape(target) do
    target
    |> WatchModels.profile_for()
    |> Map.get("shape", "rect")
  end

  @spec emulator_settings_path(Project.t() | map() | nil) :: String.t()
  defp emulator_settings_path(%{slug: slug}) when is_binary(slug) do
    "/settings?return_to=" <> URI.encode_www_form("/projects/#{slug}/emulator")
  end

  defp emulator_settings_path(_), do: "/settings"

  @emulator_simulator_setting_keys ~w(
    battery_percent charging connected clock_24h timeline_peek
    compass_heading_deg compass_valid weather
  )

  @spec emulator_simulator_capabilities_json(Project.t() | map() | nil, map() | nil) ::
          String.t()
  defp emulator_simulator_capabilities_json(project, debugger_state) do
    project
    |> SimulatorSettings.capabilities_for(debugger_state, :emulator)
    |> MapSet.to_list()
    |> Jason.encode!()
  end

  @spec emulator_simulator_settings_json(Project.t() | map() | nil, map() | nil) :: String.t()
  defp emulator_simulator_settings_json(project, debugger_state) do
    caps = SimulatorSettings.capabilities_for(project, debugger_state, :emulator)

    keys =
      Enum.reject(@emulator_simulator_setting_keys, fn
        "weather" -> not MapSet.member?(caps, "weather")
        _ -> false
      end)

    project
    |> SimulatorSettings.values_for(debugger_state)
    |> Map.take(keys)
    |> encode_simulator_settings()
  end

  @spec encode_simulator_settings(EmulatorTypes.simulator_settings()) :: String.t()
  defp encode_simulator_settings(settings), do: Jason.encode!(settings)
end
