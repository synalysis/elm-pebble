defmodule Ide.Debugger.Types.DeviceRequest do
  @moduledoc """
  Simulated Pebble device API request derived from init `Cmd` calls in introspect.
  """

  alias Ide.Debugger.Types

  @type kind :: String.t()

  @type preview :: Types.device_preview()

  @type t :: %{
          required(:kind) => kind(),
          required(:response_message) => String.t(),
          optional(:preview) => preview(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type wire_map :: t() | Types.wire_map()
end
