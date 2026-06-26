defmodule Ide.Debugger.Types.DisabledSubscription do
  @moduledoc """
  Subscription row disabled in the debugger session (`disabled_subscriptions` list).

  Runtime rows use string keys (`"target"`, `"trigger"`).
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:target) => String.t(),
          optional(:trigger) => String.t(),
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
