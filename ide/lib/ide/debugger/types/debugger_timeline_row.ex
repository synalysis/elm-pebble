defmodule Ide.Debugger.Types.DebuggerTimelineRow do
  @moduledoc """
  User-visible debugger timeline row (`RuntimeState.debugger_timeline`).
  """

  alias Ide.Debugger.Surface

  @type t :: %{
          required(:seq) => non_neg_integer(),
          required(:raw_seq) => non_neg_integer(),
          required(:type) => String.t(),
          required(:target) => String.t(),
          required(:message) => String.t(),
          optional(:message_source) => String.t() | nil,
          required(:watch) => Surface.surface_map(),
          required(:companion) => Surface.surface_map(),
          required(:phone) => Surface.surface_map()
        }
end
