defmodule Elmc.Backend.Pebble.FeatureFlags.DrawFlags.Compact do
  @moduledoc false
  alias Elmc.Types, as: ElmcTypes
  alias Elmc.Backend.SizeProfile
  alias Elmc.Backend.Pebble.Types.FeatureFlags.Keys.Draw, as: DrawKeys

  @legacy_required_keys ~w(
    draw_context
    draw_clear
    draw_rect
    draw_text
    draw_stroke_color
    draw_text_color
  )a

  @legacy_forbidden_keys ~w(
    draw_text_int
    draw_text_label
    draw_pixel
    draw_line
    draw_fill_rect
    draw_circle
    draw_fill_circle
    draw_round_rect
    draw_arc
    draw_path
    draw_fill_radial
    draw_bitmap_in_rect
    draw_vector_at
    draw_vector_sequence_at
    draw_bitmap_sequence_at
    draw_rotated_bitmap
    draw_stroke_width
    draw_antialiased
    draw_fill_color
    draw_compositing_mode
  )a

  @minimal_required_keys ~w(
    draw_clear
    draw_fill_rect
  )a

  @minimal_forbidden_keys ~w(
    draw_text_int
    draw_text_label
    draw_pixel
    draw_line
    draw_rect
    draw_circle
    draw_fill_circle
    draw_text
    draw_context
    draw_stroke_width
    draw_antialiased
    draw_stroke_color
    draw_fill_color
    draw_text_color
    draw_round_rect
    draw_arc
    draw_path
    draw_fill_radial
    draw_compositing_mode
    draw_bitmap_in_rect
    draw_vector_at
    draw_vector_sequence_at
    draw_bitmap_sequence_at
    draw_rotated_bitmap
  )a

  # Features implemented by the compact `draw_update_proc` path in pebble_app_template.c
  # (medium switch: context/colors/clear/rect/text/fill_rect).
  @subset_capable_keys MapSet.new(~w(
    draw_clear
    draw_fill_rect
    draw_rect
    draw_text
    draw_context
    draw_stroke_color
    draw_text_color
    draw_fill_color
    draw_stroke_width
    draw_antialiased
  )a)

  # Input may be draw-only (no :compact_draw yet) or full feature_flags.
  @spec compute(map()) :: %{compact_draw: boolean()}
  def compute(%{} = flags), do: compute(flags, %{})

  @spec compute(map(), ElmcTypes.compile_options() | map()) :: %{compact_draw: boolean()}
  def compute(%{} = flags, opts) when is_map(opts) do
    legacy_compact? =
      Enum.all?(@legacy_required_keys, &Map.fetch!(flags, &1)) and
        Enum.all?(@legacy_forbidden_keys, &(not Map.fetch!(flags, &1)))

    minimal_compact? =
      Enum.all?(@minimal_required_keys, &Map.fetch!(flags, &1)) and
        Enum.all?(@minimal_forbidden_keys, &(not Map.fetch!(flags, &1)))

    subset_compact? =
      SizeProfile.prune_capabilities?(opts) and compact_subset?(flags)

    %{compact_draw: legacy_compact? or minimal_compact? or subset_compact?}
  end

  defp compact_subset?(%{} = flags) do
    enabled =
      DrawKeys.keys()
      |> Enum.reject(&(&1 in [:compact_draw, :draw_text_any]))
      |> Enum.filter(&(Map.get(flags, &1) == true))

    enabled != [] and Enum.all?(enabled, &MapSet.member?(@subset_capable_keys, &1))
  end
end
