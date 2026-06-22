defmodule IdeWeb.WorkspaceLive.DebuggerPreview.SvgOpNormalize do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview.{SvgTextOptions, WireMap}
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: PreviewTypes

  @type svg_op :: PreviewTypes.svg_op()
  @type wire_map :: PreviewTypes.wire_map()

  defp compact_scene_text_label(op) when is_map(op) do
    text =
      to_string(
        Map.get(op, "text") || Map.get(op, :text) || Map.get(op, "label") || Map.get(op, :label) ||
          ""
      )

    case text do
      "" ->
        case compact_op_text_label_tag(op) do
          0 -> "Waiting for companion app"
          _ -> ""
        end

      "WaitingForCompanion" ->
        "Waiting for companion app"

      other ->
        other
    end
  end

  defp compact_op_text_label_tag(op) when is_map(op) do
    case Map.get(op, "label_tag") || Map.get(op, :label_tag) do
      n when is_integer(n) -> n
      n when is_float(n) -> trunc(n)
      _ -> -1
    end
  end
  @spec normalize(wire_map()) :: svg_op() | nil
  def normalize(op) when is_map(op) do
    kind = to_string(Map.get(op, "kind") || Map.get(op, :kind) || "")

    normalized =
      case kind do
        "push_context" ->
          %{kind: :push_context}

        "pop_context" ->
          %{kind: :pop_context}

        "stroke_width" ->
          case WireMap.map_integer_required(op, "value") do
            {:ok, value} -> %{kind: :stroke_width, value: max(value, 1)}
            :error -> unresolved_svg_op("stroke_width", ["value"], op)
          end

        "antialiased" ->
          case WireMap.map_integer_required(op, "value") do
            {:ok, value} -> %{kind: :antialiased, value: value != 0}
            :error -> unresolved_svg_op("antialiased", ["value"], op)
          end

        "stroke_color" ->
          normalize_style_color_op(:stroke_color, op, "stroke_color")

        "fill_color" ->
          normalize_style_color_op(:fill_color, op, "fill_color")

        "text_color" ->
          normalize_style_color_op(:text_color, op, "text_color")

        "compositing_mode" ->
          case WireMap.map_integer_required(op, "value") do
            {:ok, value} -> %{kind: :compositing_mode, value: value}
            :error -> unresolved_svg_op("compositing_mode", ["value"], op)
          end

        "clear" ->
          case WireMap.map_integer_required(op, "color") do
            {:ok, color} -> %{kind: :clear, color: color}
            :error -> unresolved_svg_op("clear", ["color"], op)
          end

        "round_rect" ->
          case WireMap.map_integers_required(op, ["x", "y", "w", "h", "radius", "fill"]) do
            {:ok, [x, y, w, h, radius, fill]} ->
              %{kind: :round_rect, x: x, y: y, w: w, h: h, radius: radius, fill: fill}

            :error ->
              unresolved_svg_op("round_rect", ["x", "y", "w", "h", "radius", "fill"], op)
          end

        "rect" ->
          case WireMap.map_integers_required(op, ["x", "y", "w", "h", "fill"]) do
            {:ok, [x, y, w, h, fill]} -> %{kind: :rect, x: x, y: y, w: w, h: h, fill: fill}
            :error -> unresolved_svg_op("rect", ["x", "y", "w", "h", "fill"], op)
          end

        "fill_rect" ->
          case WireMap.map_integers_required(op, ["x", "y", "w", "h", "fill"]) do
            {:ok, [x, y, w, h, fill]} -> %{kind: :fill_rect, x: x, y: y, w: w, h: h, fill: fill}
            :error -> unresolved_svg_op("fill_rect", ["x", "y", "w", "h", "fill"], op)
          end

        "line" ->
          case WireMap.map_integers_required(op, ["x1", "y1", "x2", "y2", "color"]) do
            {:ok, [x1, y1, x2, y2, color]} ->
              %{kind: :line, x1: x1, y1: y1, x2: x2, y2: y2, color: color}

            :error ->
              unresolved_svg_op("line", ["x1", "y1", "x2", "y2", "color"], op)
          end

        "arc" ->
          case WireMap.map_integers_required(op, ["x", "y", "w", "h", "start_angle", "end_angle"]) do
            {:ok, [x, y, w, h, start_angle, end_angle]} ->
              %{
                kind: :arc,
                x: x,
                y: y,
                w: w,
                h: h,
                start_angle: start_angle,
                end_angle: end_angle
              }

            :error ->
              unresolved_svg_op("arc", ["x", "y", "w", "h", "start_angle", "end_angle"], op)
          end

        "fill_radial" ->
          case WireMap.map_integers_required(op, ["x", "y", "w", "h", "start_angle", "end_angle"]) do
            {:ok, [x, y, w, h, start_angle, end_angle]} ->
              %{
                kind: :fill_radial,
                x: x,
                y: y,
                w: w,
                h: h,
                start_angle: start_angle,
                end_angle: end_angle
              }

            :error ->
              unresolved_svg_op(
                "fill_radial",
                ["x", "y", "w", "h", "start_angle", "end_angle"],
                op
              )
          end

        "path_filled" ->
          case WireMap.map_path_required(op) do
            {:ok, path} ->
              Map.put(path, :kind, :path_filled)

            :error ->
              unresolved_svg_op("path_filled", ["points", "offset_x", "offset_y", "rotation"], op)
          end

        "path_outline" ->
          case WireMap.map_path_required(op) do
            {:ok, path} ->
              Map.put(path, :kind, :path_outline)

            :error ->
              unresolved_svg_op(
                "path_outline",
                ["points", "offset_x", "offset_y", "rotation"],
                op
              )
          end

        "path_outline_open" ->
          case WireMap.map_path_required(op) do
            {:ok, path} ->
              Map.put(path, :kind, :path_outline_open)

            :error ->
              unresolved_svg_op(
                "path_outline_open",
                ["points", "offset_x", "offset_y", "rotation"],
                op
              )
          end

        "circle" ->
          case WireMap.map_integers_required(op, ["cx", "cy", "r", "color"]) do
            {:ok, [cx, cy, r, color]} -> %{kind: :circle, cx: cx, cy: cy, r: r, color: color}
            :error -> unresolved_svg_op("circle", ["cx", "cy", "r", "color"], op)
          end

        "fill_circle" ->
          case WireMap.map_integers_required(op, ["cx", "cy", "r", "color"]) do
            {:ok, [cx, cy, r, color]} -> %{kind: :fill_circle, cx: cx, cy: cy, r: r, color: color}
            :error -> unresolved_svg_op("fill_circle", ["cx", "cy", "r", "color"], op)
          end

        "pixel" ->
          case WireMap.map_integers_required(op, ["x", "y", "color"]) do
            {:ok, [x, y, color]} -> %{kind: :pixel, x: x, y: y, color: color}
            :error -> unresolved_svg_op("pixel", ["x", "y", "color"], op)
          end

        "bitmap_in_rect" ->
          case WireMap.map_integers_required(op, ["bitmap_id", "x", "y", "w", "h"]) do
            {:ok, [bitmap_id, x, y, w, h]} ->
              %{kind: :bitmap_in_rect, bitmap_id: bitmap_id, x: x, y: y, w: w, h: h}
              |> maybe_put_svg_resource(op)

            :error ->
              unresolved_svg_op("bitmap_in_rect", ["bitmap_id", "x", "y", "w", "h"], op)
          end

        "rotated_bitmap" ->
          case WireMap.map_integers_required(op, [
                 "bitmap_id",
                 "src_w",
                 "src_h",
                 "angle",
                 "center_x",
                 "center_y"
               ]) do
            {:ok, [bitmap_id, src_w, src_h, angle, center_x, center_y]} ->
              %{
                kind: :rotated_bitmap,
                bitmap_id: bitmap_id,
                src_w: src_w,
                src_h: src_h,
                angle: angle,
                center_x: center_x,
                center_y: center_y
              }
              |> maybe_put_svg_resource(op)

            :error ->
              unresolved_svg_op(
                "rotated_bitmap",
                ["bitmap_id", "src_w", "src_h", "angle", "center_x", "center_y"],
                op
              )
          end

        "vector_at" ->
          case WireMap.map_integers_required(op, ["vector_id", "x", "y"]) do
            {:ok, [vector_id, x, y]} ->
              %{kind: :vector_at, vector_id: vector_id, x: x, y: y}
              |> maybe_put_svg_resource(op)

            :error ->
              unresolved_svg_op("vector_at", ["vector_id", "x", "y"], op)
          end

        "vector_sequence_at" ->
          case WireMap.map_integers_required(op, ["animation_id", "vector_id", "x", "y"]) do
            {:ok, [animation_id, vector_id, x, y]} ->
              %{kind: :vector_sequence_at, animation_id: animation_id, vector_id: vector_id, x: x, y: y}
              |> maybe_put_svg_resource(op)

            :error ->
              unresolved_svg_op("vector_sequence_at", ["animation_id", "vector_id", "x", "y"], op)
          end

        "bitmap_sequence_at" ->
          case WireMap.map_integers_required(op, ["animation_id", "bitmap_animation_id", "x", "y"]) do
            {:ok, [animation_id, bitmap_animation_id, x, y]} ->
              %{
                kind: :bitmap_sequence_at,
                animation_id: animation_id,
                bitmap_animation_id: bitmap_animation_id,
                x: x,
                y: y
              }
              |> maybe_put_svg_resource(op)

            :error ->
              unresolved_svg_op("bitmap_sequence_at", ["animation_id", "bitmap_animation_id", "x", "y"], op)
          end

        "text_int" ->
          case WireMap.map_integers_required(op, ["x", "y"]) do
            {:ok, [x, y]} ->
              text = to_string(Map.get(op, "text") || Map.get(op, :text) || "")

              if text == "",
                do: unresolved_svg_op("text_int", ["x", "y", "text"], op),
                else: %{kind: :text_int, x: x, y: y, text: text}

            :error ->
              unresolved_svg_op("text_int", ["x", "y", "text"], op)
          end

        "text_label" ->
          case WireMap.map_integers_required(op, ["x", "y"]) do
            {:ok, [x, y]} ->
              text = compact_scene_text_label(op)

              if text == "",
                do: unresolved_svg_op("text_label", ["x", "y", "text"], op),
                else: %{kind: :text_label, x: x, y: y, text: text}

            :error ->
              unresolved_svg_op("text_label", ["x", "y", "text"], op)
          end

        "text" ->
          case WireMap.map_integers_required(op, ["x", "y"]) do
            {:ok, [x, y]} ->
              text = to_string(Map.get(op, "text") || Map.get(op, :text) || "")

              if text == "",
                do: unresolved_svg_op("text", ["x", "y", "text"], op),
                else: text_box_svg_op(op, x, y, text)

            :error ->
              unresolved_svg_op("text", ["x", "y", "text"], op)
          end

        "unresolved" ->
          unresolved_svg_op(
            to_string(Map.get(op, "node_type") || Map.get(op, :node_type) || "node"),
            [],
            op
          )

        _ ->
          nil
      end

    maybe_put_svg_source(normalized, op)
  end

  def normalize(_op), do: nil

  @spec maybe_put_svg_source(svg_op(), wire_map()) :: svg_op()
  defp maybe_put_svg_source(%{} = normalized, original) when is_map(original) do
    case Map.get(original, "source") || Map.get(original, :source) do
      %{} = source -> Map.put(normalized, :source, source)
      _ -> normalized
    end
  end

  defp maybe_put_svg_source(normalized, _original), do: normalized

  @spec maybe_put_svg_resource(svg_op(), wire_map()) :: svg_op()
  defp maybe_put_svg_resource(op, original) when is_map(op) and is_map(original) do
    case Map.get(original, "resource") || Map.get(original, :resource) do
      value when is_binary(value) or is_atom(value) -> Map.put(op, :resource, value)
      %{"ctor" => ctor} -> Map.put(op, :resource, ctor)
      %{ctor: ctor} -> Map.put(op, :resource, ctor)
      _ -> op
    end
  end

  defp maybe_put_svg_resource(op, _original), do: op

  @spec text_box_svg_op(wire_map(), integer(), integer(), String.t()) :: svg_op()
  defp text_box_svg_op(op, x, y, text) when is_map(op) and is_integer(x) and is_integer(y) do
    base = %{kind: :text_label, x: x, y: y, text: text}

    case WireMap.map_integers_required(op, ["w", "h"]) do
      {:ok, [w, h]} ->
        Map.merge(base, %{
          w: w,
          h: h,
          text_align:
            SvgTextOptions.normalized_alignment(
              Map.get(op, "text_align") || Map.get(op, :text_align)
            ),
          text_overflow:
            SvgTextOptions.normalized_overflow(
              Map.get(op, "text_overflow") || Map.get(op, :text_overflow)
            ),
          font_size: h
        })

      :error ->
        base
    end
  end

  @spec normalize_style_color_op(atom(), wire_map(), String.t(), String.t()) :: svg_op()
  defp normalize_style_color_op(kind, op, node_type, value_key \\ "color")
       when is_atom(kind) and is_map(op) and is_binary(node_type) and is_binary(value_key) do
    value =
      case WireMap.map_integer_required(op, value_key) do
        {:ok, color} ->
          {:ok, color}

        :error when value_key == "color" ->
          WireMap.map_integer_required(op, "value")

        :error ->
          :error
      end

    case value do
      {:ok, color} -> %{kind: kind, color: color}
      :error -> unresolved_svg_op(node_type, [value_key], op)
    end
  end

  @spec unresolved_svg_op(String.t(), [String.t()], wire_map()) :: svg_op()
  defp unresolved_svg_op(node_type, required_keys, op) do
    %{
      kind: :unresolved,
      node_type: to_string(node_type),
      required_keys: required_keys,
      provided_int_count: WireMap.map_integer(op, "provided_int_count", 0),
      required_int_count: WireMap.map_integer(op, "required_int_count", length(required_keys))
    }
  end
end
