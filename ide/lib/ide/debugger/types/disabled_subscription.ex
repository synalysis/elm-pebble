defmodule Ide.Debugger.Types.DisabledSubscription do
  @moduledoc """
  Subscription row disabled in the debugger session (`disabled_subscriptions` list).

  Runtime rows use string keys (`"target"`, `"trigger"`).
  """

  @type t :: %{
          optional(:target) => String.t(),
          optional(:trigger) => String.t(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type wire_map :: t() | map()
end
