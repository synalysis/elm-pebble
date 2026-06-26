defmodule Ide.Debugger.Types.PendingProtocolDeliveryItem do
  @moduledoc """
  Queued AppMessage delivery for async `PendingProtocolDelivery` drain.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          required(:recipient) => String.t(),
          required(:payload) => Types.protocol_tx_rx_payload()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_item :: t() | Types.wire_map()
end
