defmodule Ide.Debugger.Types.TrackedHttpCommand do
  @moduledoc """
  HTTP command tracked on companion surface during debugger init/update (`tracked_http_commands`).
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:kind) => String.t(),
          optional(:method) => String.t(),
          optional(:url) => String.t(),
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
