defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Summary do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.{Expr, Normalize, ViewOutput}
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Util

  @type rendered_node :: Types.rendered_node()
  @type model_map :: Types.model_map()
  @type runtime_input :: Types.runtime_input()
  @type runtime_value :: Types.runtime_value()

  @spec rendered_view_preview(runtime_input() | nil) :: String.t()
  def rendered_view_preview(nil), do: "(no snapshot)"

  def rendered_view_preview(runtime) when is_map(runtime) do
    tree = Map.get(runtime, :view_tree) || Map.get(runtime, "view_tree")
    model = preview_runtime_model(runtime)
    runtime_ops = ViewOutput.preview_lines(runtime)

    case tree do
      %{} = node ->
        tree_text = format_rendered_node(node, 0, model, nil) |> String.trim_trailing()
        Util.join_preview_sections(runtime_ops, tree_text)

      _ ->
        "(no rendered view in snapshot)"
    end
  end

  def rendered_view_preview(_), do: "(no snapshot)"

  @spec format_rendered_node(rendered_node(), non_neg_integer(), model_map(), String.t() | nil) ::
          String.t()
  defp format_rendered_node(node, depth, model, arg_name)
       when is_map(node) and is_integer(depth) and is_map(model) do
    indent = String.duplicate("  ", max(depth, 0))
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "node")

    children = Map.get(node, "children") || Map.get(node, :children) || []

    child_text =
      children
      |> Enum.filter(&is_map/1)
      |> rendered_child_rows(node)
      |> Enum.map_join("", fn {child, child_arg_name} ->
        format_rendered_node(child, depth + 1, model, child_arg_name)
      end)

    if hidden_rendered_node_type?(type) do
      child_text
    else
      summary = rendered_node_summary(node, model, arg_name)

      "#{indent}- #{summary}\n#{child_text}"
    end
  end

  defp format_rendered_node(_node, _depth, _model, _arg_name), do: ""

  @spec hidden_rendered_node_type?(String.t()) :: boolean()
  defp hidden_rendered_node_type?(type) when is_binary(type) do
    type in ["debuggerRenderStep", "elmcRuntimeStep"]
  end

  @spec render_suffix(String.t() | integer() | nil) :: String.t()
  defp render_suffix(""), do: ""
  defp render_suffix(nil), do: ""
  defp render_suffix(value), do: "[#{value}]"

  @spec rendered_node_summary(rendered_node(), model_map(), String.t() | nil) :: String.t()
  def rendered_node_summary(node, model, arg_name \\ nil)

  def rendered_node_summary(node, model, arg_name) when is_map(node) and is_map(model) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "node")
    label = Map.get(node, "label") || Map.get(node, :label) || ""
    text = Map.get(node, "text") || Map.get(node, :text) || ""
    value_hint = rendered_value_hint(node, model)
    value = rendered_node_value(node, value_hint)
    arg_name = rendered_arg_name(arg_name)
    detail = rendered_node_detail_suffix(node)

    cond do
      arg_name != nil and value != "" ->
        [value, render_suffix(arg_name), detail]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" ")

      arg_name != nil ->
        [type, render_suffix(arg_name), detail]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" ")

      true ->
        [type, render_suffix(label), render_suffix(text), render_suffix(value_hint), detail]
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()
        |> Enum.join(" ")
    end
  end

  def rendered_node_summary(_node, _model, _arg_name), do: "node"

  @spec rendered_node_detail_suffix(rendered_node()) :: String.t()
  defp rendered_node_detail_suffix(node) when is_map(node) do
    fields =
      node
      |> rendered_detail_fields()
      |> Enum.flat_map(fn field ->
        case map_scalar_detail(node, field) do
          "" -> []
          value -> ["#{field}=#{rendered_detail_value(node, field, value)}"]
        end
      end)

    child_count = rendered_visible_child_count(node)
    count_suffix = rendered_child_count_suffix(node, child_count)

    (fields ++ List.wrap(count_suffix))
    |> Enum.reject(&(&1 in ["", nil]))
    |> case do
      [] -> ""
      parts -> "(" <> Enum.join(parts, ", ") <> ")"
    end
  end

  @spec rendered_detail_value(rendered_node(), String.t(), String.t()) :: String.t()
  defp rendered_detail_value(node, field, value)
       when is_map(node) and is_binary(field) and is_binary(value) do
    if rendered_color_field?(node, field) do
      color_value = scalar_map_value(node, field)

      case rendered_color_label(color_value) do
        "" -> value
        label -> "#{value} #{label}"
      end
    else
      value
    end
  end

  @spec rendered_color_field?(rendered_node(), String.t()) :: boolean()
  defp rendered_color_field?(node, field) when is_map(node) and is_binary(field) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")

    field in rendered_node_color_fields(type)
  end

  @spec rendered_node_color_fields(String.t()) :: [String.t()]
  defp rendered_node_color_fields(type) do
    case type do
      "clear" -> ["color"]
      "pixel" -> ["color"]
      "line" -> ["color"]
      "rect" -> ["color"]
      "fillRect" -> ["fill"]
      "circle" -> ["color"]
      "fillCircle" -> ["color"]
      "roundRect" -> ["fill"]
      _ -> []
    end
  end

  @spec rendered_color_label(integer()) :: String.t()
  defp rendered_color_label(value) when is_integer(value) and value >= 0 and value <= 255 do
    name = pebble_color_name(value)
    hex = pebble_color_hex(value)

    case name do
      "" -> "(#{hex})"
      _ -> "(#{name}, #{hex})"
    end
  end

  defp rendered_color_label(_value), do: ""

  @spec pebble_color_name(integer()) :: String.t()
  defp pebble_color_name(value) do
    case value do
      0x00 -> "clearColor"
      0xC0 -> "black"
      0xC1 -> "oxfordBlue"
      0xC2 -> "dukeBlue"
      0xC3 -> "blue"
      0xC4 -> "darkGreen"
      0xC5 -> "midnightGreen"
      0xC6 -> "cobaltBlue"
      0xC7 -> "blueMoon"
      0xC8 -> "islamicGreen"
      0xC9 -> "jaegerGreen"
      0xCA -> "tiffanyBlue"
      0xCB -> "vividCerulean"
      0xCC -> "green"
      0xCD -> "malachite"
      0xCE -> "mediumSpringGreen"
      0xCF -> "cyan"
      0xD0 -> "bulgarianRose"
      0xD1 -> "imperialPurple"
      0xD2 -> "indigo"
      0xD3 -> "electricUltramarine"
      0xD4 -> "armyGreen"
      0xD5 -> "darkGray"
      0xD6 -> "liberty"
      0xD7 -> "veryLightBlue"
      0xD8 -> "kellyGreen"
      0xD9 -> "mayGreen"
      0xDA -> "cadetBlue"
      0xDB -> "pictonBlue"
      0xDC -> "brightGreen"
      0xDD -> "screaminGreen"
      0xDE -> "mediumAquamarine"
      0xDF -> "electricBlue"
      0xE0 -> "darkCandyAppleRed"
      0xE1 -> "jazzberryJam"
      0xE2 -> "purple"
      0xE3 -> "vividViolet"
      0xE4 -> "windsorTan"
      0xE5 -> "roseVale"
      0xE6 -> "purpureus"
      0xE7 -> "lavenderIndigo"
      0xE8 -> "limerick"
      0xE9 -> "brass"
      0xEA -> "lightGray"
      0xEB -> "babyBlueEyes"
      0xEC -> "springBud"
      0xED -> "inchworm"
      0xEE -> "mintGreen"
      0xEF -> "celeste"
      0xF0 -> "red"
      0xF1 -> "folly"
      0xF2 -> "fashionMagenta"
      0xF3 -> "magenta"
      0xF4 -> "orange"
      0xF5 -> "sunsetOrange"
      0xF6 -> "brilliantRose"
      0xF7 -> "shockingPink"
      0xF8 -> "chromeYellow"
      0xF9 -> "rajah"
      0xFA -> "melon"
      0xFB -> "richBrilliantLavender"
      0xFC -> "yellow"
      0xFD -> "icterine"
      0xFE -> "pastelYellow"
      0xFF -> "white"
      _ -> ""
    end
  end

  @spec pebble_color_hex(integer()) :: String.t()
  defp pebble_color_hex(value) when is_integer(value) do
    alpha = value |> Bitwise.bsr(6) |> Bitwise.band(0x03)
    red = value |> Bitwise.bsr(4) |> Bitwise.band(0x03)
    green = value |> Bitwise.bsr(2) |> Bitwise.band(0x03)
    blue = Bitwise.band(value, 0x03)

    [red, green, blue, alpha]
    |> Enum.map(&color_2bit_to_hex/1)
    |> Enum.join()
    |> then(&"##{&1}")
  end

  @spec color_2bit_to_hex(integer()) :: String.t()
  defp color_2bit_to_hex(value) when is_integer(value) do
    value
    |> max(0)
    |> min(3)
    |> Kernel.*(85)
    |> Integer.to_string(16)
    |> String.pad_leading(2, "0")
  end

  @spec rendered_detail_fields(rendered_node()) :: [String.t()]
  defp rendered_detail_fields(node) when is_map(node) do
    type = Map.get(node, "type") || Map.get(node, :type)
    base = Normalize.node_arg_fields(type)

    if Map.has_key?(node, "id") or Map.has_key?(node, :id) do
      ["id" | base]
    else
      base
    end
  end

  @spec map_scalar_detail(rendered_node(), String.t()) :: String.t()
  defp map_scalar_detail(node, field) when is_map(node) and is_binary(field) do
    node
    |> scalar_map_value(field)
    |> rendered_scalar_value()
  end

  @spec scalar_map_value(rendered_node(), String.t()) :: Types.runtime_value()
  defp scalar_map_value(node, field) when is_map(node) and is_binary(field) do
    cond do
      Map.has_key?(node, field) ->
        Map.get(node, field)

      true ->
        node
        |> Enum.find_value(fn
          {key, value} when is_atom(key) ->
            if Atom.to_string(key) == field, do: {:ok, value}, else: nil

          _ ->
            nil
        end)
        |> case do
          {:ok, value} -> value
          _ -> nil
        end
    end
  end

  @spec rendered_visible_child_count(rendered_node()) :: non_neg_integer()
  defp rendered_visible_child_count(node) when is_map(node) do
    node
    |> Map.get("children", Map.get(node, :children, []))
    |> Enum.filter(fn
      %{} = child ->
        type = to_string(Map.get(child, "type") || Map.get(child, :type) || "")
        not hidden_rendered_node_type?(type)

      _ ->
        false
    end)
    |> length()
  end

  @spec rendered_child_count_suffix(rendered_node(), non_neg_integer()) :: String.t() | nil
  defp rendered_child_count_suffix(node, child_count) when is_map(node) and child_count > 0 do
    case to_string(Map.get(node, "type") || Map.get(node, :type) || "") do
      "windowStack" -> "#{child_count} #{pluralize("window", child_count)}"
      "window" -> "#{child_count} #{pluralize("layer", child_count)}"
      "canvasLayer" -> "#{child_count} #{pluralize("op", child_count)}"
      "group" -> "#{child_count} #{pluralize("op", child_count)}"
      _ -> nil
    end
  end

  defp rendered_child_count_suffix(_node, _child_count), do: nil

  @spec pluralize(String.t(), non_neg_integer()) :: String.t()
  defp pluralize(noun, 1), do: noun
  defp pluralize(noun, _count), do: noun <> "s"

  @spec rendered_child_rows([rendered_node()], rendered_node()) ::
          [{rendered_node(), String.t() | nil}]
  defp rendered_child_rows(children, parent) when is_list(children) and is_map(parent) do
    arg_names = rendered_node_arg_names(parent, length(children))

    children
    |> Enum.with_index()
    |> Enum.map(fn {child, index} ->
      {child, Enum.at(arg_names, index)}
    end)
  end

  @spec rendered_arg_name(rendered_node()) :: String.t() | nil
  defp rendered_arg_name(name) when is_binary(name) do
    trimmed = String.trim(name)
    if trimmed == "", do: nil, else: trimmed
  end

  defp rendered_arg_name(_name), do: nil

  @spec rendered_node_arg_names(rendered_node(), non_neg_integer()) :: [String.t()]
  defp rendered_node_arg_names(parent, child_count)
       when is_map(parent) and is_integer(child_count) do
    explicit = Map.get(parent, "arg_names") || Map.get(parent, :arg_names) || []

    if explicit != [] do
      explicit
    else
      []
    end
  end

  @spec rendered_node_value(rendered_node(), String.t()) :: String.t()
  defp rendered_node_value(node, value_hint) when is_map(node) do
    cond do
      value_hint not in [nil, ""] ->
        to_string(value_hint)

      Map.has_key?(node, "value") ->
        rendered_scalar_value(Map.get(node, "value"))

      true ->
        rendered_label_value(node)
    end
  end

  @spec rendered_label_value(rendered_node()) :: String.t()
  defp rendered_label_value(node) when is_map(node) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")
    label = Map.get(node, "label") || Map.get(node, :label)

    if type in ["expr", "var"] do
      rendered_scalar_value(label)
    else
      ""
    end
  end

  @spec rendered_scalar_value(Types.runtime_value()) :: String.t()
  defp rendered_scalar_value(value) when is_integer(value), do: Integer.to_string(value)

  defp rendered_scalar_value(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 2)

  defp rendered_scalar_value(value) when is_binary(value), do: value
  defp rendered_scalar_value(value) when is_boolean(value), do: to_string(value)
  defp rendered_scalar_value(_value), do: ""

  @spec preview_runtime_model(runtime_input()) :: model_map()
  defp preview_runtime_model(runtime) when is_map(runtime) do
    nested = Map.get(runtime, :model) || Map.get(runtime, "model")

    cond do
      is_map(nested) ->
        Map.get(nested, "runtime_model") || Map.get(nested, :runtime_model) || nested

      is_map(Map.get(runtime, "runtime_model")) ->
        Map.get(runtime, "runtime_model")

      is_map(Map.get(runtime, :runtime_model)) ->
        Map.get(runtime, :runtime_model)

      true ->
        runtime
    end
  end

  @spec rendered_value_hint(Types.runtime_value(), model_map()) :: String.t() | nil
  defp rendered_value_hint(node, model) when is_map(node) and is_map(model) do
    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")
    label = to_string(Map.get(node, "label") || Map.get(node, :label) || "")
    op = to_string(Map.get(node, "op") || Map.get(node, :op) || "")
    preview_model = preview_runtime_model(model)

    cond do
      type == "field" ->
        node
        |> rendered_node_children()
        |> List.first()
        |> rendered_value_hint(preview_model) ||
          (node
           |> rendered_node_children()
           |> List.first()
           |> evaluated_rendered_scalar_hint(preview_model))

      type == "call" and label == "__idiv__" ->
        evaluate_rendered_binop_hint(node, preview_model, div: 2)

      type == "call" ->
        evaluated_rendered_scalar_hint(node, model)

      type == "expr" and op in ["tuple_first_expr", "tuple_second_expr"] ->
        evaluated_rendered_scalar_hint(node, model)

      type == "expr" and op == "field_access" and String.starts_with?(label, "model.") ->
        evaluated_rendered_scalar_hint(node, model) ||
          label
          |> String.replace_prefix("model.", "")
          |> then(&Map.get(preview_model, &1))
          |> rendered_int_hint()

      type == "var" ->
        evaluated_rendered_scalar_hint(node, model) || rendered_int_hint(Map.get(model, label))

      true ->
        nil
    end
  end

  defp rendered_value_hint(_node, _model), do: nil

  @spec evaluate_rendered_binop_hint(rendered_node(), model_map(), [div: pos_integer()]) ::
          String.t() | nil
  defp evaluate_rendered_binop_hint(node, model, div: _divisor) when is_map(node) and is_map(model) do
    case rendered_node_children(node) do
      [left, right | _] ->
        with left_int when is_integer(left_int) <- rendered_expr_int(left, model),
             right_int when is_integer(right_int) <- rendered_expr_int(right, model),
             true <- right_int != 0 do
          Integer.to_string(div(left_int, right_int))
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp evaluate_rendered_binop_hint(_node, _model, _op), do: nil

  @spec rendered_expr_int(rendered_node(), model_map()) :: integer() | nil
  defp rendered_expr_int(node, model) when is_map(node) and is_map(model) do
    op = to_string(Map.get(node, "op") || Map.get(node, :op) || "")
    label = to_string(Map.get(node, "label") || Map.get(node, :label) || "")

    cond do
      is_integer(Map.get(node, "value")) ->
        Map.get(node, "value")

      is_float(Map.get(node, "value")) ->
        trunc(Map.get(node, "value"))

      op == "field_access" and String.starts_with?(label, "model.") ->
        label
        |> String.replace_prefix("model.", "")
        |> then(&Map.get(model, &1))
        |> case do
          n when is_integer(n) -> n
          n when is_float(n) -> trunc(n)
          _ -> nil
        end

      true ->
        case Expr.expr_scalar(node) do
          n when is_integer(n) -> n
          n when is_float(n) -> trunc(n)
          _ -> nil
        end
    end
  end

  defp rendered_expr_int(_node, _model), do: nil

  @spec rendered_node_children(rendered_node()) :: [rendered_node()]
  defp rendered_node_children(node) when is_map(node) do
    case Map.get(node, "children") || Map.get(node, :children) do
      children when is_list(children) -> Enum.filter(children, &is_map/1)
      _ -> []
    end
  end

  @spec evaluated_rendered_scalar_hint(Types.runtime_value(), model_map()) :: String.t() | nil
  defp evaluated_rendered_scalar_hint(node, _model) when is_map(node) do
    (Map.get(node, "value") ||
       Map.get(node, :value) ||
       Map.get(node, "evaluated_value") ||
       Map.get(node, :evaluated_value))
    |> rendered_scalar_hint()
  end

  defp evaluated_rendered_scalar_hint(_node, _model), do: nil

  @spec rendered_scalar_hint(Types.runtime_value()) :: String.t() | nil
  defp rendered_scalar_hint(value) when is_integer(value), do: Integer.to_string(value)

  defp rendered_scalar_hint(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact])

  defp rendered_scalar_hint(value) when is_binary(value), do: value
  defp rendered_scalar_hint(value) when is_boolean(value), do: to_string(value)
  defp rendered_scalar_hint(_value), do: nil

  @spec rendered_int_hint(Types.runtime_value()) :: String.t() | nil
  defp rendered_int_hint(value) when is_integer(value), do: Integer.to_string(value)
  defp rendered_int_hint(value) when is_float(value), do: Integer.to_string(trunc(value))
  defp rendered_int_hint(_), do: nil

end
