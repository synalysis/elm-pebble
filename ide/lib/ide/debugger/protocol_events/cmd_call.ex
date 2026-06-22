defmodule Ide.Debugger.ProtocolEvents.CmdCall do
  @moduledoc false

  alias Ide.Debugger.ProtocolEvents.CmdCall.Core
  alias Ide.Debugger.ProtocolEvents.CmdCall.Expand
  alias Ide.Debugger.ProtocolEvents.CmdCall.Schema

  defdelegate events_from_cmd_call(state, target_surface, cmd_call, model, message_value, ctx), to: Expand
  defdelegate normalize_elmc_wire_ctor(value), to: Core
  defdelegate events_for_model_commands(state, model, target, message, message_value, ctx), to: Expand
  defdelegate weather_condition_from_settings(settings), to: Expand
  defdelegate protocol_schema_from_state_or_model(state, model, events_ctx), to: Schema
  defdelegate project_schema(state, events_ctx), to: Schema
  defdelegate normalize_from_schema(protocol_events, state, events_ctx), to: Schema
  defdelegate normalize_protocol_message_value_from_schema(schema, direction, message_value, message), to: Schema
  defdelegate protocol_message_ctor(value), to: Schema
end
