defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Live do
  @moduledoc false
  @dialyzer :no_match

  alias Ide.Debugger.CursorSeq
  alias Phoenix.Component
  alias Ide.Debugger
  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Timeline
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util
  @default_event_limit 500

  @spec assign_defaults(Types.socket()) :: Types.socket()
  def assign_defaults(socket) do
    socket
    |> Component.assign(:debugger_state, nil)
    |> Component.assign(:debugger_event_limit, @default_event_limit)
    |> Component.assign(:debugger_since_seq, nil)
    |> Component.assign(:debugger_types, [])
    |> Component.assign(:debugger_cursor_seq, nil)
    |> Component.assign(:debugger_follow_latest, true)
    |> Component.assign(:debugger_cursor_watch_runtime, nil)
    |> Component.assign(:debugger_cursor_companion_runtime, nil)
    |> Component.assign(:debugger_cursor_phone_runtime, nil)
    |> Component.assign(:debugger_hovered_rendered_scope, nil)
    |> Component.assign(:debugger_hovered_rendered_path, nil)
    |> Component.assign(:debugger_trigger_buttons, [])
    |> Component.assign(:debugger_watch_trigger_buttons, [])
    |> Component.assign(:debugger_companion_trigger_buttons, [])
    |> Component.assign(:debugger_watch_auto_fire, false)
    |> Component.assign(:debugger_companion_auto_fire, false)
    |> Component.assign(:debugger_auto_fire_subscriptions, [])
    |> Component.assign(:debugger_disabled_subscriptions, [])
    |> Component.assign(:debugger_configuration_draft_values, %{})
    |> Component.assign(:debugger_trigger_modal_open, false)
    |> Component.assign(:debugger_trigger_form, Component.to_form(%{}, as: :debugger_trigger))
    |> Component.assign(:debugger_rows, [])
    |> Component.assign(:debugger_timeline_mode, "mixed")
    |> Component.assign(:debugger_selected_row, nil)
    |> Component.assign(:debugger_watch_runtime, nil)
    |> Component.assign(:debugger_companion_runtime, nil)
    |> Component.assign(:debugger_watch_view_runtime, nil)
    |> Component.assign(:debugger_bootstrap_status, :idle)
    |> Component.assign(:debugger_bootstrap_progress, nil)
    |> Component.assign(:debugger_bootstrap_token, nil)
    |> Component.assign(:debugger_companion_bootstrap_status, :idle)
    |> Component.assign(:debugger_companion_bootstrap_progress, nil)
    |> Component.assign(:debugger_runtime_refresh_ref, nil)
    |> Component.assign(:debugger_runtime_refresh_seq, 0)
  end

  @spec refresh(Types.socket()) :: Types.socket()
  def refresh(socket) do
    case socket.assigns[:project] do
      nil ->
        assign_defaults(socket)

      project ->
        {:ok, debugger_state} =
          Debugger.snapshot(Projects.scope_key(project),
            event_limit: socket.assigns[:debugger_event_limit] || @default_event_limit,
            since_seq: socket.assigns[:debugger_since_seq],
            types: socket.assigns[:debugger_types]
          )

        assign_timeline(socket, debugger_state)
    end
  end

  @spec refresh_following_debugger_latest(Types.socket()) :: Types.socket()
  def refresh_following_debugger_latest(socket) do
    follow_latest? =
      Map.get(socket.assigns, :debugger_follow_latest, debugger_cursor_at_latest?(socket))

    socket = refresh(socket)

    if follow_latest? do
      jump_latest_debugger(socket)
    else
      socket
    end
  end

  @spec set_debugger_cursor_seq(Types.socket(), Types.wire_input()) :: Types.socket()
  def set_debugger_cursor_seq(socket, value) do
    case parse_since_seq(value) do
      nil ->
        socket

      seq ->
        socket
        |> assign_debugger_cursor(seq)
        |> Component.assign(:debugger_follow_latest, false)
    end
  end

  @spec set_debugger_timeline_mode(Types.socket(), Types.wire_input()) :: Types.socket()
  def set_debugger_timeline_mode(socket, value) do
    Component.assign(socket, :debugger_timeline_mode, Util.normalize_debugger_timeline_mode(value))
  end

  @spec jump_latest(Types.socket()) :: Types.socket()
  def jump_latest(socket) do
    socket =
      case socket.assigns[:debugger_state] do
        %{events: events} when is_list(events) and events != [] ->
          [latest | _rest] = events
          assign_cursor(socket, latest.seq)

        _ ->
          socket
      end

    jump_latest_debugger(socket)
  end

  @spec step_back(Types.socket()) :: Types.socket()
  def step_back(socket) do
    move_cursor(socket, :back)
  end

  @spec step_forward(Types.socket()) :: Types.socket()
  def step_forward(socket) do
    move_cursor(socket, :forward)
  end

  @spec maybe_reload(Types.socket(), String.t() | nil, String.t(), String.t(), String.t() | nil) ::
          Types.socket()
  def maybe_reload(socket, rel_path, content, reason, source_root \\ nil) do
    case socket.assigns[:project] do
      nil ->
        socket

      project ->
        {:ok, _state} =
          Debugger.reload(Projects.scope_key(project), %{
            rel_path: rel_path,
            source: content,
            reason: reason,
            source_root: source_root || "watch"
          })

        refresh(socket)
    end
  end
  @spec parse_since_seq(Types.wire_input()) :: Types.maybe_non_neg_integer()
  defp parse_since_seq(value) when is_integer(value) and value >= 0, do: value

  defp parse_since_seq(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> nil
    end
  end

  defp parse_since_seq(_value), do: nil
  @spec assign_timeline(Types.socket(), map()) :: Types.socket()
  defp assign_timeline(socket, debugger_state) do
    events = Map.get(debugger_state, :events, [])

    cursor_seq =
      normalize_debugger_cursor_seq(debugger_state, events, socket.assigns[:debugger_cursor_seq])

    snapshot_runtime =
      events
      |> snapshot_runtime_at_cursor(cursor_seq)
      |> with_live_runtime_fallback(debugger_state)

    debug_mode = Timeline.debug_mode_enabled?(socket)

    debugger =
      debugger_assigns(cursor_seq, snapshot_runtime, debugger_state, debug_mode)

    socket
    |> Component.assign(:debugger_state, debugger_state)
    |> Component.assign(:debugger_cursor_watch_runtime, snapshot_runtime.watch)
    |> Component.assign(:debugger_cursor_companion_runtime, snapshot_runtime.companion)
    |> Component.assign(:debugger_cursor_phone_runtime, snapshot_runtime.phone)
    |> Component.assign(:debugger_cursor_seq, debugger.cursor_seq)
    |> Component.assign(:debugger_rows, debugger.rows)
    |> Component.assign(:debugger_selected_row, debugger.selected)
    |> Component.assign(:debugger_watch_runtime, debugger.watch_runtime)
    |> Component.assign(:debugger_companion_runtime, debugger.companion_runtime)
    |> Component.assign(:debugger_watch_view_runtime, debugger.watch_view_runtime)
    |> Component.assign(:debugger_trigger_buttons, trigger_buttons(debugger_state))
    |> Component.assign(
      :debugger_watch_trigger_buttons,
      subscription_trigger_buttons(debugger_state, :watch)
    )
    |> Component.assign(
      :debugger_companion_trigger_buttons,
      subscription_trigger_buttons(debugger_state, :companion)
    )
    |> Component.assign(:debugger_watch_auto_fire, auto_fire_enabled?(debugger_state, :watch))
    |> Component.assign(
      :debugger_companion_auto_fire,
      auto_fire_enabled?(debugger_state, :companion)
    )
    |> Component.assign(
      :debugger_auto_fire_subscriptions,
      auto_fire_subscriptions(debugger_state)
    )
    |> Component.assign(:debugger_disabled_subscriptions, disabled_subscriptions(debugger_state))
  end

  @spec assign_cursor(Types.socket(), Types.maybe_non_neg_integer()) :: Types.socket()
  defp assign_cursor(socket, cursor_seq) do
    events =
      case socket.assigns[:debugger_state] do
        %{events: list} when is_list(list) -> list
        _ -> []
      end

    normalized_cursor = Timeline.normalize_cursor_seq(events, cursor_seq)

    snapshot_runtime =
      events
      |> snapshot_runtime_at_cursor(normalized_cursor)
      |> with_live_runtime_fallback(socket.assigns[:debugger_state])

    debug_mode = Timeline.debug_mode_enabled?(socket)

    debugger =
      debugger_assigns(
        normalized_cursor,
        snapshot_runtime,
        socket.assigns[:debugger_state],
        debug_mode
      )

    socket
    |> Component.assign(:debugger_cursor_watch_runtime, snapshot_runtime.watch)
    |> Component.assign(:debugger_cursor_companion_runtime, snapshot_runtime.companion)
    |> Component.assign(:debugger_cursor_phone_runtime, snapshot_runtime.phone)
    |> Component.assign(:debugger_cursor_seq, debugger.cursor_seq)
    |> Component.assign(:debugger_rows, debugger.rows)
    |> Component.assign(:debugger_selected_row, debugger.selected)
    |> Component.assign(:debugger_watch_runtime, debugger.watch_runtime)
    |> Component.assign(:debugger_companion_runtime, debugger.companion_runtime)
    |> Component.assign(:debugger_watch_view_runtime, debugger.watch_view_runtime)
  end

  @spec move_cursor(Types.socket(), :back | :forward) :: Types.socket()
  defp move_cursor(socket, direction) do
    events =
      case socket.assigns[:debugger_state] do
        %{events: list} when is_list(list) -> list
        _ -> []
      end

    cursor_seq = socket.assigns[:debugger_cursor_seq]
    seqs = Enum.map(events, & &1.seq)

    next_cursor =
      case Enum.find_index(seqs, &(&1 == cursor_seq)) do
        nil ->
          Timeline.normalize_cursor_seq(events, nil)

        index ->
          max_index = max(length(seqs) - 1, 0)

          case direction do
            :back -> Enum.at(seqs, min(index + 1, max_index))
            :forward -> Enum.at(seqs, max(index - 1, 0))
          end
      end

    assign_cursor(socket, next_cursor)
  end

  @spec assign_debugger_cursor(Types.socket(), Types.maybe_non_neg_integer()) :: Types.socket()
  defp assign_debugger_cursor(socket, debugger_cursor_seq) do
    debugger_state = socket.assigns[:debugger_state]

    snapshot_runtime = %{
      watch: socket.assigns[:debugger_cursor_watch_runtime],
      companion: socket.assigns[:debugger_cursor_companion_runtime],
      phone: socket.assigns[:debugger_cursor_phone_runtime]
    }

    debug_mode = Timeline.debug_mode_enabled?(socket)

    debugger = debugger_assigns(debugger_cursor_seq, snapshot_runtime, debugger_state, debug_mode)

    socket
    |> Component.assign(:debugger_cursor_seq, debugger.cursor_seq)
    |> Component.assign(:debugger_rows, debugger.rows)
    |> Component.assign(:debugger_selected_row, debugger.selected)
    |> Component.assign(:debugger_watch_runtime, debugger.watch_runtime)
    |> Component.assign(:debugger_companion_runtime, debugger.companion_runtime)
    |> Component.assign(:debugger_watch_view_runtime, debugger.watch_view_runtime)
  end

  @spec jump_latest_debugger(Types.socket()) :: Types.socket()
  defp jump_latest_debugger(socket) do
    debug_mode = Timeline.debug_mode_enabled?(socket)

    latest_seq =
      case socket.assigns[:debugger_state] do
        %{} = debugger_state -> latest_debugger_seq(debugger_state, debug_mode)
        _ -> nil
      end

    case latest_seq do
      seq when is_integer(seq) ->
        socket
        |> assign_debugger_cursor(seq)
        |> Component.assign(:debugger_follow_latest, true)

      _ ->
        socket
    end
  end

  @spec debugger_cursor_at_latest?(Types.socket()) :: boolean()
  defp debugger_cursor_at_latest?(socket) do
    debug_mode = Timeline.debug_mode_enabled?(socket)

    latest_seq =
      case socket.assigns[:debugger_state] do
        %{} = debugger_state -> latest_debugger_seq(debugger_state, debug_mode)
        _ -> nil
      end

    case latest_seq do
      seq when is_integer(seq) ->
        cursor_seq = socket.assigns[:debugger_cursor_seq]
        is_nil(cursor_seq) or cursor_seq == seq

      _ ->
        is_nil(socket.assigns[:debugger_cursor_seq])
    end
  end

  @spec latest_debugger_seq(map(), boolean()) :: Types.maybe_non_neg_integer()
  defp latest_debugger_seq(debugger_state, debug_mode) when is_map(debugger_state) do
    debugger_state
    |> Timeline.debugger_rows()
    |> Timeline.filter_debugger_rows_for_display(debug_mode)
    |> Enum.map(&Map.get(&1, :seq))
    |> Enum.filter(&is_integer/1)
    |> case do
      [] -> nil
      seqs -> Enum.max(seqs)
    end
  end

  @spec debugger_assigns(
          Types.maybe_non_neg_integer(),
          %{
            watch: map() | nil,
            companion: map() | nil,
            phone: map() | nil
          },
          map() | nil,
          boolean()
        ) :: map()
  defp debugger_assigns(cursor_seq, snapshot_runtime, debugger_state, debug_mode) do
    rows =
      debugger_state
      |> Timeline.debugger_rows()
      |> Timeline.filter_debugger_rows_for_display(debug_mode)

    selected = Timeline.select_debugger_row(rows, cursor_seq)
    resolved_cursor_seq = if selected, do: selected.seq, else: nil

    watch_runtime =
      case selected do
        %{watch_runtime: %{} = runtime} -> runtime
        _ -> snapshot_runtime.watch
      end

    companion_runtime =
      case selected do
        %{companion_runtime: %{} = runtime} -> runtime
        _ -> snapshot_runtime.companion
      end

    phone_runtime =
      case selected do
        %{phone_runtime: %{} = runtime} -> runtime
        _ -> snapshot_runtime.phone
      end

    companion_runtime = Util.companion_or_phone_runtime(companion_runtime, phone_runtime)

    watch_view_runtime =
      case watch_runtime do
        %{} = runtime ->
          Ide.Debugger.RuntimePreview.render_view_from_surface(runtime, :watch) || runtime

        _ ->
          nil
      end

    %{
      rows: rows,
      cursor_seq: resolved_cursor_seq,
      selected: selected,
      watch_runtime: watch_runtime,
      companion_runtime: companion_runtime,
      watch_view_runtime: watch_view_runtime
    }
  end
  defp normalize_debugger_cursor_seq(debugger_state, events, cursor_seq) do
    case Timeline.normalize_cursor_seq(events, cursor_seq) do
      seq when is_integer(seq) ->
        seq

      _ ->
        debugger_state
        |> Timeline.debugger_rows(500)
        |> CursorSeq.resolve_at_or_before(cursor_seq)
    end
  end

  @spec snapshot_runtime_at_cursor([map()], Types.maybe_non_neg_integer()) :: %{
          watch: map() | nil,
          companion: map() | nil,
          phone: map() | nil
        }
  def snapshot_runtime_at_cursor(events, cursor_seq) when is_list(events) do
    normalized = Timeline.normalize_cursor_seq(events, cursor_seq)
    upper = Util.timeline_upper_seq(events, normalized)

    %{
      watch: nearest_surface_runtime_at_or_before(events, upper, :watch),
      companion: nearest_surface_runtime_at_or_before(events, upper, :companion),
      phone: nearest_surface_runtime_at_or_before(events, upper, :phone)
    }
  end

  def snapshot_runtime_at_cursor(_events, _cursor_seq),
    do: %{watch: nil, companion: nil, phone: nil}

  @spec with_live_runtime_fallback(map(), map() | nil) :: %{
          watch: map() | nil,
          companion: map() | nil,
          phone: map() | nil
        }
  defp with_live_runtime_fallback(snapshot_runtime, debugger_state)
       when is_map(snapshot_runtime) and is_map(debugger_state) do
    %{
      watch: snapshot_runtime.watch || Map.get(debugger_state, :watch),
      companion: snapshot_runtime.companion || Map.get(debugger_state, :companion),
      phone: snapshot_runtime.phone || Map.get(debugger_state, :phone)
    }
  end

  defp with_live_runtime_fallback(snapshot_runtime, _debugger_state), do: snapshot_runtime

  @spec trigger_button_row(map(), map()) :: map()
  defp trigger_button_row(row, debugger_state) when is_map(row) and is_map(debugger_state) do
    %{
      id: Map.get(row, :id) || Map.get(row, "id"),
      label: Map.get(row, :label) || Map.get(row, "label"),
      trigger: Map.get(row, :trigger) || Map.get(row, "trigger"),
      trigger_display: Map.get(row, :trigger_display) || Map.get(row, "trigger_display"),
      target: Map.get(row, :target) || Map.get(row, "target"),
      message: Map.get(row, :message) || Map.get(row, "message"),
      source: Map.get(row, :source) || Map.get(row, "source"),
      button: Map.get(row, :button) || Map.get(row, "button"),
      button_event: Map.get(row, :button_event) || Map.get(row, "button_event"),
      interval_ms: Map.get(row, :interval_ms) || Map.get(row, "interval_ms"),
      declared_interval_ms:
        Map.get(row, :declared_interval_ms) || Map.get(row, "declared_interval_ms"),
      model_active?: Map.get(row, :model_active, Map.get(row, "model_active", true)) == true,
      injection_supported?:
        Debugger.subscription_trigger_injection_modal_supported?(debugger_state, row)
    }
  end

  @spec trigger_buttons(map()) :: [map()]
  def trigger_buttons(debugger_state) when is_map(debugger_state) do
    [:watch, :companion]
    |> Enum.flat_map(&Debugger.trigger_candidates(debugger_state, &1))
    |> Enum.map(&trigger_button_row(&1, debugger_state))
    |> Enum.filter(fn row ->
      is_binary(row.id) and row.id != "" and is_binary(row.trigger) and row.trigger != ""
    end)
  end

  def trigger_buttons(_), do: []

  @spec subscription_trigger_buttons(map(), :watch | :companion) :: [map()]
  defp subscription_trigger_buttons(debugger_state, target)
       when is_map(debugger_state) and target in [:watch, :companion] do
    debugger_state
    |> Debugger.trigger_candidates(target)
    |> Enum.map(&trigger_button_row(&1, debugger_state))
    |> Enum.filter(fn row ->
      row.source == "subscription" and is_binary(row.id) and row.id != "" and
        is_binary(row.trigger) and row.trigger != ""
    end)
  end

  defp subscription_trigger_buttons(_debugger_state, _target), do: []

  @spec auto_fire_enabled?(map(), :watch | :companion) :: boolean()
  defp auto_fire_enabled?(debugger_state, target)
       when is_map(debugger_state) and target in [:watch, :companion] do
    auto_tick = Map.get(debugger_state, :auto_tick, %{})
    source_root = if target == :companion, do: "phone", else: "watch"

    Map.get(auto_tick, :enabled) == true and
      source_root in List.wrap(Map.get(auto_tick, :targets, []))
  end

  defp auto_fire_enabled?(_debugger_state, _target), do: false

  defp auto_fire_subscriptions(debugger_state) when is_map(debugger_state) do
    auto_tick = Map.get(debugger_state, :auto_tick, %{})

    case Map.get(auto_tick, :subscriptions) do
      xs when is_list(xs) -> xs
      _ -> []
    end
  end

  defp disabled_subscriptions(debugger_state) when is_map(debugger_state) do
    case Map.get(debugger_state, :disabled_subscriptions) ||
           Map.get(debugger_state, "disabled_subscriptions") do
      xs when is_list(xs) -> xs
      _ -> []
    end
  end

  @spec cursor_runtime(map() | nil, :watch | :companion | :phone) :: map() | nil
  defp cursor_runtime(nil, _kind), do: nil

  defp cursor_runtime(event, :watch) when is_map(event), do: Map.get(event, :watch)
  defp cursor_runtime(event, :companion) when is_map(event), do: Map.get(event, :companion)
  defp cursor_runtime(event, :phone) when is_map(event), do: Map.get(event, :phone)

  @spec nearest_surface_runtime_at_or_before(
          [map()],
          non_neg_integer(),
          :watch | :companion | :phone
        ) ::
          map() | nil
  def nearest_surface_runtime_at_or_before(events, upper_seq, surface)
       when is_list(events) and is_integer(upper_seq) and upper_seq >= 0 and
              surface in [:watch, :companion, :phone] do
    events
    |> Enum.filter(fn event ->
      seq = Map.get(event, :seq)
      is_integer(seq) and seq <= upper_seq
    end)
    |> Enum.sort_by(&Map.get(&1, :seq), :desc)
    |> Enum.find_value(fn event ->
      case cursor_runtime(event, surface) do
        %{} = runtime -> runtime
        _ -> nil
      end
    end)
  end

end
