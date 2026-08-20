defmodule Ide.Pebble.TextLayout do
  @moduledoc false

  @doc """
  Pixels to lift a center-aligned text `GRect` so the ink sits in the box.

  Pebble `GTextAlignmentCenter` is horizontal only; Gothic/TTF glyphs rest on
  the baseline. When the project declared a font height and the destination is
  only a few pixels taller (date windows), lift the layout. Tall time bands
  (`declared + 6 < box_h`) stay top-aligned.
  """
  @spec center_aligned_lift(integer(), integer()) :: non_neg_integer()
  def center_aligned_lift(box_h, declared_h)
      when is_integer(box_h) and box_h > 0 and is_integer(declared_h) and declared_h > 0 and
             declared_h + 6 >= box_h do
    up = div(declared_h, 6)

    up =
      if box_h > declared_h do
        up + div(box_h - declared_h, 2)
      else
        up
      end

    max(up, 1)
  end

  def center_aligned_lift(_box_h, _declared_h), do: 0

  @doc """
  Top of the text layout box after the same lift the emulator applies.
  """
  @spec center_aligned_origin_y(integer(), integer(), integer()) :: integer()
  def center_aligned_origin_y(box_y, box_h, declared_h)
      when is_integer(box_y) and is_integer(box_h) and is_integer(declared_h) do
    box_y - center_aligned_lift(box_h, declared_h)
  end
end
