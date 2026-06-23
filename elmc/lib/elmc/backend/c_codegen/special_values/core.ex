defmodule Elmc.Backend.CCodegen.SpecialValues.Core do
  @moduledoc false

  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.CCodegen.SpecialValues.{Dispatcher, Helpers}
  alias Elmc.Backend.CCodegen.Types

  @spec msg_tag_param(Types.ir_expr()) :: Types.ir_expr()
  def msg_tag_param(expr), do: Helpers.constructor_tag_expr(expr)

  @spec subscription_to_msg_params([Types.ir_expr()]) :: [Types.ir_expr()]
  def subscription_to_msg_params(args) when is_list(args) do
    case List.last(args) do
      nil -> []
      to_msg -> [Helpers.constructor_tag_expr(to_msg)]
    end
  end

  @spec encoded_sub_as_tuple(Types.ir_expr(), [Types.ir_expr()]) :: Types.ir_expr()
  def encoded_sub_as_tuple(mask_expr, args) when is_list(args) do
    arity = length(args)
    payload = args ++ List.duplicate(%{op: :int_literal, value: 0}, max(0, 6 - arity))
    %{op: :tuple2, left: mask_expr, right: Helpers.tuple_chain(payload)}
  end

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()

  def special_value_from_target(target, []) when is_binary(target) do
    cond do
      target in ["True", "Basics.True"] or String.ends_with?(target, ".True") ->
        %{op: :bool_literal, value: true}

      target in ["False", "Basics.False"] or String.ends_with?(target, ".False") ->
        %{op: :bool_literal, value: false}

      target in ["LT", "Basics.LT"] or String.ends_with?(target, ".LT") ->
        %{op: :order_literal, value: -1}

      target in ["EQ", "Basics.EQ"] or String.ends_with?(target, ".EQ") ->
        %{op: :order_literal, value: 0}

      target in ["GT", "Basics.GT"] or String.ends_with?(target, ".GT") ->
        %{op: :order_literal, value: 1}

      target in ["Basics.e"] ->
        %{op: :float_literal, value: 2.718281828459045}

      target in ["Basics.pi"] ->
        %{op: :float_literal, value: 3.141592653589793}

      target == "()" ->
        %{op: :runtime_call, function: "elmc_unit", args: []}

      Map.has_key?(IRQueries.bundled_union_constructor_tags(), target) ->
        %{op: :int_literal, value: Map.fetch!(IRQueries.bundled_union_constructor_tags(), target)}

      true ->
        nil
    end
  end

  def special_value_from_target(_target, _args), do: nil

  @spec normalize_special_target(String.t()) :: String.t()
  def normalize_special_target(target) when is_binary(target) do
    normalize_bare_special_target(target)
  end

  @spec normalize_bare_special_target(String.t()) :: String.t()
  defp normalize_bare_special_target(target) when is_binary(target) do
    case target do
      "Clear" -> "Pebble.Ui.clear"
      "Pixel" -> "Pebble.Ui.pixel"
      "Line" -> "Pebble.Ui.line"
      "RectOp" -> "Pebble.Ui.rect"
      "FillRect" -> "Pebble.Ui.fillRect"
      "Circle" -> "Pebble.Ui.circle"
      "FillCircle" -> "Pebble.Ui.fillCircle"
      "TextInt" -> "Pebble.Ui.textInt"
      "TextLabel" -> "Pebble.Ui.textLabel"
      "Text" -> "Pebble.Ui.text"
      "StrokeWidth" -> "Pebble.Ui.strokeWidth"
      "Antialiased" -> "Pebble.Ui.antialiased"
      "StrokeColor" -> "Pebble.Ui.strokeColor"
      "FillColor" -> "Pebble.Ui.fillColor"
      "TextColor" -> "Pebble.Ui.textColor"
      "CompositingMode" -> "Pebble.Ui.compositingMode"
      "Group" -> "Pebble.Ui.group"
      "PathFilled" -> "Pebble.Ui.pathFilled"
      "PathOutline" -> "Pebble.Ui.pathOutline"
      "PathOutlineOpen" -> "Pebble.Ui.pathOutlineOpen"
      "RoundRect" -> "Pebble.Ui.roundRect"
      "Arc" -> "Pebble.Ui.arc"
      "FillRadial" -> "Pebble.Ui.fillRadial"
      "BitmapInRect" -> "Pebble.Ui.drawBitmapInRect"
      "RotatedBitmap" -> "Pebble.Ui.drawRotatedBitmap"
      "VectorAt" -> "Pebble.Ui.drawVectorAt"
      "VectorSequenceAt" -> "Pebble.Ui.drawVectorSequenceAt"
      "BitmapSequenceAt" -> "Pebble.Ui.drawBitmapSequenceAt"
      other -> other
    end
  end

  @spec compiler_folded_union_constructors() :: MapSet.t(String.t())
  def compiler_folded_union_constructors do
    MapSet.new(["Pebble.Ui.Rotation"])
  end

  @spec constructor_tag(String.t()) :: non_neg_integer()
  def constructor_tag(name) do
    tags = Process.get(:elmc_constructor_tags, %{})

    Map.get_lazy(tags, name, fn ->
      name
      |> String.split(".")
      |> List.last()
      |> then(&Map.get(tags, &1, 0))
    end)
  end

  @spec pebble_angle_expr(Types.ir_expr()) :: Types.ir_expr()
  def pebble_angle_expr(rotation) when is_map(rotation) do
    rotation =
      case rotation do
        %{op: :qualified_call, target: target, args: args} ->
          case Dispatcher.special_value_from_target(target, args) do
            nil -> rotation
            folded -> folded
          end

        _ ->
          rotation
      end

    case Helpers.compile_time_pebble_angle_expr(rotation) do
      {:ok, expr} -> expr
      :error -> Helpers.rotation_to_pebble_angle_call(rotation)
    end
  end
end
