defmodule IdeWeb.WorkspaceLive.DebuggerPage do
  @moduledoc false
  use IdeWeb, :html

  alias Ide.Debugger
  alias Ide.Projects.Project
  alias Ide.Resources.ResourceStore
  alias IdeWeb.WorkspaceLive.DebuggerPreview
  alias IdeWeb.WorkspaceLive.DebuggerSupport

  @debugger_model_metadata_keys ~w(
    last_message
    last_operation
    step_counter
    last_runtime_step_message
    last_runtime_step_op
    runtime_last_message
    runtime_message_source
    runtime_model_source
    protocol_last_inbound_message
    protocol_last_inbound_from
    protocol_inbound_count
    protocol_last_trigger
    configuration
  )

  @spec render(term()) :: term()
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
            id="debugger-copy-agent-state"
            text={debugger_agent_state_clipboard_text(assigns)}
            label="Copy for agent"
            title="Copy timeline, watch model, companion model, and rendered view as one markdown document"
          />
          <button
            type="button"
            phx-click="debugger-toggle-advanced"
            class="rounded bg-zinc-100 px-2 py-1 text-xs font-medium text-zinc-700 hover:bg-zinc-200"
          >
            {if @debugger_advanced_debug_tools, do: "Hide advanced tools", else: "Advanced tools"}
          </button>
        </div>
      </div>
      <p :if={@debugger_state} class="mt-2 text-[11px] text-zinc-500">
        running: {to_string(@debugger_state.running)} · events: {length(@debugger_state.events)} · selected seq: {@debugger_cursor_seq ||
          "none"} · profile: {@debugger_state.watch_profile_id || "basalt"}
      </p>
      <div class="mt-3 flex flex-wrap items-center gap-2">
        <button
          type="button"
          phx-click="debugger-start"
          class="rounded bg-zinc-800 px-2 py-1 text-xs font-medium text-white hover:bg-zinc-700"
        >
          {if debugger_state_running?(@debugger_state), do: "Restart", else: "Start"}
        </button>
        <form class="flex items-center gap-1" phx-change="debugger-set-watch-profile">
          <label class="flex items-center gap-1 text-xs text-zinc-600">
            <span>Watch model</span>
            <select
              name="watch_profile_id"
              class="rounded border border-zinc-300 bg-white px-2 py-1 text-xs"
            >
              <option
                :for={profile <- Ide.Debugger.watch_profiles()}
                value={profile["id"]}
                selected={
                  profile["id"] ==
                    selected_debugger_watch_profile_id(@debugger_state, @project)
                }
              >
                {profile["label"]}
              </option>
            </select>
          </label>
        </form>
      </div>
      <div class="mt-3 grid min-h-0 flex-1 grid-cols-12 gap-3">
        <div class="col-span-12 flex min-h-0 flex-col rounded border border-zinc-200 bg-zinc-50 p-2 lg:col-span-3">
          <div class="flex items-center justify-between gap-2">
            <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-600">Timeline</h3>
            <div class="flex items-center gap-1">
              <.debugger_copy_button
                id="debugger-timeline-copy"
                text={
                  @debugger_rows
                  |> DebuggerSupport.debugger_rows_for_mode(@debugger_timeline_mode)
                  |> DebuggerSupport.debugger_timeline_text()
                }
                title="Copy visible timeline as raw text"
              />
              <form phx-change="debugger-set-timeline-mode">
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
            :if={@debugger_timeline_mode != "separate"}
            class="mt-2 min-h-0 flex-1 overflow-auto rounded border border-zinc-200 bg-white"
          >
            <.debugger_debugger_timeline_rows
              rows={
                DebuggerSupport.debugger_rows_for_mode(
                  @debugger_rows,
                  @debugger_timeline_mode
                )
              }
              selected_row={@debugger_selected_row}
              empty_label="No update messages for this timeline view."
            />
          </div>
          <div
            :if={@debugger_timeline_mode == "separate"}
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
        <div class="col-span-12 grid min-h-0 grid-cols-2 gap-3 lg:col-span-4">
          <div class="flex min-h-0 flex-col rounded border border-zinc-200 bg-zinc-50 p-2">
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-600">
                Watch model
              </h3>
              <.debugger_copy_button
                id="debugger-watch-model-copy"
                text={DebuggerSupport.copy_json(debugger_debugger_model(@debugger_watch_runtime))}
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
          <div class="flex min-h-0 flex-col rounded border border-zinc-200 bg-zinc-50 p-2">
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-600">
                Companion model
              </h3>
              <.debugger_copy_button
                id="debugger-companion-model-copy"
                text={DebuggerSupport.copy_json(debugger_debugger_model(@debugger_companion_runtime))}
                title="Copy companion model as JSON"
              />
            </div>
            <.debugger_model_tree runtime={@debugger_companion_runtime} />
            <.debugger_companion_configuration
              runtime={@debugger_companion_runtime}
              debugger_state={@debugger_state}
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
        <div class="col-span-12 grid min-h-0 grid-cols-2 gap-3 lg:col-span-5">
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
          <div class="h-full min-h-0">
            <.debugger_view_preview
              runtime={@debugger_watch_view_runtime}
              project={@project}
              title="Visual preview"
              show_watch_buttons={true}
              watch_trigger_buttons={@debugger_watch_trigger_buttons}
              disabled_subscriptions={@debugger_disabled_subscriptions}
              hover_scope="watch-live"
              hovered_rendered_scope={@debugger_hovered_rendered_scope}
              hovered_rendered_path={@debugger_hovered_rendered_path}
            />
          </div>
        </div>
      </div>
      <p
        :if={@debugger_advanced_debug_tools}
        class="mt-3 rounded border border-amber-100 bg-amber-50/80 px-2 py-1.5 text-xs text-amber-950"
      >
        Saving <span class="font-mono text-[11px]">.elm</span>
        from watch / protocol / phone parses
        with the IDE’s elmc frontend into <span class="font-medium">parser snapshots</span>
        of <span class="font-mono text-[11px]">init</span>
        (static tuple peel), <span class="font-mono text-[11px]">Msg</span>
        constructors, and a <span class="font-medium">view outline</span>
        replace the sample preview on that surface when the outline is non-empty (watch, companion for protocol, phone for phone). Elm is still
        <span class="font-medium">not executed</span>
        (<span class="font-mono text-[11px]">update</span> / runtime pixels are not live yet).
      </p>
      <.debugger_trigger_modal open={@debugger_trigger_modal_open} form={@debugger_trigger_form} />
      <div
        :if={@debugger_advanced_debug_tools}
        class="mt-4 overflow-auto border-t border-zinc-200 pt-4"
      >
        <h3 class="text-sm font-semibold">Controls</h3>
        <div class="mt-2 flex items-center gap-2">
          <.button phx-click="debugger-start" class="!bg-zinc-800 hover:!bg-zinc-700">
            {if debugger_state_running?(@debugger_state),
              do: "Restart debugger",
              else: "Start debugger"}
          </.button>
          <.button phx-click="debugger-tick" class="!bg-zinc-100 !text-zinc-800 hover:!bg-zinc-200">
            Inject tick
          </.button>
          <.button
            phx-click="debugger-auto-tick-start"
            class="!bg-zinc-100 !text-zinc-800 hover:!bg-zinc-200"
          >
            Start auto tick
          </.button>
          <.button
            phx-click="debugger-auto-tick-stop"
            class="!bg-zinc-100 !text-zinc-800 hover:!bg-zinc-200"
          >
            Stop auto tick
          </.button>
        </div>
        <form class="mt-2 flex flex-wrap items-end gap-2" phx-change="debugger-set-watch-profile">
          <label class="flex flex-col gap-1 text-xs text-zinc-600">
            <span>Watch model profile</span>
            <select
              name="watch_profile_id"
              class="rounded border border-zinc-300 bg-white px-2 py-1 text-xs"
            >
              <option
                :for={profile <- Ide.Debugger.watch_profiles()}
                value={profile["id"]}
                selected={
                  profile["id"] ==
                    selected_debugger_watch_profile_id(@debugger_state, @project)
                }
              >
                {profile["label"]}
              </option>
            </select>
          </label>
        </form>
        <.form
          :if={@debugger_advanced_debug_tools}
          for={@debugger_export_form}
          id="debugger-export-trace-form"
          phx-submit="debugger-export-trace"
          class="mt-3 grid grid-cols-1 gap-2 rounded border border-zinc-200 bg-zinc-50 p-2 md:grid-cols-[1fr_1fr_auto]"
        >
          <input
            type="text"
            name="debugger_export[compare_cursor_seq]"
            value={@debugger_export_form[:compare_cursor_seq].value}
            placeholder={"compare cursor (blank = current #{if is_integer(@debugger_cursor_seq), do: @debugger_cursor_seq, else: "latest"})"}
            class="w-full rounded border border-zinc-300 bg-white px-2 py-1 text-[11px] text-zinc-900"
          />
          <input
            type="text"
            name="debugger_export[baseline_cursor_seq]"
            value={@debugger_export_form[:baseline_cursor_seq].value}
            placeholder={"baseline cursor (blank = preview #{if is_integer(@debugger_replay_preview_seq), do: @debugger_replay_preview_seq, else: "latest before current"})"}
            class="w-full rounded border border-zinc-300 bg-white px-2 py-1 text-[11px] text-zinc-900"
          />
          <.button type="submit" class="!bg-zinc-100 !text-zinc-800 hover:!bg-zinc-200">
            Export trace (JSON)
          </.button>
        </.form>
        <p class="mt-2 text-sm text-zinc-600">
          Tracks watch + companion runtime substrate with deterministic event sequencing.
        </p>
        <p :if={@debugger_state && @debugger_state.auto_tick} class="mt-1 text-[11px] text-zinc-500">
          auto tick: {if @debugger_state.auto_tick.enabled, do: "on", else: "off"} · interval {@debugger_state.auto_tick.interval_ms ||
            "—"}ms · target {@debugger_state.auto_tick.target || "all"}
        </p>
        <div
          :if={@debugger_advanced_debug_tools && @debugger_trace_export}
          class="mt-3 rounded border border-zinc-200 bg-zinc-50 p-2"
        >
          <p class="text-[11px] text-zinc-700">
            Deterministic export · sha256 {@debugger_trace_export.sha256} · {@debugger_trace_export.byte_size} bytes
          </p>
          <p
            :if={
              @debugger_trace_export_context &&
                (is_integer(@debugger_trace_export_context.compare_cursor_seq) ||
                   is_integer(@debugger_trace_export_context.baseline_cursor_seq))
            }
            class="mt-1 text-[10px] text-zinc-500"
          >
            runtime compare anchors:
            current {@debugger_trace_export_context.compare_cursor_seq || "latest"} · baseline {@debugger_trace_export_context.baseline_cursor_seq ||
              "latest before current"}
          </p>
          <pre class="mt-2 max-h-48 overflow-auto rounded bg-zinc-900 p-2 text-[10px] text-zinc-100 select-all"><%= @debugger_trace_export.json %></pre>
        </div>

        <.form
          :if={@debugger_advanced_debug_tools}
          for={@debugger_import_form}
          id="debugger-import-trace-form"
          phx-submit="debugger-import-trace"
          class="mt-4 space-y-2 border-t border-zinc-200 pt-4"
        >
          <h3 class="text-sm font-semibold">Import / replay trace</h3>
          <p class="text-[11px] text-zinc-600">
            Paste JSON from <span class="font-medium">Export trace</span>. The trace’s
            <span class="font-mono">project_slug</span>
            must match this project.
          </p>
          <textarea
            name="debugger_import[json]"
            rows="5"
            class="w-full rounded border border-zinc-300 bg-white p-2 font-mono text-[11px] text-zinc-900"
            placeholder="Paste export JSON (export_version 1)"
          >{@debugger_import_form[:json].value}</textarea>
          <.button type="submit" class="!bg-zinc-800 hover:!bg-zinc-700">
            Import trace
          </.button>
        </.form>

        <.form
          for={@debugger_filter_form}
          phx-change="debugger-set-filters"
          class="mt-3 grid grid-cols-1 gap-2 md:grid-cols-2"
        >
          <.input
            field={@debugger_filter_form[:types]}
            type="text"
            label="Event types (comma-separated)"
            placeholder="debugger.update_in,debugger.protocol_tx"
          />
          <.input
            field={@debugger_filter_form[:since_seq]}
            type="text"
            label="Only events with seq >"
            placeholder="0"
          />
        </.form>

        <div :if={@debugger_state} class="mt-3 space-y-3 text-xs">
          <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1">
            running: {to_string(@debugger_state.running)} · revision: {@debugger_state.revision ||
              "none"} ·
            events: {length(@debugger_state.events)} · cursor seq: {@debugger_cursor_seq || "none"} · profile: {@debugger_state.watch_profile_id ||
              "basalt"}
          </p>
          <div class="flex flex-wrap items-center gap-2">
            <.button
              phx-click="debugger-jump-latest"
              disabled={@debugger_state.events == []}
              class="!bg-zinc-800 hover:!bg-zinc-700"
            >
              Jump latest
            </.button>
            <.button
              phx-click="debugger-step-back"
              disabled={@debugger_state.events == []}
              class="!bg-zinc-100 !text-zinc-800 hover:!bg-zinc-200"
            >
              Step back
            </.button>
            <.button
              phx-click="debugger-step-forward"
              disabled={@debugger_state.events == []}
              class="!bg-zinc-100 !text-zinc-800 hover:!bg-zinc-200"
            >
              Step forward
            </.button>
            <.button
              phx-click="debugger-continue-from-cursor"
              disabled={@debugger_state.events == []}
              class="!bg-emerald-100 !text-emerald-900 hover:!bg-emerald-200"
            >
              Continue from cursor snapshot
            </.button>
            <span class="text-zinc-600">
              selected event type: {(@debugger_selected_event && @debugger_selected_event.type) ||
                "none"}
            </span>
          </div>
          <div class="rounded border border-zinc-200 bg-zinc-50 p-2">
            <p class="mb-1 text-[11px] font-semibold text-zinc-700">
              Trigger injection (subscription/button triggers)
            </p>
            <div class="flex flex-wrap gap-1">
              <button
                :for={row <- @debugger_trigger_buttons}
                type="button"
                phx-click="debugger-open-trigger-modal"
                phx-value-trigger={row.trigger}
                phx-value-target={row.target}
                phx-value-message={row.message}
                disabled={not subscription_trigger_injection_supported?(row)}
                title={subscription_trigger_button_title(row)}
                class="rounded bg-zinc-200 px-2 py-1 text-[11px] font-medium text-zinc-800 hover:bg-zinc-300 disabled:cursor-not-allowed disabled:opacity-50"
              >
                {row.label}
              </button>
            </div>
          </div>
          <p class="text-[11px] text-zinc-500">
            With Debugger selected: <kbd class="rounded bg-zinc-200 px-1">j</kbd>
            step to older event, <kbd class="rounded bg-zinc-200 px-1">k</kbd>
            step to newer, <kbd class="rounded bg-zinc-200 px-1">/</kbd>
            focus timeline search (not while typing in a field).
          </p>
          <.form
            :if={@debugger_advanced_debug_tools}
            for={@debugger_replay_form}
            phx-change="debugger-replay-change"
            phx-submit="debugger-replay-recent"
            class="grid grid-cols-1 gap-2 rounded border border-zinc-200 bg-zinc-50 p-2 md:grid-cols-5"
          >
            <label class="flex flex-col gap-1 text-[11px] text-zinc-700">
              <span>Replay count</span>
              <input
                type="number"
                name="debugger_replay[count]"
                min="1"
                max="50"
                value={@debugger_replay_form[:count].value}
                class="rounded border border-zinc-300 bg-white px-2 py-1 text-[11px]"
              />
            </label>
            <label class="flex flex-col gap-1 text-[11px] text-zinc-700">
              <span>Target</span>
              <select
                name="debugger_replay[target]"
                class="rounded border border-zinc-300 bg-white px-2 py-1 text-[11px]"
              >
                <option value="all" selected={@debugger_replay_form[:target].value == "all"}>
                  all
                </option>
                <option value="watch" selected={@debugger_replay_form[:target].value == "watch"}>
                  watch
                </option>
                <option
                  value="companion"
                  selected={@debugger_replay_form[:target].value == "companion"}
                >
                  companion
                </option>
                <option value="protocol" selected={@debugger_replay_form[:target].value == "protocol"}>
                  protocol
                </option>
                <option value="phone" selected={@debugger_replay_form[:target].value == "phone"}>
                  phone
                </option>
              </select>
            </label>
            <label class="flex items-center gap-2 text-[11px] text-zinc-700 md:pt-5">
              <input
                type="checkbox"
                name="debugger_replay[cursor_bound]"
                value="true"
                checked={@debugger_replay_form[:cursor_bound].value in ["true", true, "on", "1", 1]}
              />
              <span>Bound to cursor seq</span>
            </label>
            <label class="flex flex-col gap-1 text-[11px] text-zinc-700">
              <span>Replay mode</span>
              <select
                name="debugger_replay[mode]"
                class="rounded border border-zinc-300 bg-white px-2 py-1 text-[11px]"
              >
                <option value="frozen" selected={@debugger_replay_form[:mode].value == "frozen"}>
                  frozen preview
                </option>
                <option value="live" selected={@debugger_replay_form[:mode].value == "live"}>
                  live query
                </option>
              </select>
            </label>
            <div class="md:pt-4">
              <.button type="submit" class="!bg-zinc-100 !text-zinc-800 hover:!bg-zinc-200">
                Replay recent
              </.button>
            </div>
          </.form>
          <p
            :if={@debugger_advanced_debug_tools && @debugger_replay_live_warning}
            class="text-[11px] text-amber-900"
          >
            Live replay warning: timeline advanced since last preview, so submit may replay different rows.
            <span
              :if={is_integer(@debugger_replay_live_drift)}
              class={[
                "ml-1 rounded px-1",
                case DebuggerSupport.replay_live_drift_severity(@debugger_replay_live_drift) do
                  :mild -> "bg-amber-100 text-amber-900"
                  :medium -> "bg-orange-100 text-orange-900"
                  :high -> "bg-rose-100 text-rose-900"
                  _ -> "bg-zinc-100 text-zinc-700"
                end
              ]}
              title={
                case DebuggerSupport.replay_live_drift_severity(@debugger_replay_live_drift) do
                  :mild -> "Mild drift: 1-3 seq"
                  :medium -> "Medium drift: 4-10 seq"
                  :high -> "High drift: 11+ seq"
                  _ -> "No drift"
                end
              }
            >
              drift +{@debugger_replay_live_drift} seq
            </span>
            <button
              type="button"
              phx-click="debugger-replay-refresh-preview"
              class="ml-2 rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-medium text-amber-900 hover:bg-amber-200"
            >
              Refresh preview now
            </button>
            <span class="ml-2 text-[10px] text-zinc-600">
              [!] mild 1-3, [!!] medium 4-10, [!!!] high 11+
            </span>
          </p>
          <p
            :if={@debugger_advanced_debug_tools && is_integer(@debugger_replay_preview_seq)}
            class="text-[11px] text-zinc-500"
          >
            Preview baseline seq: {@debugger_replay_preview_seq}
          </p>
          <p :if={@debugger_advanced_debug_tools} class="text-[11px] text-zinc-600">
            Replay preview:
            <span :if={@debugger_replay_preview == []}> no matching update messages</span>
            <span :if={@debugger_replay_preview != []}>
              {@debugger_replay_preview
              |> Enum.map(fn row -> "##{row.seq} #{row.target}: #{row.message}" end)
              |> Enum.join(" | ")}
            </span>
          </p>
          <p
            :if={@debugger_advanced_debug_tools && @debugger_replay_compare}
            class="text-[11px] text-zinc-600"
          >
            Replay validator:
            <span
              :if={@debugger_replay_compare.status == :match}
              class="rounded bg-emerald-100 px-1 text-emerald-800"
            >
              matched
            </span>
            <span
              :if={@debugger_replay_compare.status == :mismatch}
              class="rounded bg-amber-100 px-1 text-amber-900"
            >
              diverged ({@debugger_replay_compare.reason})
            </span>
            <span
              :if={@debugger_replay_compare.status == :none}
              class="rounded bg-zinc-100 px-1 text-zinc-700"
            >
              no applied replay yet
            </span>
            · preview {@debugger_replay_compare.preview_count} · applied {@debugger_replay_compare.applied_count}
          </p>
          <p
            :if={
              @debugger_advanced_debug_tools &&
                @debugger_replay_compare &&
                @debugger_replay_compare.status == :mismatch &&
                (@debugger_replay_compare.mismatch_preview ||
                   @debugger_replay_compare.mismatch_applied)
            }
            class="text-[11px] text-amber-900"
          >
            Mismatch detail:
            preview {case @debugger_replay_compare.mismatch_preview do
              nil ->
                "(none)"

              row ->
                "##{row.seq} #{row.target}: #{row.message}"
            end} vs applied {case @debugger_replay_compare.mismatch_applied do
              nil ->
                "(none)"

              row ->
                "##{row.seq} #{row.target}: #{row.message}"
            end}
          </p>
          <.form
            :if={@debugger_advanced_debug_tools}
            for={@debugger_compare_form}
            phx-change="debugger-set-compare-baseline"
            class="grid grid-cols-1 gap-2 rounded border border-zinc-200 bg-zinc-50 p-2 md:grid-cols-4"
          >
            <label class="flex flex-col gap-1 text-[11px] text-zinc-700">
              <span>Snapshot compare baseline seq</span>
              <input
                type="text"
                name="debugger_compare[baseline_seq]"
                value={@debugger_compare_form[:baseline_seq].value}
                placeholder="(blank disables compare)"
                class="rounded border border-zinc-300 bg-white px-2 py-1 text-[11px]"
              />
            </label>
            <div class="flex items-end gap-2 pb-0.5">
              <button
                type="button"
                phx-click="debugger-use-preview-baseline"
                class="rounded bg-zinc-200 px-2 py-1 text-[11px] font-medium text-zinc-800 hover:bg-zinc-300"
              >
                Use replay preview seq
              </button>
            </div>
            <p class="col-span-full text-[11px] text-zinc-600">
              Snapshot compare baseline is independent from replay validation.
            </p>
          </.form>
          <p
            :if={@debugger_advanced_debug_tools && @debugger_runtime_fingerprint_compare}
            class="text-[11px] text-zinc-600"
          >
            Runtime fingerprint compare:
            <span class="font-mono">
              cursor {@debugger_runtime_fingerprint_compare.cursor_seq}
            </span>
            vs
            <span class="font-mono">
              baseline {@debugger_runtime_fingerprint_compare.compare_cursor_seq}
            </span>
            · changed surfaces {@debugger_runtime_fingerprint_compare.changed_surface_count} · backend drift surfaces {Map.get(
              @debugger_runtime_fingerprint_compare,
              :backend_changed_surface_count,
              0
            )} · key-target drift surfaces {Map.get(
              @debugger_runtime_fingerprint_compare,
              :key_target_changed_surface_count,
              0
            )}
            <span :if={map_size(@debugger_runtime_fingerprint_compare.surfaces || %{}) > 0}>
              ( {@debugger_runtime_fingerprint_compare.surfaces
              |> Enum.map(fn {surface, row} ->
                status = if row[:changed], do: "changed", else: "same"
                "#{surface}=#{status}"
              end)
              |> Enum.join(", ")} )
            </span>
            <span :if={
              Map.get(@debugger_runtime_fingerprint_compare, :backend_changed_surface_count, 0) > 0
            }>
              · backend detail {DebuggerSupport.backend_drift_detail(
                @debugger_runtime_fingerprint_compare
              ) || "(none)"}
            </span>
            <span :if={
              Map.get(@debugger_runtime_fingerprint_compare, :key_target_changed_surface_count, 0) >
                0
            }>
              · key-target detail {DebuggerSupport.key_target_drift_detail(
                @debugger_runtime_fingerprint_compare
              ) || "(none)"}
            </span>
            <span :if={is_binary(Map.get(@debugger_runtime_fingerprint_compare, :drift_detail))}>
              · drift detail {Map.get(@debugger_runtime_fingerprint_compare, :drift_detail)}
            </span>
          </p>
          <p
            :if={@debugger_advanced_debug_tools && @debugger_last_replay}
            class="text-[11px] text-zinc-600"
          >
            Last applied replay:
            <span class="font-mono">
              seq #{@debugger_last_replay.seq}
            </span>
            · target {@debugger_last_replay.target || "all"} ·
            source {@debugger_last_replay.replay_source || "recent_query"} ·
            replayed {@debugger_last_replay.replayed_count || 0}/{@debugger_last_replay.requested_count ||
              0}
            <span :if={is_integer(@debugger_last_replay.cursor_seq)}>
              · cursor &lt;= {@debugger_last_replay.cursor_seq}
            </span>
            <span :if={@debugger_last_replay.replay_preview != []}>
              · rows {@debugger_last_replay.replay_preview
              |> Enum.map(fn row ->
                seq = row[:seq] || row["seq"]
                target = row[:target] || row["target"]
                message = row[:message] || row["message"]
                "##{seq} #{target}: #{message}"
              end)
              |> Enum.join(" | ")}
            </span>
          </p>
          <p
            :if={
              @debugger_advanced_debug_tools &&
                @debugger_last_replay &&
                map_size(@debugger_last_replay.replay_telemetry || %{}) > 0
            }
            class="text-[11px] text-zinc-500"
          >
            Replay telemetry: {case @debugger_last_replay.replay_telemetry do
              telemetry when is_map(telemetry) ->
                mode = telemetry[:mode] || telemetry["mode"] || "unknown"
                source = telemetry[:source] || telemetry["source"] || "unknown"
                drift_band = telemetry[:drift_band] || telemetry["drift_band"] || "none"
                "mode #{mode} · source #{source} · drift-band #{drift_band}"

              _ ->
                "n/a"
            end}
          </p>
          <.form
            for={@debugger_timeline_form}
            phx-change="debugger-set-cursor"
            class="grid grid-cols-1 gap-2 md:grid-cols-2"
          >
            <.input
              field={@debugger_timeline_form[:seq]}
              type="text"
              label="Jump to seq"
              placeholder="1"
            />
            <label class="flex flex-col gap-1 text-[11px] font-medium text-zinc-700">
              <span>Timeline scrubber</span>
              <input
                type="range"
                name="debugger_timeline[range_seq]"
                min={DebuggerSupport.min_seq(@debugger_state.events)}
                max={DebuggerSupport.max_seq(@debugger_state.events)}
                value={@debugger_cursor_seq || DebuggerSupport.min_seq(@debugger_state.events)}
                disabled={@debugger_state.events == []}
                class="w-full"
              />
            </label>
          </.form>
          <div class="flex flex-wrap items-center gap-2">
            <button
              type="button"
              phx-click="debugger-filter-type"
              phx-value-type="*"
              class="rounded bg-zinc-100 px-2 py-1 text-[11px] font-medium text-zinc-700 hover:bg-zinc-200"
            >
              all ({length(@debugger_state.events)})
            </button>
            <button
              :for={{type, count} <- DebuggerSupport.event_type_counts(@debugger_state.events)}
              type="button"
              phx-click="debugger-filter-type"
              phx-value-type={type}
              class={[
                "rounded px-2 py-1 text-[11px] font-medium",
                Enum.member?(@debugger_types, type) && "bg-zinc-800 text-zinc-100",
                !Enum.member?(@debugger_types, type) &&
                  "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
              ]}
            >
              {type} ({count})
            </button>
          </div>
          <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
            Live runtime tip (latest state)
          </p>
          <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
            <pre class="max-h-52 overflow-auto rounded bg-zinc-900 p-2 text-[11px] text-zinc-100"><%= DebuggerSupport.runtime_json(@debugger_state.watch) %></pre>
            <pre class="max-h-52 overflow-auto rounded bg-zinc-900 p-2 text-[11px] text-zinc-100"><%= DebuggerSupport.runtime_json(@debugger_state.companion) %></pre>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <button
              :for={kind <- ["all", "protocol", "update", "render", "lifecycle", "other"]}
              type="button"
              phx-click="debugger-set-timeline-kind"
              phx-value-kind={kind}
              class={[
                "rounded px-2 py-1 text-[11px] font-medium",
                Atom.to_string(@debugger_timeline_kind) == kind &&
                  "bg-zinc-800 text-zinc-100",
                Atom.to_string(@debugger_timeline_kind) != kind &&
                  "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
              ]}
            >
              {kind}
            </button>
            <.form
              for={to_form(%{"limit" => @debugger_timeline_limit}, as: :timeline)}
              phx-change="debugger-set-timeline-limit"
            >
              <label class="flex items-center gap-2 text-[11px] text-zinc-700">
                <span>Rows</span>
                <select
                  name="timeline[limit]"
                  class="rounded border border-zinc-300 bg-white px-2 py-1 text-[11px]"
                >
                  <option
                    :for={limit <- [10, 30, 100, 200]}
                    value={limit}
                    selected={limit == @debugger_timeline_limit}
                  >
                    {limit}
                  </option>
                </select>
              </label>
            </.form>
            <.form
              for={to_form(%{"query" => @debugger_timeline_query}, as: :timeline)}
              phx-change="debugger-set-timeline-search"
            >
              <label class="flex items-center gap-2 text-[11px] text-zinc-700">
                <span>Search</span>
                <input
                  id="debugger-timeline-search"
                  type="text"
                  name="timeline[query]"
                  value={@debugger_timeline_query}
                  placeholder="type or message"
                  class="rounded border border-zinc-300 bg-white px-2 py-1 text-[11px]"
                />
              </label>
            </.form>
          </div>
          <div class="overflow-x-auto rounded border border-zinc-200">
            <table class="min-w-full text-[11px]">
              <thead class="bg-zinc-50 text-zinc-600">
                <tr>
                  <th class="px-2 py-1 text-left">Seq</th>
                  <th class="px-2 py-1 text-left">Type</th>
                  <th class="px-2 py-1 text-left">Target</th>
                  <th class="px-2 py-1 text-left">Message</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={
                    row <-
                      DebuggerSupport.filtered_event_summaries(
                        @debugger_state.events,
                        @debugger_timeline_kind,
                        @debugger_timeline_limit,
                        @debugger_timeline_query
                      )
                  }
                  phx-click="debugger-select-event"
                  phx-value-seq={row.seq}
                  class={[
                    "cursor-pointer border-t border-zinc-100",
                    @debugger_cursor_seq == row.seq && "bg-zinc-800 text-zinc-100",
                    @debugger_cursor_seq != row.seq && "hover:bg-zinc-50"
                  ]}
                >
                  <td class="px-2 py-1 font-mono">#{row.seq}</td>
                  <td class="px-2 py-1">
                    <span
                      :for={
                        fragment <-
                          DebuggerSupport.highlight_fragments(row.type, @debugger_timeline_query)
                      }
                      class={fragment.match? && "rounded bg-yellow-200 px-0.5 text-zinc-900"}
                    >
                      {fragment.text}
                    </span>
                  </td>
                  <td class="px-2 py-1">{row.target || "-"}</td>
                  <td class="max-w-[20rem] px-2 py-1">
                    <div class="truncate">
                      <span
                        :for={
                          fragment <-
                            DebuggerSupport.highlight_fragments(
                              row.message || "-",
                              @debugger_timeline_query
                            )
                        }
                        class={fragment.match? && "rounded bg-yellow-200 px-0.5 text-zinc-900"}
                      >
                        {fragment.text}
                      </span>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
            Update messages (simulated <span class="font-mono">update</span>
            pipeline, through selected seq)
          </p>
          <div class="overflow-x-auto rounded border border-zinc-200">
            <table class="min-w-full text-[11px]">
              <thead class="bg-zinc-50 text-zinc-600">
                <tr>
                  <th class="px-2 py-1 text-left">Seq</th>
                  <th class="px-2 py-1 text-left">Target</th>
                  <th class="px-2 py-1 text-left">Message</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={
                    row <-
                      DebuggerSupport.update_messages_at_cursor(
                        @debugger_state.events,
                        @debugger_cursor_seq,
                        40
                      )
                  }
                  phx-click="debugger-select-event"
                  phx-value-seq={row.seq}
                  class={[
                    "cursor-pointer border-t border-zinc-100",
                    @debugger_cursor_seq == row.seq && "bg-zinc-800 text-zinc-100",
                    @debugger_cursor_seq != row.seq && "hover:bg-zinc-50"
                  ]}
                >
                  <td class="px-2 py-1 font-mono">#{row.seq}</td>
                  <td class="px-2 py-1">{row.target || "—"}</td>
                  <td class="max-w-[28rem] truncate px-2 py-1">{row.message || "—"}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
            Protocol exchange (watch ↔ companion, through selected seq)
          </p>
          <div class="overflow-x-auto rounded border border-zinc-200">
            <table class="min-w-full text-[11px]">
              <thead class="bg-zinc-50 text-zinc-600">
                <tr>
                  <th class="px-2 py-1 text-left">Seq</th>
                  <th class="px-2 py-1 text-left">Dir</th>
                  <th class="px-2 py-1 text-left">From</th>
                  <th class="px-2 py-1 text-left">To</th>
                  <th class="px-2 py-1 text-left">Message</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={
                    row <-
                      DebuggerSupport.protocol_exchange_at_cursor(
                        @debugger_state.events,
                        @debugger_cursor_seq,
                        40
                      )
                  }
                  phx-click="debugger-select-event"
                  phx-value-seq={row.seq}
                  class={[
                    "cursor-pointer border-t border-zinc-100",
                    @debugger_cursor_seq == row.seq && "bg-zinc-800 text-zinc-100",
                    @debugger_cursor_seq != row.seq && "hover:bg-zinc-50"
                  ]}
                >
                  <td class="px-2 py-1 font-mono">#{row.seq}</td>
                  <td class="px-2 py-1 font-mono">{row.kind}</td>
                  <td class="px-2 py-1">{row.from || "—"}</td>
                  <td class="px-2 py-1">{row.to || "—"}</td>
                  <td class="max-w-[24rem] truncate px-2 py-1">{row.message || "—"}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
            <% debugger_render_rows =
              DebuggerSupport.render_events_at_cursor(
                @debugger_state.events,
                @debugger_cursor_seq,
                24
              ) %>
            <% debugger_lifecycle_rows =
              DebuggerSupport.lifecycle_events_at_cursor(
                @debugger_state.events,
                @debugger_cursor_seq,
                12
              ) %>
            <div>
              <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
                View renders (through selected seq)
              </p>
              <div class="overflow-x-auto rounded border border-zinc-200">
                <table class="min-w-full text-[11px]">
                  <thead class="bg-zinc-50 text-zinc-600">
                    <tr>
                      <th class="px-2 py-1 text-left">Seq</th>
                      <th class="px-2 py-1 text-left">Target</th>
                      <th class="px-2 py-1 text-left">Root</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= if debugger_render_rows == [] do %>
                      <tr class="border-t border-zinc-100">
                        <td class="px-2 py-2 text-zinc-500 italic" colspan="3">
                          No view renders through this point. Reload or step forward to record
                          <span class="font-mono not-italic">debugger.view_render</span>
                          events.
                        </td>
                      </tr>
                    <% else %>
                      <tr
                        :for={row <- debugger_render_rows}
                        phx-click="debugger-select-event"
                        phx-value-seq={row.seq}
                        class={[
                          "cursor-pointer border-t border-zinc-100",
                          @debugger_cursor_seq == row.seq && "bg-zinc-800 text-zinc-100",
                          @debugger_cursor_seq != row.seq && "hover:bg-zinc-50"
                        ]}
                      >
                        <td class="px-2 py-1 font-mono">#{row.seq}</td>
                        <td class="px-2 py-1">{row.target || "—"}</td>
                        <td class="max-w-[16rem] truncate px-2 py-1 font-mono">
                          {row.root || "—"}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
            <div>
              <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
                Lifecycle (start / reset / reload / elm_introspect / elmc check / compile / manifest)
              </p>
              <div class="overflow-x-auto rounded border border-zinc-200">
                <table class="min-w-full text-[11px]">
                  <thead class="bg-zinc-50 text-zinc-600">
                    <tr>
                      <th class="px-2 py-1 text-left">Seq</th>
                      <th class="px-2 py-1 text-left">Type</th>
                      <th class="px-2 py-1 text-left">Summary</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= if debugger_lifecycle_rows == [] do %>
                      <tr class="border-t border-zinc-100">
                        <td class="px-2 py-2 text-zinc-500 italic" colspan="3">
                          No lifecycle events through this point. Start the debugger or move the
                          cursor past <span class="font-mono not-italic">debugger.start</span>.
                        </td>
                      </tr>
                    <% else %>
                      <tr
                        :for={row <- debugger_lifecycle_rows}
                        phx-click="debugger-select-event"
                        phx-value-seq={row.seq}
                        class={[
                          "cursor-pointer border-t border-zinc-100",
                          @debugger_cursor_seq == row.seq && "bg-zinc-800 text-zinc-100",
                          @debugger_cursor_seq != row.seq && "hover:bg-zinc-50"
                        ]}
                      >
                        <td class="px-2 py-1 font-mono">#{row.seq}</td>
                        <td class="px-2 py-1 font-mono">{row.type}</td>
                        <td class="max-w-[20rem] truncate px-2 py-1">{row.summary}</td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
          <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
            Cursor runtime snapshot (frozen at selected seq)
          </p>
          <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
            <pre class="max-h-44 overflow-auto rounded border border-zinc-200 bg-zinc-50 p-2 text-[11px] text-zinc-900"><%= DebuggerSupport.runtime_json(@debugger_cursor_watch_runtime) %></pre>
            <pre class="max-h-44 overflow-auto rounded border border-zinc-200 bg-zinc-50 p-2 text-[11px] text-zinc-900"><%= DebuggerSupport.runtime_json(@debugger_cursor_companion_runtime) %></pre>
          </div>
          <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
            Parser snapshot summary (static elmc parse, at cursor)
          </p>
          <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
            <pre class="max-h-36 overflow-auto whitespace-pre-wrap rounded border border-emerald-100 bg-emerald-50/80 p-2 font-mono text-[11px] text-emerald-950"><%= DebuggerSupport.format_elm_introspect_brief(@debugger_cursor_watch_runtime) %></pre>
            <pre class="max-h-36 overflow-auto whitespace-pre-wrap rounded border border-emerald-100 bg-emerald-50/80 p-2 font-mono text-[11px] text-emerald-950"><%= DebuggerSupport.format_elm_introspect_brief(@debugger_cursor_companion_runtime) %></pre>
          </div>
          <% debugger_diag =
            DebuggerSupport.diagnostics_preview_at_cursor(
              @debugger_state.events,
              @debugger_cursor_seq
            ) %>
          <% debugger_elmc_diag_rows_list = debugger_diag.rows %>
          <% debugger_elmc_diag_label =
            DebuggerSupport.diagnostics_preview_source_label(debugger_diag.source) %>
          <div
            :if={debugger_elmc_diag_rows_list != []}
            class="mt-3 rounded-lg border border-zinc-200 bg-white p-2 shadow-sm"
          >
            <p class="mb-1 text-[11px] font-semibold text-zinc-700">
              Elmc diagnostics · {debugger_elmc_diag_label}
            </p>
            <.debugger_elmc_diagnostic_preview rows={debugger_elmc_diag_rows_list} />
          </div>
          <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
            <div>
              <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
                Rendered view (watch, at cursor)
              </p>
              <.debugger_rendered_view_tree
                id="debugger-watch-rendered-view"
                scope="watch-cursor"
                runtime={@debugger_cursor_watch_runtime}
              />
            </div>
            <div>
              <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
                Rendered view (companion / phone app, at cursor)
              </p>
              <.debugger_rendered_view_tree
                id="debugger-companion-rendered-view"
                scope="companion-cursor"
                runtime={@debugger_cursor_companion_runtime}
              />
            </div>
          </div>
          <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
            <.debugger_view_preview
              runtime={@debugger_cursor_watch_runtime}
              project={@project}
              title="Watch · visual preview"
              hover_scope="watch-cursor"
              hovered_rendered_scope={@debugger_hovered_rendered_scope}
              hovered_rendered_path={@debugger_hovered_rendered_path}
            />
            <.debugger_view_preview
              runtime={@debugger_cursor_companion_runtime}
              project={@project}
              title="Companion / phone app · visual preview"
              hover_scope="companion-cursor"
              hovered_rendered_scope={@debugger_hovered_rendered_scope}
              hovered_rendered_path={@debugger_hovered_rendered_path}
            />
          </div>
          <pre class="max-h-44 overflow-auto rounded border border-zinc-200 bg-zinc-50 p-2 text-[11px] text-zinc-900"><%= DebuggerSupport.event_json(@debugger_selected_event) %></pre>
          <div class="grid grid-cols-1 gap-2 lg:grid-cols-2">
            <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
              newer event: {(@debugger_newer_event && @debugger_newer_event.seq) || "none"} ·
              type: {(@debugger_newer_event && @debugger_newer_event.type) || "none"}
            </p>
            <p class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1 text-[11px] text-zinc-700">
              older event: {(@debugger_older_event && @debugger_older_event.seq) || "none"} ·
              type: {(@debugger_older_event && @debugger_older_event.type) || "none"}
            </p>
          </div>
          <pre class="max-h-44 overflow-auto rounded border border-zinc-200 bg-zinc-50 p-2 text-[11px] text-zinc-900"><%= DebuggerSupport.payload_diff_json(@debugger_older_event, @debugger_selected_event) %></pre>
          <div class="rounded border border-zinc-200 bg-white p-2">
            <p class="mb-2 text-[11px] font-semibold uppercase tracking-wide text-zinc-600">
              Recent timeline events (click to inspect)
            </p>
            <div class="max-h-40 overflow-auto">
              <button
                :for={event <- Enum.take(@debugger_state.events, 30)}
                type="button"
                phx-click="debugger-select-event"
                phx-value-seq={event.seq}
                class={[
                  "mb-1 w-full rounded px-2 py-1 text-left text-[11px]",
                  @debugger_cursor_seq == event.seq &&
                    "bg-zinc-800 text-zinc-100",
                  @debugger_cursor_seq != event.seq &&
                    "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
                ]}
              >
                #{event.seq} · {event.type}
              </button>
            </div>
          </div>
          <pre class="max-h-52 overflow-auto rounded bg-zinc-900 p-2 text-[11px] text-zinc-100"><%= DebuggerSupport.event_json(@debugger_state.events) %></pre>
        </div>
      </div>
    </section>
    """
  end

  attr(:rows, :list, required: true)

  @spec debugger_elmc_diagnostic_preview(term()) :: term()
  defp debugger_elmc_diagnostic_preview(assigns) do
    ~H"""
    <div class="max-h-40 overflow-auto rounded border border-zinc-100">
      <table class="min-w-full text-[10px] text-zinc-800">
        <thead class="sticky top-0 bg-zinc-50 text-zinc-600">
          <tr>
            <th class="px-1.5 py-0.5 text-left font-medium">Sev</th>
            <th class="px-1.5 py-0.5 text-left font-medium">Src</th>
            <th class="px-1.5 py-0.5 text-left font-medium">Where</th>
            <th class="px-1.5 py-0.5 text-left font-medium">Message</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} class="border-t border-zinc-100 align-top">
            <td class="px-1.5 py-0.5 font-mono text-zinc-700">
              {debugger_diag_field(row, "severity")}
            </td>
            <td class="px-1.5 py-0.5 font-mono text-zinc-600">
              {debugger_diag_field(row, "source")}
            </td>
            <td class="max-w-[10rem] truncate px-1.5 py-0.5 font-mono text-zinc-600">
              {debugger_diag_where(row)}
            </td>
            <td class="max-w-[28rem] truncate px-1.5 py-0.5 text-zinc-800">
              {debugger_diag_field(row, "message")}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:text, :string, required: true)
  attr(:label, :string, default: "Copy")
  attr(:title, :string, default: "Copy to clipboard")
  attr(:copy_selector, :string, default: nil)

  @spec debugger_copy_button(term()) :: term()
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

  @spec debugger_debugger_timeline_rows(term()) :: term()
  defp debugger_debugger_timeline_rows(assigns) do
    ~H"""
    <button
      :for={row <- @rows}
      type="button"
      phx-click="debugger-select-debugger-event"
      phx-value-seq={row.seq}
      class={debugger_debugger_timeline_row_class(row, @selected_row)}
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

  @spec debugger_debugger_timeline_row_class(term(), term()) :: [String.t() | boolean()]
  defp debugger_debugger_timeline_row_class(row, selected_row) do
    selected? =
      is_map(row) and is_map(selected_row) and
        Map.get(row, :seq) == Map.get(selected_row, :seq)

    target = if is_map(row), do: Map.get(row, :target), else: nil

    target_class =
      case target do
        "watch" -> "bg-sky-50 hover:bg-sky-100"
        "companion" -> "bg-emerald-50 hover:bg-emerald-100"
        _ -> "bg-white hover:bg-blue-50"
      end

    [
      "block w-full border-b border-zinc-100 px-2 py-1.5 text-left text-[11px]",
      target_class,
      selected? && "bg-blue-100 text-blue-950 ring-1 ring-inset ring-blue-300"
    ]
  end

  attr(:runtime, :any, required: true)

  @spec debugger_model_tree(term()) :: term()
  defp debugger_model_tree(assigns) do
    model = debugger_debugger_model(assigns.runtime)
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

  @spec debugger_companion_configuration(term()) :: term()
  defp debugger_companion_configuration(assigns) do
    configuration =
      debugger_companion_configuration_model(
        Map.get(assigns.debugger_state || %{}, :companion) ||
          Map.get(assigns.debugger_state || %{}, "companion")
      ) ||
        debugger_companion_configuration_model(assigns.runtime)

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

  @spec debugger_companion_configuration_field(term()) :: term()
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
        checked={@control_value == true}
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
        type={debugger_configuration_input_type(@control_type)}
        value={debugger_configuration_input_value(@control_value)}
        min={@control["min"]}
        max={@control["max"]}
        step={debugger_configuration_input_step(@control_type, @control)}
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

  @spec debugger_model_node(term()) :: term()
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

  @spec debugger_model_children(term()) :: [%{label: String.t(), value: term()}]
  defp debugger_model_children(value) when is_map(value) do
    if debugger_model_elm_constructor?(value) do
      []
    else
      value
      |> Enum.map(fn {key, child_value} -> %{label: to_string(key), value: child_value} end)
      |> Enum.sort_by(& &1.label)
    end
  end

  defp debugger_model_children(value) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.map(fn {child_value, index} -> %{label: "[#{index}]", value: child_value} end)
  end

  defp debugger_model_children(_value), do: []

  @spec debugger_model_tooltip(String.t(), term(), [map()], String.t()) :: String.t()
  defp debugger_model_tooltip(label, _value, [], scalar)
       when is_binary(label) and is_binary(scalar),
       do: "#{label} = #{scalar}"

  defp debugger_model_tooltip(label, value, _children, _scalar) when is_binary(label) do
    "#{label} #{debugger_model_container_label(value)}"
  end

  @spec debugger_model_scalar(term()) :: String.t()
  defp debugger_model_scalar(value) when is_map(value) do
    if debugger_model_elm_constructor?(value),
      do: debugger_model_elm_value(value),
      else: inspect(value)
  end

  defp debugger_model_scalar(nil), do: "null"
  defp debugger_model_scalar(value) when is_binary(value), do: inspect(value)
  defp debugger_model_scalar(value) when is_boolean(value), do: to_string(value)
  defp debugger_model_scalar(value) when is_number(value), do: to_string(value)
  defp debugger_model_scalar(value) when is_atom(value), do: Atom.to_string(value)
  defp debugger_model_scalar(value), do: inspect(value)

  @spec debugger_model_container_label(map() | list()) :: String.t()
  defp debugger_model_container_label(value) when is_map(value) do
    if debugger_model_elm_constructor?(value),
      do: debugger_model_elm_value(value),
      else: "{#{map_size(value)}}"
  end

  defp debugger_model_container_label(value) when is_list(value), do: "[#{length(value)}]"

  @spec debugger_model_elm_constructor?(term()) :: boolean()
  defp debugger_model_elm_constructor?(value) when is_map(value) do
    ctor = Map.get(value, "ctor") || Map.get(value, "$ctor") || Map.get(value, :ctor)
    args = Map.get(value, "args") || Map.get(value, "$args") || Map.get(value, :args) || []

    is_binary(ctor) and is_list(args) and
      value
      |> Map.keys()
      |> Enum.all?(&(to_string(&1) in ["ctor", "args", "$ctor", "$args"]))
  end

  @spec debugger_model_elm_value(map()) :: String.t()
  defp debugger_model_elm_value(%{} = value) do
    ctor = Map.get(value, "ctor") || Map.get(value, "$ctor") || Map.get(value, :ctor)
    args = Map.get(value, "args") || Map.get(value, "$args") || Map.get(value, :args) || []

    case {ctor, args} do
      {ctor, []} when is_binary(ctor) ->
        ctor

      {ctor, args} when is_binary(ctor) and is_list(args) ->
        rendered_args =
          args
          |> Enum.map(&debugger_model_elm_arg_value/1)
          |> Enum.join(" ")

        String.trim("#{ctor} #{rendered_args}")

      _ ->
        inspect(value)
    end
  end

  @spec debugger_model_elm_arg_value(term()) :: String.t()
  defp debugger_model_elm_arg_value(%{} = value) do
    if debugger_model_elm_constructor?(value) do
      rendered = debugger_model_elm_value(value)

      if constructor_arg_count(value) > 0 do
        "(" <> rendered <> ")"
      else
        rendered
      end
    else
      debugger_model_elm_record_value(value)
    end
  end

  defp debugger_model_elm_arg_value(value) when is_list(value) do
    inner =
      value
      |> Enum.map(&debugger_model_elm_arg_value/1)
      |> Enum.join(", ")

    "[" <> inner <> "]"
  end

  defp debugger_model_elm_arg_value(value) when is_boolean(value),
    do: if(value, do: "True", else: "False")

  defp debugger_model_elm_arg_value(value), do: debugger_model_scalar(value)

  @spec debugger_model_elm_record_value(map()) :: String.t()
  defp debugger_model_elm_record_value(value) when is_map(value) do
    inner =
      value
      |> Enum.map(fn {key, child_value} ->
        "#{key} = #{debugger_model_elm_arg_value(child_value)}"
      end)
      |> Enum.sort()
      |> Enum.join(", ")

    "{ " <> inner <> " }"
  end

  @spec constructor_arg_count(map()) :: non_neg_integer()
  defp constructor_arg_count(%{} = value) do
    args = Map.get(value, "args") || Map.get(value, "$args") || Map.get(value, :args) || []
    if is_list(args), do: length(args), else: 0
  end

  @spec debugger_debugger_model(term()) :: map()
  defp debugger_debugger_model(runtime) do
    runtime
    |> debugger_runtime_model()
    |> hide_debugger_model_metadata()
  end

  @spec debugger_agent_state_clipboard_text(map()) :: String.t()
  defp debugger_agent_state_clipboard_text(%{} = assigns) do
    project = Map.get(assigns, :project)

    timeline_text =
      assigns
      |> Map.get(:debugger_rows, [])
      |> DebuggerSupport.debugger_rows_for_mode(
        Map.get(assigns, :debugger_timeline_mode, "mixed")
      )
      |> DebuggerSupport.debugger_timeline_text()

    selected_seq =
      case Map.get(assigns, :debugger_selected_row) do
        %{seq: s} -> s
        %{"seq" => s} -> s
        _ -> nil
      end

    state = Map.get(assigns, :debugger_state)

    DebuggerSupport.debugger_agent_state_markdown(%{
      project_name: project_name_for_clipboard(project),
      project_slug: project_slug_for_clipboard(project),
      timeline_mode: Map.get(assigns, :debugger_timeline_mode, "mixed"),
      timeline_text: timeline_text,
      watch_model_json:
        DebuggerSupport.copy_json(
          debugger_debugger_model(Map.get(assigns, :debugger_watch_runtime))
        ),
      companion_model_json:
        DebuggerSupport.copy_json(
          debugger_debugger_model(Map.get(assigns, :debugger_companion_runtime))
        ),
      rendered_view_json:
        DebuggerSupport.copy_json(
          debugger_rendered_tree(Map.get(assigns, :debugger_watch_view_runtime))
        ),
      session_running: state && debugger_state_running?(state),
      session_event_count: if(state, do: length(state.events), else: nil),
      debugger_cursor_seq: Map.get(assigns, :debugger_cursor_seq),
      selected_timeline_seq: selected_seq,
      watch_profile_id: state && debugger_state_watch_profile_id(state, project)
    })
  end

  defp project_name_for_clipboard(%Project{name: name}) when is_binary(name), do: name
  defp project_name_for_clipboard(_), do: ""

  defp project_slug_for_clipboard(%Project{slug: slug}) when is_binary(slug), do: slug
  defp project_slug_for_clipboard(_), do: ""

  defp debugger_state_watch_profile_id(state, project) do
    case Map.get(state, :watch_profile_id) do
      nil -> selected_debugger_watch_profile_id(state, project)
      id -> id
    end
  end

  @spec debugger_companion_configuration_model(term()) :: map() | nil
  defp debugger_companion_configuration_model(runtime) do
    model = debugger_runtime_model(runtime)

    case Map.get(model, "configuration") || Map.get(model, :configuration) do
      %{} = configuration -> configuration
      _ -> nil
    end
  end

  @spec debugger_configuration_input_type(term()) :: String.t()
  defp debugger_configuration_input_type("number"), do: "number"
  defp debugger_configuration_input_type("color"), do: "color"
  defp debugger_configuration_input_type("slider"), do: "range"
  defp debugger_configuration_input_type(_), do: "text"

  @spec debugger_configuration_input_value(term()) :: String.t()
  defp debugger_configuration_input_value(nil), do: ""
  defp debugger_configuration_input_value(value) when is_binary(value), do: value
  defp debugger_configuration_input_value(value) when is_boolean(value), do: to_string(value)
  defp debugger_configuration_input_value(value) when is_number(value), do: to_string(value)
  defp debugger_configuration_input_value(value), do: inspect(value)

  @spec debugger_configuration_input_step(String.t(), map()) :: String.t() | number() | nil
  defp debugger_configuration_input_step("number", control) when is_map(control) do
    Map.get(control, "step") || "any"
  end

  defp debugger_configuration_input_step(_control_type, control) when is_map(control) do
    Map.get(control, "step")
  end

  defp debugger_configuration_input_step(_control_type, _control), do: nil

  @spec hide_debugger_model_metadata(term()) :: map()
  defp hide_debugger_model_metadata(model) when is_map(model) do
    atom_keys = Enum.map(@debugger_model_metadata_keys, &String.to_atom/1)
    Map.drop(model, @debugger_model_metadata_keys ++ atom_keys)
  end

  defp hide_debugger_model_metadata(_model), do: %{}

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
        <.form for={@form} phx-submit="debugger-submit-trigger" class="mt-3 space-y-3">
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
          <label class="flex flex-col gap-1 text-xs text-zinc-600">
            <span>Trigger</span>
            <input
              type="text"
              value={@form[:trigger].value}
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

  attr(:title, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:target, :string, required: true)
  attr(:auto_fire_subscriptions, :list, default: [])
  attr(:disabled_subscriptions, :list, default: [])

  @spec debugger_subscription_buttons(term()) :: term()
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
            disabled={
              not subscription_trigger_enabled?(@disabled_subscriptions, @target, row.trigger) or
                not subscription_trigger_injection_supported?(row)
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

  defp subscription_trigger_enabled?(disabled_subscriptions, target, trigger)
       when is_list(disabled_subscriptions) and is_binary(target) and is_binary(trigger) do
    not Enum.any?(disabled_subscriptions, fn row ->
      row_target = Map.get(row, "target") || Map.get(row, :target)
      row_trigger = Map.get(row, "trigger") || Map.get(row, :trigger)
      row_target == debugger_auto_fire_target(target) and row_trigger == trigger
    end)
  end

  defp subscription_trigger_enabled?(_disabled_subscriptions, _target, _trigger), do: true

  @spec subscription_trigger_injection_supported?(map()) :: boolean()
  defp subscription_trigger_injection_supported?(%{injection_supported?: true}), do: true
  defp subscription_trigger_injection_supported?(%{"injection_supported?" => true}), do: true
  defp subscription_trigger_injection_supported?(_row), do: false

  @spec subscription_trigger_button_title(map()) :: String.t()
  defp subscription_trigger_button_title(row) when is_map(row) do
    if subscription_trigger_injection_supported?(row) do
      "Fire this subscribed event"
    else
      "This subscribed event needs a payload shape the debugger form cannot represent."
    end
  end

  defp subscription_trigger_button_title(_row),
    do: "This subscribed event needs a payload shape the debugger form cannot represent."

  defp subscription_auto_fire_enabled?(auto_fire_subscriptions, target, trigger)
       when is_list(auto_fire_subscriptions) and is_binary(target) and is_binary(trigger) do
    Enum.any?(auto_fire_subscriptions, fn row ->
      row_target = Map.get(row, "target") || Map.get(row, :target)
      row_trigger = Map.get(row, "trigger") || Map.get(row, :trigger)

      row_target == debugger_auto_fire_target(target) and
        (row_trigger == "*" or row_trigger == trigger)
    end)
  end

  defp subscription_auto_fire_enabled?(_auto_fire_subscriptions, _target, _trigger), do: false

  @spec subscription_auto_fire_toggle_visible?([map()], String.t(), map()) :: boolean()
  defp subscription_auto_fire_toggle_visible?(auto_fire_subscriptions, target, row)
       when is_list(auto_fire_subscriptions) and is_binary(target) and is_map(row) do
    trigger = to_string(Map.get(row, :trigger) || Map.get(row, "trigger") || "")
    interval_ms = Map.get(row, :interval_ms) || Map.get(row, "interval_ms")

    interval_auto? = is_integer(interval_ms) and interval_ms > 0
    recurring_event? = recurring_auto_fire_trigger?(trigger)

    interval_auto? or recurring_event? or
      subscription_auto_fire_enabled?(auto_fire_subscriptions, target, trigger)
  end

  defp subscription_auto_fire_toggle_visible?(_auto_fire_subscriptions, _target, _row), do: false

  @spec recurring_auto_fire_trigger?(String.t()) :: boolean()
  defp recurring_auto_fire_trigger?(trigger) when is_binary(trigger) do
    trigger =
      trigger
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/, "")

    String.contains?(trigger, "ontick") or
      String.contains?(trigger, "onsecondchange") or
      String.contains?(trigger, "onminutechange") or
      String.contains?(trigger, "onhourchange")
  end

  defp recurring_auto_fire_trigger?(_trigger), do: false

  attr(:runtime, :any, required: true)
  attr(:project, :any, default: nil)
  attr(:title, :string, default: "Visual preview")
  attr(:show_watch_buttons, :boolean, default: false)
  attr(:watch_trigger_buttons, :list, default: [])
  attr(:disabled_subscriptions, :list, default: [])
  attr(:hover_scope, :string, default: nil)
  attr(:hovered_rendered_scope, :any, default: nil)
  attr(:hovered_rendered_path, :any, default: nil)

  @spec debugger_view_preview(term()) :: term()
  defp debugger_view_preview(assigns) do
    tree = debugger_preview_tree(assigns.runtime)
    rendered_tree = debugger_rendered_tree(assigns.runtime)
    {screen_w, screen_h} = debugger_preview_dimensions(assigns.runtime, tree)
    screen_round? = DebuggerPreview.screen_round?(assigns.runtime, tree)
    clip_radius = min(screen_w, screen_h) / 2
    clip_id = debugger_preview_clip_id(assigns, screen_w, screen_h, screen_round?)
    svg_id = debugger_preview_svg_id(assigns)

    svg_ops =
      tree
      |> debugger_watch_svg_ops(assigns.runtime)
      |> hydrate_bitmap_svg_ops(assigns.project)

    unresolved_ops = Enum.filter(svg_ops, &(&1.kind == :unresolved))

    hover_box =
      if assigns.hover_scope != nil and assigns.hover_scope == assigns.hovered_rendered_scope do
        DebuggerSupport.rendered_node_bounds(
          rendered_tree,
          assigns.hovered_rendered_path,
          screen_w,
          screen_h
        )
      else
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
      |> assign(:preview_svg_class, debugger_preview_svg_class(screen_round?))
      |> assign(:svg_ops, svg_ops)
      |> assign(:unresolved_ops, unresolved_ops)
      |> assign(:hover_box, hover_box)
      |> assign(
        :watch_button_controls,
        debugger_watch_button_controls(
          assigns.watch_trigger_buttons,
          assigns.disabled_subscriptions
        )
      )
      |> assign(
        :accel_control,
        debugger_accel_control(assigns.watch_trigger_buttons, assigns.disabled_subscriptions)
      )

    ~H"""
    <div
      class="flex h-full min-h-0 flex-col rounded border border-zinc-200 bg-zinc-50 p-2"
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
          if(@show_watch_buttons, do: "grid grid-cols-[auto_minmax(0,1fr)_auto]", else: "block"),
          "items-center gap-2"
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
                <g>
                  <title :if={debugger_svg_op_tooltip(op) != nil}>
                    {debugger_svg_op_tooltip(op)}
                  </title>
                  <rect
                    :if={op.kind == :clear}
                    x="0"
                    y="0"
                    width={@screen_w}
                    height={@screen_h}
                    fill={debugger_svg_color(op.color, "white")}
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
                    transform={"rotate(#{debugger_pebble_angle_deg(op.angle)} #{op.center_x} #{op.center_y})"}
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
                    stroke={debugger_svg_color(op.stroke_color, "#111111")}
                    stroke-width={op.stroke_width || 1}
                  />
                  <rect
                    :if={op.kind == :rect}
                    x={op.x}
                    y={op.y}
                    width={op.w}
                    height={op.h}
                    fill="none"
                    stroke={debugger_svg_color(op.stroke_color, "#111111")}
                    stroke-width={op.stroke_width || 1}
                  />
                  <rect
                    :if={op.kind == :fill_rect}
                    x={op.x}
                    y={op.y}
                    width={op.w}
                    height={op.h}
                    fill={debugger_svg_color(op.fill_color, "#111111")}
                    stroke={
                      debugger_svg_color(
                        op.stroke_color,
                        debugger_svg_color(op.fill_color, "#111111")
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
                    stroke={debugger_svg_color(op.stroke_color, "#111111")}
                    stroke-width={op.stroke_width || 1}
                  />
                  <path
                    :if={op.kind == :arc}
                    d={debugger_arc_path(op)}
                    fill="none"
                    stroke={debugger_svg_color(op.stroke_color, "#111111")}
                    stroke-width={op.stroke_width || 1}
                  />
                  <path
                    :if={op.kind == :fill_radial}
                    d={debugger_arc_sector_path(op)}
                    fill={debugger_svg_color(op.fill_color, "#111111")}
                    stroke={
                      debugger_svg_color(
                        op.stroke_color,
                        debugger_svg_color(op.fill_color, "#111111")
                      )
                    }
                    stroke-width={op.stroke_width || 1}
                  />
                  <path
                    :if={op.kind == :path_filled}
                    d={debugger_path_d(op, true)}
                    fill={debugger_svg_color(op.fill_color, "#111111")}
                    stroke={
                      debugger_svg_color(
                        op.stroke_color,
                        debugger_svg_color(op.fill_color, "#111111")
                      )
                    }
                    stroke-width={op.stroke_width || 1}
                  />
                  <path
                    :if={op.kind == :path_outline}
                    d={debugger_path_d(op, true)}
                    fill="none"
                    stroke={debugger_svg_color(op.stroke_color, "#111111")}
                    stroke-width={op.stroke_width || 1}
                  />
                  <path
                    :if={op.kind == :path_outline_open}
                    d={debugger_path_d(op, false)}
                    fill="none"
                    stroke={debugger_svg_color(op.stroke_color, "#111111")}
                    stroke-width={op.stroke_width || 1}
                  />
                  <circle
                    :if={op.kind == :circle}
                    cx={op.cx}
                    cy={op.cy}
                    r={op.r}
                    fill="none"
                    stroke={debugger_svg_color(op.stroke_color, "#111111")}
                    stroke-width={op.stroke_width || 1}
                  />
                  <circle
                    :if={op.kind == :fill_circle}
                    cx={op.cx}
                    cy={op.cy}
                    r={op.r}
                    fill={debugger_svg_color(op.fill_color, "#111111")}
                    stroke={
                      debugger_svg_color(
                        op.stroke_color,
                        debugger_svg_color(op.fill_color, "#111111")
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
                    fill={debugger_svg_color(op.stroke_color, "#111111")}
                  />
                  <text
                    :if={op.kind == :text_int}
                    x={op.x}
                    y={op.y}
                    font-size="14"
                    font-family="monospace"
                    fill={debugger_svg_color(op.text_color, "#111111")}
                  >
                    {op.text}
                  </text>
                  <text
                    :if={op.kind == :text_label}
                    x={debugger_text_svg_x(op)}
                    y={debugger_text_svg_y(op)}
                    font-size={debugger_text_svg_font_size(op)}
                    font-family="sans-serif"
                    text-anchor={debugger_text_svg_anchor(op)}
                    dominant-baseline={debugger_text_svg_baseline(op)}
                    fill={debugger_svg_color(op.text_color, "#111111")}
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
          <div :if={@show_watch_buttons} class="flex flex-col items-stretch gap-2">
            <.debugger_watch_button button={@watch_button_controls.up} />
            <.debugger_watch_button button={@watch_button_controls.select} />
            <.debugger_watch_button button={@watch_button_controls.down} />
          </div>
        </div>
        <p :if={@svg_ops == []} class="mt-1 text-center text-[10px] text-zinc-500">
          No drawable primitives found in this snapshot.
        </p>
        <p :if={@unresolved_ops != []} class="mt-1 text-center text-[10px] text-amber-700">
          {debugger_unresolved_svg_summary(@unresolved_ops)}
        </p>
      </div>
      <.debugger_accel_control :if={@accel_control} control={@accel_control} />
    </div>
    """
  end

  attr(:control, :map, required: true)

  @spec debugger_accel_control(term()) :: term()
  defp debugger_accel_control(assigns) do
    ~H"""
    <div class="min-h-0 flex-1 rounded border border-zinc-200 bg-white p-2">
      <div class="flex items-center justify-between gap-2">
        <p class="text-[11px] font-semibold uppercase tracking-wide text-zinc-600">
          Accelerometer
        </p>
        <p class="text-[10px] text-zinc-500" data-accel-readout>
          x 0 · y 0 · z 1000
        </p>
      </div>
      <div
        id="debugger-accel-pad"
        phx-hook="DebuggerAccelPad"
        data-trigger={@control.trigger}
        data-target={@control.target}
        data-message={@control.message}
        class="mt-2 flex justify-center"
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

  attr(:button, :map, required: true)

  @spec debugger_watch_button(term()) :: term()
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
        "min-w-12 rounded-full border px-2 py-1 text-[10px] font-semibold uppercase tracking-wide shadow-sm transition",
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

  @spec debugger_watch_button_controls(term(), term()) :: map()
  defp debugger_watch_button_controls(rows, disabled_subscriptions) when is_list(rows) do
    [:back, :up, :select, :down]
    |> Map.new(fn button ->
      row = debugger_watch_button_row(rows, button)
      {button, debugger_watch_button_control(button, row, disabled_subscriptions)}
    end)
  end

  defp debugger_watch_button_controls(_rows, disabled_subscriptions),
    do: debugger_watch_button_controls([], disabled_subscriptions)

  @spec debugger_accel_control(term(), term()) :: map() | nil
  defp debugger_accel_control(rows, disabled_subscriptions) when is_list(rows) do
    rows
    |> Enum.find(&accel_trigger_row?/1)
    |> case do
      %{} = row ->
        target = Map.get(row, :target) || Map.get(row, "target") || "watch"
        trigger = Map.get(row, :trigger) || Map.get(row, "trigger") || "on_accel"
        message = Map.get(row, :message) || Map.get(row, "message")

        if is_binary(message) and message != "" and
             subscription_trigger_enabled?(disabled_subscriptions, target, trigger) do
          %{
            trigger: trigger,
            target: target,
            message: message
          }
        end

      _ ->
        nil
    end
  end

  defp debugger_accel_control(_rows, _disabled_subscriptions), do: nil

  @spec accel_trigger_row?(term()) :: boolean()
  defp accel_trigger_row?(row) when is_map(row) do
    trigger = Map.get(row, :trigger) || Map.get(row, "trigger")
    trigger in ["on_accel", "on_accel_data"]
  end

  defp accel_trigger_row?(_row), do: false

  @spec debugger_watch_button_control(atom(), term(), term()) :: map()
  defp debugger_watch_button_control(button, row, disabled_subscriptions) when is_map(row) do
    enabled? =
      subscription_trigger_enabled?(
        disabled_subscriptions,
        Map.get(row, :target) || Map.get(row, "target") || "watch",
        Map.get(row, :trigger) || Map.get(row, "trigger") || ""
      )

    %{
      id: Atom.to_string(button),
      label: debugger_watch_button_label(button),
      trigger: Map.get(row, :trigger) || Map.get(row, "trigger"),
      target: Map.get(row, :target) || Map.get(row, "target") || "watch",
      message: Map.get(row, :message) || Map.get(row, "message"),
      enabled: enabled?,
      title: "Trigger #{debugger_watch_button_label(button)} button event"
    }
  end

  defp debugger_watch_button_control(button, _row, _disabled_subscriptions) do
    label = debugger_watch_button_label(button)

    %{
      id: Atom.to_string(button),
      label: label,
      trigger: "",
      target: "watch",
      message: "",
      enabled: false,
      title: "#{label} button is not subscribed in this snapshot"
    }
  end

  @spec debugger_watch_button_row([map()], atom()) :: map() | nil
  defp debugger_watch_button_row(rows, button) when is_list(rows) do
    button_name = Atom.to_string(button)

    Enum.find(rows, &watch_button_metadata_match?(&1, button_name, "pressed")) ||
      Enum.find(rows, &watch_button_metadata_match?(&1, button_name, nil)) ||
      Enum.find(rows, &watch_button_trigger_match?(&1, button_name))
  end

  @spec watch_button_metadata_match?(term(), String.t(), String.t() | nil) :: boolean()
  defp watch_button_metadata_match?(row, button_name, event_name) when is_map(row) do
    row_button = Map.get(row, :button) || Map.get(row, "button")
    row_event = Map.get(row, :button_event) || Map.get(row, "button_event")

    row_button == button_name and (is_nil(event_name) or row_event == event_name)
  end

  defp watch_button_metadata_match?(_row, _button_name, _event_name), do: false

  @spec watch_button_trigger_match?(term(), String.t()) :: boolean()
  defp watch_button_trigger_match?(row, button_name) when is_map(row) do
    trigger = Map.get(row, :trigger) || Map.get(row, "trigger")
    trigger in watch_button_trigger_names(button_name)
  end

  defp watch_button_trigger_match?(_row, _button_name), do: false

  @spec watch_button_trigger_names(String.t()) :: [String.t()]
  defp watch_button_trigger_names("back"), do: ["button_back", "on_button_back"]
  defp watch_button_trigger_names("up"), do: ["button_up", "on_button_up"]
  defp watch_button_trigger_names("select"), do: ["button_select", "on_button_select"]
  defp watch_button_trigger_names("down"), do: ["button_down", "on_button_down"]
  defp watch_button_trigger_names(_button), do: []

  @spec debugger_watch_button_label(atom()) :: String.t()
  defp debugger_watch_button_label(:back), do: "Back"
  defp debugger_watch_button_label(:up), do: "Up"
  defp debugger_watch_button_label(:select), do: "Select"
  defp debugger_watch_button_label(:down), do: "Down"

  attr(:id, :string, required: true)
  attr(:scope, :string, required: true)
  attr(:runtime, :any, required: true)

  @spec debugger_rendered_view_tree(term()) :: term()
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

  @spec debugger_rendered_node(term()) :: term()
  defp debugger_rendered_node(assigns) do
    node = assigns.node
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "node")

    children =
      (Map.get(node, "children") || Map.get(node, :children) || [])
      |> Enum.filter(&is_map/1)
      |> debugger_rendered_child_rows(node, assigns.path)
      |> Enum.reject(fn %{node: child} ->
        child_type = to_string(Map.get(child, "type") || Map.get(child, :type) || "")
        debugger_hidden_rendered_node_type?(child_type)
      end)

    assigns =
      assigns
      |> assign(:type, type)
      |> assign(
        :summary,
        DebuggerSupport.rendered_node_summary(node, assigns.model, assigns.arg_name)
      )
      |> assign(:source_tooltip, debugger_rendered_node_source_tooltip(node))
      |> assign(:children, children)

    ~H"""
    <div :if={!debugger_hidden_rendered_node_type?(@type)} class="pl-1">
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

  @spec debugger_hidden_rendered_node_type?(term()) :: term()
  defp debugger_hidden_rendered_node_type?(type) when is_binary(type) do
    type in ["debuggerRenderStep", "elmcRuntimeStep"]
  end

  defp debugger_hidden_rendered_node_type?(_), do: false

  @spec debugger_rendered_node_source_tooltip(map()) :: String.t() | nil
  defp debugger_rendered_node_source_tooltip(node) when is_map(node) do
    source = Map.get(node, "source") || Map.get(node, :source)

    with %{} <- source,
         call when is_binary(call) and call != "" <-
           Map.get(source, "call") || Map.get(source, :call) ||
             Map.get(node, "qualified_target") || Map.get(node, :qualified_target) ||
             rendered_node_tooltip_call(node),
         path when is_binary(path) and path != "" <-
           Map.get(source, "path") || Map.get(source, :path),
         line when is_integer(line) <- Map.get(source, "line") || Map.get(source, :line) do
      "#{call} at #{path}:#{line}"
    else
      _ -> nil
    end
  end

  defp debugger_rendered_node_source_tooltip(_node), do: nil

  defp rendered_node_tooltip_call(node) when is_map(node) do
    type = Map.get(node, "type") || Map.get(node, :type)
    if is_binary(type) and type != "", do: "Ui.#{type}", else: nil
  end

  @spec debugger_rendered_child_rows([map()], map(), String.t()) :: [
          %{node: map(), arg_name: String.t() | nil, path: String.t()}
        ]
  defp debugger_rendered_child_rows(children, parent, parent_path)
       when is_list(children) and is_map(parent) and is_binary(parent_path) do
    arg_names = debugger_rendered_node_arg_names(parent, length(children))

    children
    |> Enum.with_index()
    |> Enum.map(fn {child, index} ->
      %{node: child, arg_name: Enum.at(arg_names, index), path: "#{parent_path}.#{index}"}
    end)
  end

  @spec debugger_rendered_node_arg_names(map(), non_neg_integer()) :: [String.t()]
  defp debugger_rendered_node_arg_names(parent, child_count)
       when is_map(parent) and is_integer(child_count) do
    explicit = Map.get(parent, "arg_names") || Map.get(parent, :arg_names) || []

    if explicit != [] do
      explicit
    else
      []
    end
  end

  @spec debugger_diag_field(term(), term()) :: term()
  defp debugger_diag_field(row, key) when is_map(row) and is_binary(key) do
    v =
      Map.get(row, key) ||
        case key do
          "severity" -> Map.get(row, :severity)
          "source" -> Map.get(row, :source)
          "message" -> Map.get(row, :message)
          "file" -> Map.get(row, :file)
          "line" -> Map.get(row, :line)
          "column" -> Map.get(row, :column)
          _ -> nil
        end

    case v do
      nil -> "—"
      "" -> "—"
      other -> to_string(other)
    end
  end

  @spec debugger_diag_where(term()) :: term()
  defp debugger_diag_where(row) when is_map(row) do
    file = Map.get(row, "file") || Map.get(row, :file)
    line = Map.get(row, "line") || Map.get(row, :line)
    col = Map.get(row, "column") || Map.get(row, :column)

    cond do
      file in [nil, ""] ->
        "—"

      line in [nil, ""] ->
        to_string(file)

      col in [nil, ""] ->
        "#{file}:#{line}"

      true ->
        "#{file}:#{line}:#{col}"
    end
  end

  @spec debugger_watch_svg_ops(term(), term()) :: term()
  defp debugger_watch_svg_ops(tree, runtime), do: DebuggerPreview.svg_ops(tree, runtime)

  @spec hydrate_bitmap_svg_ops(term(), term()) :: term()
  defp hydrate_bitmap_svg_ops(rows, %Project{} = project) when is_list(rows) do
    Enum.map(rows, fn
      %{kind: :bitmap_in_rect, bitmap_id: bitmap_id} = row ->
        Map.put(row, :href, bitmap_href_for(project, bitmap_id))

      %{kind: :rotated_bitmap, bitmap_id: bitmap_id} = row ->
        Map.put(row, :href, bitmap_href_for(project, bitmap_id))

      other ->
        other
    end)
  end

  defp hydrate_bitmap_svg_ops(rows, _project), do: rows

  @spec bitmap_href_for(term(), term()) :: term()
  defp bitmap_href_for(%Project{} = project, bitmap_id) when is_integer(bitmap_id) do
    with {:ok, path} <- ResourceStore.bitmap_file_path_by_id(project, bitmap_id),
         {:ok, bytes} <- File.read(path) do
      "data:#{bitmap_mime_for_path(path)};base64," <> Base.encode64(bytes)
    else
      _ -> nil
    end
  end

  defp bitmap_href_for(_project, _bitmap_id), do: nil

  @spec bitmap_mime_for_path(term()) :: term()
  defp bitmap_mime_for_path(path) when is_binary(path) do
    case path |> Path.extname() |> String.downcase() do
      ".png" -> "image/png"
      ".bmp" -> "image/bmp"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "application/octet-stream"
    end
  end

  @spec debugger_pebble_angle_deg(term()) :: term()
  defp debugger_pebble_angle_deg(angle) when is_integer(angle) do
    angle * 360.0 / 65_536.0
  end

  defp debugger_pebble_angle_deg(_), do: 0.0

  @spec debugger_unresolved_svg_summary(term()) :: term()
  defp debugger_unresolved_svg_summary(rows), do: DebuggerPreview.unresolved_summary(rows)

  @spec debugger_svg_op_tooltip(term()) :: String.t() | nil
  defp debugger_svg_op_tooltip(op) when is_map(op) do
    source = Map.get(op, :source) || Map.get(op, "source")

    with %{} <- source,
         call when is_binary(call) and call != "" <-
           Map.get(source, "call") || Map.get(source, :call),
         path when is_binary(path) and path != "" <-
           Map.get(source, "path") || Map.get(source, :path),
         line when is_integer(line) <- Map.get(source, "line") || Map.get(source, :line) do
      "#{call} at #{path}:#{line}"
    else
      _ -> nil
    end
  end

  defp debugger_svg_op_tooltip(_op), do: nil

  @spec debugger_rendered_tree(term()) :: term()
  defp debugger_rendered_tree(runtime), do: DebuggerSupport.rendered_tree(runtime)

  @spec debugger_preview_tree(term()) :: term()
  defp debugger_preview_tree(%{} = runtime) do
    view_tree = Map.get(runtime, :view_tree) || Map.get(runtime, "view_tree")

    if is_map(view_tree) and map_size(view_tree) > 0 do
      view_tree
    else
      model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}
      elm_introspect = Map.get(model, "elm_introspect") || Map.get(model, :elm_introspect) || %{}
      parser_tree = Map.get(elm_introspect, "view_tree") || Map.get(elm_introspect, :view_tree)
      if is_map(parser_tree), do: parser_tree, else: nil
    end
  end

  defp debugger_preview_tree(_runtime), do: nil

  @spec debugger_preview_dimensions(term(), term()) :: term()
  defp debugger_preview_dimensions(runtime, tree),
    do: DebuggerPreview.screen_dimensions(runtime, tree)

  @spec debugger_preview_clip_id(term(), pos_integer(), pos_integer(), boolean()) :: String.t()
  defp debugger_preview_clip_id(assigns, screen_w, screen_h, screen_round?) do
    key = {
      Map.get(assigns, :title),
      Map.get(assigns, :hover_scope),
      screen_w,
      screen_h,
      screen_round?
    }

    "debugger-preview-clip-#{:erlang.phash2(key)}"
  end

  @spec debugger_preview_svg_class(boolean()) :: [String.t()]
  defp debugger_preview_svg_class(true) do
    [
      "mx-auto h-52 w-52 rounded-full border border-zinc-700 bg-white shadow-inner object-contain"
    ]
  end

  defp debugger_preview_svg_class(false) do
    [
      "mx-auto h-52 w-[11.25rem] rounded border border-zinc-700 bg-white shadow-inner object-contain"
    ]
  end

  @spec debugger_preview_svg_id(term()) :: String.t()
  defp debugger_preview_svg_id(assigns) do
    key = {Map.get(assigns, :title), Map.get(assigns, :hover_scope)}
    "debugger-preview-svg-#{:erlang.phash2(key)}"
  end

  @spec debugger_arc_path(term()) :: term()
  defp debugger_arc_path(op), do: DebuggerPreview.arc_path(op)

  @spec debugger_arc_sector_path(term()) :: term()
  defp debugger_arc_sector_path(op) when is_map(op) do
    arc = DebuggerPreview.arc_path(op)

    if arc == "" do
      ""
    else
      cx = (op.x || 0) + max(op.w || 1, 1) / 2.0
      cy = (op.y || 0) + max(op.h || 1, 1) / 2.0
      arc <> " L #{Float.round(cx, 2)} #{Float.round(cy, 2)} Z"
    end
  end

  defp debugger_arc_sector_path(_), do: ""

  @spec debugger_path_d(term(), term()) :: term()
  defp debugger_path_d(op, close_shape?) when is_map(op) and is_boolean(close_shape?) do
    points = Map.get(op, :points, []) || []
    offset_x = Map.get(op, :offset_x, 0) || 0
    offset_y = Map.get(op, :offset_y, 0) || 0
    rotation = Map.get(op, :rotation, 0) || 0
    rotation_rad = rotation * 2.0 * :math.pi() / 65_536.0
    cos_r = :math.cos(rotation_rad)
    sin_r = :math.sin(rotation_rad)

    transformed =
      points
      |> Enum.map(fn
        [x, y] when is_integer(x) and is_integer(y) ->
          xr = x * cos_r - y * sin_r
          yr = x * sin_r + y * cos_r
          {xr + offset_x, yr + offset_y}

        {x, y} when is_integer(x) and is_integer(y) ->
          xr = x * cos_r - y * sin_r
          yr = x * sin_r + y * cos_r
          {xr + offset_x, yr + offset_y}

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)

    case transformed do
      [] ->
        ""

      [{sx, sy} | rest] ->
        base =
          "M #{Float.round(sx, 2)} #{Float.round(sy, 2)} " <>
            Enum.map_join(rest, " ", fn {x, y} ->
              "L #{Float.round(x, 2)} #{Float.round(y, 2)}"
            end)

        if close_shape?, do: base <> " Z", else: base
    end
  end

  defp debugger_path_d(_op, _close_shape?), do: ""

  @spec debugger_text_svg_x(term()) :: number()
  defp debugger_text_svg_x(%{x: x, w: w}) when is_number(x) and is_number(w), do: x + w / 2
  defp debugger_text_svg_x(%{x: x}) when is_number(x), do: x
  defp debugger_text_svg_x(_op), do: 0

  @spec debugger_text_svg_y(term()) :: number()
  defp debugger_text_svg_y(%{y: y, h: h}) when is_number(y) and is_number(h), do: y + h / 2
  defp debugger_text_svg_y(%{y: y}) when is_number(y), do: y
  defp debugger_text_svg_y(_op), do: 0

  @spec debugger_text_svg_font_size(term()) :: pos_integer()
  defp debugger_text_svg_font_size(%{font_size: size}) when is_integer(size) and size > 0,
    do: size

  defp debugger_text_svg_font_size(%{h: height}) when is_integer(height) and height > 0,
    do: height

  defp debugger_text_svg_font_size(_op), do: 11

  @spec debugger_text_svg_anchor(term()) :: String.t() | nil
  defp debugger_text_svg_anchor(%{text_align: "center", w: w}) when is_number(w), do: "middle"
  defp debugger_text_svg_anchor(_op), do: nil

  @spec debugger_text_svg_baseline(term()) :: String.t() | nil
  defp debugger_text_svg_baseline(%{h: h}) when is_number(h), do: "middle"
  defp debugger_text_svg_baseline(_op), do: nil

  @spec debugger_svg_color(term(), term()) :: term()
  defp debugger_svg_color(value, _fallback) when is_integer(value) do
    case value do
      1 ->
        "#111111"

      0 ->
        "white"

      packed ->
        alpha = Bitwise.band(Bitwise.bsr(packed, 6), 0x03)
        red = Bitwise.band(Bitwise.bsr(packed, 4), 0x03)
        green = Bitwise.band(Bitwise.bsr(packed, 2), 0x03)
        blue = Bitwise.band(packed, 0x03)

        rgba_float(red, green, blue, alpha)
    end
  end

  defp debugger_svg_color(_value, fallback), do: fallback

  @spec rgba_float(term(), term(), term(), term()) :: term()
  defp rgba_float(r2, g2, b2, a2) do
    r = color_2bit_to_8bit(r2)
    g = color_2bit_to_8bit(g2)
    b = color_2bit_to_8bit(b2)
    a = Float.round(color_2bit_to_8bit(a2) / 255.0, 2)
    "rgba(#{r}, #{g}, #{b}, #{a})"
  end

  @spec color_2bit_to_8bit(term()) :: term()
  defp color_2bit_to_8bit(value) when is_integer(value), do: max(0, min(3, value)) * 85

  @spec debugger_runtime_model(term()) :: term()
  defp debugger_runtime_model(runtime), do: DebuggerPreview.runtime_model(runtime)

  @spec debugger_state_running?(term()) :: boolean()
  defp debugger_state_running?(%{running: true}), do: true
  defp debugger_state_running?(_), do: false

  @spec selected_debugger_watch_profile_id(term(), term()) :: String.t()
  defp selected_debugger_watch_profile_id(%{watch_profile_id: watch_profile_id}, _project)
       when is_binary(watch_profile_id) do
    normalize_debugger_watch_profile_id(watch_profile_id)
  end

  defp selected_debugger_watch_profile_id(_debugger_state, project),
    do: project_debugger_watch_profile_id(project)

  @spec project_debugger_watch_profile_id(Project.t() | term()) :: String.t()
  defp project_debugger_watch_profile_id(%Project{} = project) do
    settings = project.debugger_settings || %{}
    normalize_debugger_watch_profile_id(Map.get(settings, "watch_profile_id"))
  end

  defp project_debugger_watch_profile_id(_), do: default_debugger_watch_profile_id()

  @spec normalize_debugger_watch_profile_id(term()) :: String.t()
  defp normalize_debugger_watch_profile_id(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if normalized in debugger_watch_profile_ids(),
      do: normalized,
      else: default_debugger_watch_profile_id()
  end

  defp normalize_debugger_watch_profile_id(_), do: default_debugger_watch_profile_id()

  @spec debugger_watch_profile_ids() :: [String.t()]
  defp debugger_watch_profile_ids do
    Debugger.watch_profiles()
    |> Enum.map(&Map.get(&1, "id"))
    |> Enum.filter(&is_binary/1)
  end

  @spec default_debugger_watch_profile_id() :: String.t()
  defp default_debugger_watch_profile_id do
    debugger_watch_profile_ids()
    |> List.first()
    |> case do
      id when is_binary(id) -> id
      _ -> "basalt"
    end
  end

  @spec debugger_auto_fire_target(term()) :: String.t()
  defp debugger_auto_fire_target("protocol"), do: "protocol"
  defp debugger_auto_fire_target("companion"), do: "phone"
  defp debugger_auto_fire_target(_target), do: "watch"
end
