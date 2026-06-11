defmodule Ide.Resources.ResourceStore.GeneratedModule do
  @moduledoc false

  alias Ide.Resources.{BitmapVariants, CtorNaming, Types}
  alias Ide.Resources.ResourceStore.Coercion

  @type generated_bitmap_row :: %{
          ctor: String.t(),
          name: String.t(),
          width: non_neg_integer(),
          height: non_neg_integer()
        }

  @type generated_font_row :: %{
          ctor: String.t(),
          name: String.t(),
          height: non_neg_integer()
        }

  @type generated_vector_row :: %{ctor: String.t(), name: String.t()}

  @type generated_animation_row :: %{
          ctor: String.t(),
          name: String.t(),
          width: non_neg_integer(),
          height: non_neg_integer(),
          frame_count: non_neg_integer(),
          duration_ms: non_neg_integer()
        }

  @type resource_kind :: :bitmap | :font | :vector | :animation

  @spec read_only_generated_module?(String.t(), String.t()) :: boolean()
  def read_only_generated_module?(source_root, rel_path)
      when is_binary(source_root) and is_binary(rel_path) do
    {normalize_source_root(source_root), normalize_editor_rel_path(rel_path)} in [
      {"watch", "src/Pebble/Ui/Resources.elm"},
      {"watch", "src/Pebble/Ui/Bitmap.elm"},
      {"phone", "src/Companion/GeneratedPreferences.elm"}
    ]
  end

  def read_only_generated_module?(_, _), do: false

  @spec source(
          [Types.manifest_wire_row()],
          [Types.manifest_wire_row()],
          [Types.manifest_wire_row()],
          [Types.manifest_wire_row()]
        ) :: String.t()
  def source(bitmap_entries, font_entries, vector_entries, animation_entries) do
    bitmap_rows =
      bitmap_entries
      |> Enum.map(&normalize_bitmap_row/1)
      |> Enum.reject(&(&1.ctor == ""))
      |> sort_generated_resource_rows(:bitmap)

    font_rows =
      font_entries
      |> Enum.map(&normalize_font_row/1)
      |> Enum.reject(&(&1.ctor == ""))
      |> sort_generated_resource_rows(:font)

    {static_vector_entries, animated_vector_entries} =
      Enum.split_with(vector_entries, &(CtorNaming.vector_kind_from_row(&1) == :vector_static))

    static_vector_rows =
      static_vector_entries
      |> Enum.map(&normalize_vector_row/1)
      |> Enum.reject(&(&1.ctor == ""))
      |> sort_generated_resource_rows(:vector)

    animated_vector_rows =
      animated_vector_entries
      |> Enum.map(&normalize_vector_row/1)
      |> Enum.reject(&(&1.ctor == ""))
      |> sort_generated_resource_rows(:vector)

    animated_bitmap_rows =
      animation_entries
      |> Enum.map(&normalize_animation_row/1)
      |> Enum.reject(&(&1.ctor == ""))
      |> sort_generated_resource_rows(:animation)

    {static_bitmap_type_decl, static_bitmap_all_decl, static_bitmap_info_decl} =
      generated_named_resource_section(
        type_name: "StaticBitmap",
        nil_ctor: "NoStaticBitmap",
        all_name: "allStaticBitmaps",
        info_type: "StaticBitmapInfo",
        info_fn: "staticBitmapInfo",
        record_field: "staticBitmap",
        rows: bitmap_rows,
        dimension_fields: true
      )

    {animated_bitmap_type_decl, animated_bitmap_all_decl, animated_bitmap_info_decl} =
      generated_named_resource_section(
        type_name: "AnimatedBitmap",
        nil_ctor: "NoAnimatedBitmap",
        all_name: "allAnimatedBitmaps",
        info_type: "AnimatedBitmapInfo",
        info_fn: "animatedBitmapInfo",
        record_field: "animatedBitmap",
        rows: animated_bitmap_rows,
        dimension_fields: true,
        animation_fields: true
      )

    {static_vector_type_decl, static_vector_all_decl, static_vector_info_decl} =
      generated_named_resource_section(
        type_name: "StaticVector",
        nil_ctor: "NoStaticVector",
        all_name: "allStaticVectors",
        info_type: "StaticVectorInfo",
        info_fn: "staticVectorInfo",
        record_field: "staticVector",
        rows: static_vector_rows
      )

    {animated_vector_type_decl, animated_vector_all_decl, animated_vector_info_decl} =
      generated_named_resource_section(
        type_name: "AnimatedVector",
        nil_ctor: "NoAnimatedVector",
        all_name: "allAnimatedVectors",
        info_type: "AnimatedVectorInfo",
        info_fn: "animatedVectorInfo",
        record_field: "animatedVector",
        rows: animated_vector_rows
      )

    {font_type_decl, font_all_decl} =
      case Enum.map(font_rows, & &1.ctor) do
        [] ->
          {"type Font\n    = DefaultFont",
           "allFonts : List Font\nallFonts =\n    [ DefaultFont ]"}

        list ->
          type_rows = Enum.map_join(list, "\n    | ", & &1)
          all_rows = Enum.map_join(list, ", ", & &1)

          {"type Font\n    = #{type_rows}",
           "allFonts : List Font\nallFonts =\n    [ #{all_rows} ]"}
      end

    font_info_decl =
      case font_rows do
        [] ->
          """
          type alias FontInfo =
              { font : Font
              , name : String
              , height : Int
              }

          fontInfo : Font -> FontInfo
          fontInfo font =
              case font of
                  DefaultFont ->
                      { font = DefaultFont, name = "DefaultFont", height = 0 }
          """

        rows ->
          cases =
            Enum.map_join(rows, "\n", fn row ->
              """
                  #{row.ctor} ->
                      { font = #{row.ctor}, name = "#{elm_string(row.name)}", height = #{row.height} }
              """
            end)

          """
          type alias FontInfo =
              { font : Font
              , name : String
              , height : Int
              }

          fontInfo : Font -> FontInfo
          fontInfo font =
              case font of
          #{cases}
          """
      end

    """
    module Pebble.Ui.Resources exposing
        ( AnimatedBitmap(..)
        , AnimatedBitmapInfo
        , AnimatedVector(..)
        , AnimatedVectorInfo
        , Font(..)
        , FontInfo
        , StaticBitmap(..)
        , StaticBitmapInfo
        , StaticVector(..)
        , StaticVectorInfo
        , allAnimatedBitmaps
        , allAnimatedVectors
        , allFonts
        , allStaticBitmaps
        , allStaticVectors
        , animatedBitmapInfo
        , animatedVectorInfo
        , fontInfo
        , staticBitmapInfo
        , staticVectorInfo
        )

    {-| Generated from the resources configured on the project settings Resources page.
    Edit bitmap, vector, and font assets there instead of editing this read-only file.
    -}

    #{static_bitmap_type_decl}

    #{static_bitmap_all_decl}

    #{static_bitmap_info_decl}

    #{animated_bitmap_type_decl}

    #{animated_bitmap_all_decl}

    #{animated_bitmap_info_decl}

    #{font_type_decl}

    #{font_all_decl}

    #{font_info_decl}

    #{static_vector_type_decl}

    #{static_vector_all_decl}

    #{static_vector_info_decl}

    #{animated_vector_type_decl}

    #{animated_vector_all_decl}

    #{animated_vector_info_decl}
    """
  end

  defp generated_named_resource_section(opts) do
    type_name = Keyword.fetch!(opts, :type_name)
    nil_ctor = Keyword.fetch!(opts, :nil_ctor)
    all_name = Keyword.fetch!(opts, :all_name)
    info_type = Keyword.fetch!(opts, :info_type)
    info_fn = Keyword.fetch!(opts, :info_fn)
    record_field = Keyword.fetch!(opts, :record_field)
    rows = Keyword.fetch!(opts, :rows)
    dimension_fields? = Keyword.get(opts, :dimension_fields, false)
    animation_fields? = Keyword.get(opts, :animation_fields, false)

    ctors = Enum.map(rows, & &1.ctor)

    {type_decl, all_decl} =
      case ctors do
        [] ->
          {"""
           type #{type_name}
               = #{nil_ctor}
           """,
           """
           #{all_name} : List #{type_name}
           #{all_name} =
               [ #{nil_ctor} ]
           """}

        list ->
          type_rows = Enum.map_join(list, "\n    | ", & &1)
          all_rows = Enum.map_join(list, ", ", & &1)

          {"""
           type #{type_name}
               = #{type_rows}
           """,
           """
           #{all_name} : List #{type_name}
           #{all_name} =
               [ #{all_rows} ]
           """}
      end

    info_decl =
      case rows do
        [] ->
          empty_info_decl(
            type_name,
            nil_ctor,
            info_type,
            info_fn,
            record_field,
            dimension_fields?,
            animation_fields?
          )

        row_list ->
          cases =
            Enum.map_join(row_list, "\n", fn row ->
              info_case_row(row, record_field, dimension_fields?, animation_fields?)
            end)

          populated_info_decl(
            type_name,
            info_type,
            info_fn,
            record_field,
            dimension_fields?,
            animation_fields?,
            cases
          )
      end

    {type_decl, all_decl, info_decl}
  end

  defp empty_info_decl(
         type_name,
         nil_ctor,
         info_type,
         info_fn,
         record_field,
         dimension_fields?,
         animation_fields?
       ) do
    record_fields =
      info_record_fields(type_name, record_field, dimension_fields?, animation_fields?)

    nil_record =
      info_record_literal(
        record_field,
        nil_ctor,
        nil_ctor,
        0,
        0,
        0,
        0,
        dimension_fields?,
        animation_fields?
      )

    """
    type alias #{info_type} =
        { #{record_fields}
        }

    #{info_fn} : #{type_name} -> #{info_type}
    #{info_fn} #{record_field} =
        case #{record_field} of
            #{nil_ctor} ->
                #{nil_record}
    """
  end

  defp populated_info_decl(
         type_name,
         info_type,
         info_fn,
         record_field,
         dimension_fields?,
         animation_fields?,
         cases
       ) do
    record_fields =
      info_record_fields(type_name, record_field, dimension_fields?, animation_fields?)

    """
    type alias #{info_type} =
        { #{record_fields}
        }

    #{info_fn} : #{type_name} -> #{info_type}
    #{info_fn} #{record_field} =
        case #{record_field} of
    #{cases}
    """
  end

  defp info_record_fields(type_name, record_field, dimension_fields?, animation_fields?) do
    parts =
      ["#{record_field} : #{type_name}", "name : String"]
      |> maybe_add_info_field(dimension_fields?, "width : Int")
      |> maybe_add_info_field(dimension_fields?, "height : Int")
      |> maybe_add_info_field(animation_fields?, "frameCount : Int")
      |> maybe_add_info_field(animation_fields?, "durationMs : Int")

    Enum.join(parts, "\n    , ")
  end

  defp maybe_add_info_field(parts, true, field), do: parts ++ [field]
  defp maybe_add_info_field(parts, false, _field), do: parts

  defp info_case_row(row, record_field, dimension_fields?, animation_fields?) do
    literal =
      info_record_literal(
        record_field,
        row.ctor,
        row.ctor,
        Map.get(row, :width, 0),
        Map.get(row, :height, 0),
        Map.get(row, :frame_count, 0),
        Map.get(row, :duration_ms, 0),
        dimension_fields?,
        animation_fields?
      )

    """
            #{row.ctor} ->
                #{literal}
    """
  end

  defp info_record_literal(
         record_field,
         value_ctor,
         name,
         width,
         height,
         frame_count,
         duration_ms,
         dimension_fields?,
         animation_fields?
       ) do
    parts =
      ["#{record_field} = #{value_ctor}", ~s(name = "#{elm_string(name)}")]
      |> maybe_add_info_literal(dimension_fields?, "width = #{width}")
      |> maybe_add_info_literal(dimension_fields?, "height = #{height}")
      |> maybe_add_info_literal(animation_fields?, "frameCount = #{frame_count}")
      |> maybe_add_info_literal(animation_fields?, "durationMs = #{duration_ms}")

    "{ " <> Enum.join(parts, ", ") <> " }"
  end

  defp maybe_add_info_literal(parts, true, field), do: parts ++ [field]
  defp maybe_add_info_literal(parts, false, _field), do: parts

  @spec sort_generated_resource_rows(
          [generated_bitmap_row() | generated_font_row() | generated_vector_row() | generated_animation_row()],
          resource_kind()
        ) ::
          [generated_bitmap_row() | generated_font_row() | generated_vector_row() | generated_animation_row()]
  defp sort_generated_resource_rows(rows, kind)
       when is_list(rows) and kind in [:bitmap, :font, :vector, :animation] do
    Enum.sort_by(rows, &resource_row_sort_key(&1, kind))
  end

  defp resource_row_sort_key(%{ctor: ctor}, :font), do: {0, ctor}

  defp resource_row_sort_key(%{ctor: ctor}, :bitmap) do
    {resource_prefix_rank(ctor, CtorNaming.prefix(:bitmap_static)), ctor}
  end

  defp resource_row_sort_key(%{ctor: ctor}, :animation) do
    {resource_prefix_rank(ctor, CtorNaming.prefix(:bitmap_animated)), ctor}
  end

  defp resource_row_sort_key(%{ctor: ctor}, :vector) do
    rank =
      cond do
        String.starts_with?(ctor, CtorNaming.prefix(:vector_static)) -> 0
        String.starts_with?(ctor, CtorNaming.prefix(:vector_animated)) -> 1
        true -> 2
      end

    {rank, ctor}
  end

  defp resource_prefix_rank(ctor, expected_prefix)
       when is_binary(ctor) and is_binary(expected_prefix) do
    if String.starts_with?(ctor, expected_prefix), do: 0, else: 1
  end

  @spec normalize_bitmap_row(Types.manifest_wire_row()) :: generated_bitmap_row()
  defp normalize_bitmap_row(row) do
    normalized = row |> BitmapVariants.normalize_row() |> CtorNaming.ensure_row!(:bitmap_static)
    {width, height} = BitmapVariants.primary_dimensions(normalized)
    ctor = Map.get(normalized, "ctor", "")

    %{
      ctor: ctor,
      name: to_string(Map.get(row, "name", ctor)),
      width: width,
      height: height
    }
  end

  @spec normalize_font_row(Types.manifest_wire_row()) :: generated_font_row()
  defp normalize_font_row(row) do
    ctor = to_string(Map.get(row, "ctor", ""))

    %{
      ctor: ctor,
      name: to_string(Map.get(row, "name", ctor)),
      height: Coercion.positive_integer_or_default(Map.get(row, "height", 0), 0)
    }
  end

  @spec normalize_vector_row(Types.manifest_wire_row()) :: generated_vector_row()
  defp normalize_vector_row(row) do
    normalized = CtorNaming.ensure_row!(row, CtorNaming.vector_kind_from_row(row))
    ctor = to_string(Map.get(normalized, "ctor", ""))

    %{
      ctor: ctor,
      name: to_string(Map.get(row, "name", ctor))
    }
  end

  @spec normalize_animation_row(Types.manifest_wire_row()) :: generated_animation_row()
  defp normalize_animation_row(row) when is_map(row) do
    normalized = CtorNaming.ensure_row!(row, :bitmap_animated)
    ctor = to_string(Map.get(normalized, "ctor", ""))

    %{
      ctor: ctor,
      name: to_string(Map.get(row, "name", ctor)),
      width: Coercion.integer_or_zero(Map.get(row, "width", 0)),
      height: Coercion.integer_or_zero(Map.get(row, "height", 0)),
      frame_count: Coercion.integer_or_zero(Map.get(row, "frame_count", 0)),
      duration_ms: Coercion.integer_or_zero(Map.get(row, "duration_ms", 0))
    }
  end

  @spec elm_string(String.t()) :: String.t()
  defp elm_string(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  defp normalize_source_root(source_root) do
    source_root
    |> String.trim()
    |> String.trim("/")
  end

  defp normalize_editor_rel_path(rel_path) do
    rel_path =
      rel_path
      |> String.trim()
      |> String.trim_leading("/")

    rel_path =
      if String.starts_with?(rel_path, "src/") do
        rel_path
      else
        "src/" <> rel_path
      end

    if Path.extname(rel_path) == "" do
      rel_path <> ".elm"
    else
      rel_path
    end
  end
end
