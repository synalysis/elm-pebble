defmodule Ide.Debugger.Types.PendingProtocolDeliveryItem do
  @moduledoc """
  Queued AppMessage delivery for async `PendingProtocolDelivery` drain.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          required(:recipient) => String.t(),
          required(:payload) => Types.protocol_tx_rx_payload()
        }

  @type wire_item :: t() | Types.wire_map()
end
