defmodule Ide.Debugger.Types.ResetEventPayload do
  @moduledoc "Payload for `debugger.reset` events (empty contract map)."

  @type t :: %{optional(atom()) => term(), optional(String.t()) => term()}

  @spec empty() :: t()
  def empty, do: %{}
end
