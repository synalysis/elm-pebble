defmodule Ide.Debugger.Protocol.Event do
  @moduledoc """
  Runtime protocol event surfaced by the semantic executor / debugger step loop.
  """

  alias Ide.Debugger.Types.ProtocolTxRxPayload

  @type t :: %{
          optional(:type) => String.t(),
          optional(:payload) => ProtocolTxRxPayload.t() | map(),
          optional(:from) => String.t(),
          optional(:to) => String.t(),
          optional(:message) => String.t(),
          optional(:message_value) => term(),
          optional(:trigger) => String.t(),
          optional(:message_source) => String.t(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type wire_event :: t() | map()
end
