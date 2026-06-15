defmodule IdeWeb.WorkspaceLive.DebuggerPreview.SvgStyle do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: PreviewTypes

  @type svg_op :: PreviewTypes.svg_op()
  @type svg_style :: PreviewTypes.svg_style()
  @type wire_value :: PreviewTypes.wire_value()

  @spec apply_state([svg_op()]) :: [svg_op()]
  def apply_state(ops) when is_list(ops) do
    {rows, _stack} =
      Enum.reduce(ops, {[], [default()]}, fn op, {rows, stack} ->
        style = List.first(stack) || default()

        case op.kind do
          :push_context ->
            {rows, [style | stack]}

          :pop_context ->
            {rows, pop(stack)}

          :stroke_width ->
            {rows, update(stack, :stroke_width, op.value)}

          :antialiased ->
            {rows, update(stack, :antialiased, op.value)}

          :stroke_color ->
            {rows, update(stack, :stroke_color, op.color)}

          :fill_color ->
            {rows, update(stack, :fill_color, op.color)}

          :text_color ->
            {rows, update(stack, :text_color, op.color)}

          :compositing_mode ->
            {rows, update(stack, :compositing_mode, op.value)}

          _ ->
            {[apply_to_op(op, style) | rows], stack}
        end
      end)

    Enum.reverse(rows)
  end

  @spec default() :: svg_style()
  defp default do
    %{
      stroke_color: nil,
      fill_color: nil,
      text_color: nil,
      stroke_width: 1,
      antialiased: true,
      compositing_mode: 0
    }
  end

  @spec pop([svg_style()]) :: [svg_style()]
  defp pop([_current, parent | rest]), do: [parent | rest]
  defp pop(stack), do: stack

  @spec update([svg_style()], atom(), wire_value()) :: [svg_style()]
  defp update([style | rest], key, value), do: [Map.put(style, key, value) | rest]
  defp update([], key, value), do: [Map.put(default(), key, value)]

  @spec apply_to_op(svg_op(), svg_style()) :: svg_op()
  defp apply_to_op(%{kind: :unresolved} = op, _style), do: op
  defp apply_to_op(%{kind: :clear} = op, _style), do: op

  defp apply_to_op(%{kind: kind} = op, style)
       when kind in [
              :line,
              :rect,
              :round_rect,
              :arc,
              :path_outline,
              :path_outline_open,
              :circle,
              :pixel
            ] do
    op
    |> Map.put(
      :stroke_color,
      style_color(style, :stroke_color, Map.get(op, :color) || Map.get(op, :fill))
    )
    |> Map.put(:stroke_width, style.stroke_width || 1)
    |> put_common(style)
  end

  defp apply_to_op(%{kind: kind} = op, style)
       when kind in [:fill_rect, :fill_circle, :path_filled, :fill_radial] do
    op
    |> Map.put(
      :fill_color,
      style_color(style, :fill_color, Map.get(op, :color) || Map.get(op, :fill))
    )
    |> Map.put(
      :stroke_color,
      style_color(style, :stroke_color, Map.get(op, :color) || Map.get(op, :fill))
    )
    |> Map.put(:stroke_width, style.stroke_width || 1)
    |> put_common(style)
  end

  defp apply_to_op(%{kind: kind} = op, style) when kind in [:text_int, :text_label] do
    op
    |> Map.put(:text_color, style_color(style, :text_color, Map.get(op, :color)))
    |> put_common(style)
  end

  defp apply_to_op(op, style), do: put_common(op, style)

  @spec put_common(svg_op(), svg_style()) :: svg_op()
  defp put_common(op, style) do
    op
    |> Map.put(:antialiased, style.antialiased)
    |> Map.put(:compositing_mode, style.compositing_mode)
  end

  @spec style_color(svg_style(), atom(), wire_value()) :: integer() | nil
  defp style_color(style, key, fallback), do: Map.get(style, key) || fallback
end
