defmodule Ide.Debugger.Types.DeviceRequest do
  @moduledoc """
  Simulated Pebble device API request derived from init `Cmd` calls in introspect.
  """

  @type kind :: String.t()

  @type preview :: term()

  @type t :: %{
          required(:kind) => kind(),
          required(:response_message) => String.t(),
          optional(:preview) => preview(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type wire_map :: t() | map()
end
