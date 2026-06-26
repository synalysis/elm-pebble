defmodule Ide.Debugger.Types.SessionAttrs do
  @moduledoc """
  Optional attributes for `Debugger.start_session/2` and `set_watch_profile/2`.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:watch_profile_id) => String.t(),
          optional(:launch_reason) => String.t(),
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
