# Regenerate DebuggerSupport split. Run from ide/: mix run scripts/split_debugger_support.exs
#
# Reads the monolith backup (or debugger_support.ex if it is still the monolith).
# Produces debugger_support/{types,replay,export,diagnostics,util,timeline,rendered,live}.ex
# and a thin debugger_support.ex facade with defdelegates.

root = Path.dirname(Path.dirname(Path.expand(__ENV__.file)))
facade_path = Path.join(root, "lib/ide_web/live/workspace_live/debugger_support.ex")
monolith_path = "/tmp/debugger_support.monolith.ex"

src_path =
  cond do
    File.exists?(monolith_path) ->
      monolith_path

    File.exists?(facade_path) and File.read!(facade_path) =~ "defdelegate assign_defaults" ->
      raise "debugger_support.ex is already the facade; restore #{monolith_path} first"

    true ->
      facade_path
  end

out_dir = Path.join(root, "lib/ide_web/live/workspace_live/debugger_support")

lines =
  src_path
  |> File.read!()
  |> String.split("\n", trim: false)
  |> then(fn ls -> if List.last(ls) == "", do: Enum.drop(ls, -1), else: ls end)

slice = fn ranges ->
  Enum.flat_map(ranges, fn {a, b} -> Enum.slice(lines, a - 1, b - a + 1) end)
  |> Enum.map(&(&1 <> "\n"))
  |> IO.iodata_to_binary()
end

types_body =
  slice.([{16, 82}])
  |> String.replace(~r/^  alias .*\n/, "")

base_aliases = [
  {"CursorSeq.", "  alias Ide.Debugger.CursorSeq"},
  {"Debugger.", "  alias Ide.Debugger"},
  {"ElmIntrospect.", "  alias Ide.Debugger.ElmIntrospect"},
  {"RuntimeArtifacts.", "  alias Ide.Debugger.RuntimeArtifacts"},
  {"RuntimeFingerprintDrift.", "  alias Ide.Debugger.RuntimeFingerprintDrift"},
  {"Projects.", "  alias Ide.Projects"},
  {"Project.", "  alias Ide.Projects.Project"},
  {"PdcDecoder.", "  alias Ide.Resources.PdcDecoder"},
  {"ResourceStore.", "  alias Ide.Resources.ResourceStore"},
  {"Types.", "  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types"},
  {"Component.", "  alias Phoenix.Component"}
]

cross_aliases = [
  {"Diagnostics.", "  alias IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics"},
  {"Export.", "  alias IdeWeb.WorkspaceLive.DebuggerSupport.Export"},
  {"Live.", "  alias IdeWeb.WorkspaceLive.DebuggerSupport.Live"},
  {"Replay.", "  alias IdeWeb.WorkspaceLive.DebuggerSupport.Replay"},
  {"Rendered.", "  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered"},
  {"Timeline.", "  alias IdeWeb.WorkspaceLive.DebuggerSupport.Timeline"},
  {"Util.", "  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util"}
]

