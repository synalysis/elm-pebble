defmodule Ide.Debugger.ProtocolEvents.CmdCall.Schema do
  @moduledoc false

  alias Ide.Debugger.ProtocolEvents.CmdCall.Core

  defdelegate protocol_schema_from_state_or_model(state, model, events_ctx), to: Core
  defdelegate project_schema(state, events_ctx), to: Core
  defdelegate normalize_from_schema(protocol_events, state, events_ctx), to: Core
  defdelegate normalize_protocol_message_value_from_schema(schema, direction, message_value, message), to: Core
  defdelegate protocol_message_ctor(value), to: Core
end
