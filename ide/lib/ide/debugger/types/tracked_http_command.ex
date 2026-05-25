defmodule Ide.Debugger.Types.TrackedHttpCommand do
  @moduledoc """
  HTTP command tracked on companion surface during debugger init/update (`tracked_http_commands`).
  """

  @type t :: %{
          optional(:kind) => String.t(),
          optional(:method) => String.t(),
          optional(:url) => String.t(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type wire_map :: t() | map()
end
