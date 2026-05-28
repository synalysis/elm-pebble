defmodule Ide.Debugger.Types.RuntimeFollowupRow do
  @moduledoc """
  Runtime step follow-up row (`followup_messages` / init cmd followups).
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:message) => String.t(),
          optional(:package) => String.t(),
          optional(:command) => Types.TrackedHttpCommand.wire_map(),
          optional(String.t()) => Types.wire_input(),
          optional(atom()) => Types.wire_input()
        }

  @type wire_row :: t() | map()
end
