defmodule IdeWeb.WorkspaceLive.DebuggerPreview.ViewTreeOps do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview.{RuntimeAccess, SvgOpNormalize, SvgTextOptions, WireMap}
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: PreviewTypes

  @default_screen_w 144
  @default_screen_h 168

  @type view_tree :: PreviewTypes.view_tree() | nil
  @type view_node :: PreviewTypes.view_node()
  @type model_map :: PreviewTypes.model_map()
  @type wire_map :: PreviewTypes.wire_map()
  @type svg_op :: PreviewTypes.svg_op()
  @type wire_value :: PreviewTypes.wire_value()

  @spec ops_from_tree(view_tree(), integer() | nil, model_map()) :: [svg_op()]
  def ops_from_tree(tree, primary_int, model) when is_map(tree) do
    tree
    |> collect_view_nodes()
    |> Enum.flat_map(&svg_op_from_node(&1, primary_int, model))
  end

  def ops_from_tree(_tree, _primary_int, _model), do: []

  @spec node_rect_fields(view_node()) ::
          {integer() | nil, integer() | nil, integer() | nil, integer() | nil}
  defp node_rect_fields(node) when is_map(node) do
    bounds = Map.get(node, "bounds") || Map.get(node, :bounds) || %{}

    {
      WireMap.map_integer(node, "x", WireMap.map_integer(bounds, "x", nil)),
      WireMap.map_integer(node, "y", WireMap.map_integer(bounds, "y", nil)),
      WireMap.map_integer(node, "w", WireMap.map_integer(bounds, "w", nil)),
      WireMap.map_integer(node, "h", WireMap.map_integer(bounds, "h", nil))
    }
  end

  @spec node_point_xy(view_node(), String.t()) :: {integer() | nil, integer() | nil}
  defp node_point_xy(node, key) when is_map(node) and is_binary(key) do
    point = Map.get(node, key) || Map.get(node, String.to_atom(key)) || %{}

    {
      WireMap.map_integer(point, "x", WireMap.map_integer(node, "x", nil)),
      WireMap.map_integer(point, "y", WireMap.map_integer(node, "y", nil))
    }
  end
  @spec collect_view_nodes(view_tree()) :: [view_node()]
  defp collect_view_nodes(node) when is_map(node) do
    type = node |> Map.get("type", Map.get(node, :type, "")) |> to_string()

    cond do
      type == "if" ->
        []

      type == "group" ->
        collect_group_view_nodes(node)

      true ->
        collect_view_nodes_in_node(node, type)
    end
  end

  defp collect_view_nodes(_), do: []

  @spec collect_group_view_nodes(view_node()) :: [view_node()]
  defp collect_group_view_nodes(node) when is_map(node) do
    children =
      node
      |> node_children()
      |> Enum.flat_map(&collect_view_nodes/1)

    [%{"type" => "push_context"}] ++
      group_style_nodes(node) ++ children ++ [%{"type" => "pop_context"}]
  end

  @spec group_style_nodes(view_node()) :: [PreviewTypes.group_style_map()]
  defp group_style_nodes(node) when is_map(node) do
    style =
      case Map.get(node, "style") || Map.get(node, :style) do
        %{} = value -> value
        _ -> %{}
      end

    [
      style_node(style, "stroke_color"),
      style_node(style, "fill_color"),
      style_node(style, "text_color")
    ]
    |> Enum.reject(&is_nil/1)
  end

  @spec style_node(PreviewTypes.group_style_map(), String.t()) :: PreviewTypes.group_style_map() | nil
  defp style_node(style, key) when is_map(style) and is_binary(key) do
    case Map.get(style, key) || Map.get(style, String.to_atom(key)) do
      value when is_integer(value) -> %{"type" => key, "color" => value}
      _ -> nil
    end
  end

  @spec collect_view_nodes_in_node(view_node(), String.t()) :: [view_node()]
  defp collect_view_nodes_in_node(node, type) when is_map(node) and is_binary(type) do
    children =
      case node["children"] || node[:children] do
        list when is_list(list) -> list
        _ -> []
      end

    here = if type != "", do: [node], else: []
    child_nodes = children |> Enum.filter(&is_map/1) |> Enum.flat_map(&collect_view_nodes/1)
    here ++ child_nodes
  end

  @spec svg_op_from_node(view_node(), integer() | nil, model_map()) :: [svg_op()]
  defp svg_op_from_node(node, primary_int, model) when is_map(node) do
    type = node |> Map.get("type", Map.get(node, :type, "")) |> to_string()
    ints = node_int_args(node, model)

    case concrete_svg_op_from_node(node) do
      %{} = op ->
        [op]

      nil ->
        svg_op_from_node_children(node, type, ints, primary_int, model)
    end
  end

  defp svg_op_from_node(_node, _primary_int, _model), do: []

  @spec concrete_svg_op_from_node(view_node()) :: svg_op() | nil
  defp concrete_svg_op_from_node(node) when is_map(node) do
    type = node |> Map.get("type", Map.get(node, :type, "")) |> to_string()

    op =
      case type do
        "push_context" ->
          %{"kind" => "push_context"}

        "pop_context" ->
          %{"kind" => "pop_context"}

        "stroke_color" ->
          %{"kind" => "stroke_color", "color" => Map.get(node, "color") || Map.get(node, :color)}

        "fill_color" ->
          %{"kind" => "fill_color", "color" => Map.get(node, "color") || Map.get(node, :color)}

        "text_color" ->
          %{"kind" => "text_color", "color" => Map.get(node, "color") || Map.get(node, :color)}

        "clear" ->
          %{"kind" => "clear", "color" => Map.get(node, "color") || Map.get(node, :color)}

        "roundRect" ->
          %{
            "kind" => "round_rect",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "w" => Map.get(node, "w") || Map.get(node, :w),
            "h" => Map.get(node, "h") || Map.get(node, :h),
            "radius" => Map.get(node, "radius") || Map.get(node, :radius),
            "fill" =>
              Map.get(node, "fill") || Map.get(node, :fill) || Map.get(node, "color") ||
                Map.get(node, :color)
          }

        "rect" ->
          %{
            "kind" => "rect",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "w" => Map.get(node, "w") || Map.get(node, :w),
            "h" => Map.get(node, "h") || Map.get(node, :h),
            "fill" =>
              Map.get(node, "fill") || Map.get(node, :fill) || Map.get(node, "color") ||
                Map.get(node, :color)
          }

        "fillRect" ->
          %{
            "kind" => "fill_rect",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "w" => Map.get(node, "w") || Map.get(node, :w),
            "h" => Map.get(node, "h") || Map.get(node, :h),
            "fill" =>
              Map.get(node, "fill") || Map.get(node, :fill) || Map.get(node, "color") ||
                Map.get(node, :color)
          }

        "line" ->
          %{
            "kind" => "line",
            "x1" => Map.get(node, "x1") || Map.get(node, :x1),
            "y1" => Map.get(node, "y1") || Map.get(node, :y1),
            "x2" => Map.get(node, "x2") || Map.get(node, :x2),
            "y2" => Map.get(node, "y2") || Map.get(node, :y2),
            "color" => Map.get(node, "color") || Map.get(node, :color)
          }

        "arc" ->
          %{
            "kind" => "arc",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "w" => Map.get(node, "w") || Map.get(node, :w),
            "h" => Map.get(node, "h") || Map.get(node, :h),
            "start_angle" => Map.get(node, "start_angle") || Map.get(node, :start_angle),
            "end_angle" => Map.get(node, "end_angle") || Map.get(node, :end_angle)
          }

        "fillRadial" ->
          %{
            "kind" => "fill_radial",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "w" => Map.get(node, "w") || Map.get(node, :w),
            "h" => Map.get(node, "h") || Map.get(node, :h),
            "start_angle" => Map.get(node, "start_angle") || Map.get(node, :start_angle),
            "end_angle" => Map.get(node, "end_angle") || Map.get(node, :end_angle)
          }

        "circle" ->
          %{
            "kind" => "circle",
            "cx" => Map.get(node, "cx") || Map.get(node, :cx),
            "cy" => Map.get(node, "cy") || Map.get(node, :cy),
            "r" => Map.get(node, "r") || Map.get(node, :r),
            "color" => Map.get(node, "color") || Map.get(node, :color)
          }

        "fillCircle" ->
          %{
            "kind" => "fill_circle",
            "cx" => Map.get(node, "cx") || Map.get(node, :cx),
            "cy" => Map.get(node, "cy") || Map.get(node, :cy),
            "r" => Map.get(node, "r") || Map.get(node, :r),
            "color" => Map.get(node, "color") || Map.get(node, :color)
          }

        "pixel" ->
          %{
            "kind" => "pixel",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "color" => Map.get(node, "color") || Map.get(node, :color)
          }

        "bitmapInRect" ->
          %{
            "kind" => "bitmap_in_rect",
            "bitmap_id" => Map.get(node, "bitmap_id") || Map.get(node, :bitmap_id),
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "w" => Map.get(node, "w") || Map.get(node, :w),
            "h" => Map.get(node, "h") || Map.get(node, :h)
          }

        "drawBitmapInRect" ->
          {x, y, w, h} = node_rect_fields(node)

          %{
            "kind" => "bitmap_in_rect",
            "resource" => Map.get(node, "resource") || Map.get(node, :resource),
            "bitmap_id" => Map.get(node, "bitmap_id") || Map.get(node, :bitmap_id) || 0,
            "x" => x,
            "y" => y,
            "w" => w,
            "h" => h
          }

        "drawRotatedBitmap" ->
          {src_w, src_h, _, _} = node_rect_fields(node)
          {center_x, center_y} = node_point_xy(node, "origin")

          %{
            "kind" => "rotated_bitmap",
            "resource" => Map.get(node, "resource") || Map.get(node, :resource),
            "bitmap_id" => Map.get(node, "bitmap_id") || Map.get(node, :bitmap_id) || 0,
            "src_w" => src_w,
            "src_h" => src_h,
            "angle" =>
              Map.get(node, "rotation") || Map.get(node, :rotation) || Map.get(node, "angle") ||
                Map.get(node, :angle),
            "center_x" => center_x,
            "center_y" => center_y
          }

        "drawBitmapSequenceAt" ->
          {x, y} = node_point_xy(node, "origin")

          %{
            "kind" => "bitmap_sequence_at",
            "resource" => Map.get(node, "resource") || Map.get(node, :resource),
            "animation_id" => Map.get(node, "animation_id") || Map.get(node, :animation_id) || 0,
            "bitmap_animation_id" =>
              Map.get(node, "bitmap_animation_id") || Map.get(node, :bitmap_animation_id) || 0,
            "x" => x,
            "y" => y
          }

        "drawVectorAt" ->
          %{
            "kind" => "vector_at",
            "resource" => Map.get(node, "resource") || Map.get(node, :resource),
            "vector_id" => Map.get(node, "vector_id") || Map.get(node, :vector_id),
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y)
          }

        "drawVectorSequenceAt" ->
          %{
            "kind" => "vector_sequence_at",
            "animation_id" => Map.get(node, "animation_id") || Map.get(node, :animation_id) || 0,
            "vector_id" => Map.get(node, "vector_id") || Map.get(node, :vector_id),
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y)
          }

        "text" ->
          {x, y, w, h} = node_rect_fields(node)

          %{
            "kind" => "text",
            "x" => x,
            "y" => y,
            "w" => w,
            "h" => h,
            "text" =>
              Map.get(node, "text") || Map.get(node, :text) || Map.get(node, "label") ||
                Map.get(node, :label),
            "text_align" =>
              SvgTextOptions.normalized_alignment(
                Map.get(node, "text_align") || Map.get(node, :text_align)
              ),
            "text_overflow" =>
              SvgTextOptions.normalized_overflow(
                Map.get(node, "text_overflow") || Map.get(node, :text_overflow)
              )
          }

        "textInt" ->
          %{
            "kind" => "text_int",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "text" =>
              Map.get(node, "text") || Map.get(node, :text) || Map.get(node, "value") ||
                Map.get(node, :value)
          }

        "textLabel" ->
          %{
            "kind" => "text_label",
            "x" => Map.get(node, "x") || Map.get(node, :x),
            "y" => Map.get(node, "y") || Map.get(node, :y),
            "text" => Map.get(node, "text") || Map.get(node, :text)
          }

        _ ->
          nil
      end

    case op do
      %{} ->
        case SvgOpNormalize.normalize(op) do
          %{kind: :unresolved} = unresolved ->
            if node_children(node) == [], do: unresolved, else: nil

          normalized ->
            normalized
        end

      nil ->
        nil
    end
  end

  @spec svg_op_from_node_children(
          view_node(),
          String.t(),
          [integer()],
          integer() | nil,
          model_map()
        ) :: [svg_op()]
  defp svg_op_from_node_children(node, type, ints, primary_int, model) do
    case type do
      "clear" ->
        case require_ints(ints, 1) do
          {:ok, [color]} ->
            [%{kind: :clear, color: color}]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "clear",
                provided_int_count: length(ints),
                required_int_count: 1
              }
            ]
        end

      "roundRect" ->
        case require_ints(ints, 6) do
          {:ok, [x, y, w, h, radius, fill]} ->
            [
              %{
                kind: :round_rect,
                x: clamp(x, 0, @default_screen_w - 1),
                y: clamp(y, 0, @default_screen_h - 1),
                w: clamp(w, 1, @default_screen_w),
                h: clamp(h, 1, @default_screen_h),
                radius: clamp(radius, 0, 80),
                fill: fill
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "roundRect",
                provided_int_count: length(ints),
                required_int_count: 6
              }
            ]
        end

      "rect" ->
        case require_ints(ints, 5) do
          {:ok, [x, y, w, h, fill]} ->
            [
              %{
                kind: :rect,
                x: clamp(x, 0, @default_screen_w - 1),
                y: clamp(y, 0, @default_screen_h - 1),
                w: clamp(w, 1, @default_screen_w),
                h: clamp(h, 1, @default_screen_h),
                fill: fill
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "rect",
                provided_int_count: length(ints),
                required_int_count: 5
              }
            ]
        end

      "fillRect" ->
        case require_ints(ints, 5) do
          {:ok, [x, y, w, h, fill]} ->
            [
              %{
                kind: :fill_rect,
                x: clamp(x, 0, @default_screen_w - 1),
                y: clamp(y, 0, @default_screen_h - 1),
                w: clamp(w, 1, @default_screen_w),
                h: clamp(h, 1, @default_screen_h),
                fill: fill
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "fillRect",
                provided_int_count: length(ints),
                required_int_count: 5
              }
            ]
        end

      "line" ->
        case require_ints(ints, 5) do
          {:ok, [x1, y1, x2, y2, color]} ->
            [
              %{
                kind: :line,
                x1: clamp(x1, 0, @default_screen_w - 1),
                y1: clamp(y1, 0, @default_screen_h - 1),
                x2: clamp(x2, 0, @default_screen_w - 1),
                y2: clamp(y2, 0, @default_screen_h - 1),
                color: color
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "line",
                provided_int_count: length(ints),
                required_int_count: 5
              }
            ]
        end

      "arc" ->
        case require_ints(ints, 6) do
          {:ok, [x, y, w, h, start_angle, end_angle]} ->
            [
              %{
                kind: :arc,
                x: clamp(x, 0, @default_screen_w - 1),
                y: clamp(y, 0, @default_screen_h - 1),
                w: clamp(w, 1, @default_screen_w),
                h: clamp(h, 1, @default_screen_h),
                start_angle: start_angle,
                end_angle: end_angle
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "arc",
                provided_int_count: length(ints),
                required_int_count: 6
              }
            ]
        end

      "fillRadial" ->
        case require_ints(ints, 6) do
          {:ok, [x, y, w, h, start_angle, end_angle]} ->
            [
              %{
                kind: :fill_radial,
                x: clamp(x, 0, @default_screen_w - 1),
                y: clamp(y, 0, @default_screen_h - 1),
                w: clamp(w, 1, @default_screen_w),
                h: clamp(h, 1, @default_screen_h),
                start_angle: start_angle,
                end_angle: end_angle
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "fillRadial",
                provided_int_count: length(ints),
                required_int_count: 6
              }
            ]
        end

      "pathFilled" ->
        case path_from_view_node(node) do
          {:ok, path} ->
            [
              %{
                kind: :path_filled,
                points: path.points,
                offset_x: path.offset_x,
                offset_y: path.offset_y,
                rotation: path.rotation
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "pathFilled",
                provided_int_count: length(ints),
                required_int_count: 4
              }
            ]
        end

      "pathOutline" ->
        case path_from_view_node(node) do
          {:ok, path} ->
            [
              %{
                kind: :path_outline,
                points: path.points,
                offset_x: path.offset_x,
                offset_y: path.offset_y,
                rotation: path.rotation
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "pathOutline",
                provided_int_count: length(ints),
                required_int_count: 4
              }
            ]
        end

      "pathOutlineOpen" ->
        case path_from_view_node(node) do
          {:ok, path} ->
            [
              %{
                kind: :path_outline_open,
                points: path.points,
                offset_x: path.offset_x,
                offset_y: path.offset_y,
                rotation: path.rotation
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "pathOutlineOpen",
                provided_int_count: length(ints),
                required_int_count: 4
              }
            ]
        end

      "circle" ->
        case require_ints(ints, 4) do
          {:ok, [cx, cy, r, color]} ->
            [
              %{
                kind: :circle,
                cx: clamp(cx, 0, @default_screen_w - 1),
                cy: clamp(cy, 0, @default_screen_h - 1),
                r: clamp(r, 1, 80),
                color: color
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "circle",
                provided_int_count: length(ints),
                required_int_count: 4
              }
            ]
        end

      "fillCircle" ->
        case require_ints(ints, 4) do
          {:ok, [cx, cy, r, color]} ->
            [
              %{
                kind: :fill_circle,
                cx: clamp(cx, 0, @default_screen_w - 1),
                cy: clamp(cy, 0, @default_screen_h - 1),
                r: clamp(r, 1, 80),
                color: color
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "fillCircle",
                provided_int_count: length(ints),
                required_int_count: 4
              }
            ]
        end

      "pixel" ->
        case require_ints(ints, 3) do
          {:ok, [x, y, color]} ->
            [
              %{
                kind: :pixel,
                x: clamp(x, 0, @default_screen_w - 1),
                y: clamp(y, 0, @default_screen_h - 1),
                color: color
              }
            ]

          :error ->
            [
              %{
                kind: :unresolved,
                node_type: "pixel",
                provided_int_count: length(ints),
                required_int_count: 3
              }
            ]
        end

      kind when kind in ["drawRotatedBitmap"] ->
        rotated_bitmap_svg_ops_from_children(node, model, length(ints))

      kind when kind in ["drawBitmapInRect", "bitmapInRect"] ->
        case node_children(node) do
          [bitmap_node, bounds_node | _] ->
            with bitmap_id when is_integer(bitmap_id) <- bitmap_node_id(bitmap_node, model),
                 {:ok, [x, y, w, h]} <- rect_node_ints(bounds_node, model) do
              [
                %{
                  kind: :bitmap_in_rect,
                  bitmap_id: bitmap_id,
                  x: clamp(x, 0, @default_screen_w - 1),
                  y: clamp(y, 0, @default_screen_h - 1),
                  w: clamp(w, 1, @default_screen_w),
                  h: clamp(h, 1, @default_screen_h)
                }
              ]
            else
              _ ->
                unresolved_node("bitmapInRect", length(ints), 5)
            end

          _ ->
            unresolved_node("bitmapInRect", length(ints), 5)
        end

      kind when kind in ["drawVectorAt", "vectorAt"] ->
        case require_ints(ints, 3) do
          {:ok, [vector_id, x, y]} ->
            if vector_id == 0 do
              []
            else
              [%{kind: :vector_at, vector_id: vector_id, x: x, y: y}]
            end

          :error ->
            case node_children(node) do
              [vector_node, x_node, y_node | _] ->
                with vector_id when is_integer(vector_id) <- vector_node_id(vector_node, model),
                     x when is_integer(x) <- node_int_value(x_node, model),
                     y when is_integer(y) <- node_int_value(y_node, model),
                     true <- vector_id != 0 do
                  [%{kind: :vector_at, vector_id: vector_id, x: x, y: y}]
                else
                  _ ->
                    unresolved_node("drawVectorAt", length(ints), 3)
                end

              [vector_node, point_node | _] ->
                with vector_id when is_integer(vector_id) <- vector_node_id(vector_node, model),
                     {:ok, [x, y]} <- point_pair_from_point_node(point_node),
                     true <- vector_id != 0 do
                  [%{kind: :vector_at, vector_id: vector_id, x: x, y: y}]
                else
                  _ ->
                    unresolved_node("drawVectorAt", length(ints), 3)
                end

              _ ->
                unresolved_node("drawVectorAt", length(ints), 3)
            end
        end

      kind when kind in ["drawVectorSequenceAt", "vectorSequenceAt"] ->
        case require_ints(ints, 4) do
          {:ok, [animation_id, vector_id, x, y]} ->
            if vector_id == 0 do
              []
            else
              [
                %{
                  kind: :vector_sequence_at,
                  animation_id: animation_id,
                  vector_id: vector_id,
                  x: x,
                  y: y
                }
              ]
            end

          :error ->
            case node_children(node) do
              [animation_node, vector_node, x_node, y_node | _] ->
                with animation_id when is_integer(animation_id) <-
                       node_int_value(animation_node, model),
                     vector_id when is_integer(vector_id) <- vector_node_id(vector_node, model),
                     x when is_integer(x) <- node_int_value(x_node, model),
                     y when is_integer(y) <- node_int_value(y_node, model),
                     true <- vector_id != 0 do
                  [
                    %{
                      kind: :vector_sequence_at,
                      animation_id: animation_id,
                      vector_id: vector_id,
                      x: x,
                      y: y
                    }
                  ]
                else
                  _ ->
                    unresolved_node("drawVectorSequenceAt", length(ints), 4)
                end

              [animation_node, vector_node, point_node | _] ->
                with animation_id when is_integer(animation_id) <-
                       node_int_value(animation_node, model),
                     vector_id when is_integer(vector_id) <- vector_node_id(vector_node, model),
                     {:ok, [x, y]} <- point_pair_from_point_node(point_node),
                     true <- vector_id != 0 do
                  [
                    %{
                      kind: :vector_sequence_at,
                      animation_id: animation_id,
                      vector_id: vector_id,
                      x: x,
                      y: y
                    }
                  ]
                else
                  _ ->
                    unresolved_node("drawVectorSequenceAt", length(ints), 4)
                end

              _ ->
                unresolved_node("drawVectorSequenceAt", length(ints), 4)
            end
        end

      kind when kind in ["RotatedBitmap", "rotatedBitmap"] ->
        case require_ints(ints, 6) do
          {:ok, [bitmap_id, src_w, src_h, angle, center_x, center_y]} when bitmap_id > 0 ->
            [
              %{
                kind: :rotated_bitmap,
                bitmap_id: bitmap_id,
                src_w: src_w,
                src_h: src_h,
                angle: angle,
                center_x: center_x,
                center_y: center_y
              }
            ]

          {:ok, _} ->
            rotated_bitmap_svg_ops_from_children(node, model, length(ints))

          :error ->
            rotated_bitmap_svg_ops_from_children(node, model, length(ints))
        end

      kind when kind in ["BitmapInRect", "bitmapInRect"] ->
        case require_ints(ints, 5) do
          {:ok, [bitmap_id, x, y, w, h]} when bitmap_id > 0 ->
            [
              %{
                kind: :bitmap_in_rect,
                bitmap_id: bitmap_id,
                x: x,
                y: y,
                w: w,
                h: h
              }
            ]

          {:ok, _} ->
            bitmap_in_rect_svg_ops_from_children(node, model, length(ints))

          :error ->
            bitmap_in_rect_svg_ops_from_children(node, model, length(ints))
        end

      kind when kind in ["BitmapSequenceAt", "bitmapSequenceAt"] ->
        case require_ints(ints, 4) do
          {:ok, [animation_id, bitmap_animation_id, x, y]} when bitmap_animation_id > 0 ->
            [
              %{
                kind: :bitmap_sequence_at,
                animation_id: animation_id,
                bitmap_animation_id: bitmap_animation_id,
                x: x,
                y: y
              }
            ]

          {:ok, _} ->
            bitmap_sequence_svg_ops_from_children(node, model, length(ints))

          :error ->
            bitmap_sequence_svg_ops_from_children(node, model, length(ints))
        end

      kind when kind in ["drawBitmapSequenceAt", "bitmapSequenceAt"] ->
        case require_ints(ints, 4) do
          {:ok, [animation_id, bitmap_animation_id, x, y]} when bitmap_animation_id > 0 ->
            [
              %{
                kind: :bitmap_sequence_at,
                animation_id: animation_id,
                bitmap_animation_id: bitmap_animation_id,
                x: x,
                y: y
              }
            ]

          {:ok, _} ->
            bitmap_sequence_svg_ops_from_children(node, model, length(ints))

          :error ->
            bitmap_sequence_svg_ops_from_children(node, model, length(ints))
        end

      "text" ->
        case node_children(node) do
          [_font_node, x_node, y_node, w_node, h_node, value_node | _] ->
            with x when is_integer(x) <- node_int_value(x_node, model),
                 y when is_integer(y) <- node_int_value(y_node, model),
                 w when is_integer(w) <- node_int_value(w_node, model),
                 h when is_integer(h) <- node_int_value(h_node, model) do
              [
                %{
                  kind: :text_label,
                  x: clamp(x, 0, @default_screen_w - 1),
                  y: clamp(y, 0, @default_screen_h),
                  w: clamp(w, 1, @default_screen_w),
                  h: clamp(h, 1, @default_screen_h),
                  font_size: clamp(h, 1, @default_screen_h),
                  text_align: "center",
                  text_overflow: "word_wrap",
                  text: RuntimeAccess.text_label_from_node(value_node, model)
                }
              ]
            else
              _ ->
                unresolved_node("text", length(ints), 6)
            end

          [_font_node, options_node, bounds_node, value_node | _] ->
            with {:ok, [x, y, w, h]} <- rect_node_ints(bounds_node, model) do
              {alignment, overflow} = text_option_names_from_node(options_node, model)

              [
                %{
                  kind: :text_label,
                  x: clamp(x, 0, @default_screen_w - 1),
                  y: clamp(y, 0, @default_screen_h),
                  w: clamp(w, 1, @default_screen_w),
                  h: clamp(h, 1, @default_screen_h),
                  font_size: clamp(h, 1, @default_screen_h),
                  text_align: alignment,
                  text_overflow: overflow,
                  text: RuntimeAccess.text_label_from_node(value_node, model)
                }
              ]
            else
              _ ->
                unresolved_node("text", length(ints), 6)
            end

          [_font_node, bounds_node, value_node | _] ->
            with {:ok, [x, y, w, h]} <- rect_node_ints(bounds_node, model) do
              [
                %{
                  kind: :text_label,
                  x: clamp(x, 0, @default_screen_w - 1),
                  y: clamp(y, 0, @default_screen_h),
                  w: clamp(w, 1, @default_screen_w),
                  h: clamp(h, 1, @default_screen_h),
                  font_size: clamp(h, 1, @default_screen_h),
                  text_align: "center",
                  text_overflow: "word_wrap",
                  text: RuntimeAccess.text_label_from_node(value_node, model)
                }
              ]
            else
              _ ->
                unresolved_node("text", length(ints), 6)
            end

          _ ->
            unresolved_node("text", length(ints), 6)
        end

      "textInt" ->
        case node_children(node) do
          [_font_node, pos_node, value_node | _] ->
            with {:ok, [x, y]} <- point_pair_from_point_node(pos_node),
                 value when is_integer(value) <- node_int_value(value_node) || primary_int do
              [
                %{
                  kind: :text_int,
                  x: clamp(x, 0, @default_screen_w - 1),
                  y: clamp(y, 0, @default_screen_h),
                  text: Integer.to_string(value)
                }
              ]
            else
              _ ->
                [
                  %{
                    kind: :unresolved,
                    node_type: "textInt",
                    provided_int_count: length(ints),
                    required_int_count: 3
                  }
                ]
            end

          _ ->
            [
              %{
                kind: :unresolved,
                node_type: "textInt",
                provided_int_count: length(ints),
                required_int_count: 3
              }
            ]
        end

      "textLabel" ->
        case node_children(node) do
          [_font_node, pos_node | _] ->
            case point_pair_from_point_node(pos_node) do
              {:ok, [x, y]} ->
                [
                  %{
                    kind: :text_label,
                    x: clamp(x, 0, @default_screen_w - 1),
                    y: clamp(y, 0, @default_screen_h),
                    text: RuntimeAccess.text_label_from_node(node, model)
                  }
                ]

              :error ->
                [
                  %{
                    kind: :unresolved,
                    node_type: "textLabel",
                    provided_int_count: length(ints),
                    required_int_count: 3
                  }
                ]
            end

          _ ->
            [
              %{
                kind: :unresolved,
                node_type: "textLabel",
                provided_int_count: length(ints),
                required_int_count: 3
              }
            ]
        end

      _ ->
        []
    end
  end

  @spec unresolved_node(String.t(), non_neg_integer(), pos_integer()) :: [svg_op()]
  defp unresolved_node(node_type, provided_int_count, required_int_count) do
    [
      %{
        kind: :unresolved,
        node_type: node_type,
        provided_int_count: provided_int_count,
        required_int_count: required_int_count
      }
    ]
  end

  @spec node_int_args(view_node(), model_map()) :: [integer()]
  defp node_int_args(node, model) when is_map(node) do
    case structured_node_int_args(node, model) do
      {:ok, values} ->
        values

      :error ->
        node
        |> node_children()
        |> Enum.map(&node_int_value(&1, model))
        |> Enum.reject(&is_nil/1)
    end
  end

  @spec structured_node_int_args(view_node(), model_map()) :: {:ok, [integer()]} | :error
  defp structured_node_int_args(node, model) when is_map(node) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")
    children = node_children(node)

    case {type, children} do
      {"clear", [color_node | _]} ->
        with color when is_integer(color) <- node_color_value(color_node, model) do
          {:ok, [color]}
        else
          _ -> :error
        end

      {kind, [bounds_node, color_node | _]} when kind in ["rect", "fillRect"] ->
        with {:ok, [x, y, w, h]} <- rect_node_ints(bounds_node, model),
             color when is_integer(color) <- node_color_value(color_node, model) do
          {:ok, [x, y, w, h, color]}
        else
          _ -> :error
        end

      {"roundRect", [bounds_node, radius_node, color_node | _]} ->
        with {:ok, [x, y, w, h]} <- rect_node_ints(bounds_node, model),
             radius when is_integer(radius) <- node_int_value(radius_node, model),
             color when is_integer(color) <- node_color_value(color_node, model) do
          {:ok, [x, y, w, h, radius, color]}
        else
          _ -> :error
        end

      {kind, [bounds_node, start_node, end_node | _]} when kind in ["arc", "fillRadial"] ->
        with {:ok, [x, y, w, h]} <- rect_node_ints(bounds_node, model),
             start_angle when is_integer(start_angle) <- node_int_value(start_node, model),
             end_angle when is_integer(end_angle) <- node_int_value(end_node, model) do
          {:ok, [x, y, w, h, start_angle, end_angle]}
        else
          _ -> :error
        end

      {"pixel", [pos_node, color_node | _]} ->
        with {:ok, [x, y]} <- point_node_ints(pos_node, model),
             color when is_integer(color) <- node_color_value(color_node, model) do
          {:ok, [x, y, color]}
        else
          _ -> :error
        end

      {"line", [start_node, end_node, color_node | _]} ->
        with {:ok, [x1, y1]} <- point_node_ints(start_node, model),
             {:ok, [x2, y2]} <- point_node_ints(end_node, model),
             color when is_integer(color) <- node_color_value(color_node, model) do
          {:ok, [x1, y1, x2, y2, color]}
        else
          _ -> :error
        end

      {kind, [center_node, radius_node, color_node | _]} when kind in ["circle", "fillCircle"] ->
        with {:ok, [cx, cy]} <- point_node_ints(center_node, model),
             radius when is_integer(radius) <- node_int_value(radius_node, model),
             color when is_integer(color) <- node_color_value(color_node, model) do
          {:ok, [cx, cy, radius, color]}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  @spec node_int_value(view_node()) :: integer() | nil
  defp node_int_value(node), do: node_int_value(node, %{})

  @spec node_int_value(view_node(), model_map()) :: integer() | nil
  defp node_int_value(node, model) when is_map(node) do
    evaluated = evaluated_node_value(node, model)
    value = Map.get(node, "value") || Map.get(node, :value)
    op = to_string(Map.get(node, "op") || Map.get(node, :op) || "")

    cond do
      is_integer(evaluated) ->
        evaluated

      is_float(evaluated) ->
        trunc(evaluated)

      op == "field_access" ->
        RuntimeAccess.field_access_int(node, model)

      is_integer(value) ->
        value

      is_float(value) ->
        trunc(value)

      is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> nil
        end

      true ->
        label = (Map.get(node, "label") || Map.get(node, :label) || "") |> to_string()
        label_ints = extract_ints(label)
        List.first(label_ints)
    end
  end

  defp node_int_value(_node, _model), do: nil

  @spec evaluated_node_value(view_node(), model_map()) :: wire_value()
  defp evaluated_node_value(node, _model) when is_map(node) do
    Map.get(node, "value") ||
      Map.get(node, :value) ||
      Map.get(node, "evaluated_value") ||
      Map.get(node, :evaluated_value)
  end

  @spec node_color_value(view_node(), model_map()) :: integer() | nil
  defp node_color_value(node, model) when is_map(node) do
    node_int_value(node, model) || color_constructor_value(node, model)
  end

  @spec bitmap_in_rect_svg_ops_from_children(view_node(), model_map(), non_neg_integer()) ::
          [svg_op()]
  defp bitmap_in_rect_svg_ops_from_children(node, model, int_count) do
    case node_children(node) do
      [bitmap_node, bounds_node | _] ->
        with bitmap_id when is_integer(bitmap_id) <- bitmap_node_id(bitmap_node, model),
             {:ok, [x, y, w, h]} <- rect_node_ints(bounds_node, model),
             true <- bitmap_id > 0 do
          [
            %{
              kind: :bitmap_in_rect,
              bitmap_id: bitmap_id,
              x: clamp(x, 0, @default_screen_w - 1),
              y: clamp(y, 0, @default_screen_h - 1),
              w: clamp(w, 1, @default_screen_w),
              h: clamp(h, 1, @default_screen_h)
            }
          ]
        else
          _ -> unresolved_node("BitmapInRect", int_count, 5)
        end

      _ ->
        unresolved_node("BitmapInRect", int_count, 5)
    end
  end

  @spec rotated_bitmap_svg_ops_from_children(view_node(), model_map(), non_neg_integer()) ::
          [svg_op()]
  defp rotated_bitmap_svg_ops_from_children(node, model, int_count) do
    case node_children(node) do
      [bitmap_node, bounds_node, rotation_node, center_node | _] ->
        with bitmap_id when is_integer(bitmap_id) <- bitmap_node_id(bitmap_node, model),
             {:ok, [src_w, src_h, _x, _y]} <- rect_node_ints(bounds_node, model),
             angle when is_integer(angle) <- node_int_value(rotation_node, model),
             {:ok, [center_x, center_y]} <- point_pair_from_point_node(center_node),
             true <- bitmap_id > 0 do
          [
            %{
              kind: :rotated_bitmap,
              bitmap_id: bitmap_id,
              src_w: src_w,
              src_h: src_h,
              angle: angle,
              center_x: center_x,
              center_y: center_y
            }
          ]
        else
          _ -> unresolved_node("RotatedBitmap", int_count, 6)
        end

      _ ->
        unresolved_node("RotatedBitmap", int_count, 6)
    end
  end

  @spec bitmap_sequence_svg_ops_from_children(view_node(), model_map(), non_neg_integer()) ::
          [svg_op()]
  defp bitmap_sequence_svg_ops_from_children(node, model, int_count) do
    case node_children(node) do
      [playback_node, resource_node, x_node, y_node | _] ->
        with playback_id when is_integer(playback_id) <- node_int_value(playback_node, model),
             resource_id when is_integer(resource_id) <- animation_node_id(resource_node, model),
             x when is_integer(x) <- node_int_value(x_node, model),
             y when is_integer(y) <- node_int_value(y_node, model),
             true <- resource_id > 0 do
          [
            %{
              kind: :bitmap_sequence_at,
              animation_id: playback_id,
              bitmap_animation_id: resource_id,
              x: x,
              y: y
            }
          ]
        else
          _ -> unresolved_node("BitmapSequenceAt", int_count, 4)
        end

      [playback_node, resource_node, point_node | _] ->
        with playback_id when is_integer(playback_id) <- node_int_value(playback_node, model),
             resource_id when is_integer(resource_id) <- animation_node_id(resource_node, model),
             {:ok, [x, y]} <- point_pair_from_point_node(point_node),
             true <- resource_id > 0 do
          [
            %{
              kind: :bitmap_sequence_at,
              animation_id: playback_id,
              bitmap_animation_id: resource_id,
              x: x,
              y: y
            }
          ]
        else
          _ -> unresolved_node("BitmapSequenceAt", int_count, 4)
        end

      _ ->
        unresolved_node("BitmapSequenceAt", int_count, 4)
    end
  end

  @spec bitmap_node_id(view_node(), model_map()) :: integer() | nil
  defp bitmap_node_id(node, model) when is_map(node) do
    evaluated = evaluated_node_value(node, model)

    target =
      to_string(Map.get(node, "qualified_target") || Map.get(node, :qualified_target) || "")

    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")

    cond do
      is_integer(evaluated) ->
        evaluated

      is_integer(Map.get(node, "tag") || Map.get(node, :tag)) ->
        (Map.get(node, "tag") || Map.get(node, :tag)) + 1

      target in [
        "Resources.NoBitmap",
        "Pebble.Ui.Resources.NoBitmap",
        "Resources.NoStaticBitmap",
        "Pebble.Ui.Resources.NoStaticBitmap"
      ] or type in ["NoBitmap", "NoStaticBitmap"] ->
        0

      true ->
        nil
    end
  end

  @spec animation_node_id(view_node(), model_map()) :: integer() | nil
  defp animation_node_id(node, model) when is_map(node) do
    evaluated = evaluated_node_value(node, model)

    target =
      to_string(Map.get(node, "qualified_target") || Map.get(node, :qualified_target) || "")

    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")

    cond do
      is_integer(evaluated) ->
        evaluated

      target in [
        "Resources.NoAnimation",
        "Pebble.Ui.Resources.NoAnimation",
        "Resources.NoAnimatedBitmap",
        "Pebble.Ui.Resources.NoAnimatedBitmap"
      ] or type in ["NoAnimation", "NoAnimatedBitmap"] ->
        0

      is_integer(Map.get(node, "tag") || Map.get(node, :tag)) ->
        (Map.get(node, "tag") || Map.get(node, :tag)) + 1

      true ->
        nil
    end
  end

  @spec vector_node_id(view_node(), model_map()) :: integer() | nil
  defp vector_node_id(node, model) when is_map(node) do
    evaluated = evaluated_node_value(node, model)

    target =
      to_string(Map.get(node, "qualified_target") || Map.get(node, :qualified_target) || "")

    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")

    cond do
      is_integer(evaluated) ->
        evaluated

      target in [
        "Resources.NoVectorGraphic",
        "Pebble.Ui.Resources.NoVectorGraphic",
        "Resources.NoStaticVector",
        "Pebble.Ui.Resources.NoStaticVector",
        "Resources.NoAnimatedVector",
        "Pebble.Ui.Resources.NoAnimatedVector"
      ] or type in ["NoVectorGraphic", "NoStaticVector", "NoAnimatedVector"] ->
        0

      is_integer(Map.get(node, "tag") || Map.get(node, :tag)) ->
        (Map.get(node, "tag") || Map.get(node, :tag)) + 1

      true ->
        nil
    end
  end

  @spec color_constructor_value(view_node(), model_map()) :: integer() | nil
  defp color_constructor_value(node, model) when is_map(node) do
    target =
      to_string(Map.get(node, "qualified_target") || Map.get(node, :qualified_target) || "")

    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")
    name = target |> String.split(".") |> List.last()
    name = if name in [nil, ""], do: type, else: name

    case name do
      "indexed" ->
        node
        |> node_children()
        |> List.first()
        |> node_int_value(model)

      "clearColor" ->
        0x00

      "black" ->
        0xC0

      "red" ->
        0xF0

      "chromeYellow" ->
        0xF8

      "green" ->
        0xCC

      "blue" ->
        0xC3

      "white" ->
        0xFF

      _ ->
        nil
    end
  end

  @spec rect_node_ints(view_node(), model_map()) :: {:ok, [integer()]} | :error
  defp rect_node_ints(node, model), do: record_field_ints(node, ["x", "y", "w", "h"], model)

  @spec point_node_ints(view_node(), model_map()) :: {:ok, [integer()]} | :error
  defp point_node_ints(node, model), do: record_field_ints(node, ["x", "y"], model)

  @spec text_option_names_from_node(view_node(), model_map()) :: {String.t(), String.t()}
  defp text_option_names_from_node(node, model) do
    case record_field_ints(node, ["alignment", "overflow"], model) do
      {:ok, [alignment, overflow]} ->
        {SvgTextOptions.alignment_name(alignment), SvgTextOptions.overflow_name(overflow)}

      :error ->
        {"center", "word_wrap"}
    end
  end

  @spec record_field_ints(view_node(), [String.t()], model_map()) :: {:ok, [integer()]} | :error
  defp record_field_ints(node, keys, model) when is_map(node) and is_list(keys) do
    evaluated = evaluated_node_value(node, model)

    values =
      Enum.map(keys, fn key ->
        field_value =
          cond do
            is_map(evaluated) ->
              Map.get(evaluated, key) || Map.get(evaluated, String.to_atom(key))

            true ->
              nil
          end

        if is_integer(field_value) do
          field_value
        else
          node
          |> field_node(key)
          |> field_value_int(model)
        end
      end)

    if Enum.all?(values, &is_integer/1), do: {:ok, values}, else: :error
  end

  defp record_field_ints(_node, _keys, _model), do: :error

  @spec field_node(view_node(), String.t()) :: view_node() | nil
  defp field_node(node, key) when is_map(node) and is_binary(key) do
    node
    |> node_children()
    |> Enum.find(fn child ->
      to_string(Map.get(child, "type") || Map.get(child, :type) || "") == "field" and
        to_string(Map.get(child, "label") || Map.get(child, :label) || "") == key
    end)
  end

  defp field_node(_node, _key), do: nil

  @spec node_children(view_node()) :: [view_node()]
  defp node_children(node) when is_map(node) do
    case Map.get(node, "children") || Map.get(node, :children) do
      list when is_list(list) ->
        Enum.filter(list, &is_map/1)

      _ ->
        type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")
        op = to_string(Map.get(node, "op") || Map.get(node, :op) || "")
        fields = Map.get(node, "fields") || Map.get(node, :fields)

        if (type == "record" or (type == "expr" and op == "record_literal")) and is_map(fields) do
          fields
          |> Enum.map(fn {k, v} ->
            child =
              cond do
                is_map(v) -> v
                is_integer(v) -> %{"type" => "expr", "value" => v}
                is_float(v) -> %{"type" => "expr", "value" => trunc(v)}
                is_binary(v) -> %{"type" => "expr", "label" => v}
                true -> %{"type" => "expr", "label" => to_string(v)}
              end

            %{
              "type" => "field",
              "label" => to_string(k),
              "children" => [child]
            }
          end)
        else
          []
        end
    end
  end

  @spec path_from_view_node(view_node()) :: {:ok, PreviewTypes.svg_path()} | :error
  defp path_from_view_node(node) when is_map(node) do
    case WireMap.map_path_required(node) do
      {:ok, path} ->
        {:ok, path}

      :error ->
        path_from_view_node_children(node)
    end
  end

  @spec path_from_view_node_children(view_node()) :: {:ok, PreviewTypes.svg_path()} | :error
  defp path_from_view_node_children(node) when is_map(node) do
    children = node_children(node)

    case children do
      [points_node, ox_node, oy_node, rot_node | _] ->
        with {:ok, points} <- points_from_points_node(points_node),
             ox when is_integer(ox) <- node_int_value(ox_node),
             oy when is_integer(oy) <- node_int_value(oy_node),
             rot when is_integer(rot) <- node_int_value(rot_node) do
          {:ok, %{points: points, offset_x: ox, offset_y: oy, rotation: rot}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  @spec points_from_points_node(view_node()) :: {:ok, [[integer()]]} | :error
  defp points_from_points_node(node) when is_map(node) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")

    if type == "List" do
      children = node_children(node)

      pairs =
        children
        |> Enum.map(&point_pair_from_point_node/1)

      if Enum.all?(pairs, &match?({:ok, _}, &1)) do
        {:ok, Enum.map(pairs, fn {:ok, pair} -> pair end)}
      else
        :error
      end
    else
      :error
    end
  end

  @spec point_pair_from_point_node(view_node()) :: {:ok, [integer()]} | :error
  defp point_pair_from_point_node(node) when is_map(node) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")
    op = to_string(Map.get(node, "op") || Map.get(node, :op) || "")

    case {type, op} do
      {"tuple2", _} ->
        children = node_children(node)

        case children do
          [x_node, y_node | _] ->
            x = node_int_value(x_node)
            y = node_int_value(y_node)
            if is_integer(x) and is_integer(y), do: {:ok, [x, y]}, else: :error

          _ ->
            :error
        end

      {"record", _} ->
        fields =
          node
          |> node_children()
          |> Enum.filter(&(to_string(Map.get(&1, "type") || Map.get(&1, :type) || "") == "field"))

        x =
          fields
          |> Enum.find(&(to_string(Map.get(&1, "label") || Map.get(&1, :label) || "") == "x"))
          |> field_value_int()

        y =
          fields
          |> Enum.find(&(to_string(Map.get(&1, "label") || Map.get(&1, :label) || "") == "y"))
          |> field_value_int()

        if is_integer(x) and is_integer(y), do: {:ok, [x, y]}, else: :error

      {"expr", "record_literal"} ->
        fields =
          node
          |> node_children()
          |> Enum.filter(&(to_string(Map.get(&1, "type") || Map.get(&1, :type) || "") == "field"))

        x =
          fields
          |> Enum.find(&(to_string(Map.get(&1, "label") || Map.get(&1, :label) || "") == "x"))
          |> field_value_int()

        y =
          fields
          |> Enum.find(&(to_string(Map.get(&1, "label") || Map.get(&1, :label) || "") == "y"))
          |> field_value_int()

        if is_integer(x) and is_integer(y), do: {:ok, [x, y]}, else: :error

      _ ->
        :error
    end
  end

  defp point_pair_from_point_node(_), do: :error

  @spec field_value_int(view_node()) :: integer() | nil
  defp field_value_int(field_node), do: field_value_int(field_node, %{})

  @spec field_value_int(view_node(), model_map()) :: integer() | nil
  defp field_value_int(field_node, model) when is_map(field_node) do
    case node_children(field_node) do
      [value_node | _] -> node_int_value(value_node, model)
      _ -> nil
    end
  end

  defp field_value_int(_field_node, _model), do: nil

  @spec extract_ints(String.t()) :: [integer()]
  defp extract_ints(text) when is_binary(text) do
    Regex.scan(~r/-?\d+/, text)
    |> Enum.map(fn [raw] -> String.to_integer(raw) end)
  end

  @spec require_ints([integer()], pos_integer()) :: {:ok, [integer()]} | :error
  defp require_ints(values, required)
       when is_list(values) and is_integer(required) and required > 0 do
    if length(values) >= required do
      head = Enum.take(values, required)
      if Enum.all?(head, &is_integer/1), do: {:ok, head}, else: :error
    else
      :error
    end
  end

  defp require_ints(_values, _required), do: :error

  @spec clamp(integer(), integer(), integer()) :: integer()
  defp clamp(value, min, max) when is_integer(value), do: max(min, min(value, max))

end
