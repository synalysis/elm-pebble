defmodule Ide.Debugger.Types.DebuggerContractEventPayload do
  @moduledoc """
  Summary payload for `debugger.contract` timeline events (compile-time contract merge).
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:module) => String.t() | nil,
          optional(:rel_path) => String.t() | nil,
          optional(:source_root) => String.t(),
          optional(:target) => String.t(),
          optional(:source_byte_size) => non_neg_integer() | nil,
          optional(:source_line_count) => non_neg_integer() | nil,
          optional(:port_module) => boolean(),
          optional(:module_exposing) => String.t() | [String.t()] | nil,
          optional(:module_exposing_preview) => String.t(),
          optional(:msg_count) => non_neg_integer(),
          optional(:update_branch_count) => non_neg_integer(),
          optional(:update_branches_preview) => String.t(),
          optional(:init_case_branch_count) => non_neg_integer(),
          optional(:init_case_branches_preview) => String.t(),
          optional(:view_branch_count) => non_neg_integer(),
          optional(:view_branches_preview) => String.t(),
          optional(:subscriptions_case_branch_count) => non_neg_integer(),
          optional(:subscriptions_case_branches_preview) => String.t(),
          optional(:subscription_count) => non_neg_integer(),
          optional(:subscriptions_preview) => String.t(),
          optional(:init_cmd_count) => non_neg_integer(),
          optional(:init_cmd_preview) => String.t(),
          optional(:update_cmd_count) => non_neg_integer(),
          optional(:update_cmd_preview) => String.t(),
          optional(:port_count) => non_neg_integer(),
          optional(:ports_preview) => String.t(),
          optional(:import_count) => non_neg_integer(),
          optional(:imports_preview) => String.t(),
          optional(:import_entry_count) => non_neg_integer(),
          optional(:import_entries_preview) => String.t(),
          optional(:type_alias_count) => non_neg_integer(),
          optional(:type_aliases_preview) => String.t(),
          optional(:union_type_count) => non_neg_integer(),
          optional(:union_types_preview) => String.t(),
          optional(:top_level_function_count) => non_neg_integer(),
          optional(:top_level_functions_preview) => String.t(),
          optional(:view_root) => String.t(),
          optional(:view_outline) => boolean(),
          optional(:init_case_subject) => String.t(),
          optional(:subscriptions_case_subject) => String.t(),
          optional(:update_case_subject) => String.t(),
          optional(:view_case_subject) => String.t(),
          optional(:main_kind) => String.t() | nil,
          optional(:main_target) => String.t() | nil,
          optional(:main_field_count) => non_neg_integer(),
          optional(:init_params) => [String.t()],
          optional(:update_params) => [String.t()],
          optional(:view_params) => [String.t()],
          optional(:subscriptions_params) => [String.t()],
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()

  @spec from_introspect(Types.elm_introspect(), String.t() | nil, String.t(), boolean()) :: t()
  def from_introspect(ei, rel_path, source_root, view_outline) when is_map(ei) do
    msgs = Map.get(ei, "msg_constructors") || []
    msgs = if is_list(msgs), do: msgs, else: []
    branches = Map.get(ei, "update_case_branches") || []
    branches = if is_list(branches), do: branches, else: []
    vbr = Map.get(ei, "view_case_branches") || []
    vbr = if is_list(vbr), do: vbr, else: []
    ibr = Map.get(ei, "init_case_branches") || []
    ibr = if is_list(ibr), do: ibr, else: []
    sbr = Map.get(ei, "subscriptions_case_branches") || []
    sbr = if is_list(sbr), do: sbr, else: []
    subs = Map.get(ei, "subscription_ops") || []
    subs = if is_list(subs), do: subs, else: []
    icmd = Map.get(ei, "init_cmd_ops") || []
    icmd = if is_list(icmd), do: icmd, else: []
    ucmd = Map.get(ei, "update_cmd_ops") || []
    ucmd = if is_list(ucmd), do: ucmd, else: []
    vt = Map.get(ei, "view_tree") || %{}
    root = Map.get(vt, "type") || Map.get(vt, :type) || "unknown"

    preview = preview_join(branches, 4, ", ")
    sub_preview = preview_join(subs, 3, ", ")
    init_cmd_preview = preview_join(icmd, 3, ", ")
    update_cmd_preview = preview_join(ucmd, 3, ", ")
    view_case_preview = preview_join(vbr, 4, ", ")
    init_case_preview = preview_join(ibr, 4, ", ")
    subscriptions_case_preview = preview_join(sbr, 4, ", ")

    prts = Map.get(ei, "ports") || []
    prts = if is_list(prts), do: prts, else: []
    imps = Map.get(ei, "imported_modules") || []
    imps = if is_list(imps), do: imps, else: []
    import_preview = preview_join(imps, 8, ", ")

    ta = Map.get(ei, "type_aliases") || []
    ta = if is_list(ta), do: ta, else: []
    uni = Map.get(ei, "unions") || []
    uni = if is_list(uni), do: uni, else: []
    fns = Map.get(ei, "functions") || []
    fns = if is_list(fns), do: fns, else: []

    type_aliases_preview = preview_join(ta, 5, ", ")
    union_types_preview = preview_join(uni, 5, ", ")
    top_level_functions_preview = preview_join(fns, 8, ", ")
    port_preview = preview_join(prts, 6, ", ")

    mp = Map.get(ei, "main_program")
    main_fields = if is_map(mp), do: Map.get(mp, "fields") || [], else: []
    main_fields = if is_list(main_fields), do: main_fields, else: []

    ucs = Map.get(ei, "update_case_subject")
    vcs = Map.get(ei, "view_case_subject")
    ics = Map.get(ei, "init_case_subject")
    scs = Map.get(ei, "subscriptions_case_subject")

    port_module = Map.get(ei, "port_module") == true
    mex = Map.get(ei, "module_exposing")

    module_exposing_preview =
      case mex do
        ".." ->
          "(..)"

        xs when is_list(xs) and xs != [] ->
          preview_join(xs, 8, ", ")

        _ ->
          "—"
      end

    ient = Map.get(ei, "import_entries") || []
    ient = if is_list(ient), do: ient, else: []

    import_entries_preview =
      ient
      |> Enum.take(4)
      |> Enum.map(&ElmEx.DebuggerContract.import_entry_summary/1)
      |> Enum.join("; ")
      |> then(fn s ->
        cond do
          s == "" ->
            "—"

          length(ient) > 4 ->
            s <> "…"

          true ->
            s
        end
      end)

    sbs = Map.get(ei, "source_byte_size")
    slc = Map.get(ei, "source_line_count")

    base0 = %{
      module: Map.get(ei, "module"),
      rel_path: rel_path,
      source_root: source_root,
      target: target_label(source_root),
      source_byte_size: sbs,
      source_line_count: slc,
      port_module: port_module,
      module_exposing: mex,
      module_exposing_preview: module_exposing_preview,
      msg_count: length(msgs),
      update_branch_count: length(branches),
      update_branches_preview: preview,
      init_case_branch_count: length(ibr),
      init_case_branches_preview: init_case_preview,
      view_branch_count: length(vbr),
      view_branches_preview: view_case_preview,
      subscriptions_case_branch_count: length(sbr),
      subscriptions_case_branches_preview: subscriptions_case_preview,
      subscription_count: length(subs),
      subscriptions_preview: sub_preview,
      init_cmd_count: length(icmd),
      init_cmd_preview: init_cmd_preview,
      update_cmd_count: length(ucmd),
      update_cmd_preview: update_cmd_preview,
      port_count: length(prts),
      ports_preview: port_preview,
      import_count: length(imps),
      imports_preview: import_preview,
      import_entry_count: length(ient),
      import_entries_preview: import_entries_preview,
      type_alias_count: length(ta),
      type_aliases_preview: type_aliases_preview,
      union_type_count: length(uni),
      union_types_preview: union_types_preview,
      top_level_function_count: length(fns),
      top_level_functions_preview: top_level_functions_preview,
      view_root: root,
      view_outline: view_outline
    }

    base =
      base0
      |> maybe_put_string_field(:init_case_subject, ics)
      |> maybe_put_string_field(:subscriptions_case_subject, scs)
      |> maybe_put_string_field(:update_case_subject, ucs)
      |> maybe_put_string_field(:view_case_subject, vcs)

    param_payload =
      [:init_params, :update_params, :view_params, :subscriptions_params]
      |> Enum.reduce(%{}, fn atom_key, acc ->
        str = Atom.to_string(atom_key)
        xs = Map.get(ei, str) || []
        xs = if is_list(xs), do: xs, else: []

        if xs != [] do
          Map.put(acc, atom_key, xs)
        else
          acc
        end
      end)

    merged_main =
      if is_map(mp) do
        %{
          main_kind: Map.get(mp, "kind"),
          main_target: Map.get(mp, "target"),
          main_field_count: length(main_fields)
        }
      else
        %{}
      end

    Map.merge(base, Map.merge(merged_main, param_payload))
  end

  @spec target_label(String.t()) :: String.t()
  defp target_label("watch"), do: "watch"
  defp target_label("protocol"), do: "companion"
  defp target_label("phone"), do: "phone"
  defp target_label(_), do: "watch"

  @spec preview_join([String.t()], non_neg_integer(), String.t()) :: String.t()
  defp preview_join(items, take_count, separator) when is_list(items) do
    items
    |> Enum.take(take_count)
    |> Enum.join(separator)
    |> then(fn s -> if length(items) > take_count, do: s <> "…", else: s end)
  end

  @spec maybe_put_string_field(t(), atom() | String.t(), String.t()) :: t()
  defp maybe_put_string_field(map, key, value) when is_map(map) do
    if is_binary(value) and value != "" do
      Map.put(map, key, value)
    else
      map
    end
  end
end
