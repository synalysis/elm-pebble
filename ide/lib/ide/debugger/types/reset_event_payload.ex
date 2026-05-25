defmodule Ide.Debugger.Types.ResetEventPayload do
  @moduledoc "Payload for `debugger.reset` events (empty contract map)."
  alias Ide.Debugger.Types

  @type t :: %{optional(atom()) => Types.wire_input(), optional(String.t()) => Types.wire_input()}

  @spec empty() :: t()
  def empty, do: %{}
end
