defmodule Ide.Debugger.Types.InjectTriggerAttrs do
  @moduledoc """
  Attributes for `Debugger.inject_trigger/2`.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:target) => Types.surface_target() | String.t() | atom(),
          optional(:trigger) => String.t(),
          optional(:message) => String.t() | nil,
          optional(:message_value) => Types.subscription_payload() | nil,
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
