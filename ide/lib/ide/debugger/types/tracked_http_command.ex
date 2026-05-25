defmodule Ide.Debugger.Types.TrackedHttpCommand do
  @moduledoc """
  HTTP command tracked on companion surface during debugger init/update (`tracked_http_commands`).
  """

  alias Ide.Debugger.Types
  @type t :: %{
          optional(:kind) => String.t(),
          optional(:method) => String.t(),
          optional(:url) => String.t(),
          optional(String.t()) => Types.wire_input(),
          optional(atom()) => Types.wire_input()
        }

  @type wire_map :: t() | map()
end
