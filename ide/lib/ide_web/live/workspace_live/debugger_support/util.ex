defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Util do
  @moduledoc false
  @dialyzer :no_match

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util.{Debugger, Elm, Payload, Timeline, WireMap}

  defdelegate map_lookup(map, key), to: WireMap
  defdelegate map_string(map, key), to: WireMap
  defdelegate map_scalar_string(map, key), to: WireMap
  defdelegate map_integer(map, key), to: WireMap
  defdelegate map_map(map, key), to: WireMap
  defdelegate map_list(map, key), to: WireMap

  defdelegate timeline_upper_seq(events, cursor_seq), to: Timeline, as: :upper_seq
  defdelegate timeline_kind_for_type(type), to: Timeline, as: :kind_for_type

  defdelegate protocol_payload_field(payload, key), to: Payload, as: :field
  defdelegate payload_target(payload), to: Payload, as: :target
  defdelegate payload_message(payload), to: Payload, as: :message

  defdelegate elm_value(value), to: Elm, as: :value
  defdelegate elm_field_name(key), to: Elm, as: :field_name

  defdelegate normalize_debugger_timeline_mode(value), to: Debugger, as: :normalize_timeline_mode
  defdelegate debugger_target(target), to: Debugger, as: :target
  defdelegate debugger_target_runtime(target, watch_runtime, companion_runtime), to: Debugger, as: :target_runtime
  defdelegate debugger_other_runtime(target, watch_runtime, companion_runtime), to: Debugger, as: :other_runtime
  defdelegate companion_or_phone_runtime(companion_runtime, phone_runtime), to: Debugger
  defdelegate app_runtime?(runtime), to: Debugger

  @spec join_preview_sections(String.t(), String.t()) :: String.t()
  def join_preview_sections("", tree_text), do: tree_text
  def join_preview_sections(runtime_text, ""), do: runtime_text

  def join_preview_sections(runtime_text, tree_text) do
    "#{runtime_text}\n#{tree_text}"
  end
end
