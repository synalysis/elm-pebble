defmodule Ide.Debugger.Types.PendingHttpFollowupItem do
  @moduledoc """
  Queued `elm/http` follow-up for async `PendingHttpFollowups` drain.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          required(:target) => String.t(),
          required(:target_name) => String.t(),
          required(:package) => String.t(),
          required(:command) => Types.cmd_call(),
          optional(:followup_message) => String.t() | nil,
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_item :: t() | Types.wire_map()
end
