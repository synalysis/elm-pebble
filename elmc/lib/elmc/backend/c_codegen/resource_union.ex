defmodule Elmc.Backend.CCodegen.ResourceUnion do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.CCodegen.Types

  @spec constructor?(String.t(), [Types.ir_expr()]) :: boolean()
  def constructor?(target, args) when is_binary(target) and is_list(args) do
    args == [] and Map.has_key?(slot_map(), ctor_name(target))
  end

  def constructor?(_target, _args), do: false

  @spec int_literal_value(Types.ir_expr()) :: integer()
  def int_literal_value(%{op: :int_literal, value: value, union_ctor: ctor}) when is_binary(ctor) do
    case Map.get(slot_map(), ctor_name(ctor)) do
      slot when is_integer(slot) and slot > 0 -> slot
      _ -> value
    end
  end

  def int_literal_value(%{op: :int_literal, value: value}), do: value

  @spec index_expr(String.t()) :: Types.ir_expr()
  def index_expr(target) when is_binary(target) do
    %{op: :int_literal, value: slot_index(target)}
  end

  @spec slot_index(String.t()) :: pos_integer()
  def slot_index(target) when is_binary(target) do
    ctor = ctor_name(target)

    case slot_map() do
      %{^ctor => index} when is_integer(index) and index > 0 ->
        index

      _ ->
        SpecialValues.constructor_tag(target) + 1
    end
  end

  @spec slot_map() :: %{String.t() => pos_integer()}
  defp slot_map do
    Enum.reduce(
      [
        :elmc_vector_resource_slots,
        :elmc_bitmap_resource_slots,
        :elmc_animation_resource_slots
      ],
      %{},
      fn key, acc ->
        case Process.get(key, %{}) do
          %{} = slots -> Map.merge(acc, slots)
          _ -> acc
        end
      end
    )
  end

  @spec ctor_name(String.t()) :: String.t()
  defp ctor_name(target) when is_binary(target) do
    target |> String.split(".") |> List.last()
  end
end
