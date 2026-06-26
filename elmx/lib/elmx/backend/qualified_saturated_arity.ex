defmodule Elmx.Backend.QualifiedSaturatedArity do
  @moduledoc false

  alias Elmx.Runtime.Stdlib

  # Saturated arity for qualified targets not covered by `qualified_full_arity/1`.
  @saturated_arity %{
    "Tuple.first" => 1,
    "Tuple.second" => 1,
    "Basics.toFloat" => 1,
    "Basics.floor" => 1,
    "Basics.ceiling" => 1,
    "Basics.round" => 1,
    "Basics.truncate" => 1,
    "Basics.always" => 2,
    "Result.toMaybe" => 1,
    "Time.posixToMillis" => 1,
    "Time.millisToPosix" => 1
  }

  @spec saturated(String.t()) :: {:ok, pos_integer()} | :error
  def saturated(target) when is_binary(target) do
    case Stdlib.qualified_full_arity(target) do
      {:ok, arity} -> {:ok, arity}
      :error -> Map.fetch(@saturated_arity, target)
    end
  end
end