alias_used? = fn body, needle ->
  Regex.match?(~r/(?<![A-Za-z0-9_.])#{Regex.escape(needle)}/, body)
end

aliases_for = fn body ->
  (base_aliases ++ cross_aliases)
  |> Enum.sort_by(fn {needle, _} -> byte_size(needle) end, :desc)
  |> Enum.filter(fn {needle, _} -> alias_used?.(body, needle) end)
  |> Enum.map(fn {_, line} -> line end)
  |> Enum.uniq()
  |> Enum.map(&(&1 <> "\n"))
  |> IO.iodata_to_binary()
end

replay_body = slice.([{218, 374}, {3216, 3282}])

export_body = slice.([{1490, 2015}])

diagnostics_body = slice.([{2017, 2028}, {2050, 2426}])

util_body = slice.([{3016, 3131}, {3691, 3702}, {4292, 4575}])

timeline_body =
  slice.([{2428, 3015}, {3133, 3202}, {3533, 3536}])
  |> String.replace("defp normalize_cursor_seq(", "def normalize_cursor_seq(")

rendered_body = slice.([{376, 1488}, {2030, 2048}, {3704, 4290}])

live_body = slice.([{84, 216}, {3204, 3214}, {3284, 3531}, {3538, 3548}, {3549, 3690}])

live_header = """
  @default_event_limit 500

"""

# Cross-module calls from Live -> Timeline / Util (not local defs or @specs).
live_body =
  live_body
  |> String.replace("debugger_rows()", "Timeline.debugger_rows()")
  |> String.replace("debugger_rows(", "Timeline.debugger_rows(")
  |> String.replace("filter_debugger_rows_for_display(", "Timeline.filter_debugger_rows_for_display(")
  |> String.replace("select_debugger_row(", "Timeline.select_debugger_row(")
  |> String.replace("normalize_cursor_seq(", "Timeline.normalize_cursor_seq(")
  |> String.replace("timeline_upper_seq(", "Util.timeline_upper_seq(")
  |> String.replace("debug_mode_enabled?(", "Timeline.debug_mode_enabled?(")
  |> String.replace("nearest_surface_runtime_at_or_before(", "Live.nearest_surface_runtime_at_or_before(")
  |> String.replace("latest_debugger_seq(", "Live.latest_debugger_seq(")
  |> String.replace("debugger_cursor_at_latest?(", "Live.debugger_cursor_at_latest?(")
  |> String.replace("Timeline.Timeline.", "Timeline.")

# Restore self-references in Live definitions
live_body =
  live_body
  |> String.replace("Live.nearest_surface_runtime_at_or_before(", "nearest_surface_runtime_at_or_before(")
  |> String.replace("Live.latest_debugger_seq(", "latest_debugger_seq(")
  |> String.replace("Live.debugger_cursor_at_latest?(", "debugger_cursor_at_latest?(")
  |> String.replace("defp nearest_surface_runtime_at_or_before(", "def nearest_surface_runtime_at_or_before(")

timeline_body =
  timeline_body
  |> String.replace("defp select_debugger_row(", "def select_debugger_row(")
  |> String.replace("defp debug_mode_enabled?(", "def debug_mode_enabled?(")
  |> String.replace("nearest_surface_runtime_at_or_before(", "Live.nearest_surface_runtime_at_or_before(")
  |> String.replace("timeline_upper_seq(", "Util.timeline_upper_seq(")
  |> String.replace("protocol_payload_field(", "Util.protocol_payload_field(")
  |> String.replace("elm_value(", "Util.elm_value(")
  |> String.replace("elm_field_name(", "Util.elm_field_name(")
  |> String.replace("normalize_debugger_timeline_mode(", "Util.normalize_debugger_timeline_mode(")
  |> String.replace("companion_or_phone_runtime(", "Util.companion_or_phone_runtime(")
  |> String.replace("debugger_target(", "Util.debugger_target(")
  |> String.replace("debugger_target_runtime(", "Util.debugger_target_runtime(")
  |> String.replace("debugger_other_runtime(", "Util.debugger_other_runtime(")
  |> String.replace("app_runtime?(", "Util.app_runtime?(")
  |> String.replace("payload_message(", "Util.payload_message(")
  |> String.replace("payload_target(", "Util.payload_target(")
  |> String.replace("timeline_kind_for_type(", "Util.timeline_kind_for_type(")
  |> String.replace("map_string(", "Util.map_string(")
  |> String.replace("map_scalar_string(", "Util.map_scalar_string(")
  |> String.replace("map_integer(", "Util.map_integer(")
  |> String.replace("map_lookup(", "Util.map_lookup(")
  |> String.replace("map_map(", "Util.map_map(")
  |> String.replace("map_list(", "Util.map_list(")
  |> String.replace("Util.Util.", "Util.")
  |> String.replace("Live.Live.", "Live.")

diagnostics_body =
  diagnostics_body
  |> String.replace("normalize_cursor_seq(", "Timeline.normalize_cursor_seq(")
  |> String.replace("map_string(", "Util.map_string(")
  |> String.replace("map_scalar_string(", "Util.map_scalar_string(")
  |> String.replace("map_integer(", "Util.map_integer(")
  |> String.replace("format_view_tree_node(", "Diagnostics.format_view_tree_node(")

diagnostics_body =
  String.replace(diagnostics_body, "Diagnostics.format_view_tree_node(", "format_view_tree_node(")

rendered_util_fns = ~w(
  map_integer map_string map_scalar_string map_map map_list map_lookup join_preview_sections
)

rendered_body =
  rendered_body
  |> String.replace("parser_expression_view_tree?", "ElmIntrospect.ViewTree.parser_expression_view_tree?")
  |> String.replace(
    "ElmIntrospect.ViewTree.parser_expression_view_tree?(",
    "parser_expression_view_tree?("
  )
  |> then(fn body ->
    Enum.reduce(rendered_util_fns, body, fn fun, acc ->
      acc
      |> String.replace("defp #{fun}(", "@@defp_#{fun}@@(")
      |> String.replace("def #{fun}(", "@@def_#{fun}@@(")
      |> String.replace(~r/(?<!\.)#{fun}\(/, "Util.#{fun}(")
      |> String.replace("@@defp_#{fun}@@(", "defp #{fun}(")
      |> String.replace("@@def_#{fun}@@(", "def #{fun}(")
    end)
  end)
  |> String.replace("Util.Util.", "Util.")

replay_body =
  replay_body
  |> String.replace("timeline_upper_seq(", "Util.timeline_upper_seq(")
  |> String.replace("map_string(", "Util.map_string(")
  |> String.replace("map_map(", "Util.map_map(")
  |> String.replace("map_list(", "Util.map_list(")
  |> String.replace("map_integer(", "Util.map_integer(")
  |> String.replace("normalize_preview_target(", "Replay.normalize_preview_target(")

replay_body =
  String.replace(replay_body, "Replay.normalize_preview_target(", "normalize_preview_target(")

mod_for = fn name ->
  cond do
    name in ["assign_defaults", "refresh", "refresh_following_debugger_latest",
             "set_debugger_cursor_seq", "set_debugger_timeline_mode", "jump_latest",
             "step_back", "step_forward", "maybe_reload", "trigger_buttons",
             "snapshot_runtime_at_cursor", "nearest_surface_runtime_at_or_before"] ->
      :live

    name in ["replay_preview_rows", "replay_metadata_at_cursor", "replay_compare",
             "replay_live_warning?", "replay_live_drift", "replay_live_drift_severity"] ->
      :replay

    name in ["copy_json", "debugger_agent_state_markdown", "format_debugger_contract_brief"] ->
      :export

    name in ["view_tree_outline", "model_diagnostic_preview", "event_diagnostic_preview",
             "diagnostics_preview_at_cursor", "diagnostics_preview_source_label",
             "debugger_contract_at_cursor", "runtime_fingerprints_at_cursor",
             "runtime_fingerprint_compare_at_cursor", "backend_drift_detail",
             "key_target_drift_detail", "merge_drift_detail"] ->
      :diagnostics

    name in ["event_json", "payload_diff_json", "event_type_counts", "event_summaries",
             "protocol_exchange_at_cursor", "update_messages_at_cursor", "debugger_rows",
             "debugger_rows_for_target", "debugger_rows_for_mode",
             "filter_debugger_rows_for_display", "debugger_runtime_status_row?",
             "debugger_timeline_text", "debugger_message_label", "selected_debugger_row",
             "render_events_at_cursor", "lifecycle_events_at_cursor",
             "filtered_event_summaries", "highlight_fragments", "seq_bounds", "min_seq",
             "max_seq", "normalize_cursor_seq", "select_debugger_row", "debug_mode_enabled?"] ->
      :timeline

    name in ["runtime_json", "rendered_tree", "rendered_node_bounds", "rendered_view_preview",
             "rendered_node_summary"] ->
      :rendered

    true ->
      :live
  end
end

mod_name = fn
  :types -> "IdeWeb.WorkspaceLive.DebuggerSupport.Types"
  :replay -> "IdeWeb.WorkspaceLive.DebuggerSupport.Replay"
  :export -> "IdeWeb.WorkspaceLive.DebuggerSupport.Export"
  :diagnostics -> "IdeWeb.WorkspaceLive.DebuggerSupport.Diagnostics"
  :util -> "IdeWeb.WorkspaceLive.DebuggerSupport.Util"
  :timeline -> "IdeWeb.WorkspaceLive.DebuggerSupport.Timeline"
  :rendered -> "IdeWeb.WorkspaceLive.DebuggerSupport.Rendered"
  :live -> "IdeWeb.WorkspaceLive.DebuggerSupport.Live"
end

fix_util_defs = fn body ->
  body
  |> String.replace("defp Util.", "def ")
  |> String.replace("def Util.", "def ")
  |> String.replace("@spec Util.", "@spec ")
end

fix_timeline_defs = fn body ->
  body
  |> String.replace("defp Util.", "def ")
  |> String.replace("def Util.", "def ")
  |> String.replace("@spec Util.", "@spec ")
  |> String.replace("defp Live.", "def ")
  |> String.replace("def Live.", "def ")
  |> String.replace("@spec Live.", "@spec ")
end

fix_rendered_defs = fn body ->
  body
  |> String.replace("defp Util.", "defp ")
  |> String.replace("def Util.", "def ")
  |> String.replace("@spec Util.", "@spec ")
end

fix_live_defs = fn body ->
  body
  |> String.replace("defp Timeline.", "defp ")
  |> String.replace("defp Util.", "defp ")
  |> String.replace("def Timeline.", "def ")
  |> String.replace("def Util.", "def ")
  |> String.replace("defp Live.", "defp ")
  |> String.replace("def Live.", "def ")
  |> String.replace("@spec Timeline.", "@spec ")
  |> String.replace("@spec Live.", "@spec ")
end

type_names = ~w(
  socket maybe_non_neg_integer timeline_kind event_type_counts event_summary
  highlight_fragment protocol_row update_message_row debugger_row render_event_row
  lifecycle_row replay_preview_row replay_compare wire_input rendered_node view_tree
  events runtime_value debugger_state_map
)

qualify_line = fn line ->
  Enum.reduce(type_names, line, fn name, acc ->
    pattern = ~r/(?<!\.)#{Regex.escape(name)}\(\)/

    acc
    |> then(&Regex.replace(pattern, &1, "Types.#{name}()"))
  end)
end

qualify_types = fn body ->
  body
  |> String.split("\n", trim: false)
  |> Enum.map_reduce(false, fn line, in_spec? ->
    in_spec? =
      String.contains?(line, "@spec") or
        (in_spec? and not Regex.match?(~r/^\s*(def|defp|@doc|@moduledoc)/, line))

    qualified =
      if in_spec? or String.starts_with?(String.trim(line), "@type"),
        do: qualify_line.(line),
        else: line

    {qualified, in_spec?}
  end)
  |> elem(0)
  |> Enum.join("\n")
  |> String.replace("Types.Types.", "Types.")
end

prepare_body = fn short, raw ->
  case short do
    "Util" ->
      raw |> fix_util_defs.() |> String.replace("  defp ", "  def ") |> qualify_types.()

    "Timeline" ->
      raw |> fix_timeline_defs.() |> qualify_types.()

    "Live" ->
      raw
      |> fix_live_defs.()
      |> String.replace("normalize_debugger_timeline_mode(", "Util.normalize_debugger_timeline_mode(")
      |> String.replace("companion_or_phone_runtime(", "Util.companion_or_phone_runtime(")
      |> qualify_types.()

    "Types" ->
      raw

    "Rendered" ->
      raw |> fix_rendered_defs.() |> qualify_types.()

    _other ->
      raw |> qualify_types.()
  end
end

write_mod = fn short, raw ->
  mod = "IdeWeb.WorkspaceLive.DebuggerSupport.#{short}"
  body = prepare_body.(short, raw)
  prefix = if short == "Types", do: "", else: aliases_for.(body)

  content = """
  defmodule #{mod} do
    @moduledoc false
    @dialyzer :no_match

  #{prefix}#{body}end
  """

  path = Path.join(out_dir, String.downcase(short) <> ".ex")
  File.write!(path, content)
end

File.mkdir_p!(out_dir)

write_mod.("Types", types_body)
write_mod.("Replay", replay_body)
write_mod.("Export", export_body)
write_mod.("Util", util_body)
write_mod.("Diagnostics", diagnostics_body)
write_mod.("Timeline", timeline_body)
write_mod.("Rendered", rendered_body)
write_mod.("Live", live_header <> live_body)

defdelegateable_args? = fn args ->
  Regex.match?(
    ~r/^\([a-z][a-z0-9_?!]*(?:,\s*[a-z][a-z0-9_?!]*(?:\s*\\[^,)]+)?)*\)$/,
    args
  ) and
    not Regex.match?(~r/(?:^|[,(]\s*)nil(?:\s*[,)]|\s*\\)|, true\)|, false\)|"[^"]*"/, args)
