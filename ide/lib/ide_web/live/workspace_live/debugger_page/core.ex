defmodule IdeWeb.WorkspaceLive.DebuggerPage.Core do
  @moduledoc false
  use IdeWeb, :html

  import IdeWeb.WatchInteractives

  alias IdeWeb.WorkspaceLive.DebuggerPreview

  alias IdeWeb.WorkspaceLive.DebuggerPage.{
    Assigns,
    BitmapHydration,
    CompanionConfiguration,
    Export,
    ModelMetadata,
    ModelTree,
    Preview,
    RenderedTree,
    SessionState,
    SpeakerSamples,
    SubscriptionControls,
    SvgRender,
    Timeline,
    WatchButtons,
    WatchProfiles
  }

  alias IdeWeb.WorkspaceLive.DebuggerSupport
  alias Ide.Debugger.Types.CompanionConfiguration, as: ConfigTypes
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes
  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Projects.Project
  alias Phoenix.LiveView.Rendered

  @type assigns :: Assigns.t()
  @type rendered :: Rendered.t()
  @type model_node :: SupportTypes.model_tree_node()
  @type config_field :: ConfigTypes.field()
  @type trigger_row :: SupportTypes.trigger_button_row()
  @type svg_op :: SupportTypes.svg_op()
  @type wire_input :: DebuggerTypes.wire_input()
  @type view_preview_assigns :: Assigns.view_preview_assigns()
  @type model_value :: SupportTypes.wire_value()

  @spec render(assigns()) :: rendered()
  def render(assigns) do
    ~H"""
    <section
      :if={@pane == :debugger}
      class="flex min-h-0 flex-1 flex-col overflow-hidden rounded-lg border border-zinc-200 bg-white p-4 shadow-sm"
    >
      <div class="flex items-start justify-between gap-3">
        <div>
          <h2 class="text-base font-semibold">Debugger</h2>
          <p class="mt-1 text-sm text-zinc-600">
            Elm-style update timeline with selected watch/companion models and watch render output.
          </p>
        </div>
        <div class="flex shrink-0 flex-col items-end gap-2 sm:flex-row sm:items-center">
          <.debugger_copy_button
            :if={@debug_mode}
            id="debugger-copy-agent-state"
            text={Export.agent_state_clipboard_text(assigns, @project)}
            label="Copy for agent"
            title="Copy timeline, watch model, companion model, and rendered view as one markdown document"
          />
        </div>
      </div>
      <p :if={@debugger_state} class="mt-2 text-[11px] text-zinc-500">
        running: {to_string(@debugger_state.running)} · events: {length(@debugger_state.events)} · selected seq: {@debugger_cursor_seq ||
          "none"} · profile: {@debugger_state.watch_profile_id || "basalt"}
      </p>
      <div
        :if={@debugger_speaker_effect}
        id="debugger-speaker-effect"
        class="hidden"
        phx-hook="DebuggerSpeaker"
        data-project-slug={@project.slug}
        data-speaker-samples={SpeakerSamples.json(@project, @speaker_samples)}
        data-speaker-effect={Jason.encode!(@debugger_speaker_effect)}
      >
      </div>
      <div class="mt-3 flex flex-wrap items-center gap-2">
        <button
          type="button"
          phx-click="debugger-start"
          disabled={SessionState.bootstrap_busy?(@debugger_bootstrap_status)}
          class={[
            "rounded px-2 py-1 text-xs font-medium text-white",
            (SessionState.bootstrap_busy?(@debugger_bootstrap_status) &&
               "cursor-not-allowed bg-zinc-400") || "bg-zinc-800 hover:bg-zinc-700"
          ]}
        >
          {SessionState.start_button_label(@debugger_state, @debugger_bootstrap_status)}
        </button>
        <form class="flex items-center gap-2" phx-change="debugger-set-watch-profile">
          <label class="flex items-center gap-2 text-xs text-zinc-600">
            <span class="shrink-0">Watch model</span>
            <select
              name="watch_profile_id"
              disabled={SessionState.bootstrap_busy?(@debugger_bootstrap_status)}
              class={[
                "min-w-[12rem] max-w-full rounded border border-zinc-300 bg-white py-1 pl-2 pr-8 text-xs",
                SessionState.bootstrap_busy?(@debugger_bootstrap_status) &&
                  "cursor-not-allowed opacity-60"
              ]}
            >
              <option
                :for={profile <- Ide.Debugger.watch_profiles()}
                value={profile["id"]}
                selected={
                  profile["id"] ==
                    WatchProfiles.selected_id(@debugger_state, @project)
                }
              >
                {profile["label"]}
              </option>
            </select>
          </label>
        </form>
      </div>
      <div
        :if={SessionState.bootstrap_busy?(@debugger_bootstrap_status)}
        class="mt-2 w-full max-w-xl"
        data-testid="debugger-bootstrap-progress"
      >
        <p class="text-xs text-zinc-600">
          {@debugger_bootstrap_progress || "Starting debugger…"}
        </p>
        <div
          class="mt-1 h-1.5 overflow-hidden rounded-full bg-zinc-200"
          role="progressbar"
          aria-busy="true"
        >
          <div class="h-full w-1/3 animate-pulse rounded-full bg-zinc-600" />
        </div>
      </div>
      <div
        :if={SessionState.companion_bootstrap_busy?(@debugger_companion_bootstrap_status)}
        class="mt-2 w-full max-w-xl"
        data-testid="debugger-companion-bootstrap-progress"
      >
        <p class="text-xs text-zinc-600">
          {@debugger_companion_bootstrap_progress || "Loading companion app…"}
        </p>
        <div
          class="mt-1 h-1.5 overflow-hidden rounded-full bg-zinc-200"
          role="progressbar"
          aria-busy="true"
        >
          <div class="h-full w-1/3 animate-pulse rounded-full bg-zinc-500" />
        </div>
      </div>
      <div class="mt-3 grid min-h-0 flex-1 grid-cols-12 gap-3">
        <div class="col-span-12 flex min-h-0 flex-col rounded border border-zinc-200 bg-zinc-50 p-2 lg:col-span-3">
          <div class="flex items-center justify-between gap-2">
            <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-600">Timeline</h3>
            <div class="flex items-center gap-1">
              <span class="text-[10px] text-zinc-500" title="Step timeline when the pane is focused">
                j/k step
              </span>
              <.debugger_copy_button
                id="debugger-timeline-copy"
                text={
                  @debugger_rows
                  |> DebuggerSupport.debugger_rows_for_mode(
                    SessionState.visible_timeline_mode(@debugger_timeline_mode, @companion_app_present)
                  )
                  |> DebuggerSupport.debugger_timeline_text()
                }
                title="Copy visible timeline as raw text"
              />
              <form :if={@companion_app_present} phx-change="debugger-set-timeline-mode">
                <select
                  name="mode"
                  class="rounded border border-zinc-300 bg-white px-1.5 py-1 text-[11px] text-zinc-800"
                >
                  <option value="watch" selected={@debugger_timeline_mode == "watch"}>watch</option>
                  <option value="companion" selected={@debugger_timeline_mode == "companion"}>
                    companion
                  </option>
                  <option value="mixed" selected={@debugger_timeline_mode == "mixed"}>mixed</option>
                  <option value="separate" selected={@debugger_timeline_mode == "separate"}>
                    separate
                  </option>
                </select>
              </form>
            </div>
          </div>
          <div
            :if={
              SessionState.visible_timeline_mode(@debugger_timeline_mode, @companion_app_present) !=
                "separate"
            }
            class="mt-2 min-h-0 flex-1 overflow-auto rounded border border-zinc-200 bg-white"
          >
            <.debugger_debugger_timeline_rows
              rows={
                DebuggerSupport.debugger_rows_for_mode(
                  @debugger_rows,
                  SessionState.visible_timeline_mode(@debugger_timeline_mode, @companion_app_present)
                )
              }
              selected_row={@debugger_selected_row}
              empty_label="No update messages for this timeline view."
            />
          </div>
          <div
            :if={
              SessionState.visible_timeline_mode(@debugger_timeline_mode, @companion_app_present) ==
                "separate"
            }
            class="mt-2 grid min-h-0 flex-1 grid-rows-2 gap-2"
          >
            <div class="min-h-0 overflow-auto rounded border border-zinc-200 bg-white">
              <p class="sticky top-0 border-b border-zinc-100 bg-zinc-50 px-2 py-1 text-[10px] font-semibold uppercase tracking-wide text-zinc-500">
                Watch
              </p>
              <.debugger_debugger_timeline_rows
                rows={DebuggerSupport.debugger_rows_for_target(@debugger_rows, "watch")}
                selected_row={@debugger_selected_row}
                empty_label="No watch update messages."
              />
            </div>
            <div class="min-h-0 overflow-auto rounded border border-zinc-200 bg-white">
              <p class="sticky top-0 border-b border-zinc-100 bg-zinc-50 px-2 py-1 text-[10px] font-semibold uppercase tracking-wide text-zinc-500">
                Companion
              </p>
              <.debugger_debugger_timeline_rows
                rows={DebuggerSupport.debugger_rows_for_target(@debugger_rows, "companion")}
                selected_row={@debugger_selected_row}
                empty_label="No companion update messages."
              />
            </div>
          </div>
        </div>
        <div class={[
          "col-span-12 grid min-h-0 gap-3",
          if(@companion_app_present, do: "lg:col-span-4", else: "lg:col-span-3"),
          if(@companion_app_present, do: "grid-cols-2", else: "grid-cols-1")
        ]}>
          <div class="flex min-h-0 flex-col rounded border border-zinc-200 bg-zinc-50 p-2">
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-600">
                Watch model
              </h3>
              <.debugger_copy_button
                id="debugger-watch-model-copy"
                text={DebuggerSupport.copy_json(ModelMetadata.public_model(@debugger_watch_runtime))}
                title="Copy watch model as JSON"
              />
            </div>
            <.debugger_model_tree runtime={@debugger_watch_runtime} />
            <.debugger_subscription_buttons
              title="Watch subscribed events"
              rows={@debugger_watch_trigger_buttons}
              target="watch"
              auto_fire_subscriptions={@debugger_auto_fire_subscriptions}
              disabled_subscriptions={@debugger_disabled_subscriptions}
            />
          </div>
          <div
            :if={@companion_app_present}
            class="flex min-h-0 flex-col rounded border border-zinc-200 bg-zinc-50 p-2"
          >
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-600">
                Companion model
              </h3>
              <.debugger_copy_button
                id="debugger-companion-model-copy"
                text={
                  DebuggerSupport.copy_json(ModelMetadata.public_model(@debugger_companion_runtime))
                }
                title="Copy companion model as JSON"
              />
            </div>
            <.debugger_model_tree runtime={@debugger_companion_runtime} />
            <.debugger_companion_configuration
              runtime={@debugger_companion_runtime}
              debugger_state={@debugger_state}
              draft_values={@debugger_configuration_draft_values}
            />
            <.debugger_subscription_buttons
              title="Companion subscribed events"
              rows={@debugger_companion_trigger_buttons}
              target="phone"
              auto_fire_subscriptions={@debugger_auto_fire_subscriptions}
              disabled_subscriptions={@debugger_disabled_subscriptions}
            />
          </div>
        </div>
        <div class={[
          "col-span-12 grid min-h-0 grid-cols-2 gap-3",
          if(@companion_app_present, do: "lg:col-span-5", else: "lg:col-span-6")
        ]}>
          <div class="flex min-h-0 flex-col rounded border border-zinc-200 bg-zinc-50 p-2">
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-600">
                Rendered view
              </h3>
              <.debugger_copy_button
                id="debugger-rendered-view-copy"
                text={DebuggerSupport.copy_json(debugger_rendered_tree(@debugger_watch_view_runtime))}
                title="Copy rendered view as JSON"
              />
            </div>
            <.debugger_rendered_view_tree
              id="debugger-watch-rendered-view"
              scope="watch-live"
              runtime={@debugger_watch_view_runtime}
            />
          </div>
          <div class="flex h-full min-h-0 flex-col gap-3 overflow-y-auto pr-1">
            <.debugger_view_preview
              runtime={@debugger_watch_view_runtime}
              project={@project}
              title="Visual preview"
              fill={false}
              show_watch_buttons={true}
              watch_trigger_buttons={@debugger_watch_trigger_buttons}
              disabled_subscriptions={@debugger_disabled_subscriptions}
              hover_scope="watch-live"
              hovered_rendered_scope={@debugger_hovered_rendered_scope}
              hovered_rendered_path={@debugger_hovered_rendered_path}
            />
            <.simulator_settings_form
              id="debugger-simulator-settings"
              project={@project}
              debugger_state={@debugger_state}
              mode={:debugger}
              description="Simulated date/time affects debugger stepping only; the embedded QEMU watch face uses host clock unless you use an external SDK emulator (emu-set-time)."
            />
            <.watch_interactives_panel
              id="debugger-watch-interactives"
              project={@project}
              debugger_state={@debugger_state}
              mode={:debugger}
              watch_trigger_buttons={@debugger_watch_trigger_buttons}
              disabled_subscriptions={@debugger_disabled_subscriptions}
              running={SessionState.running?(@debugger_state)}
            />
          </div>
        </div>
      </div>
      <.debugger_trigger_modal open={@debugger_trigger_modal_open} form={@debugger_trigger_form} />
    </section>
    """
  end

  attr(:id, :string, required: true)
  attr(:text, :string, required: true)
  attr(:label, :string, default: "Copy")
  attr(:title, :string, default: "Copy to clipboard")
  attr(:copy_selector, :string, default: nil)

  @spec debugger_copy_button(assigns()) :: rendered()
  defp debugger_copy_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-hook="CopyToClipboard"
      data-copy-text={@text}
      data-copy-selector={@copy_selector}
      title={@title}
      class="shrink-0 rounded bg-zinc-900 px-2 py-1 text-[10px] font-medium text-white hover:bg-zinc-800"
    >
      {@label}
    </button>
    """
  end

  attr(:rows, :list, required: true)
  attr(:selected_row, :any, default: nil)
  attr(:empty_label, :string, default: "No update messages.")

  @spec debugger_debugger_timeline_rows(assigns()) :: rendered()
  defp debugger_debugger_timeline_rows(assigns) do
    ~H"""
    <button
      :for={row <- @rows}
      type="button"
      phx-click="debugger-select-debugger-event"
      phx-value-seq={row.seq}
      class={Timeline.row_class(row, @selected_row)}
    >
      <span class="font-mono text-zinc-500">#{row.seq}</span>
      <span class="ml-1 rounded bg-zinc-100 px-1 font-medium text-zinc-700">
        {row.target}
      </span>
      <span class="ml-1 font-mono text-zinc-900">
        {DebuggerSupport.debugger_message_label(row.message)}
      </span>
    </button>
    <p :if={@rows == []} class="p-2 text-xs text-zinc-500">
      {@empty_label}
    </p>
    """
  end

  attr(:runtime, :any, required: true)

  @spec debugger_model_tree(assigns()) :: rendered()
  defp debugger_model_tree(assigns) do
    model = ModelMetadata.public_model(assigns.runtime)
    assigns = assign(assigns, :model, model)

    ~H"""
    <div class="mt-2 min-h-0 flex-1 overflow-auto rounded border border-zinc-200 bg-white p-2 font-mono text-[11px] text-zinc-900">
      <.debugger_model_node
        :if={is_map(@model) && map_size(@model) > 0}
        label="model"
        value={@model}
        depth={0}
      />
      <p :if={!is_map(@model) || map_size(@model) == 0} class="text-zinc-500">(no runtime model)</p>
    </div>
    """
  end

  attr(:runtime, :any, required: true)
  attr(:debugger_state, :any, default: nil)
  attr(:draft_values, :map, default: %{})

  @spec debugger_companion_configuration(assigns()) :: rendered()
  defp debugger_companion_configuration(assigns) do
    configuration =
      CompanionConfiguration.model(
        Map.get(assigns.debugger_state || %{}, :companion) ||
          Map.get(assigns.debugger_state || %{}, "companion")
      ) ||
        CompanionConfiguration.model(assigns.runtime)

    configuration =
      if is_map(configuration) and map_size(assigns.draft_values) > 0 do
        CompanionConfiguration.put_values(configuration, assigns.draft_values)
      else
        configuration
      end

    assigns = assign(assigns, :configuration, configuration)

    ~H"""
    <div
      :if={is_map(@configuration)}
      class="mt-2 shrink-0 rounded border border-emerald-200 bg-white p-2 text-[11px] text-zinc-900"
      data-testid="debugger-companion-configuration"
    >
      <div class="flex items-center justify-between gap-2">
        <h4 class="text-[10px] font-semibold uppercase tracking-wide text-emerald-700">
          Configuration
        </h4>
        <button
          type="button"
          phx-click="debugger-reset-configuration"
          class="text-[10px] font-medium text-emerald-700 underline-offset-2 hover:underline"
        >
          Reset
        </button>
      </div>
      <.form
        for={%{}}
        as={:configuration}
        phx-change="debugger-change-configuration"
        phx-submit="debugger-save-configuration"
        class="mt-2 max-h-60 overflow-auto rounded border border-zinc-100 bg-zinc-50"
      >
        <section
          :for={section <- @configuration["sections"] || []}
          class="border-b border-zinc-100 last:border-b-0"
        >
          <p class="border-b border-zinc-100 bg-white px-2 py-1 text-[10px] font-semibold uppercase tracking-wide text-zinc-500">
            {section["title"] || "Preferences"}
          </p>
          <div class="divide-y divide-zinc-100">
            <.debugger_companion_configuration_field
              :for={field <- section["fields"] || []}
              field={field}
            />
          </div>
        </section>
        <div class="sticky bottom-0 border-t border-zinc-100 bg-white p-2">
          <button
            type="submit"
            class="w-full rounded bg-emerald-600 px-2 py-1 text-[11px] font-semibold text-white hover:bg-emerald-700"
          >
            Save configuration
          </button>
        </div>
      </.form>
    </div>
    """
  end

  attr(:field, :map, required: true)

  @spec debugger_companion_configuration_field(config_field()) :: rendered()
  defp debugger_companion_configuration_field(assigns) do
    control = Map.get(assigns.field, "control", %{})

    assigns =
      assigns
      |> assign(:control, control)
      |> assign(:field_id, Map.get(assigns.field, "id", ""))
      |> assign(:field_label, Map.get(assigns.field, "label", ""))
      |> assign(:control_type, Map.get(control, "type", "text"))
      |> assign(:control_default, Map.get(control, "default"))
      |> assign(:control_value, Map.get(control, "value", Map.get(control, "default")))

    ~H"""
    <label class="block px-2 py-1.5">
      <div class="flex items-center justify-between gap-2">
        <span class="font-medium text-zinc-700">{@field_label}</span>
        <span class="font-mono text-[10px] text-zinc-400">{@field_id}</span>
      </div>
      <input
        :if={@control_type == "toggle"}
        type="hidden"
        name={"configuration[#{@field_id}]"}
        value="false"
      />
      <input
        :if={@control_type == "toggle"}
        name={"configuration[#{@field_id}]"}
        type="checkbox"
        value="true"
        checked={CompanionConfiguration.truthy?(@control_value)}
        class="mt-1 rounded border-zinc-300"
      />
      <select
        :if={@control_type == "choice"}
        name={"configuration[#{@field_id}]"}
        class="mt-1 w-full rounded border border-zinc-200 bg-white px-2 py-1 text-[11px]"
      >
        <option
          :for={option <- @control["options"] || []}
          value={option["value"]}
          selected={option["value"] == @control_value}
        >
          {option["label"]}
        </option>
      </select>
      <input
        :if={@control_type in ["text", "number", "color", "slider"]}
        name={"configuration[#{@field_id}]"}
        type={CompanionConfiguration.input_type(@control_type)}
        value={CompanionConfiguration.input_value(@control_value)}
        min={@control["min"]}
        max={@control["max"]}
        step={CompanionConfiguration.input_step(@control_type, @control)}
        class="mt-1 w-full rounded border border-zinc-200 bg-white px-2 py-1 text-[11px]"
      />
      <p
        :if={@control_type not in ["toggle", "choice", "text", "number", "color", "slider"]}
        class="mt-1 text-zinc-500"
      >
        Unsupported control: {@control_type}
      </p>
    </label>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :any, required: true)
  attr(:depth, :integer, default: 0)

  @spec debugger_model_node(model_node()) :: rendered()
  defp debugger_model_node(assigns) do
    children = debugger_model_children(assigns.value)
    scalar = debugger_model_scalar(assigns.value)

    assigns =
      assigns
      |> assign(:children, children)
      |> assign(:scalar, scalar)
      |> assign(:tooltip, debugger_model_tooltip(assigns.label, assigns.value, children, scalar))
      |> assign(:open, assigns.depth < 2)

    ~H"""
    <div class="pl-1">
      <details :if={@children != []} open={@open} class="mt-0.5">
        <summary class="cursor-pointer select-none text-zinc-800" title={@tooltip}>
          <span class="font-semibold">{@label}</span>
          <span class="text-zinc-500">{debugger_model_container_label(@value)}</span>
        </summary>
        <div class="ml-3 border-l border-zinc-200 pl-2">
          <.debugger_model_node
            :for={child <- @children}
            label={child.label}
            value={child.value}
            depth={@depth + 1}
          />
        </div>
      </details>
      <div :if={@children == []} class="mt-0.5 truncate" title={@tooltip}>
        <span class="font-semibold text-zinc-800">{@label}</span>
        <span class="text-zinc-500"> = </span>
        <span class="text-zinc-700">{@scalar}</span>
      </div>
    </div>
    """
  end

  @spec debugger_model_children(model_node()) :: [%{label: String.t(), value: model_value()}]
  defp debugger_model_children(value), do: ModelTree.debugger_model_children(value)

  @spec debugger_model_tooltip(String.t(), model_node(), [ModelTree.model_child_row()], String.t()) ::
          String.t()
  defp debugger_model_tooltip(label, value, children, scalar),
    do: ModelTree.debugger_model_tooltip(label, value, children, scalar)

  @spec debugger_model_scalar(model_node()) :: String.t()
  defp debugger_model_scalar(value), do: ModelTree.debugger_model_scalar(value)

  @spec debugger_model_container_label(SupportTypes.model_map() | list()) :: String.t()
  defp debugger_model_container_label(value), do: ModelTree.debugger_model_container_label(value)

  attr(:open, :boolean, required: true)
  attr(:form, :any, required: true)

  defp debugger_trigger_modal(assigns) do
    ~H"""
    <div :if={@open} class="fixed inset-0 z-50 grid place-items-center p-4">
      <div class="absolute inset-0 bg-black/40" phx-click="debugger-close-trigger-modal"></div>
      <div class="relative z-10 w-full max-w-md rounded-lg bg-white p-4 shadow-xl">
        <h3 class="text-sm font-semibold">Fire subscribed event</h3>
        <p class="mt-1 text-xs text-zinc-500">
          Review the message payload before injecting it into the debugger.
        </p>
        <.form
          for={@form}
          phx-change="debugger-trigger-form-change"
          phx-submit="debugger-submit-trigger"
          class="mt-3 space-y-3"
        >
          <input type="hidden" name="debugger_trigger[target]" value={@form[:target].value} />
          <input type="hidden" name="debugger_trigger[trigger]" value={@form[:trigger].value} />
          <input
            type="hidden"
            name="debugger_trigger[payload_kind]"
            value={@form[:payload_kind].value}
          />
          <input
            type="hidden"
            name="debugger_trigger[message_constructor]"
            value={@form[:message_constructor].value}
          />
          <input
            :if={@form[:payload_kind].value == "companion_bridge"}
            type="hidden"
            name="debugger_trigger[companion_contract]"
            value={@form[:companion_contract].value}
          />
          <label class="flex flex-col gap-1 text-xs text-zinc-600">
            <span>Trigger</span>
            <input
              type="text"
              value={@form[:trigger_display].value || @form[:trigger].value}
              readonly
              class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 font-mono text-[11px]"
            />
          </label>
          <.input
            :if={@form[:payload_kind].value == "message"}
            field={@form[:message]}
            type="text"
            label="Message"
            placeholder="Tick"
          />
          <.companion_bridge_trigger_fields
            :if={@form[:payload_kind].value == "companion_bridge"}
            form={@form}
          />
          <.input
            :if={@form[:payload_kind].value == "integer"}
            field={@form[:payload]}
            type="number"
            label="Value"
          />
          <.input
            :if={@form[:payload_kind].value == "boolean"}
            field={@form[:payload]}
            type="select"
            label="Value"
            options={[{"True", "True"}, {"False", "False"}]}
          />
          <label
            :if={@form[:payload_kind].value == "none"}
            class="flex flex-col gap-1 text-xs text-zinc-600"
          >
            <span>Message</span>
            <input
              type="text"
              value={@form[:message].value}
              readonly
              class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 font-mono text-[11px]"
            />
          </label>
          <p class="text-[11px] text-zinc-500">
            Time subscriptions use the current local clock. System subscriptions use editable simulated values.
          </p>
          <div class="flex justify-end gap-2 pt-2">
            <button
              type="button"
              phx-click="debugger-close-trigger-modal"
              class="rounded px-3 py-2 text-xs text-zinc-600"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="rounded bg-zinc-900 px-3 py-2 text-xs font-medium text-white hover:bg-zinc-800"
            >
              Fire event
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr(:form, :any, required: true)

  defp companion_bridge_trigger_fields(assigns) do
    plain_result? = assigns.form[:companion_plain_result].value in [true, "true"]
    json_payload? = assigns.form[:companion_json_payload].value in [true, "true"]
    fields = List.wrap(assigns.form[:companion_fields].value)

    assigns =
      assigns
      |> assign(:plain_result?, plain_result?)
      |> assign(:json_payload?, json_payload?)
      |> assign(:fields, fields)

    ~H"""
    <.input
      :if={not @plain_result?}
      field={@form[:result]}
      type="select"
      label="Result"
      options={[{"Ok", "Ok"}, {"Err", "Err"}]}
    />
    <.input
      :if={not @plain_result? and @form[:result].value == "Err"}
      field={@form[:error_message]}
      type="text"
      label="Error message"
      placeholder="Unavailable"
    />
    <div :if={not @json_payload? and @form[:result].value != "Err"} class="space-y-2">
      <label :for={field <- @fields} class="flex flex-col gap-1 text-xs text-zinc-600">
        <span>{field["label"] || field[:label]}</span>
        <input
          :if={(field["type"] || field[:type]) == "string"}
          type="text"
          name={"debugger_trigger[companion_field_#{field["key"] || field[:key]}]"}
          value={field["value"] || field[:value]}
          class="rounded border border-zinc-200 px-2 py-1 font-mono text-[11px]"
        />
        <input
          :if={(field["type"] || field[:type]) == "integer"}
          type="number"
          name={"debugger_trigger[companion_field_#{field["key"] || field[:key]}]"}
          value={field["value"] || field[:value]}
          class="rounded border border-zinc-200 px-2 py-1 font-mono text-[11px]"
        />
        <select
          :if={(field["type"] || field[:type]) == "boolean"}
          name={"debugger_trigger[companion_field_#{field["key"] || field[:key]}]"}
          class="rounded border border-zinc-200 px-2 py-1 text-[11px]"
        >
          <option value="true" selected={(field["value"] || field[:value]) == "true"}>True</option>
          <option value="false" selected={(field["value"] || field[:value]) == "false"}>False</option>
        </select>
      </label>
    </div>
    <label
      :if={@json_payload? and @form[:result].value != "Err"}
      class="flex flex-col gap-1 text-xs text-zinc-600"
    >
      <span>Payload (JSON)</span>
      <textarea
        name="debugger_trigger[payload_json]"
        rows="6"
        class="rounded border border-zinc-200 px-2 py-1 font-mono text-[11px]"
      >{@form[:payload_json].value}</textarea>
    </label>
    """
  end

  attr(:title, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:target, :string, required: true)
  attr(:auto_fire_subscriptions, :list, default: [])
  attr(:disabled_subscriptions, :list, default: [])

  @spec debugger_subscription_buttons(assigns()) :: rendered()
  defp debugger_subscription_buttons(assigns) do
    ~H"""
    <div class="mt-2 shrink-0 rounded border border-zinc-200 bg-white p-2">
      <p class="text-[11px] font-semibold text-zinc-700">{@title}</p>
      <div class="mt-1 flex flex-wrap gap-1">
        <div :for={row <- @rows} class="inline-flex items-center gap-1 rounded bg-zinc-100 px-1 py-1">
          <form
            :if={not subscription_trigger_enabled?(@disabled_subscriptions, @target, row.trigger)}
            phx-change="debugger-set-subscription-enabled"
            class="flex items-center gap-1"
          >
            <input type="hidden" name="target" value={@target} />
            <input type="hidden" name="trigger" value={row.trigger} />
            <input type="hidden" name="enabled" value="false" />
            <input
              type="checkbox"
              name="enabled"
              value="true"
              checked={subscription_trigger_enabled?(@disabled_subscriptions, @target, row.trigger)}
              class="rounded border-zinc-300"
              title="Enable this subscribed event"
            />
            <span class="text-[9px] uppercase tracking-wide text-zinc-500">Enabled</span>
          </form>
          <form
            :if={subscription_auto_fire_toggle_visible?(@auto_fire_subscriptions, @target, row)}
            phx-change="debugger-set-auto-fire"
            class="flex items-center gap-1"
          >
            <input type="hidden" name="target" value={@target} />
            <input type="hidden" name="trigger" value={row.trigger} />
            <input type="hidden" name="enabled" value="false" />
            <input
              type="checkbox"
              name="enabled"
              value="true"
              checked={
                subscription_auto_fire_enabled?(@auto_fire_subscriptions, @target, row.trigger)
              }
              disabled={
                not subscription_trigger_enabled?(@disabled_subscriptions, @target, row.trigger)
              }
              class="rounded border-zinc-300"
              title="Auto-fire this subscribed event"
            />
            <span class="text-[9px] uppercase tracking-wide text-zinc-500">Auto</span>
          </form>
          <button
            type="button"
            phx-click="debugger-open-trigger-modal"
            phx-value-trigger={row.trigger}
            phx-value-target={row.target}
            phx-value-message={row.message}
            phx-value-trigger-display={row.trigger_display}
            disabled={
              not subscription_trigger_enabled?(@disabled_subscriptions, @target, row.trigger) or
                not subscription_trigger_injection_supported?(row) or
                not row.model_active?
            }
            title={subscription_trigger_button_title(row)}
            class="rounded bg-zinc-200 px-2 py-1 text-[10px] font-medium text-zinc-800 hover:bg-zinc-300 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {row.label}
          </button>
        </div>
        <span :if={@rows == []} class="text-[11px] text-zinc-500">
          No parsed subscriptions for this app.
        </span>
      </div>
    </div>
    """
  end

  @spec subscription_trigger_enabled?(
          [IdeWeb.WorkspaceLive.DebuggerFlow.Types.auto_fire_subscription_row()],
          String.t(),
          String.t()
        ) :: boolean()
  defp subscription_trigger_enabled?(disabled_subscriptions, target, trigger),
    do: SubscriptionControls.enabled?(disabled_subscriptions, target, trigger)

  @spec subscription_trigger_injection_supported?(trigger_row()) :: boolean()
  defp subscription_trigger_injection_supported?(row),
    do: SubscriptionControls.injection_supported?(row)

  @spec subscription_trigger_button_title(trigger_row()) :: String.t()
  defp subscription_trigger_button_title(row), do: SubscriptionControls.button_title(row)

  @spec subscription_auto_fire_enabled?(
          [IdeWeb.WorkspaceLive.DebuggerFlow.Types.auto_fire_subscription_row()],
          String.t(),
          String.t()
        ) :: boolean()
  defp subscription_auto_fire_enabled?(auto_fire_subscriptions, target, trigger),
    do: SubscriptionControls.auto_fire_enabled?(auto_fire_subscriptions, target, trigger)

  @spec subscription_auto_fire_toggle_visible?(
          [IdeWeb.WorkspaceLive.DebuggerFlow.Types.auto_fire_subscription_row()],
          String.t(),
          trigger_row()
        ) :: boolean()
  defp subscription_auto_fire_toggle_visible?(auto_fire_subscriptions, target, row),
    do: SubscriptionControls.auto_fire_toggle_visible?(auto_fire_subscriptions, target, row)

  attr(:runtime, :any, required: true)
  attr(:project, :any, default: nil)
  attr(:title, :string, default: "Visual preview")
  attr(:fill, :boolean, default: true)
  attr(:show_watch_buttons, :boolean, default: false)
  attr(:watch_trigger_buttons, :list, default: [])
  attr(:disabled_subscriptions, :list, default: [])
  attr(:hover_scope, :string, default: nil)
  attr(:hovered_rendered_scope, :any, default: nil)
  attr(:hovered_rendered_path, :any, default: nil)

  @spec debugger_view_preview(view_preview_assigns()) :: rendered()
  defp debugger_view_preview(assigns) do
    tree = Preview.preview_tree(assigns.runtime)
    rendered_tree = debugger_rendered_tree(assigns.runtime)
    preview_tree = Preview.svg_preview_tree(rendered_tree, tree)
    {screen_w, screen_h} = Preview.dimensions(assigns.runtime, preview_tree)
    screen_round? = DebuggerPreview.screen_round?(assigns.runtime, tree)
    clip_radius = min(screen_w, screen_h) / 2
    clip_id = Preview.clip_id(assigns.title, assigns.hover_scope, screen_w, screen_h, screen_round?)
    svg_id = Preview.svg_id(assigns.title, assigns.hover_scope)

    color_mode = Preview.watch_color_mode(assigns.runtime)

    svg_ops =
      preview_tree
      |> debugger_watch_svg_ops(assigns.runtime)
      |> DebuggerPreview.resolve_bitmap_svg_ops(assigns.project)
      |> hydrate_bitmap_svg_ops(assigns.project, color_mode)
      |> DebuggerPreview.hydrate_animation_svg_ops(assigns.project)
      |> DebuggerPreview.hydrate_vector_svg_ops(assigns.project)

    unresolved_ops = Enum.filter(svg_ops, &(&1.kind == :unresolved))

    hover_box =
      case {assigns.hover_scope, assigns.hovered_rendered_path} do
        {scope, path}
        when scope != nil and scope == assigns.hovered_rendered_scope and is_binary(path) ->
          DebuggerSupport.rendered_node_bounds(
            rendered_tree,
            path,
            screen_w,
            screen_h,
            assigns.project
          )

        _ ->
          nil
      end

    assigns =
      assigns
      |> assign(:tree, tree)
      |> assign(:rendered_tree, rendered_tree)
      |> assign(:screen_w, screen_w)
      |> assign(:screen_h, screen_h)
      |> assign(:screen_round?, screen_round?)
      |> assign(:clip_cx, screen_w / 2)
      |> assign(:clip_cy, screen_h / 2)
      |> assign(:clip_radius, clip_radius)
      |> assign(:clip_id, clip_id)
      |> assign(:svg_id, svg_id)
      |> assign(
        :preview_svg_class,
        Preview.svg_class(screen_round?, assigns.show_watch_buttons)
      )
      |> assign(:svg_ops, svg_ops)
      |> assign(:unresolved_ops, unresolved_ops)
      |> assign(:hover_box, hover_box)
      |> assign(
        :watch_button_controls,
        WatchButtons.controls(
          assigns.watch_trigger_buttons,
          assigns.disabled_subscriptions
        )
      )

    ~H"""
    <div
      class={[
        "flex min-h-0 flex-col rounded border border-zinc-200 bg-zinc-50 p-2",
        if(@fill, do: "h-full", else: "shrink-0")
      ]}
      data-copy-scope
    >
      <div class="mb-2 flex shrink-0 items-center justify-between gap-2">
        <p class="text-[11px] font-semibold uppercase tracking-wide text-zinc-600">
          {@title}
        </p>
        <.debugger_copy_button
          id={"#{@svg_id}-copy"}
          text=""
          label="Copy SVG"
          title="Copy visual preview SVG"
          copy_selector={"##{@svg_id}"}
        />
      </div>
      <div class="mb-2 shrink-0 rounded border border-zinc-200 bg-zinc-100 p-2">
        <div class={[
          if(@show_watch_buttons, do: "flex", else: "block"),
          "items-center justify-center gap-0.5 overflow-hidden"
        ]}>
          <.debugger_watch_button :if={@show_watch_buttons} button={@watch_button_controls.back} />
          <svg
            id={@svg_id}
            viewBox={"0 0 #{@screen_w} #{@screen_h}"}
            role="img"
            aria-label="Watch screen preview"
            class={@preview_svg_class}
          >
            <defs :if={@screen_round?}>
              <clipPath id={@clip_id}>
                <circle cx={@clip_cx} cy={@clip_cy} r={@clip_radius} />
              </clipPath>
            </defs>
            <g clip-path={if @screen_round?, do: "url(##{@clip_id})", else: nil}>
              <rect x="0" y="0" width={@screen_w} height={@screen_h} fill="white" />
              <%= for op <- @svg_ops do %>
                <.debugger_vector_sequence_anim :if={op.kind == :vector_sequence_anim} op={op} />
                <image
                  :if={op.kind == :bitmap_sequence_at and is_binary(op[:href])}
                  x={op.x}
                  y={op.y}
                  width={op.width}
                  height={op.height}
                  href={op.href}
                  preserveAspectRatio="none"
                />
                <g :if={op.kind not in [:vector_sequence_anim, :bitmap_sequence_at]}>
                  <title :if={Preview.svg_op_tooltip(op) != nil}>
                    {Preview.svg_op_tooltip(op)}
                  </title>
                  <rect
                    :if={op.kind == :clear}
                    x="0"
                    y="0"
                    width={@screen_w}
                    height={@screen_h}
                    fill={SvgRender.color(op.color, "white")}
                  />
                  <image
                    :if={op.kind == :bitmap_in_rect and is_binary(op[:href])}
                    x={op.x}
                    y={op.y}
                    width={op.w}
                    height={op.h}
                    href={op.href}
                    preserveAspectRatio="none"
                  />
                  <image
                    :if={op.kind == :rotated_bitmap and is_binary(op[:href])}
                    x={op.center_x - div(op.src_w, 2)}
                    y={op.center_y - div(op.src_h, 2)}
                    width={op.src_w}
                    height={op.src_h}
                    href={op.href}
                    transform={"rotate(#{Preview.pebble_angle_deg(op.angle)} #{op.center_x} #{op.center_y})"}
                    preserveAspectRatio="none"
                  />
                  <rect
                    :if={op.kind == :round_rect}
                    x={op.x}
                    y={op.y}
                    width={op.w}
                    height={op.h}
                    rx={op.radius}
                    ry={op.radius}
                    fill="none"
                    stroke={SvgRender.color(op.stroke_color, "#111111")}
                    stroke-width={op.stroke_width || 1}
                  />
                  <rect
                    :if={op.kind == :rect}
                    x={op.x}
                    y={op.y}
                    width={op.w}
                    height={op.h}
                    fill="none"
                    stroke={SvgRender.color(op.stroke_color, "#111111")}
                    stroke-width={op.stroke_width || 1}
                  />
                  <rect
                    :if={op.kind == :fill_rect}
                    x={op.x}
                    y={op.y}
                    width={op.w}
                    height={op.h}
                    fill={SvgRender.color(op.fill_color, "#111111")}
                    stroke={
                      SvgRender.color(
                        op.stroke_color,
                        SvgRender.color(op.fill_color, "#111111")
                      )
                    }
                    stroke-width={op.stroke_width || 1}
                  />
                  <line
                    :if={op.kind == :line}
                    x1={op.x1}
                    y1={op.y1}
                    x2={op.x2}
                    y2={op.y2}
                    stroke={SvgRender.color(op.stroke_color, "#111111")}
                    stroke-width={op.stroke_width || 1}
                  />
                  <path
                    :if={op.kind == :arc}
                    d={SvgRender.arc_path(op)}
                    fill="none"
                    stroke={SvgRender.color(op.stroke_color, "#111111")}
                    stroke-width={op.stroke_width || 1}
                  />
                  <path
                    :if={op.kind == :fill_radial}
                    d={SvgRender.arc_sector_path(op)}
                    fill={SvgRender.color(op.fill_color, "#111111")}
                    stroke={
                      SvgRender.color(
                        op.stroke_color,
                        SvgRender.color(op.fill_color, "#111111")
                      )
                    }
                    stroke-width={op.stroke_width || 1}
                  />
                  <path
                    :if={op.kind == :path_filled}
                    d={SvgRender.path_d(op, true)}
                    fill={SvgRender.color(op.fill_color, "#111111")}
                    stroke={
                      SvgRender.color(
                        op.stroke_color,
                        SvgRender.color(op.fill_color, "#111111")
                      )
                    }
                    stroke-width={op.stroke_width || 1}
                  />
                  <path
                    :if={op.kind == :path_outline}
                    d={SvgRender.path_d(op, true)}
                    fill="none"
                    stroke={SvgRender.color(op.stroke_color, "#111111")}
                    stroke-width={op.stroke_width || 1}
                  />
                  <path
                    :if={op.kind == :path_outline_open}
                    d={SvgRender.path_d(op, false)}
                    fill="none"
                    stroke={SvgRender.color(op.stroke_color, "#111111")}
                    stroke-width={op.stroke_width || 1}
                  />
                  <circle
                    :if={op.kind == :circle}
                    cx={op.cx}
                    cy={op.cy}
                    r={op.r}
                    fill="none"
                    stroke={SvgRender.color(op.stroke_color, "#111111")}
                    stroke-width={op.stroke_width || 1}
                  />
                  <circle
                    :if={op.kind == :fill_circle}
                    cx={op.cx}
                    cy={op.cy}
                    r={op.r}
                    fill={SvgRender.color(op.fill_color, "#111111")}
                    stroke={
                      SvgRender.color(
                        op.stroke_color,
                        SvgRender.color(op.fill_color, "#111111")
                      )
                    }
                    stroke-width={op.stroke_width || 1}
                  />
                  <rect
                    :if={op.kind == :pixel}
                    x={op.x}
                    y={op.y}
                    width="1"
                    height="1"
                    fill={SvgRender.color(op.stroke_color, "#111111")}
                  />
                  <text
                    :if={op.kind == :text_int}
                    x={op.x}
                    y={op.y}
                    font-size="14"
                    font-family="monospace"
                    fill={SvgRender.color(op.text_color, "#111111")}
                  >
                    {op.text}
                  </text>
                  <text
                    :if={op.kind == :text_label}
                    x={SvgRender.text_x(op)}
                    y={SvgRender.text_y(op)}
                    font-size={SvgRender.text_font_size(op)}
                    font-family="sans-serif"
                    text-anchor={SvgRender.text_anchor(op)}
                    dominant-baseline={SvgRender.text_baseline(op)}
                    fill={SvgRender.color(op.text_color, "#111111")}
                  >
                    {op.text}
                  </text>
                </g>
              <% end %>
              <rect
                :if={is_map(@hover_box)}
                x={@hover_box.x}
                y={@hover_box.y}
                width={@hover_box.w}
                height={@hover_box.h}
                fill="rgba(59, 130, 246, 0.12)"
                stroke="#2563eb"
                stroke-width="1.5"
                stroke-dasharray="3 2"
                pointer-events="none"
              />
            </g>
          </svg>
          <div :if={@show_watch_buttons} class="flex flex-col items-stretch gap-1">
            <.debugger_watch_button button={@watch_button_controls.up} />
            <.debugger_watch_button button={@watch_button_controls.select} />
            <.debugger_watch_button button={@watch_button_controls.down} />
          </div>
        </div>
        <p :if={@svg_ops == []} class="mt-1 text-center text-[10px] text-zinc-500">
          No drawable primitives found in this snapshot.
        </p>
        <p :if={@unresolved_ops != []} class="mt-1 text-center text-[10px] text-amber-700">
          {Preview.unresolved_svg_summary(@unresolved_ops)}
        </p>
      </div>
    </div>
    """
  end

  attr(:button, :map, required: true)

  @spec debugger_watch_button(assigns()) :: rendered()
  defp debugger_watch_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="debugger-inject-trigger"
      phx-value-trigger={@button.trigger}
      phx-value-target={@button.target}
      phx-value-message={@button.message}
      disabled={!@button.enabled}
      title={@button.title}
      data-testid={"debugger-watch-button-#{@button.id}"}
      class={[
        "min-w-10 rounded-full border px-1.5 py-1 text-[9px] font-semibold uppercase tracking-wide shadow-sm transition",
        if(@button.enabled,
          do: "border-zinc-500 bg-zinc-800 text-white hover:bg-zinc-700",
          else: "cursor-not-allowed border-zinc-200 bg-zinc-200 text-zinc-400"
        )
      ]}
    >
      {@button.label}
    </button>
    """
  end

  attr(:id, :string, required: true)
  attr(:scope, :string, required: true)
  attr(:runtime, :any, required: true)

  @spec debugger_rendered_view_tree(assigns()) :: rendered()
  defp debugger_rendered_view_tree(assigns) do
    tree = debugger_rendered_tree(assigns.runtime)
    model = debugger_runtime_model(assigns.runtime)
    assigns = assign(assigns, :tree, tree) |> assign(:model, model)

    ~H"""
    <div
      id={@id}
      phx-hook="PreserveRenderedDetails"
      class="mt-1 min-h-0 flex-1 overflow-auto rounded border border-zinc-200 bg-white p-2 font-mono text-[11px] text-zinc-900"
    >
      <.debugger_rendered_node
        :if={is_map(@tree)}
        node={@tree}
        model={@model}
        depth={0}
        arg_name={nil}
        path="0"
        scope={@scope}
      />
      <p :if={!is_map(@tree)} class="text-[11px] text-zinc-500">(no rendered view in snapshot)</p>
    </div>
    """
  end

  attr(:node, :map, required: true)
  attr(:model, :map, required: true)
  attr(:depth, :integer, default: 0)
  attr(:arg_name, :any, default: nil)
  attr(:path, :string, default: "0")
  attr(:scope, :string, required: true)

  @spec debugger_rendered_node(assigns()) :: rendered()
  defp debugger_rendered_node(assigns) do
    node = assigns.node
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "node")

    children =
      (Map.get(node, "children") || Map.get(node, :children) || [])
      |> Enum.filter(&is_map/1)
      |> RenderedTree.child_rows(node, assigns.path)
      |> Enum.reject(fn %{node: child} ->
        child_type = to_string(Map.get(child, "type") || Map.get(child, :type) || "")
        RenderedTree.hidden_node_type?(child_type)
      end)

    assigns =
      assigns
      |> assign(:type, type)
      |> assign(
        :summary,
        DebuggerSupport.rendered_node_summary(node, assigns.model, assigns.arg_name)
      )
      |> assign(:source_tooltip, RenderedTree.source_tooltip(node))
      |> assign(:children, children)

    ~H"""
    <div :if={!RenderedTree.hidden_node_type?(@type)} class="pl-1">
      <div :if={@children != [] && @depth < 2} class="mt-0.5">
        <div
          class="rounded px-0.5 text-zinc-800 hover:bg-blue-50 hover:text-blue-950"
          data-rendered-node-hover-path={@path}
          data-rendered-node-hover-scope={@scope}
          title={@source_tooltip}
        >
          {@summary}
        </div>
        <div class="ml-3 border-l border-zinc-200 pl-2">
          <.debugger_rendered_node
            :for={child <- @children}
            node={child.node}
            model={@model}
            depth={@depth + 1}
            arg_name={child.arg_name}
            path={child.path}
            scope={@scope}
          />
        </div>
      </div>
      <details :if={@children != [] && @depth >= 2} class="mt-0.5" data-rendered-node-path={@path}>
        <summary
          class="cursor-pointer select-none rounded px-0.5 text-zinc-800 hover:bg-blue-50 hover:text-blue-950"
          data-rendered-node-hover-path={@path}
          data-rendered-node-hover-scope={@scope}
          title={@source_tooltip}
        >
          {@summary}
        </summary>
        <div class="ml-3 border-l border-zinc-200 pl-2">
          <.debugger_rendered_node
            :for={child <- @children}
            node={child.node}
            model={@model}
            depth={@depth + 1}
            arg_name={child.arg_name}
            path={child.path}
            scope={@scope}
          />
        </div>
      </details>
      <div
        :if={@children == []}
        class="mt-0.5 rounded px-0.5 text-zinc-800 hover:bg-blue-50 hover:text-blue-950"
        data-rendered-node-hover-path={@path}
        data-rendered-node-hover-scope={@scope}
        title={@source_tooltip}
      >
        {@summary}
      </div>
    </div>
    """
  end

  @spec debugger_watch_svg_ops(SupportTypes.view_tree() | nil, SupportTypes.runtime_input()) ::
          [svg_op()]
  defp debugger_watch_svg_ops(tree, runtime), do: DebuggerPreview.svg_ops(tree, runtime)

  @spec hydrate_bitmap_svg_ops([svg_op()], Project.t() | nil, String.t() | nil) :: [svg_op()]
  defp hydrate_bitmap_svg_ops(rows, project, color_mode),
    do: BitmapHydration.hydrate_svg_ops(rows, project, color_mode)

  attr(:op, :map, required: true)

  @spec debugger_vector_sequence_anim(assigns()) :: rendered()
  defp debugger_vector_sequence_anim(assigns) do
    op = assigns.op
    frame_count = length(Map.get(op, :frame_elements, []))

    assigns =
      assigns
      |> assign(:frame_count, frame_count)
      |> assign(:frame_durations_json, Jason.encode!(Map.get(op, :durations, [])))
      |> assign(:play_count, Map.get(op, :play_count, 1))

    ~H"""
    <svg
      x={@op.x}
      y={@op.y}
      width={@op.width}
      height={@op.height}
      viewBox={"0 0 #{@op.width} #{@op.height}"}
      overflow="visible"
      id={@op.anim_id}
      phx-hook="VectorSequenceAnimation"
      phx-update="ignore"
      data-frame-durations={@frame_durations_json}
      data-play-count={@play_count}
      data-frame-count={@frame_count}
      aria-hidden="true"
    >
      <%= for {elements, index} <- Enum.with_index(@op.frame_elements) do %>
        <g
          class="debugger-vector-seq-frame"
          data-frame={index}
          style={if index == 0, do: "opacity:1", else: "opacity:0"}
        >
          {raw(elements)}
        </g>
      <% end %>
    </svg>
    """
  end

  @spec debugger_runtime_model(SupportTypes.runtime_input()) :: SupportTypes.model_map()
  defp debugger_runtime_model(runtime), do: DebuggerPreview.runtime_model(runtime)

  @spec debugger_rendered_tree(SupportTypes.runtime_input()) :: DebuggerTypes.rendered_tree() | nil
  defp debugger_rendered_tree(runtime), do: DebuggerSupport.rendered_tree(runtime)
end
