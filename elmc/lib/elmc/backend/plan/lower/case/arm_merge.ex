defmodule Elmc.Backend.Plan.Lower.Case.ArmMerge do
  @moduledoc false

  alias Elmc.Backend.Plan.Builder

  @spec publish_arm_to_merge(Builder.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Builder.t()}
  def publish_arm_to_merge(b, arm_reg, merge_reg) when arm_reg == merge_reg, do: {:ok, b}

  def publish_arm_to_merge(b, arm_reg, merge_reg) do
    consume? = not Builder.borrow_arg?(b, arm_reg)

    {_, b1} =
      Builder.emit(b, :call_runtime, %{
        dest: merge_reg,
        args: %{builtin: :retain, args: [arm_reg]},
        effects: %{
          produces: {:owned, merge_reg},
          consumes: if(consume?, do: [arm_reg], else: []),
          borrows: if(consume?, do: [], else: [arm_reg]),
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

  # Exhaustive switches have no wildcard. Routing `default` at the merge makes
  # the case dest maybe-owned (asymmetric borrow on the continuation). Land
  # unmatched tags in a sink that does not join the merge.
  @spec emit_unmatched_case_sink(Builder.t()) :: {non_neg_integer(), Builder.t()}
  def emit_unmatched_case_sink(b) do
    arm_id = b.next_block
    b_arm = Builder.begin_cfg_arm_block(b, arm_id)

    {_, b1} =
      Builder.emit(b_arm, :call_runtime, %{
        dest: nil,
        args: %{builtin: :unreachable, args: []},
        effects: %{
          fallible: false,
          produces: nil,
          consumes: [],
          borrows: []
        }
      })

    {arm_id, Builder.finish_block(b1, {:ret, :fn_out})}
  end
end
