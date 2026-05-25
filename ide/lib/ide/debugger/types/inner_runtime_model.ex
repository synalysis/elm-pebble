defmodule Ide.Debugger.Types.InnerRuntimeModel do
  @moduledoc """
  Nested `runtime_model` map inside debugger app/execution models.
  """

  @type t :: %{optional(String.t()) => term(), optional(atom()) => term()}

  @type wire_map :: t() | map()
end
