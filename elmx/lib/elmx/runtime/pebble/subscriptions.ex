defmodule Elmx.Runtime.Pebble.Subscriptions do
  @moduledoc false

  alias Elmx.Runtime.Pebble.SubscriptionMasks
  alias Elmx.Runtime.Pebble.Subscriptions.Frame, as: FrameMask
  alias Elmx.Types

  @frame_targets %{
    "Pebble.Frame.every" => :every,
    "Elm.Kernel.PebbleWatch.onFrame" => :every,
    "Pebble.Frame.atFps" => :fps
  }

  @spec mask(String.t()) :: non_neg_integer() | nil
  def mask(target) when is_binary(target), do: SubscriptionMasks.mask(target)

  @spec batch_mask(Types.ir_arg_list()) :: non_neg_integer()
  def batch_mask(items) when is_list(items) do
    Enum.reduce(items, 0, fn item, acc -> Bitwise.bor(acc, item_mask(item)) end)
  end

  @spec item_mask(Types.subscription_mask_item()) :: non_neg_integer()
  def item_mask(%{op: :int_literal, value: value}) when is_integer(value), do: value

  def item_mask(%{op: :qualified_call, target: target, args: args}) when is_binary(target) do
    case Map.get(@frame_targets, target) do
      :every -> FrameMask.mask(args)
      :fps -> FrameMask.fps_mask(args)
      _ -> if(value = mask(target), do: value, else: item_mask_from_call(target, args))
    end
  end

  def item_mask(%{op: :qualified_call1, target: target}) when is_binary(target),
    do: mask(target) || 0

  def item_mask(value) when is_integer(value), do: value
  def item_mask(_), do: 0

  defp item_mask_from_call(target, _args), do: mask(target) || 0

  @doc """
  True when every batch entry can be OR'd into a compile-time subscription mask.

  Lists that mention variables, conditionals, or non-mask runtime subs need
  `elmx_sub_batch/1` instead of a folded integer literal.
  """
  @spec static_batch?(Types.ir_arg_list()) :: boolean()
  def static_batch?(items) when is_list(items), do: Enum.all?(items, &static_batch_item?/1)

  @spec static_batch_item?(Types.subscription_mask_item()) :: boolean()
  def static_batch_item?(%{op: :int_literal, value: value}) when is_integer(value), do: true

  def static_batch_item?(%{op: :qualified_call, target: target, args: args})
      when is_binary(target) and is_list(args) do
    cond do
      Map.has_key?(@frame_targets, target) -> static_frame_args?(args)
      mask(target) != nil -> true
      true -> false
    end
  end

  def static_batch_item?(%{op: :qualified_call1, target: target}) when is_binary(target),
    do: mask(target) != nil

  def static_batch_item?(_), do: false

  defp static_frame_args?([%{op: :int_literal, value: interval} | _msg])
       when is_integer(interval),
       do: true

  defp static_frame_args?(_), do: false
end
