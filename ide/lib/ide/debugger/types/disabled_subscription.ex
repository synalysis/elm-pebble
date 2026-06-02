defmodule Ide.Debugger.Types.DisabledSubscription do
  @moduledoc """
  Subscription row disabled in the debugger session (`disabled_subscriptions` list).

  Runtime rows use string keys (`"target"`, `"trigger"`).
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:target) => String.t(),
          optional(:trigger) => String.t(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type wire_map :: t() | map()
end
