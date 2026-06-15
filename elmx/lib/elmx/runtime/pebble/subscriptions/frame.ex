defmodule Elmx.Runtime.Pebble.Subscriptions.Frame do
  @moduledoc false

  alias Elmx.Types

  @frame_base 8192

  @spec mask(Types.ir_arg_list()) :: non_neg_integer()
  def mask(args) when is_list(args) do
    ms = int_literal_at(args, 0) || 33
    @frame_base + Bitwise.bsl(clamp_ms(ms), 16)
  end

  @spec fps_mask(Types.ir_arg_list()) :: non_neg_integer()
  def fps_mask(args) when is_list(args) do
    fps = int_literal_at(args, 0) || 30
    interval = div(1000, max(fps, 1))
    @frame_base + Bitwise.bsl(clamp_ms(interval), 16)
  end

  defp int_literal_at([%{op: :int_literal, value: value} | _], 0) when is_integer(value), do: value
  defp int_literal_at(_, _), do: nil

  defp clamp_ms(ms) when is_integer(ms) do
    ms |> max(1) |> min(32_767)
  end
end
