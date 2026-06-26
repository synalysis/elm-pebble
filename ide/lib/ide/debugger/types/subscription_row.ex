defmodule Ide.Debugger.Types.SubscriptionRow do
  @moduledoc """
  Subscription filter row for auto-fire and disabled-subscription lists.

  Uses string keys `target` (`watch` | `protocol`) and `trigger` at runtime.
  """

  alias Ide.Debugger.Types
  @type target_filter :: String.t()

  @type t :: %{
          optional(:target) => target_filter(),
          optional(:trigger) => String.t(),
          optional(:enabled) => boolean(),
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
