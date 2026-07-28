defmodule Elmc.Backend.Plan.Lower.SpecialValues.RandomGenerateFold do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ConstantInt
  alias Elmc.Backend.Plan.Lower.SpecialValues

  @int_targets ~w(
    Random.int
    Elm.Kernel.Random.int
  )

  @spec fold_int_bounds(map(), map()) :: {:ok, integer(), integer()} | :error
  def fold_int_bounds(generator, env \\ %{}) when is_map(generator) and is_map(env) do
    with %{op: :qualified_call, target: target, args: [lo, hi]} <- generator,
         true <- int_target?(target),
         {:ok, lo_v} <- ConstantInt.literal_value(lo, env),
         {:ok, hi_v} <- ConstantInt.literal_value(hi, env),
         true <- hi_v >= lo_v do
      {:ok, lo_v, hi_v}
    else
      _ -> :error
    end
  end

  @spec int_target?(String.t()) :: boolean()
  defp int_target?(target) when is_binary(target) do
    normalized = SpecialValues.normalize_special_target(target)

    normalized in @int_targets or
      (String.ends_with?(normalized, ".int") and String.contains?(normalized, "Random"))
  end
end