end

synthetic_args = fn args ->
  inner =
    args
    |> String.trim_leading("(")
    |> String.trim_trailing(")")
    |> String.split(",")
    |> length()

  names =
    1..inner
    |> Enum.map(fn i -> "arg#{i}" end)
    |> Enum.join(", ")

  "(#{names})"
end

delegate_arity = fn args ->
  args
  |> String.trim_leading("(")
  |> String.trim_trailing(")")
  |> String.split(",")
  |> length()
end

delegates =
  lines
  |> Enum.flat_map(fn line ->
    case Regex.run(~r/^  def ([a-z][a-z0-9_!?]*)(\([^)]*\))(?:\s+do)?/, line) do
      [_, name, args] ->
        target = name |> mod_for.() |> mod_name.()
        [{name, args, target}]

      _ ->
        []
    end
  end)
  |> Enum.group_by(fn {name, args, _} -> {name, delegate_arity.(args)} end)
  |> Enum.map(fn {_key, entries} ->
    with_default =
      Enum.find(entries, fn {_, args, _} ->
        defdelegateable_args?.(args) and String.contains?(args, "\\")
      end)

    plain =
      Enum.find(entries, fn {_, args, _} -> defdelegateable_args?.(args) end)

    case with_default || plain do
      {name, args, target} -> {name, args, target}
      nil -> hd(entries)
    end
  end)
  |> Enum.map(fn {name, args, target} ->
    args =
      if defdelegateable_args?.(args),
        do: args,
        else: synthetic_args.(args)

    {name, args, target}
  end)
  |> Enum.sort_by(fn {name, args, _} -> {name, delegate_arity.(args)} end)
  |> Enum.map(fn {name, args, target} -> "  defdelegate #{name}#{args}, to: #{target}" end)

