defmodule Ide.Debugger.Types.AvailableTriggersAttrs do
  @moduledoc """
  Optional target filter for `Debugger.available_triggers/2`.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:target) => Types.surface_target() | String.t() | atom() | nil,
          optional(String.t()) => Types.wire_input(),
          optional(atom()) => Types.wire_input()
        }

  @type wire_map :: t() | Types.wire_map()
end
