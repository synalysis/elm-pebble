defmodule Elmc.Runtime.Executor.Types.ViewTree do
  @moduledoc """
  Debugger-style view tree nodes produced or consumed by `Elmc.Runtime.Executor`.

  Runtime maps use string keys (`"type"`, `"children"`, …).
  """

  alias Elmc.Runtime.Executor.Types.WireJson

  @type t :: %{
          optional(atom()) => WireJson.t() | [t()],
          optional(String.t()) => WireJson.t() | [t()]
        }

  @type wire_map :: t()
end
