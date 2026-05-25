defmodule Ide.Debugger.Types.SubscriptionRow do
  @moduledoc """
  Subscription filter row for auto-fire and disabled-subscription lists.

  Uses string keys `target` (`watch` | `protocol`) and `trigger` at runtime.
  """

  @type target_filter :: String.t()

  @type t :: %{
          optional(:target) => target_filter(),
          optional(:trigger) => String.t(),
          optional(:enabled) => boolean(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type wire_map :: t() | map()
end
