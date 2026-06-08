defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Timeline do
  @moduledoc false
  @dialyzer :no_match

  alias Ide.Debugger.CursorSeq
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Live
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util

  @debugger_row_keys [
    :seq,
    :debugger_seq,
    :raw_seq,
    :type,
    :target,
    :message,
    :message_source,
    :selected_runtime,
    :other_runtime,
    :watch_runtime,
    :companion_runtime,
    :phone_runtime
  ]

  @spec event_json(Types.events()) :: String.t()
  def event_json(events) when is_list(events) do
    events
    |> Enum.reverse()
    |> Jason.encode!(pretty: true)
  end

  def event_json(event) when is_map(event), do: Jason.encode!(event, pretty: true)
  def event_json(_events), do: "[]"

  @spec payload_diff_json(Types.timeline_event() | nil, Types.timeline_event() | nil) :: String.t()
  def payload_diff_json(base_event, compare_event)
      when is_map(base_event) and is_map(compare_event) do
    base_payload = Map.get(base_event, :payload, %{})
    compare_payload = Map.get(compare_event, :payload, %{})

    if is_map(base_payload) and is_map(compare_payload) do
      base_keys = Map.keys(base_payload) |> MapSet.new()
      compare_keys = Map.keys(compare_payload) |> MapSet.new()

      added_keys = MapSet.difference(compare_keys, base_keys) |> MapSet.to_list() |> Enum.sort()
      removed_keys = MapSet.difference(base_keys, compare_keys) |> MapSet.to_list() |> Enum.sort()

      changed_keys =
        MapSet.intersection(base_keys, compare_keys)
        |> MapSet.to_list()
        |> Enum.filter(fn key -> Map.get(base_payload, key) != Map.get(compare_payload, key) end)
        |> Enum.sort()

      diff = %{
        from_seq: Map.get(base_event, :seq),
        to_seq: Map.get(compare_event, :seq),
        from_type: Map.get(base_event, :type),
        to_type: Map.get(compare_event, :type),
        added: Map.take(compare_payload, added_keys),
        removed: Map.take(base_payload, removed_keys),
        changed:
          Map.new(changed_keys, fn key ->
            {key, %{from: Map.get(base_payload, key), to: Map.get(compare_payload, key)}}
          end)
      }

      Jason.encode!(diff, pretty: true)
    else
      "{}"
    end
  end

  def payload_diff_json(_base_event, _compare_event), do: "{}"

  @spec event_type_counts(Types.events()) :: Types.event_type_counts()
  def event_type_counts(events) when is_list(events) do
    events
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, grouped} -> {type, length(grouped)} end)
    |> Enum.sort_by(fn {type, _} -> type end)
  end

  def event_type_counts(_events), do: []

  @spec event_summaries(Types.events()) :: [Types.event_summary()]
  def event_summaries(events) when is_list(events) do
    Enum.map(events, fn event ->
      payload = Map.get(event, :payload, %{})

      %{
        seq: Map.get(event, :seq, 0),
        type: Map.get(event, :type, "unknown"),
        target: Util.payload_target(payload),
        message: Util.payload_message(payload)
      }
    end)
  end

  def event_summaries(_events), do: []

  @spec protocol_exchange_at_cursor(Types.events(), Types.maybe_non_neg_integer(), pos_integer()) ::
          [
            Types.protocol_row()
          ]
  def protocol_exchange_at_cursor(events, cursor_seq, limit \\ 40)

  def protocol_exchange_at_cursor(events, cursor_seq, limit)
      when is_list(events) and is_integer(limit) and limit > 0 do
    upper = Util.timeline_upper_seq(events, cursor_seq)

    events
    |> Enum.filter(fn e ->
      e.type in ["debugger.protocol_tx", "debugger.protocol_rx"] and e.seq <= upper
    end)
    |> Enum.sort_by(& &1.seq, :asc)
    |> Enum.take(-limit)
    |> Enum.map(fn e ->
      payload = Map.get(e, :payload) || %{}
      kind = if e.type == "debugger.protocol_tx", do: "tx", else: "rx"

      %{
        seq: e.seq,
        kind: kind,
        from: Util.protocol_payload_field(payload, :from),
        to: Util.protocol_payload_field(payload, :to),
        message: Util.protocol_payload_field(payload, :message)
      }
    end)
  end

  def protocol_exchange_at_cursor(_events, _cursor_seq, _limit), do: []

  @spec update_messages_at_cursor(Types.events(), Types.maybe_non_neg_integer(), pos_integer()) ::
          [
            Types.update_message_row()
          ]
  def update_messages_at_cursor(events, cursor_seq, limit \\ 40)

  def update_messages_at_cursor(events, cursor_seq, limit)
      when is_list(events) and is_integer(limit) and limit > 0 do
    upper = Util.timeline_upper_seq(events, cursor_seq)

    events
    |> Enum.filter(fn e -> e.type == "debugger.update_in" and e.seq <= upper end)
    |> Enum.sort_by(& &1.seq, :asc)
    |> Enum.take(-limit)
    |> Enum.map(fn e ->
      payload = Map.get(e, :payload) || %{}

      %{
        seq: e.seq,
        target: Util.protocol_payload_field(payload, :target),
        message: Util.protocol_payload_field(payload, :message)
      }
    end)
  end

  def update_messages_at_cursor(_events, _cursor_seq, _limit), do: []

  @spec debugger_rows(Types.events() | map() | nil, pos_integer()) :: [Types.debugger_row()]
  def debugger_rows(source, limit \\ 80)

  def debugger_rows(%{} = debugger_state, limit) when is_integer(limit) and limit > 0 do
    case Map.get(debugger_state, :debugger_timeline) ||
           Map.get(debugger_state, "debugger_timeline") do
      rows when is_list(rows) and rows != [] ->
        rows
        |> Enum.sort_by(&debugger_row_seq/1, :desc)
        |> Enum.take(limit)
        |> Enum.map(&normalize_debugger_row/1)
        |> Enum.map(&ensure_debugger_row/1)

      _ ->
        debugger_state
        |> Map.get(:events, Map.get(debugger_state, "events", []))
        |> debugger_rows(limit)
    end
  end

  def debugger_rows(events, limit) when is_list(events) and is_integer(limit) and limit > 0 do
    events
    |> Enum.filter(fn event ->
      Map.get(event, :type) in ["debugger.init_in", "debugger.update_in"]
    end)
    |> Enum.sort_by(&Map.get(&1, :seq, 0), :asc)
    |> Enum.take(-limit)
    |> Enum.with_index(1)
    |> Enum.map(fn {event, debugger_seq} ->
      payload = Map.get(event, :payload) || %{}
      raw_seq = Map.get(event, :seq, 0)
      target = Util.debugger_target(Util.protocol_payload_field(payload, :target))

      watch_runtime = Live.nearest_surface_runtime_at_or_before(events, raw_seq, :watch)
      companion_runtime = Live.nearest_surface_runtime_at_or_before(events, raw_seq, :companion)
      phone_runtime = Live.nearest_surface_runtime_at_or_before(events, raw_seq, :phone)
      companion_app_runtime = Util.companion_or_phone_runtime(companion_runtime, phone_runtime)

      %{
        seq: debugger_seq,
        debugger_seq: debugger_seq,
        raw_seq: raw_seq,
        type: debugger_type_from_event(event),
        target: target,
        message: Util.protocol_payload_field(payload, :message) || "",
        message_source: Util.protocol_payload_field(payload, :message_source),
        selected_runtime:
          Util.debugger_target_runtime(target, watch_runtime, companion_app_runtime),
        other_runtime: Util.debugger_other_runtime(target, watch_runtime, companion_app_runtime),
        watch_runtime: watch_runtime,
        companion_runtime: companion_app_runtime,
        phone_runtime: phone_runtime
      }
      |> ensure_debugger_row()
    end)
  end

  def debugger_rows(_source, _limit), do: []

  @spec ensure_debugger_row(Types.debugger_row()) :: Types.debugger_row()
  defp ensure_debugger_row(%{} = row), do: Map.take(row, @debugger_row_keys)

  @spec debugger_rows_for_target([Types.debugger_row()], String.t()) :: [Types.debugger_row()]
  def debugger_rows_for_target(rows, target)
      when is_list(rows) and target in ["watch", "companion"] do
    rows
    |> Enum.filter(fn row -> Map.get(row, :target) == target end)
    |> Enum.map(&ensure_debugger_row/1)
    |> newest_first()
  end

  def debugger_rows_for_target(_rows, _target), do: []

  @spec debugger_rows_for_mode([Types.debugger_row()], String.t()) :: [Types.debugger_row()]
  def debugger_rows_for_mode(rows, "watch"), do: debugger_rows_for_target(rows, "watch")
  def debugger_rows_for_mode(rows, "companion"), do: debugger_rows_for_target(rows, "companion")

  def debugger_rows_for_mode(rows, "mixed") when is_list(rows),
    do: rows |> Enum.map(&ensure_debugger_row/1) |> newest_first()

  def debugger_rows_for_mode(rows, "separate") when is_list(rows),
    do: rows |> Enum.map(&ensure_debugger_row/1) |> newest_first()

  def debugger_rows_for_mode(_rows, _mode), do: []

  @doc """
  Hides internal runtime executor diagnostics from the user-facing timeline unless
  IDE debug mode is enabled.
  """
  @spec filter_debugger_rows_for_display([Types.debugger_row()], boolean()) :: [
          Types.debugger_row()
        ]
  def filter_debugger_rows_for_display(rows, true) when is_list(rows), do: rows

  def filter_debugger_rows_for_display(rows, _debug_mode) when is_list(rows) do
    Enum.reject(rows, fn row ->
      debugger_runtime_status_row?(row) or debugger_http_row?(row)
    end)
  end

  def filter_debugger_rows_for_display(_rows, _debug_mode), do: []

  @spec debugger_runtime_status_row?(Types.debugger_row()) :: boolean()
  def debugger_runtime_status_row?(row) when is_map(row) do
    type = Map.get(row, :type) || Map.get(row, "type")
    source = Map.get(row, :message_source) || Map.get(row, "message_source")
    type == "runtime" and source == "runtime_status"
  end

  def debugger_runtime_status_row?(_row), do: false

  @spec debugger_http_row?(Types.debugger_row()) :: boolean()
  def debugger_http_row?(row) when is_map(row) do
    type = Map.get(row, :type) || Map.get(row, "type")
    source = Map.get(row, :message_source) || Map.get(row, "message_source")

    type == "http" or source in ["http", "http_pending"]
  end

  def debugger_http_row?(_row), do: false

  @spec debugger_timeline_text([Types.debugger_row()]) :: String.t()
  def debugger_timeline_text(rows) when is_list(rows) do
    rows
    |> newest_first()
    |> Enum.map(&debugger_timeline_line/1)
    |> Enum.join("\n")
  end

  def debugger_timeline_text(_rows), do: ""

  @spec newest_first(Types.events()) :: Types.events()
  defp newest_first(rows) when is_list(rows),
    do: Enum.sort_by(rows, &Map.get(&1, :seq, 0), :desc)

  @spec debugger_timeline_line(Types.timeline_event()) :: String.t()
  defp debugger_timeline_line(row) when is_map(row) do
    seq = Map.get(row, :seq) || Map.get(row, "seq") || "?"
    target = Map.get(row, :target) || Map.get(row, "target") || "-"
    type = Map.get(row, :type) || Map.get(row, "type") || "update"
    message = Map.get(row, :message) || Map.get(row, "message") || ""
    source = Map.get(row, :message_source) || Map.get(row, "message_source")

    type_label =
      case {type, source} do
        {"http", _} -> "http"
        {_, "http"} -> "http"
        {_, "http_pending"} -> "http (pending)"
        {other, _} -> other
      end

    "##{seq} [#{target}] #{type_label} #{message}"
    |> String.trim()
  end

  @spec normalize_debugger_row(Types.timeline_event()) :: Types.debugger_row()
  defp normalize_debugger_row(row) when is_map(row) do
    seq = debugger_row_seq(row)
    raw_seq = Map.get(row, :raw_seq) || Map.get(row, "raw_seq") || seq
    target = Util.debugger_target(Map.get(row, :target) || Map.get(row, "target"))
    watch_runtime = Map.get(row, :watch) || Map.get(row, "watch")
    companion_runtime = Map.get(row, :companion) || Map.get(row, "companion")
    phone_runtime = Map.get(row, :phone) || Map.get(row, "phone")
    companion_app_runtime = Util.companion_or_phone_runtime(companion_runtime, phone_runtime)

    %{
      seq: seq,
      debugger_seq: seq,
      raw_seq: raw_seq,
      type: Map.get(row, :type) || Map.get(row, "type") || "update",
      target: target,
      message: Map.get(row, :message) || Map.get(row, "message") || "",
      message_source: Map.get(row, :message_source) || Map.get(row, "message_source"),
      selected_runtime:
        Util.debugger_target_runtime(target, watch_runtime, companion_app_runtime),
      other_runtime: Util.debugger_other_runtime(target, watch_runtime, companion_app_runtime),
      watch_runtime: watch_runtime,
      companion_runtime: companion_app_runtime,
      phone_runtime: phone_runtime
    }
  end

  @spec debugger_row_seq(map()) :: non_neg_integer()
  defp debugger_row_seq(row) when is_map(row) do
    case Map.get(row, :seq) || Map.get(row, "seq") || Map.get(row, :debugger_seq) ||
           Map.get(row, "debugger_seq") do
      seq when is_integer(seq) and seq >= 0 -> seq
      _ -> 0
    end
  end

  defp debugger_row_seq(_row), do: 0

  @spec debugger_type_from_event(map()) :: String.t()
  defp debugger_type_from_event(%{type: "debugger.init_in"}), do: "init"
  defp debugger_type_from_event(%{type: "debugger.update_in"}), do: "update"
  defp debugger_type_from_event(_event), do: "update"

  @spec debugger_message_label(map()) :: String.t()
  def debugger_message_label(message) when is_binary(message) do
    case Regex.run(~r/^([A-Z][A-Za-z0-9_]*)(?:\s+)([\{\[].*)$/, String.trim(message)) do
      [_, constructor, json] ->
        case Jason.decode(json) do
          {:ok, value} -> "#{constructor} #{Util.elm_value(value)}"
          {:error, _reason} -> message
        end

      _ ->
        message
    end
  end

  def debugger_message_label(nil), do: ""
  def debugger_message_label(message), do: to_string(message)

  @spec selected_debugger_row(Types.events() | map() | nil, Types.maybe_non_neg_integer()) ::
          Types.debugger_row() | nil
  def selected_debugger_row(source, cursor_seq) do
    select_debugger_row(debugger_rows(source, 500), cursor_seq)
  end

  @spec select_debugger_row([Types.debugger_row()], Types.maybe_non_neg_integer()) ::
          Types.debugger_row() | nil
  def select_debugger_row(rows, cursor_seq) when is_list(rows) do
    newest_rows = Enum.sort_by(rows, &Map.get(&1, :seq, 0), :desc)
    oldest_rows = Enum.reverse(newest_rows)

    cond do
      rows == [] ->
        nil

      is_integer(cursor_seq) ->
        Enum.find(oldest_rows, fn row -> row.seq >= cursor_seq end) || List.first(newest_rows)

      true ->
        List.first(newest_rows)
    end
  end

  @spec debug_mode_enabled?(Types.socket()) :: boolean()
  def debug_mode_enabled?(socket) do
    case socket do
      %{assigns: %{debug_mode: true}} -> true
      _ -> false
    end
  end

  @spec render_events_at_cursor(Types.events(), Types.maybe_non_neg_integer(), pos_integer()) :: [
          Types.render_event_row()
        ]
  def render_events_at_cursor(events, cursor_seq, limit \\ 24)

  def render_events_at_cursor(events, cursor_seq, limit)
      when is_list(events) and is_integer(limit) and limit > 0 do
    upper = Util.timeline_upper_seq(events, cursor_seq)

    events
    |> Enum.filter(fn e -> e.type == "debugger.view_render" and e.seq <= upper end)
    |> Enum.sort_by(& &1.seq, :asc)
    |> Enum.take(-limit)
    |> Enum.map(fn e ->
      payload = Map.get(e, :payload) || %{}

      %{
        seq: e.seq,
        target: Util.protocol_payload_field(payload, :target),
        root: Util.protocol_payload_field(payload, :root)
      }
    end)
  end

  def render_events_at_cursor(_events, _cursor_seq, _limit), do: []

  @spec lifecycle_events_at_cursor(Types.events(), Types.maybe_non_neg_integer(), pos_integer()) ::
          [
            Types.lifecycle_row()
          ]
  def lifecycle_events_at_cursor(events, cursor_seq, limit \\ 12)

  def lifecycle_events_at_cursor(events, cursor_seq, limit)
      when is_list(events) and is_integer(limit) and limit > 0 do
    upper = Util.timeline_upper_seq(events, cursor_seq)

    types = [
      "debugger.start",
      "debugger.reset",
      "debugger.reload",
      "debugger.contract",
      "debugger.elm_introspect",
      "debugger.elmc_check",
      "debugger.elmc_compile",
      "debugger.elmc_manifest"
    ]

    events
    |> Enum.filter(fn e -> e.type in types and e.seq <= upper end)
    |> Enum.sort_by(& &1.seq, :asc)
    |> Enum.take(-limit)
    |> Enum.map(fn e ->
      %{
        seq: e.seq,
        type: e.type,
        summary: lifecycle_summary(e)
      }
    end)
  end

  def lifecycle_events_at_cursor(_events, _cursor_seq, _limit), do: []

  @spec lifecycle_summary(map()) :: String.t()
  defp lifecycle_summary(%{type: "debugger.reload", payload: payload}) when is_map(payload) do
    root = Util.protocol_payload_field(payload, :source_root) || "watch"
    path = Util.protocol_payload_field(payload, :rel_path) || "—"
    rev = Util.protocol_payload_field(payload, :revision) || "—"
    "#{root} · #{path} · #{rev}"
  end

  defp lifecycle_summary(%{type: type, payload: payload})
       when type in ["debugger.contract", "debugger.elm_introspect"] and is_map(payload) do
    mod = Map.get(payload, :module) || Map.get(payload, "module") || "—"
    tgt = Map.get(payload, :target) || Map.get(payload, "target") || "—"
    mc = Map.get(payload, :msg_count) || Map.get(payload, "msg_count") || 0
    vr = Map.get(payload, :view_root) || Map.get(payload, "view_root") || "—"
    ub = Map.get(payload, :update_branch_count) || Map.get(payload, "update_branch_count") || 0
    sc = Map.get(payload, :subscription_count) || Map.get(payload, "subscription_count") || 0
    ic = Map.get(payload, :init_cmd_count) || Map.get(payload, "init_cmd_count") || 0
    uc = Map.get(payload, :update_cmd_count) || Map.get(payload, "update_cmd_count") || 0
    vb = Map.get(payload, :view_branch_count) || Map.get(payload, "view_branch_count") || 0

    ibc =
      Map.get(payload, :init_case_branch_count) || Map.get(payload, "init_case_branch_count") || 0

    sbc =
      Map.get(payload, :subscriptions_case_branch_count) ||
        Map.get(payload, "subscriptions_case_branch_count") || 0

    pc = Map.get(payload, :port_count) || Map.get(payload, "port_count") || 0
    icx = Map.get(payload, :import_count) || Map.get(payload, "import_count") || 0

    iec =
      Map.get(payload, :import_entry_count) || Map.get(payload, "import_entry_count") || 0

    mk = Map.get(payload, :main_kind) || Map.get(payload, "main_kind")

    base = "#{mod} · #{tgt} · #{mc} msgs · view #{vr}"

    base = if is_integer(ub) and ub > 0, do: base <> " · #{ub} update branches", else: base
    base = if is_integer(vb) and vb > 0, do: base <> " · #{vb} view case branches", else: base
    base = if is_integer(ibc) and ibc > 0, do: base <> " · #{ibc} init case branches", else: base

    base =
      if is_integer(sbc) and sbc > 0,
        do: base <> " · #{sbc} subscriptions case branches",
        else: base

    base = if is_integer(sc) and sc > 0, do: base <> " · #{sc} subs", else: base
    base = if is_integer(ic) and ic > 0, do: base <> " · #{ic} init cmds", else: base
    base = if is_integer(uc) and uc > 0, do: base <> " · #{uc} update cmds", else: base
    base = if is_integer(pc) and pc > 0, do: base <> " · #{pc} ports", else: base
    base = if is_integer(icx) and icx > 0, do: base <> " · #{icx} imports", else: base
    base = if is_integer(iec) and iec > 0, do: base <> " · #{iec} import lines", else: base

    tac = Map.get(payload, :type_alias_count) || Map.get(payload, "type_alias_count") || 0
    unc = Map.get(payload, :union_type_count) || Map.get(payload, "union_type_count") || 0

    fnc =
      Map.get(payload, :top_level_function_count) || Map.get(payload, "top_level_function_count") ||
        0

    base = if is_integer(tac) and tac > 0, do: base <> " · #{tac} type aliases", else: base
    base = if is_integer(unc) and unc > 0, do: base <> " · #{unc} unions", else: base
    base = if is_integer(fnc) and fnc > 0, do: base <> " · #{fnc} functions", else: base

    ucs = Map.get(payload, :update_case_subject) || Map.get(payload, "update_case_subject")
    vcs = Map.get(payload, :view_case_subject) || Map.get(payload, "view_case_subject")
    ics = Map.get(payload, :init_case_subject) || Map.get(payload, "init_case_subject")

    scs =
      Map.get(payload, :subscriptions_case_subject) ||
        Map.get(payload, "subscriptions_case_subject")

    base =
      if is_integer(ub) and ub > 0 and is_binary(ucs) and ucs != "" do
        base <> " · case #{ucs}"
      else
        base
      end

    base =
      if is_integer(vb) and vb > 0 and is_binary(vcs) and vcs != "" do
        base <> " · view case #{vcs}"
      else
        base
      end

    base =
      if is_integer(ibc) and ibc > 0 and is_binary(ics) and ics != "" do
        base <> " · init case #{ics}"
      else
        base
      end

    base =
      if is_integer(sbc) and sbc > 0 and is_binary(scs) and scs != "" do
        base <> " · subs case #{scs}"
      else
        base
      end

    me = Map.get(payload, :module_exposing) || Map.get(payload, "module_exposing")

    base =
      case me do
        ".." ->
          base <> " · exposing (..)"

        xs when is_list(xs) and xs != [] ->
          base <> " · exposing (#{length(xs)})"

        _ ->
          base
      end

    pm = Map.get(payload, :port_module)
    pm = if is_boolean(pm), do: pm, else: Map.get(payload, "port_module") == true

    base =
      if pm do
        base <> " · port module"
      else
        base
      end

    if is_binary(mk) and mk != "" and mk != "unknown" do
      base <> " · main #{mk}"
    else
      base
    end
  end

  defp lifecycle_summary(%{type: "debugger.reset"}), do: "full reset"
  defp lifecycle_summary(%{type: "debugger.start"}), do: "session started"

  defp lifecycle_summary(%{type: "debugger.elmc_check", payload: payload})
       when is_map(payload) do
    status = elmc_payload_display(payload, :status)
    errs = elmc_payload_display(payload, :error_count)
    warns = elmc_payload_display(payload, :warning_count)
    path = elmc_payload_display(payload, :checked_path)
    "#{status} · #{errs} err · #{warns} warn · #{path}"
  end

  defp lifecycle_summary(%{type: "debugger.elmc_compile", payload: payload})
       when is_map(payload) do
    status = elmc_payload_display(payload, :status)
    errs = elmc_payload_display(payload, :error_count)
    rev = elmc_payload_display(payload, :revision)
    cached = elmc_payload_display(payload, :cached)
    path = elmc_payload_display(payload, :compiled_path)
    elmx = elmc_payload_display(payload, :elmx_compile_error_message)

    base = "#{status} · #{errs} err · rev #{rev} · cached=#{cached} · #{path}"

    if elmx != "—" and elmx != "" do
      base <> " · elmx: " <> String.slice(elmx, 0, 120)
    else
      base
    end
  end

  defp lifecycle_summary(%{type: "debugger.elmc_manifest", payload: payload})
       when is_map(payload) do
    status = elmc_payload_display(payload, :status)
    errs = elmc_payload_display(payload, :error_count)
    strict = elmc_payload_display(payload, :strict)
    schema = elmc_payload_display(payload, :schema_version)
    path = elmc_payload_display(payload, :manifest_path)
    "#{status} · #{errs} err · strict=#{strict} · schema #{schema} · #{path}"
  end

  defp lifecycle_summary(%{type: type}) when is_binary(type), do: type
  defp lifecycle_summary(_), do: "—"

  @spec elmc_payload_display(map(), atom() | String.t()) :: String.t()
  defp elmc_payload_display(payload, key) when is_map(payload) do
    str = Atom.to_string(key)
    v = Map.get(payload, key) || Map.get(payload, str)

    cond do
      is_binary(v) -> v
      is_integer(v) -> Integer.to_string(v)
      is_boolean(v) -> if(v, do: "true", else: "false")
      is_atom(v) -> Atom.to_string(v)
      true -> "—"
    end
  end

  @spec filtered_event_summaries(Types.events(), Types.timeline_kind(), pos_integer()) :: [
          Types.event_summary()
        ]
  def filtered_event_summaries(events, kind, limit)
      when is_list(events) and is_integer(limit) and limit > 0 do
    events
    |> event_summaries()
    |> Enum.filter(fn row -> kind == :all or Util.timeline_kind_for_type(row.type) == kind end)
    |> Enum.take(limit)
  end

  def filtered_event_summaries(_events, _kind, _limit), do: []

  @spec filtered_event_summaries(Types.events(), Types.timeline_kind(), pos_integer(), String.t()) ::
          [Types.event_summary()]
  def filtered_event_summaries(events, kind, limit, query)
      when is_binary(query) do
    query_norm = String.downcase(String.trim(query))

    filtered_event_summaries(events, kind, limit * 5)
    |> Enum.filter(fn row ->
      query_norm == "" or
        String.contains?(String.downcase(row.type), query_norm) or
        String.contains?(String.downcase(row.message || ""), query_norm)
    end)
    |> Enum.take(limit)
  end

  @spec highlight_fragments(String.t(), String.t()) :: [Types.highlight_fragment()]
  def highlight_fragments(value, query) when is_binary(value) and is_binary(query) do
    query_norm = String.trim(query)

    if query_norm == "" do
      [%{text: value, match?: false}]
    else
      pattern = Regex.compile!(Regex.escape(query_norm), "i")
      downcased_query = String.downcase(query_norm)

      pattern
      |> Regex.split(value, include_captures: true, trim: false)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn part ->
        %{text: part, match?: String.downcase(part) == downcased_query}
      end)
    end
  end

  @spec seq_bounds(Types.events()) :: {non_neg_integer(), non_neg_integer()} | nil
  def seq_bounds(events) when is_list(events) and events != [] do
    seqs = Enum.map(events, & &1.seq)
    {Enum.min(seqs), Enum.max(seqs)}
  end

  def seq_bounds(_events), do: nil

  @spec min_seq(Types.events()) :: non_neg_integer()
  def min_seq(events) do
    case seq_bounds(events) do
      {min_seq, _max_seq} -> min_seq
      nil -> 0
    end
  end

  @spec max_seq(Types.events()) :: non_neg_integer()
  def max_seq(events) do
    case seq_bounds(events) do
      {_min_seq, max_seq} -> max_seq
      nil -> 0
    end
  end

  @spec normalize_cursor_seq(Types.events(), Types.maybe_non_neg_integer()) ::
          Types.maybe_non_neg_integer()
  def normalize_cursor_seq(events, cursor_seq) do
    CursorSeq.resolve_at_or_before(events, cursor_seq)
  end
end
