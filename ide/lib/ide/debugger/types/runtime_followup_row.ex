defmodule Ide.Debugger.Types.RuntimeFollowupRow do
  @moduledoc """
  Runtime step follow-up row (`followup_messages` / init cmd followups).
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:message) => String.t(),
          optional(:package) => String.t(),
          optional(:command) => Types.tracked_http_command(),
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_row :: t() | Types.wire_map()
end
