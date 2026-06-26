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
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
