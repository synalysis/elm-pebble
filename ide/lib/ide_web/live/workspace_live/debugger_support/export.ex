defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Export do
  @moduledoc false
  @dialyzer :no_match

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.ElmIntrospect
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  def copy_json(term) do
    case Jason.encode(term, pretty: true) do
      {:ok, json} -> json
      {:error, _reason} -> Jason.encode!(inspect(term), pretty: true)
    end
  end

  @type debugger_state_export_ctx :: %{
          optional(:format_version) => String.t(),
          required(:project_name) => String.t(),
          required(:project_slug) => String.t(),
          required(:timeline_mode) => String.t(),
          required(:timeline_text) => String.t(),
          required(:watch_model_json) => String.t(),
          required(:companion_model_json) => String.t(),
          required(:rendered_view_json) => String.t(),
          optional(:session_running) => boolean() | nil,
          optional(:session_event_count) => non_neg_integer() | nil,
          optional(:debugger_cursor_seq) => non_neg_integer() | String.t() | nil,
          optional(:selected_timeline_seq) => non_neg_integer() | String.t() | nil,
          optional(:watch_profile_id) => String.t() | nil
        }

  @doc """
  Single markdown document for assistants: meta, timeline text, and JSON blocks for models and rendered tree.
  """
  @spec debugger_agent_state_markdown(debugger_state_export_ctx()) :: String.t()
  def debugger_agent_state_markdown(%{} = ctx) do
    format = Map.get(ctx, :format_version, "elm-pebble.debugger_state.v1")
    name = Map.get(ctx, :project_name, "")
    slug = Map.get(ctx, :project_slug, "")
    timeline_mode = Map.get(ctx, :timeline_mode, "")

    timeline =
      Map.get(ctx, :timeline_text, "") |> blank_fallback("(no timeline rows for this view)")

    watch_j = Map.get(ctx, :watch_model_json, "{}")
    comp_j = Map.get(ctx, :companion_model_json, "{}")
    view_j = Map.get(ctx, :rendered_view_json, "null")

    running = session_field(ctx, :session_running)
    evc = session_field(ctx, :session_event_count)
    cur = session_field(ctx, :debugger_cursor_seq)
    sel = session_field(ctx, :selected_timeline_seq)
    profile = session_field(ctx, :watch_profile_id)

    """
    # IDE debugger state export

    Use this document as context for an assistant. Sections mirror the Debugger page (live watch view / models).

    ## Meta

    - **format**: `#{format}`
    - **project**: #{name} (`#{slug}`)
    - **timeline_mode** (visible filter): `#{timeline_mode}`
    - **selected_timeline_seq**: #{sel}
    - **debugger_cursor_seq** (event cursor): #{cur}
    - **session_running**: #{running}
    - **session_event_count**: #{evc}
    - **watch_profile_id**: #{profile}

    ## Timeline

    #{timeline}

    ## Watch model

    ```json
    #{watch_j}
    ```

    ## Companion model

    ```json
    #{comp_j}
    ```

    ## Rendered view (watch, live panel)

    ```json
    #{view_j}
    ```
    """
    |> String.trim()
  end

  defp blank_fallback(s, fallback) when is_binary(s) do
    if String.trim(s) == "", do: fallback, else: s
  end

  defp blank_fallback(_, fallback), do: fallback

  defp session_field(ctx, key) do
    case Map.get(ctx, key) do
      nil -> "—"
      false -> "false"
      true -> "true"
      n when is_integer(n) -> Integer.to_string(n)
      other -> inspect(other)
    end
  end

  @doc """
  Human-readable summary of `model.elm_introspect` for a frozen runtime snapshot (e.g. at timeline cursor).
  """
  @spec format_elm_introspect_brief(map() | nil) :: String.t()
  def format_elm_introspect_brief(nil), do: "(no snapshot)"

  def format_elm_introspect_brief(%{} = runtime) do
    model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}
    ei = RuntimeArtifacts.introspect(runtime)
    mode = Map.get(model, "elm_executor_mode") || Map.get(model, :elm_executor_mode)

    case ei do
      %{} = m ->
        prefix =
          if is_binary(mode) and mode != "",
            do: "elm_executor_mode: #{mode}\n",
            else: ""

        prefix <> format_elm_introspect_inner(m)

      _ ->
        format_elm_introspect_inner(nil)
    end
  end

  def format_elm_introspect_brief(_), do: "(no snapshot)"

  @spec format_elm_introspect_inner(map() | nil) :: String.t()
  defp format_elm_introspect_inner(nil),
    do: "No parser snapshot merged for this surface at this seq."

  defp format_elm_introspect_inner(ei) when is_map(ei) do
    mod = Map.get(ei, "module") || Map.get(ei, :module) || "—"

    source_stats_line = format_source_stats_line(ei)

    exposing_line =
      format_module_exposing_line(Map.get(ei, "module_exposing") || Map.get(ei, :module_exposing))

    imps = Map.get(ei, "imported_modules") || Map.get(ei, :imported_modules) || []
    imps = if is_list(imps), do: imps, else: []

    import_line =
      case imps do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(14)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 14, do: s <> " …", else: s end)
      end

    ient = Map.get(ei, "import_entries") || Map.get(ei, :import_entries) || []
    ient = if is_list(ient), do: ient, else: []

    import_entries_line =
      case ient do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(6)
          |> Enum.map(&ElmIntrospect.import_entry_summary/1)
          |> Enum.join("; ")
          |> then(fn s -> if length(list) > 6, do: s <> " …", else: s end)
      end

    ta = Map.get(ei, "type_aliases") || Map.get(ei, :type_aliases) || []
    ta = if is_list(ta), do: ta, else: []
    uni = Map.get(ei, "unions") || Map.get(ei, :unions) || []
    uni = if is_list(uni), do: uni, else: []
    fns = Map.get(ei, "functions") || Map.get(ei, :functions) || []
    fns = if is_list(fns), do: fns, else: []

    alias_line =
      case ta do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(12)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 12, do: s <> " …", else: s end)
      end

    unions_line =
      case uni do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(12)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 12, do: s <> " …", else: s end)
      end

    functions_line =
      case fns do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(16)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 16, do: s <> " …", else: s end)
      end

    msgs = Map.get(ei, "msg_constructors") || Map.get(ei, :msg_constructors) || []
    msgs = if is_list(msgs), do: msgs, else: []

    msg_line =
      case msgs do
        [] ->
          "—"

        list ->
          shown = Enum.take(list, 10)

          Enum.join(shown, ", ") <>
            if(length(list) > length(shown), do: " …", else: "")
      end

    init = Map.get(ei, "init_model") || Map.get(ei, :init_model)
    init_line = brief_term_line(init, 220)

    ibs = Map.get(ei, "init_case_branches") || Map.get(ei, :init_case_branches) || []
    ibs = if is_list(ibs), do: ibs, else: []

    ics = Map.get(ei, "init_case_subject") || Map.get(ei, :init_case_subject)

    init_case_line =
      case ibs do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(12)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 12, do: s <> " …", else: s end)
      end

    init_case_header =
      cond do
        ibs != [] and is_binary(ics) and ics != "" ->
          "init (case #{ics}):"

        true ->
          "init (case …):"
      end

    icmd = Map.get(ei, "init_cmd_ops") || Map.get(ei, :init_cmd_ops) || []
    icmd = if is_list(icmd), do: icmd, else: []

    init_cmd_line =
      case icmd do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(10)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 10, do: s <> " …", else: s end)
      end

    vt = Map.get(ei, "view_tree") || Map.get(ei, :view_tree) || %{}
    root = Map.get(vt, "type") || Map.get(vt, :type) || "—"

    branches = Map.get(ei, "update_case_branches") || Map.get(ei, :update_case_branches) || []
    branches = if is_list(branches), do: branches, else: []

    upd_line =
      case branches do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(12)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 12, do: s <> " …", else: s end)
      end

    ucs = Map.get(ei, "update_case_subject") || Map.get(ei, :update_case_subject)

    upd_header =
      cond do
        branches != [] and is_binary(ucs) and ucs != "" ->
          "update (case #{ucs}):"

        true ->
          "update (case …):"
      end

    ucmd = Map.get(ei, "update_cmd_ops") || Map.get(ei, :update_cmd_ops) || []
    ucmd = if is_list(ucmd), do: ucmd, else: []

    update_cmd_line =
      case ucmd do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(10)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 10, do: s <> " …", else: s end)
      end

    vbr = Map.get(ei, "view_case_branches") || Map.get(ei, :view_case_branches) || []
    vbr = if is_list(vbr), do: vbr, else: []

    vcs = Map.get(ei, "view_case_subject") || Map.get(ei, :view_case_subject)

    view_case_line =
      case vbr do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(12)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 12, do: s <> " …", else: s end)
      end

    view_case_header =
      cond do
        vbr != [] and is_binary(vcs) and vcs != "" ->
          "view (case #{vcs}):"

        true ->
          "view (case …):"
      end

    scbs =
      Map.get(ei, "subscriptions_case_branches") || Map.get(ei, :subscriptions_case_branches) ||
        []

    scbs = if is_list(scbs), do: scbs, else: []

    scs = Map.get(ei, "subscriptions_case_subject") || Map.get(ei, :subscriptions_case_subject)

    subs_case_line =
      case scbs do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(12)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 12, do: s <> " …", else: s end)
      end

    subs_case_header =
      cond do
        scbs != [] and is_binary(scs) and scs != "" ->
          "subscriptions (case #{scs}):"

        true ->
          "subscriptions (case …):"
      end

    subs = Map.get(ei, "subscription_ops") || Map.get(ei, :subscription_ops) || []
    subs = if is_list(subs), do: subs, else: []

    sub_line =
      case subs do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(10)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 10, do: s <> " …", else: s end)
      end

    prts = Map.get(ei, "ports") || Map.get(ei, :ports) || []
    prts = if is_list(prts), do: prts, else: []

    ports_line =
      case prts do
        [] ->
          "—"

        list ->
          list
          |> Enum.take(12)
          |> Enum.join(", ")
          |> then(fn s -> if length(list) > 12, do: s <> " …", else: s end)
      end

    port_module =
      case Map.get(ei, "port_module") || Map.get(ei, :port_module) do
        true -> "yes"
        _ -> "no"
      end

    mp = Map.get(ei, "main_program") || Map.get(ei, :main_program)

    main_line =
      case mp do
        %{"target" => t, "kind" => k, "fields" => fs} when is_binary(t) ->
          fs = if is_list(fs), do: fs, else: []
          fld = fs |> Enum.take(8) |> Enum.join(", ")
          suffix = if length(fs) > 8, do: fld <> " …", else: fld
          suffix = if suffix != "", do: " {" <> suffix <> "}", else: ""
          "#{t} · #{k}#{suffix}"

        %{} = m ->
          t = Map.get(m, "target") || Map.get(m, :target)
          k = Map.get(m, "kind") || Map.get(m, :kind)

          if is_binary(t) and is_binary(k) do
            "#{t} · #{k}"
          else
            "—"
          end

        _ ->
          "—"
      end

    param_suffix =
      [
        {"init", Map.get(ei, "init_params") || Map.get(ei, :init_params)},
        {"update", Map.get(ei, "update_params") || Map.get(ei, :update_params)},
        {"view", Map.get(ei, "view_params") || Map.get(ei, :view_params)},
        {"subscriptions",
         Map.get(ei, "subscriptions_params") || Map.get(ei, :subscriptions_params)}
      ]
      |> Enum.flat_map(fn {label, xs} ->
        xs = if is_list(xs), do: xs, else: []
        if xs != [], do: ["#{label} λ: " <> Enum.join(xs, ", ")], else: []
      end)
      |> then(fn lines ->
        if lines == [], do: "", else: "\n" <> Enum.join(lines, "\n")
      end)

    """
    module: #{mod}
    source: #{source_stats_line}
    exposing: #{exposing_line}
    imports: #{import_line}
    import entries: #{import_entries_line}
    type aliases: #{alias_line}
    unions: #{unions_line}
    functions: #{functions_line}
    Msg: #{msg_line}
    main: #{main_line}
    #{upd_header} #{upd_line}
    update Cmd: #{update_cmd_line}
    #{subs_case_header} #{subs_case_line}
    subscriptions: #{sub_line}
    ports: #{ports_line}
    port module: #{port_module}
    init: #{init_line}
    #{init_case_header} #{init_case_line}
    init Cmd: #{init_cmd_line}
    #{view_case_header} #{view_case_line}
    view root: #{root}#{param_suffix}
    """
    |> String.trim()
  end

  @spec format_module_exposing_line(map()) :: String.t()
  defp format_module_exposing_line(".."), do: "(..)"

  defp format_module_exposing_line(names) when is_list(names) and names != [] do
    names
    |> Enum.take(16)
    |> Enum.join(", ")
    |> then(fn s -> if length(names) > 16, do: s <> " …", else: s end)
  end

  defp format_module_exposing_line(_), do: "—"

  @spec format_source_stats_line(map()) :: String.t()
  defp format_source_stats_line(ei) when is_map(ei) do
    bs = Map.get(ei, "source_byte_size") || Map.get(ei, :source_byte_size)
    ls = Map.get(ei, "source_line_count") || Map.get(ei, :source_line_count)

    cond do
      is_integer(bs) and bs >= 0 and is_integer(ls) and ls >= 0 ->
        "#{bs} bytes, #{ls} lines"

      is_integer(bs) and bs >= 0 ->
        "#{bs} bytes"

      is_integer(ls) and ls >= 0 ->
        "#{ls} lines"

      true ->
        "—"
    end
  end

  @spec brief_term_line(String.t(), Types.runtime_value()) :: String.t()
  defp brief_term_line(nil, _), do: "—"

  defp brief_term_line(term, max_chars) when is_integer(max_chars) and max_chars > 0 do
    case Jason.encode(term) do
      {:ok, s} ->
        if String.length(s) <= max_chars do
          s
        else
          String.slice(s, 0, max_chars) <> "…"
        end

      {:error, _} ->
        "…"
    end
  end

end
