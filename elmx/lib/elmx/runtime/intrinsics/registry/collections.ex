defmodule Elmx.Runtime.Intrinsics.Registry.Collections do
  @moduledoc false

  alias Elmx.Runtime.Core.Collections
  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Intrinsics.Registry.Prefix

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{}
    |> Map.merge(Prefix.handlers("elmc_dict_", "dict_", Collections))
    |> Map.merge(Prefix.handlers("elmc_set_", "set_", Collections))
    |> Map.merge(Prefix.handlers("elmc_array_", "array_", Collections))
  end
end
