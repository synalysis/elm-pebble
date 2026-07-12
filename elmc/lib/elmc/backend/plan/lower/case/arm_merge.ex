defmodule Elmc.Backend.Plan.Lower.Case.ArmMerge do
  @moduledoc false

  alias Elmc.Backend.Plan.Builder

  @spec publish_arm_to_merge(Builder.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Builder.t()}
  def publish_arm_to_merge(b, arm_reg, merge_reg) when arm_reg == merge_reg, do: {:ok, b}

  def publish_arm_to_merge(b, arm_reg, merge_reg) do
    {_, b1} =
      Builder.emit(b, :call_runtime, %{
        dest: merge_reg,
        args: %{builtin: :retain, args: [arm_reg]},
        effects: %{
          produces: {:owned, merge_reg},
          consumes: [arm_reg],
          borrows: [],
          fallible: false
        }
      })

    {:ok, b1}
  end

  @spec finish_merge(Builder.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer(), Builder.t()}
  def finish_merge(b, merge_reg, merge_id) do
    b_tagged = %{b | tag_switch_merge_block: merge_id}
    return_id = Builder.reserved_next_block_id(b_tagged)
    {:ok, merge_reg, Builder.finish_block(b_tagged, {:br, return_id})}
  end
end
