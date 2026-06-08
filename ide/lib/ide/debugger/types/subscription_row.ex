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
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type wire_map :: t() | Types.wire_map()
end