facade = """
defmodule IdeWeb.WorkspaceLive.DebuggerSupport do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type socket :: Types.socket()
  @type maybe_non_neg_integer :: Types.maybe_non_neg_integer()
  @type timeline_kind :: Types.timeline_kind()
  @type event_type_counts :: Types.event_type_counts()
  @type event_summary :: Types.event_summary()
  @type highlight_fragment :: Types.highlight_fragment()
  @type protocol_row :: Types.protocol_row()
  @type update_message_row :: Types.update_message_row()
  @type debugger_row :: Types.debugger_row()
  @type render_event_row :: Types.render_event_row()
  @type lifecycle_row :: Types.lifecycle_row()
  @type replay_preview_row :: Types.replay_preview_row()
  @type replay_compare :: Types.replay_compare()
  @type wire_input :: Types.wire_input()
  @type rendered_node :: Types.rendered_node()
  @type view_tree :: Types.view_tree()
  @type events :: Types.events()
  @type runtime_value :: Types.runtime_value()
  @type debugger_state_map :: Types.debugger_state_map()

#{Enum.join(delegates, "\n")}
end
"""

File.write!(facade_path, facade)
IO.puts("Split from #{src_path}")
IO.puts("Wrote #{length(delegates)} defdelegates and 8 submodules under #{out_dir}")
