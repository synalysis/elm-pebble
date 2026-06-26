defmodule Ide.Debugger.Types.ResetEventPayload do
  @moduledoc "Payload for `debugger.reset` events (empty contract map)."
  alias Ide.Debugger.Types

  @typedoc "Empty or extension payload for `debugger.reset` events."
  @type t :: %{optional(String.t()) => Types.wire_input()}

  @spec empty() :: t()
  def empty, do: %{}
end
