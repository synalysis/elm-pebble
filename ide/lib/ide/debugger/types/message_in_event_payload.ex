defmodule Ide.Debugger.Types.MessageInEventPayload do
  @moduledoc """
  Shared payload for `debugger.init_in` and `debugger.update_in` events.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:target) => String.t(),
          optional(:message) => String.t(),
          optional(:message_source) => String.t() | nil,
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()

  @spec from_message(String.t(), String.t(), String.t() | nil) :: t()
  def from_message(target, message, message_source)
      when is_binary(target) and is_binary(message) do
    %{
      target: target,
      message: message,
      message_source: message_source
    }
  end
end
