defmodule Ide.Debugger.Types.ActiveSubscription do
  @moduledoc """
  Runtime `active_subscriptions` row from elmx `Subscriptions.evaluate/2`.

  Produced by `cmd.subscription.register` flattening; runtime maps use **string keys**
  at the wire boundary (see `wire_map/0`).
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:kind) => String.t(),
          optional(:package) => String.t(),
          optional(:target) => String.t(),
          optional(:message) => String.t(),
          optional(:message_value) => Types.subscription_payload() | nil,
          optional(:interval_ms) => non_neg_integer(),
          optional(:event_kind) => String.t(),
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
