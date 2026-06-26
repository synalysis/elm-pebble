defmodule Elmc.Backend.Pebble.Kinds.Tables.DrawKindLuts do
  @moduledoc false

  alias Elmc.Backend.Pebble.Kinds.CNames
  alias Elmc.Backend.Pebble.Kinds.Tables.DrawKinds

  @path_feature "ELMC_PEBBLE_FEATURE_DRAW_PATH"

  @path_kinds [:path_filled, :path_outline, :path_outline_open]

  @visual_kinds [
                  :clear,
                  :pixel,
                  :line,
                  :rect,
                  :fill_rect,
                  :round_rect,
                  :arc,
                  :fill_radial,
                  :circle,
                  :fill_circle,
                  :text_int_with_font,
                  :text_label_with_font,
                  :text,
                  :bitmap_in_rect,
                  :rotated_bitmap,
                  :vector_at,
                  :vector_sequence_at
                ] ++ @path_kinds

  @full_dirty_kinds [
                      :clear,
                      :push_context,
                      :pop_context,
                      :stroke_width,
                      :antialiased,
                      :stroke_color,
                      :fill_color,
                      :text_color,
                      :context_group,
                      :compositing_mode,
                      :text_int_with_font,
                      :text_label_with_font,
                      :rotated_bitmap,
                      :vector_at,
                      :vector_sequence_at
                    ] ++ @path_kinds

  @draw_setting_tags [
    {1, :stroke_width, "ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH"},
    {2, :antialiased, "ELMC_PEBBLE_FEATURE_DRAW_ANTIALIASED"},
    {3, :stroke_color, "ELMC_PEBBLE_FEATURE_DRAW_STROKE_COLOR"},
    {4, :fill_color, "ELMC_PEBBLE_FEATURE_DRAW_FILL_COLOR"},
    {5, :text_color, "ELMC_PEBBLE_FEATURE_DRAW_TEXT_COLOR"},
    {6, :compositing_mode, "ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE"}
  ]

  @spec visual_kinds() :: [atom()]
  def visual_kinds, do: @visual_kinds

  @spec full_dirty_kinds() :: [atom()]
  def full_dirty_kinds, do: @full_dirty_kinds

  @spec predicate_lut_c(String.t(), [atom()]) :: String.t()
  def predicate_lut_c(lut_name, kinds) when is_binary(lut_name) and is_list(kinds) do
    max_id = max_kind_id()
    active = MapSet.new(kinds)

    non_path_entries =
      DrawKinds.table()
      |> Enum.flat_map(fn {kind, id} ->
        cond do
          not MapSet.member?(active, kind) -> []
          kind in @path_kinds -> []
          true -> [slot(id, 1)]
        end
      end)

    path_entries =
      if Enum.any?(@path_kinds, &MapSet.member?(active, &1)) do
        path_slots =
          @path_kinds
          |> Enum.filter(&MapSet.member?(active, &1))
          |> Enum.map(fn kind -> slot(DrawKinds.id!(kind), 1) end)
          |> Enum.join("\n")

        """
        #if #{@path_feature}
        #{path_slots}
        #endif
        """
      else
        ""
      end

    entries = non_path_entries ++ [path_entries]

    """
    static const uint8_t #{lut_name}[#{max_id + 1}] = {
    #{Enum.join(entries, "\n")}
    };
    """
    |> String.trim_trailing()
  end

  @spec predicate_lookup_c(String.t(), String.t()) :: String.t()
  def predicate_lookup_c(lut_name, kind_expr) when is_binary(lut_name) and is_binary(kind_expr) do
    max_id = max_kind_id()

    """
    ((#{kind_expr}) >= 0 && (#{kind_expr}) <= #{max_id})
      ? #{lut_name}[(#{kind_expr})]
      : 0
    """
    |> String.trim()
  end

  @spec draw_setting_kind_lut_c() :: String.t()
  def draw_setting_kind_lut_c do
    max_tag =
      @draw_setting_tags
      |> Enum.map(&elem(&1, 0))
      |> Enum.max()

    entries =
      Enum.map(@draw_setting_tags, fn {tag, kind, feature} ->
        kind_macro = CNames.draw_kind_c_name!(kind)
        setting_tag_slot(tag, kind_macro, feature)
      end)

    """
    static const int16_t elmc_pebble_draw_setting_kind_lut[#{max_tag + 1}] = {
    #{Enum.join(entries, "\n")}
    };
    """
    |> String.trim_trailing()
  end

  @spec draw_setting_kind_decode_c() :: String.t()
  def draw_setting_kind_decode_c do
    max_tag =
      @draw_setting_tags
      |> Enum.map(&elem(&1, 0))
      |> Enum.max()

    """
    #{draw_setting_kind_lut_c()}
          if (setting_tag < 1 || setting_tag > #{max_tag}) return -3;
          {
            const int16_t mapped = elmc_pebble_draw_setting_kind_lut[setting_tag];
            if (mapped < 0) return -3;
            out_cmd->kind = mapped;
            return 0;
          }
    """
    |> String.trim_trailing()
  end

  @spec max_kind_id() :: non_neg_integer()
  def max_kind_id do
    DrawKinds.table()
    |> Keyword.values()
    |> Enum.max()
  end

  defp slot(index, value), do: "  [#{index}] = #{value},"

  defp setting_tag_slot(index, value, feature) do
    """
    #if #{feature}
      [#{index}] = #{value},
    #else
      [#{index}] = -1,
    #endif
    """
    |> String.trim_trailing()
  end
end
