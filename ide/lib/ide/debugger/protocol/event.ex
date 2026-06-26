defmodule Ide.Debugger.Protocol.Event do
  @moduledoc """
  Runtime protocol event surfaced by the semantic executor / debugger step loop.
  """

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.ProtocolTxRxPayload

  @type t :: %{
          optional(:type) => String.t(),
          optional(:payload) => ProtocolTxRxPayload.t() | ProtocolTxRxPayload.wire_map(),
          optional(:from) => String.t(),
          optional(:to) => String.t(),
          optional(:message) => String.t(),
          optional(:message_value) => Types.protocol_message_wire_value(),
          optional(:trigger) => String.t(),
          optional(:message_source) => String.t(),
          optional(String.t()) => Types.wire_input()
        }

  @type wire_event :: t() | Types.wire_map()
end
