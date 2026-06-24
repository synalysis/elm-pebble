defmodule Elmc.Runtime.Executor.Types.WireJson do
  @moduledoc """
  JSON-like scalar and object values used by the experimental runtime executor.
  """

  @type t ::
          String.t()
          | integer()
          | float()
          | boolean()
          | nil
          | [t()]
          | %{optional(String.t()) => t(), optional(atom()) => t()}
end
