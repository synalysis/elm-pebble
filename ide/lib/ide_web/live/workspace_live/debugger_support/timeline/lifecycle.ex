defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Timeline.Lifecycle do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util

  @type events :: Types.events()
  @type lifecycle_row :: Types.lifecycle_row()
  @type timeline_event :: Types.timeline_event()
  @type elmc_lifecycle_payload :: Types.elmc_lifecycle_payload()
  @type maybe_non_neg_integer :: Types.maybe_non_neg_integer()

  @spec lifecycle_events_at_cursor(events(), maybe_non_neg_integer(), pos_integer()) :: [
          lifecycle_row()
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

  @spec lifecycle_summary(timeline_event()) :: String.t()
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

  @spec elmc_payload_display(elmc_lifecycle_payload(), atom() | String.t()) :: String.t()
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

end
