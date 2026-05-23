defmodule IdeWeb.WatchInteractives do
  @moduledoc false

  use IdeWeb, :html

  alias Ide.SimulatorSettings
  alias Phoenix.LiveView.Rendered

  @interactive_caps ~w(
    watch_accel
    watch_compass
    watch_app_focus
    watch_dictation
    watch_data_log
    watch_vibes
  )

  @type assigns :: map()
  @type rendered :: Rendered.t()

  attr :id, :string, required: true
  attr :project, :map, required: true
  attr :debugger_state, :map, default: nil
  attr :mode, :atom, default: :debugger
  attr :watch_trigger_buttons, :list, default: []
  attr :disabled_subscriptions, :list, default: []
  attr :running, :boolean, default: true
  attr :class, :string, default: nil

  @spec watch_interactives_panel(assigns()) :: rendered()
  def watch_interactives_panel(assigns) do
    caps = SimulatorSettings.capabilities_for(assigns.project, assigns.debugger_state, assigns.mode)
    settings = SimulatorSettings.values_for(assigns.project, assigns.debugger_state)

    assigns =
      assigns
      |> assign(:caps, caps)
      |> assign(:settings, settings)
      |> assign(:accel_control, accel_control(assigns.watch_trigger_buttons, assigns.disabled_subscriptions))
      |> assign(:show_tap?, tap_control?(assigns.watch_trigger_buttons, assigns.disabled_subscriptions))
      |> assign(:active?, interactive_active?(caps))

    ~H"""
    <div
      :if={@active?}
      id={@id}
      class={[
        "space-y-3 rounded border border-zinc-200 bg-white p-3 text-xs text-zinc-700",
        @class
      ]}
      data-copy-scope
    >
      <div>
        <h3 class="text-sm font-semibold text-zinc-900">Watch interactives</h3>
        <p class="mt-1 text-[11px] text-zinc-500">
          Simulator controls for watch sensors and input APIs used by this app.
        </p>
      </div>

      <.watch_accel_pad
        :if={MapSet.member?(@caps, "watch_accel")}
        id={"#{@id}-accel"}
        mode={@mode}
        control={@accel_control}
        running={@running}
      />

      <.watch_tap_button
        :if={MapSet.member?(@caps, "watch_accel") and @show_tap? and @mode == :debugger}
        control={@accel_control}
        running={@running}
      />

      <.watch_compass_send
        :if={MapSet.member?(@caps, "watch_compass")}
        id={"#{@id}-compass"}
        mode={@mode}
        settings={@settings}
        running={@running}
      />

      <.watch_focus_notice
        :if={MapSet.member?(@caps, "watch_app_focus")}
        settings={@settings}
      />

      <.watch_dictation_sim
        :if={MapSet.member?(@caps, "watch_dictation") and @mode == :debugger}
        id={"#{@id}-dictation"}
        running={@running}
      />

      <.watch_vibe_test
        :if={MapSet.member?(@caps, "watch_vibes") and @mode == :debugger}
        id={"#{@id}-vibes"}
        settings={@settings}
        running={@running}
      />

      <.watch_data_log_panel
        :if={MapSet.member?(@caps, "watch_data_log") and @mode == :emulator}
        id={"#{@id}-data-log"}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :mode, :atom, required: true
  attr :control, :map, default: nil
  attr :running, :boolean, default: true

  @spec watch_accel_pad(assigns()) :: rendered()
  defp watch_accel_pad(assigns) do
    ~H"""
    <div class="rounded border border-zinc-200 bg-zinc-50 p-2">
      <div class="flex items-center justify-between gap-2">
        <p class="text-[11px] font-semibold uppercase tracking-wide text-zinc-600">
          Accelerometer
        </p>
        <p class="text-[10px] text-zinc-500" data-accel-readout>
          x 0 · y 0 · z 1000
        </p>
      </div>
      <div
        id={@id}
        phx-hook="WatchAccelPad"
        data-mode={@mode}
        data-trigger={Map.get(@control || %{}, :trigger)}
        data-target={Map.get(@control || %{}, :target)}
        data-message={Map.get(@control || %{}, :message)}
        data-disabled={to_string(!@running)}
        class={[
          "mt-2 flex justify-center",
          !@running && "pointer-events-none opacity-50"
        ]}
      >
        <svg
          viewBox="0 0 120 120"
          role="application"
          aria-label="Accelerometer input pad"
          class="h-32 w-32 cursor-crosshair select-none"
        >
          <circle cx="60" cy="60" r="50" fill="#f8fafc" stroke="#71717a" stroke-width="1.5" />
          <line x1="10" y1="60" x2="110" y2="60" stroke="#d4d4d8" stroke-width="1" />
          <line x1="60" y1="10" x2="60" y2="110" stroke="#d4d4d8" stroke-width="1" />
          <g data-accel-cross transform="translate(60 60)">
            <line x1="-6" y1="0" x2="6" y2="0" stroke="#18181b" stroke-width="2" />
            <line x1="0" y1="-6" x2="0" y2="6" stroke="#18181b" stroke-width="2" />
            <circle cx="0" cy="0" r="3" fill="#18181b" />
          </g>
        </svg>
      </div>
      <p class="mt-1 text-center text-[10px] text-zinc-500">
        Click or drag inside the circle to send an accel sample.
      </p>
    </div>
    """
  end

  attr :control, :map, default: nil
  attr :running, :boolean, default: true

  @spec watch_tap_button(assigns()) :: rendered()
  defp watch_tap_button(assigns) do
    ~H"""
    <div class="rounded border border-zinc-200 bg-zinc-50 p-2">
      <p class="text-[11px] font-semibold uppercase tracking-wide text-zinc-600">Accel tap</p>
      <button
        type="button"
        phx-click="debugger-inject-trigger"
        phx-value-trigger="on_accel_tap"
        phx-value-target={@control[:target] || "watch"}
        phx-value-message={@control[:message]}
        disabled={!@running}
        class="mt-2 rounded bg-zinc-800 px-3 py-1.5 text-[11px] font-semibold text-white hover:bg-zinc-700 disabled:cursor-not-allowed disabled:opacity-50"
      >
        Send tap (X+)
      </button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :mode, :atom, required: true
  attr :settings, :map, required: true
  attr :running, :boolean, default: true

  @spec watch_compass_send(assigns()) :: rendered()
  defp watch_compass_send(assigns) do
    ~H"""
    <div class="rounded border border-zinc-200 bg-zinc-50 p-2">
      <p class="text-[11px] font-semibold uppercase tracking-wide text-zinc-600">Compass</p>
      <p class="mt-1 text-[10px] text-zinc-500">
        Uses heading and validity from simulator settings.
      </p>
      <button
        :if={@mode == :debugger}
        type="button"
        phx-click="debugger-sim-compass"
        disabled={!@running}
        class="mt-2 rounded bg-zinc-800 px-3 py-1.5 text-[11px] font-semibold text-white hover:bg-zinc-700 disabled:cursor-not-allowed disabled:opacity-50"
      >
        Send heading ({@settings["compass_heading_deg"]}°)
      </button>
      <button
        :if={@mode == :emulator}
        type="button"
        data-emulator-compass-send
        disabled={!@running}
        class="mt-2 rounded bg-zinc-800 px-3 py-1.5 text-[11px] font-semibold text-white hover:bg-zinc-700 disabled:cursor-not-allowed disabled:opacity-50"
      >
        Send heading ({@settings["compass_heading_deg"]}°)
      </button>
    </div>
    """
  end

  attr :settings, :map, required: true

  @spec watch_focus_notice(assigns()) :: rendered()
  defp watch_focus_notice(assigns) do
    ~H"""
    <div class="rounded border border-zinc-200 bg-zinc-50 p-2">
      <p class="text-[11px] font-semibold uppercase tracking-wide text-zinc-600">App focus</p>
      <p class="mt-1 text-[10px] text-zinc-500">
        Toggle <span class="font-medium">App in foreground</span>
        in simulator settings to fire a focus change.
      </p>
      <p class="mt-1 text-[10px] text-zinc-600">
        Current:
        <span class="font-medium">
          {if @settings["app_in_focus"], do: "In focus", else: "Out of focus"}
        </span>
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :running, :boolean, default: true

  @spec watch_dictation_sim(assigns()) :: rendered()
  defp watch_dictation_sim(assigns) do
    ~H"""
    <div class="rounded border border-zinc-200 bg-zinc-50 p-2">
      <p class="text-[11px] font-semibold uppercase tracking-wide text-zinc-600">Dictation</p>
      <p class="mt-1 text-[10px] text-zinc-500">
        Configure transcript or error in simulator settings, then simulate a completed session.
      </p>
      <button
        type="button"
        phx-click="debugger-sim-dictation"
        disabled={!@running}
        class="mt-2 rounded bg-zinc-800 px-3 py-1.5 text-[11px] font-semibold text-white hover:bg-zinc-700 disabled:cursor-not-allowed disabled:opacity-50"
      >
        Simulate dictation
      </button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :settings, :map, required: true
  attr :running, :boolean, default: true

  @spec watch_vibe_test(assigns()) :: rendered()
  defp watch_vibe_test(assigns) do
    ~H"""
    <div class="rounded border border-zinc-200 bg-zinc-50 p-2">
      <p class="text-[11px] font-semibold uppercase tracking-wide text-zinc-600">Vibration</p>
      <p class="mt-1 text-[10px] text-zinc-500">
        Plays the segment list from simulator settings.
      </p>
      <button
        type="button"
        phx-click="debugger-sim-vibes"
        disabled={!@running}
        class="mt-2 rounded bg-zinc-800 px-3 py-1.5 text-[11px] font-semibold text-white hover:bg-zinc-700 disabled:cursor-not-allowed disabled:opacity-50"
      >
        Play pattern
      </button>
    </div>
    """
  end

  attr :id, :string, required: true

  @spec watch_data_log_panel(assigns()) :: rendered()
  defp watch_data_log_panel(assigns) do
    ~H"""
    <div class="rounded border border-zinc-200 bg-zinc-50 p-2">
      <p class="text-[11px] font-semibold uppercase tracking-wide text-zinc-600">Data logging</p>
      <p class="mt-1 text-[10px] text-zinc-500">
        Recent data logging frames from the emulator phone bridge.
      </p>
      <div class="mt-2 max-h-40 overflow-auto rounded border border-zinc-200 bg-white">
        <table class="min-w-full text-left text-[10px]">
          <thead class="sticky top-0 border-b border-zinc-200 bg-white uppercase tracking-wide text-zinc-500">
            <tr>
              <th class="px-2 py-1">Tag</th>
              <th class="px-2 py-1">Type</th>
              <th class="px-2 py-1">Size</th>
            </tr>
          </thead>
          <tbody data-emulator-data-log-rows>
            <tr data-emulator-data-log-empty>
              <td colspan="3" class="px-2 py-2 text-zinc-500">No data logging frames yet.</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @spec interactive_active?(MapSet.t(String.t())) :: boolean()
  defp interactive_active?(caps) do
    Enum.any?(@interactive_caps, &MapSet.member?(caps, &1))
  end

  @spec accel_control(list(), list()) :: map() | nil
  defp accel_control(rows, disabled_subscriptions) when is_list(rows) do
    rows
    |> Enum.find(&accel_trigger_row?/1)
    |> case do
      %{} = row ->
        target = Map.get(row, :target) || Map.get(row, "target") || "watch"
        trigger = Map.get(row, :trigger) || Map.get(row, "trigger") || "on_accel_data"
        message = Map.get(row, :message) || Map.get(row, "message")

        if is_binary(message) and message != "" and
             subscription_trigger_enabled?(disabled_subscriptions, target, trigger) do
          %{trigger: trigger, target: target, message: message}
        else
          default_accel_control()
        end

      _ ->
        default_accel_control()
    end
  end

  defp accel_control(_rows, _disabled_subscriptions), do: default_accel_control()

  @spec default_accel_control() :: map()
  defp default_accel_control do
    %{trigger: "on_accel_data", target: "watch", message: nil}
  end

  @spec tap_control?(list(), list()) :: boolean()
  defp tap_control?(rows, disabled_subscriptions) when is_list(rows) do
    Enum.any?(rows, fn row ->
      trigger = Map.get(row, :trigger) || Map.get(row, "trigger")
      target = Map.get(row, :target) || Map.get(row, "target") || "watch"

      trigger in ["on_accel_tap", "on_accel"] and
        subscription_trigger_enabled?(disabled_subscriptions, target, trigger)
    end)
  end

  defp tap_control?(_rows, _disabled_subscriptions), do: false

  @spec accel_trigger_row?(map()) :: boolean()
  defp accel_trigger_row?(row) when is_map(row) do
    trigger = Map.get(row, :trigger) || Map.get(row, "trigger")
    trigger in ["on_accel", "on_accel_data"]
  end

  defp accel_trigger_row?(_row), do: false

  @spec subscription_trigger_enabled?(list(), String.t(), String.t()) :: boolean()
  defp subscription_trigger_enabled?(disabled_subscriptions, target, trigger)
       when is_list(disabled_subscriptions) do
    key = {to_string(target), to_string(trigger)}

    not Enum.any?(disabled_subscriptions, fn entry ->
      is_map(entry) and {Map.get(entry, :target) || Map.get(entry, "target"),
                          Map.get(entry, :trigger) || Map.get(entry, "trigger")} == key
    end)
  end

  defp subscription_trigger_enabled?(_disabled_subscriptions, _target, _trigger), do: true
end
