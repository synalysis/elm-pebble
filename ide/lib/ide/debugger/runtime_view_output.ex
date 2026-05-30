defmodule Ide.Debugger.RuntimeViewOutput do
  @moduledoc false

  alias Ide.Debugger.Types
  alias Ide.Debugger.WireValues

  @spec normalize_view_output(list()) :: Types.runtime_view_nodes()
  def normalize_view_output(value) when is_list(value), do: value
  def normalize_view_output(_), do: []
  @spec tree(Types.app_model(), Types.surface_target()) :: Types.view_output_tree() | nil
  def tree(model, target)
       when is_map(model) and target in [:watch, :companion, :phone] do
    case normalize_view_output(
           Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output)
         ) do
      [] ->
        nil

      ops ->
        {screen_w, screen_h} = runtime_view_output_screen(model)
        op_nodes = runtime_view_output_nodes(ops)

        %{
          "type" => "windowStack",
          "label" => "",
          "box" => %{"x" => 0, "y" => 0, "w" => screen_w, "h" => screen_h},
          "children" => [
            %{
              "type" => "window",
              "label" => "",
              "id" => 1,
              "children" => [
                %{
                  "type" => "canvasLayer",
                  "label" => "",
                  "id" => 1,
                  "children" => op_nodes
                }
              ]
            }
          ]
        }
    end
  end

  def tree(_model, _target), do: nil

  @spec runtime_view_output_screen(Types.app_model()) :: {pos_integer(), pos_integer()}
  def runtime_view_output_screen(model) when is_map(model) do
    runtime_model =
      case Map.get(model, "runtime_model") || Map.get(model, :runtime_model) do
        %{} = value -> value
        _ -> model
      end

    {
      positive_integer_value(
        Map.get(runtime_model, "screenW") || Map.get(runtime_model, :screenW),
        144
      ),
      positive_integer_value(
        Map.get(runtime_model, "screenH") || Map.get(runtime_model, :screenH),
        168
      )
    }
  end

  @spec positive_integer_value(Types.wire_input(), pos_integer()) :: pos_integer()
  def positive_integer_value(value, _fallback) when is_integer(value) and value > 0, do: value

  def positive_integer_value(value, _fallback) when is_float(value) and value > 0,
    do: trunc(value)

  def positive_integer_value(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  def positive_integer_value(_value, fallback), do: fallback

  @spec runtime_view_output_nodes(Types.runtime_view_nodes()) :: [Types.view_output_tree()]
  def runtime_view_output_nodes(ops) when is_list(ops) do
    {nodes, _rest} = runtime_view_output_nodes_until(ops, false)
    nodes
  end

  @spec runtime_view_output_nodes_until(Types.runtime_view_nodes(), boolean()) ::
          {[Types.view_output_tree()], Types.runtime_view_nodes()}
  def runtime_view_output_nodes_until(rows, stop_on_pop?) when is_list(rows) do
    runtime_view_output_nodes_until(rows, stop_on_pop?, [])
  end

  def runtime_view_output_nodes_until([], _stop_on_pop?, acc), do: {Enum.reverse(acc), []}

  def runtime_view_output_nodes_until([row | rest], stop_on_pop?, acc) when is_map(row) do
    case runtime_view_output_kind(row) do
      "pop_context" when stop_on_pop? ->
        {Enum.reverse(acc), rest}

      "pop_context" ->
        runtime_view_output_nodes_until(rest, stop_on_pop?, acc)

      "push_context" ->
        {group_nodes, remaining} = runtime_view_output_nodes_until(rest, true)
        {style, children} = split_runtime_view_output_group(group_nodes)

        group =
          %{"type" => "group", "label" => "", "children" => children}
          |> maybe_put_group_style(style)

        runtime_view_output_nodes_until(remaining, stop_on_pop?, [group | acc])

      kind when kind in ["stroke_color", "fill_color", "text_color"] ->
        runtime_view_output_nodes_until(rest, stop_on_pop?, [
          runtime_view_output_style_node(row) | acc
        ])

      _ ->
        case runtime_view_output_node(row) do
          %{} = node -> runtime_view_output_nodes_until(rest, stop_on_pop?, [node | acc])
          nil -> runtime_view_output_nodes_until(rest, stop_on_pop?, acc)
        end
    end
  end

  @spec split_runtime_view_output_group([Types.view_output_tree()]) ::
          {Types.wire_map(), [Types.view_output_tree()]}
  def split_runtime_view_output_group(nodes) when is_list(nodes) do
    Enum.reduce(nodes, {%{}, []}, fn node, {style, children} ->
      case Map.get(node, "type") do
        "style" ->
          {Map.put(style, Map.get(node, "key"), Map.get(node, "value")), children}

        _ ->
          {style, [node | children]}
      end
    end)
    |> then(fn {style, children} -> {style, Enum.reverse(children)} end)
  end

  @spec maybe_put_group_style(Types.view_output_tree(), Types.wire_map()) :: Types.view_output_tree()
  def maybe_put_group_style(group, style) when is_map(group) and map_size(style) > 0,
    do: Map.put(group, "style", style)

  def maybe_put_group_style(group, _style), do: group

  @spec runtime_view_output_style_node(Types.view_output_node()) :: Types.view_output_tree()
  def runtime_view_output_style_node(row) when is_map(row) do
    kind = runtime_view_output_kind(row)

    %{
      "type" => "style",
      "key" => kind,
      "value" => WireValues.map_value(row, "color") || WireValues.map_value(row, "value")
    }
  end

  @spec runtime_view_output_node(Types.view_output_node()) :: Types.view_output_tree() | nil
  def runtime_view_output_node(row) when is_map(row) do
    case runtime_view_output_kind(row) do
      "clear" ->
        %{
          "type" => "clear",
          "label" => "",
          "children" => [],
          "color" => integer_or_zero(WireValues.map_value(row, "color"))
        }
        |> maybe_put_rendered_source(row)

      "round_rect" ->
        %{
          "type" => "roundRect",
          "label" => "",
          "children" => [],
          "x" => integer_or_zero(WireValues.map_value(row, "x")),
          "y" => integer_or_zero(WireValues.map_value(row, "y")),
          "w" => integer_or_zero(WireValues.map_value(row, "w")),
          "h" => integer_or_zero(WireValues.map_value(row, "h")),
          "radius" => integer_or_zero(WireValues.map_value(row, "radius")),
          "fill" => integer_or_zero(WireValues.map_value(row, "fill"))
        }
        |> maybe_put_rendered_source(row)

      "fill_rect" ->
        %{
          "type" => "fillRect",
          "label" => "",
          "children" => [],
          "x" => integer_or_zero(WireValues.map_value(row, "x")),
          "y" => integer_or_zero(WireValues.map_value(row, "y")),
          "w" => integer_or_zero(WireValues.map_value(row, "w")),
          "h" => integer_or_zero(WireValues.map_value(row, "h")),
          "fill" => integer_or_zero(WireValues.map_value(row, "fill"))
        }
        |> maybe_put_rendered_source(row)

      "line" ->
        %{
          "type" => "line",
          "label" => "",
          "children" => [],
          "x1" => integer_or_zero(WireValues.map_value(row, "x1")),
          "y1" => integer_or_zero(WireValues.map_value(row, "y1")),
          "x2" => integer_or_zero(WireValues.map_value(row, "x2")),
          "y2" => integer_or_zero(WireValues.map_value(row, "y2")),
          "color" => integer_or_zero(WireValues.map_value(row, "color"))
        }
        |> maybe_put_rendered_source(row)

      "circle" ->
        %{
          "type" => "circle",
          "label" => "",
          "children" => [],
          "cx" => integer_or_zero(WireValues.map_value(row, "cx")),
          "cy" => integer_or_zero(WireValues.map_value(row, "cy")),
          "r" => integer_or_zero(WireValues.map_value(row, "r")),
          "color" => integer_or_zero(WireValues.map_value(row, "color"))
        }
        |> maybe_put_rendered_source(row)

      "fill_circle" ->
        %{
          "type" => "fillCircle",
          "label" => "",
          "children" => [],
          "cx" => integer_or_zero(WireValues.map_value(row, "cx")),
          "cy" => integer_or_zero(WireValues.map_value(row, "cy")),
          "r" => integer_or_zero(WireValues.map_value(row, "r")),
          "color" => integer_or_zero(WireValues.map_value(row, "color"))
        }
        |> maybe_put_rendered_source(row)

      "pixel" ->
        %{
          "type" => "pixel",
          "label" => "",
          "children" => [],
          "x" => integer_or_zero(WireValues.map_value(row, "x")),
          "y" => integer_or_zero(WireValues.map_value(row, "y")),
          "color" => integer_or_zero(WireValues.map_value(row, "color"))
        }
        |> maybe_put_rendered_source(row)

      "text" ->
        %{
          "type" => "text",
          "label" => "",
          "children" => [],
          "x" => integer_or_zero(WireValues.map_value(row, "x")),
          "y" => integer_or_zero(WireValues.map_value(row, "y")),
          "w" => integer_or_zero(WireValues.map_value(row, "w")),
          "h" => integer_or_zero(WireValues.map_value(row, "h")),
          "font_id" => integer_or_zero(WireValues.map_value(row, "font_id")),
          "text" => to_string(WireValues.map_value(row, "text") || ""),
          "text_align" => to_string(WireValues.map_value(row, "text_align") || "center"),
          "text_overflow" => to_string(WireValues.map_value(row, "text_overflow") || "word_wrap")
        }
        |> maybe_put_rendered_source(row)

      "text_label" ->
        %{
          "type" => "textLabel",
          "label" => "",
          "children" => [],
          "x" => integer_or_zero(WireValues.map_value(row, "x")),
          "y" => integer_or_zero(WireValues.map_value(row, "y")),
          "font_id" => integer_or_zero(WireValues.map_value(row, "font_id")),
          "text" => to_string(WireValues.map_value(row, "text") || "")
        }
        |> maybe_put_rendered_source(row)

      "vector_at" ->
        %{
          "type" => "drawVectorAt",
          "label" => "",
          "children" => [],
          "vector_id" => integer_or_zero(WireValues.map_value(row, "vector_id")),
          "x" => integer_or_zero(WireValues.map_value(row, "x")),
          "y" => integer_or_zero(WireValues.map_value(row, "y"))
        }
        |> maybe_put_rendered_source(row)

      "vector_sequence_at" ->
        %{
          "type" => "drawVectorSequenceAt",
          "label" => "",
          "children" => [],
          "vector_id" => integer_or_zero(WireValues.map_value(row, "vector_id")),
          "x" => integer_or_zero(WireValues.map_value(row, "x")),
          "y" => integer_or_zero(WireValues.map_value(row, "y"))
        }
        |> maybe_put_rendered_source(row)

      "bitmap_sequence_at" ->
        %{
          "type" => "drawBitmapSequenceAt",
          "label" => "",
          "children" => [],
          "animation_id" => integer_or_zero(WireValues.map_value(row, "animation_id")),
          "x" => integer_or_zero(WireValues.map_value(row, "x")),
          "y" => integer_or_zero(WireValues.map_value(row, "y"))
        }
        |> maybe_put_rendered_source(row)

      _ ->
        nil
    end
  end

  @spec maybe_put_rendered_source(Types.view_output_tree(), Types.wire_map()) ::
          Types.view_output_tree()
  def maybe_put_rendered_source(node, row) when is_map(node) and is_map(row) do
    case WireValues.map_value(row, "source") do
      %{} = source -> Map.put(node, "source", source)
      _ -> node
    end
  end

  @spec runtime_view_output_kind(Types.view_output_node()) :: String.t()
  def runtime_view_output_kind(row) when is_map(row),
    do: to_string(WireValues.map_value(row, "kind") || "")

  @spec integer_or_zero(Types.wire_input()) :: non_neg_integer()
  defp integer_or_zero(value) when is_integer(value) and value >= 0, do: value

  defp integer_or_zero(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed >= 0 -> parsed
      _ -> 0
    end
  end

  defp integer_or_zero(_), do: 0
end
