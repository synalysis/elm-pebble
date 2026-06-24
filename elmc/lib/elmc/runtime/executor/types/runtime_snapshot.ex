defmodule Elmc.Runtime.Executor.Types.RuntimeSnapshot do
  @moduledoc """
  Runtime metadata map attached to successful `Elmc.Runtime.Executor.execute/1` results.

  Runtime maps use string keys (`"engine"`, `"view_tree_source"`, …).
  """

  @type t :: %{
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type wire_map :: t()
end
