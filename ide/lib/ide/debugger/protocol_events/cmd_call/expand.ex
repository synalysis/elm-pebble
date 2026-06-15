defmodule Ide.Debugger.ProtocolEvents.CmdCall.Expand do
  @moduledoc false

  alias Ide.Debugger.ProtocolEvents.CmdCall.Core

  defdelegate events_from_cmd_call(state, target_surface, cmd_call, model, message_value, ctx), to: Core
  defdelegate events_for_model_commands(state, model, target, message, message_value, ctx), to: Core
  defdelegate weather_condition_from_settings(settings), to: Core
end
