defmodule Ide.Debugger.Types.SessionAttrs do
  @moduledoc """
  Optional attributes for `Debugger.start_session/2` and `set_watch_profile/2`.
  """

  @type t :: %{
          optional(:watch_profile_id) => String.t(),
          optional(:launch_reason) => String.t(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type wire_map :: t() | map()
end
