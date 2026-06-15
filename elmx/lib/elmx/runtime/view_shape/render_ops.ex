defmodule Elmx.Runtime.ViewShape.RenderOps do
  @moduledoc false

  alias Elmx.Runtime.Pebble.Ui, as: PebbleUi
  alias Elmx.Runtime.ViewShape
  alias Elmx.Runtime.ViewShape.Keys
  alias Elmx.Types

  @render_op_types MapSet.new(~w(
    clear fillRect rect roundRect line circle fillCircle pixel
    drawVectorAt drawVectorSequenceAt drawBitmapInRect drawBitmapSequenceAt
    drawRotatedBitmap arc fillRadial text textLabel textInt
    path pathFilled pathOutline pathOutlineOpen group
  ))

  @spec normalize_render_op_list([Types.render_op_input()]) ::
          {:ok, Types.view_output_tree()} | :error
  def normalize_render_op_list(ops) when is_list(ops) do
    ops =
      Enum.map(ops, fn
        %{"type" => _} = op -> Keys.stringify_keys(op)
        %{type: _} = op -> Keys.stringify_keys(op)
        other -> ViewShape.coerce(other)
      end)

    if render_op_list?(ops) do
      tree =
        PebbleUi.window_stack([
          PebbleUi.window(1, [
            PebbleUi.canvas_layer(1, ops)
          ])
        ])

      {:ok, Keys.stringify_keys(tree)}
    else
      :error
    end
  end

  def render_op_list?(ops) when is_list(ops),
    do: Enum.all?(ops, &render_op_shape?/1)

  def render_op_shape?(%{"type" => type}) when is_binary(type), do: draw_op_type?(type)
  def render_op_shape?(%{type: type}) when is_binary(type) or is_atom(type), do: draw_op_type?(to_string(type))
  def render_op_shape?(_), do: false

  def draw_op_type?(type) when is_binary(type), do: MapSet.member?(@render_op_types, type)
end
