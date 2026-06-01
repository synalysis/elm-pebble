defmodule Elmx.Runtime.Pebble.Subscriptions do
  @moduledoc false

  alias Elmx.Runtime.Pebble.SubscriptionMasks
  alias Elmx.Runtime.Pebble.Subscriptions.Frame, as: FrameMask

  @frame_targets %{
    "Pebble.Frame.every" => :every,
    "Elm.Kernel.PebbleWatch.onFrame" => :every,
    "Pebble.Frame.atFps" => :fps
  }

  @spec mask(String.t()) :: non_neg_integer() | nil
  def mask(target) when is_binary(target), do: SubscriptionMasks.mask(target)

  @spec batch_mask(list()) :: non_neg_integer()
  def batch_mask(items) when is_list(items) do
    Enum.reduce(items, 0, fn item, acc -> Bitwise.bor(acc, item_mask(item)) end)
  end

  @spec item_mask(term()) :: non_neg_integer()
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
end
