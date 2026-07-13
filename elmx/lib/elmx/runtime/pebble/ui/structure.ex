defmodule Elmx.Runtime.Pebble.Ui.Structure do
  @moduledoc false

  alias Elmx.Runtime.Pebble.Ui.Helpers
  alias Elmx.Types

  def window_stack(windows) when is_list(windows),
    do: %{type: "windowStack", label: "", children: Enum.map(windows, &Helpers.normalize_child/1)}

  @spec window(Types.ui_layer_id(), [Types.ui_node()]) :: Types.ui_node()
  def window(id, layers) do
    children = [Helpers.expr_node(id) | Enum.map(layers, &Helpers.normalize_child/1)]
    %{type: "window", label: "", children: children}
  end

  @spec canvas_layer(Types.ui_layer_id(), [Types.ui_node()]) :: Types.ui_node()
  def canvas_layer(z, ops) do
    %{type: "canvasLayer", label: "", children: [Helpers.expr_node(z) | Enum.map(ops, &Helpers.draw_op/1)]}
  end

  @spec group(Types.wire_map()) :: Types.ui_node()
  def group(%{style: style, ops: ops}) when is_map(style) do
    %{type: "group", label: "", children: Enum.map(ops, &Helpers.draw_op/1), style: style}
  end

  def group(other), do: %{type: "group", label: "", children: [Helpers.normalize_child(other)]}

  @spec context([Types.ui_node()], [Types.ui_node()]) :: Types.ui_node()
  def context(settings, ops) when is_list(settings) and is_list(ops) do
    %{type: "group", label: "", children: Enum.map(ops, &Helpers.draw_op/1), style: Helpers.context_style(settings)}
  end

  @spec to_ui_node([Types.ui_node()]) :: Types.ui_node()
  def to_ui_node(ops) when is_list(ops) do
    window_stack([
      window(1, [
        canvas_layer(1, ops)
      ])
    ])
  end

  def to_ui_node(node), do: Helpers.normalize_child(node)


end
