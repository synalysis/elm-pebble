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

  @stdlib_kernel_modules MapSet.new(~w(
    List Random Basics Utils String Bitwise Char Tuple Debug
    Maybe Result Task Dict Set Array JsArray Process
  ))

  @kernel_json_to_decode %{
    "decodeString" => "Json.Decode.string",
    "decodeBool" => "Json.Decode.bool",
    "decodeInt" => "Json.Decode.int",
    "decodeFloat" => "Json.Decode.float",
    "decodeList" => "Json.Decode.list",
    "decodeArray" => "Json.Decode.array",
    "decodeNull" => "Json.Decode.null",
    "decodeField" => "Json.Decode.field",
    "decodeIndex" => "Json.Decode.index",
    "decodeKeyValuePairs" => "Json.Decode.keyValuePairs",
    "decodeValue" => "Json.Decode.value",
    "andThen" => "Json.Decode.andThen",
    "fail" => "Json.Decode.fail",
    "succeed" => "Json.Decode.succeed",
    "oneOf" => "Json.Decode.oneOf",
    "map1" => "Json.Decode.map",
    "map2" => "Json.Decode.map2",
    "map3" => "Json.Decode.map3",
    "map4" => "Json.Decode.map4",
    "map5" => "Json.Decode.map5",
    "map6" => "Json.Decode.map6",
    "map7" => "Json.Decode.map7",
    "map8" => "Json.Decode.map8",
    "run" => "Json.Decode.decodeValue",
    "runOnString" => "Json.Decode.decodeString",
    "encode" => "Json.Encode.encode",
    "encodeNull" => "Json.Encode.null"
  }

  @spec normalize_special_target(String.t()) :: String.t()
  def normalize_special_target(target) when is_binary(target) do
    target
    |> normalize_bare_special_target()
    |> denormalize_kernel_shorthand()
    |> denormalize_utils_alias()
  end

  @spec operator_call_rewrite(String.t(), Types.special_value_args()) ::
          Types.special_value_result()
  def operator_call_rewrite(target, args) when is_binary(target) and is_list(args) do
    # Empty args are function *values* (`Basics.gt` / `Utils.gt` as first-class).
    # Do not rewrite those into a zero-arg `__gt__` call — let callers lower a
    # closure / forwarding wrapper via type arity or special-value lambdas.
    #
    # Binary compares must become `:compare` IR rather than `call_fn` to a
    # missing `Basics.__gt__` stub (WASM).
    case {operator_call_name(target), args} do
      {nil, _} ->
        nil

      {_name, []} ->
        nil

      {name, [left, right]} when name in ~w(__eq__ __neq__ __lt__ __lte__ __gt__ __gte__) ->
        %{op: :compare, kind: compare_op_kind(name), left: left, right: right}

      {name, _} ->
        %{op: :call, name: name, args: args}
    end
  end

  defp compare_op_kind("__eq__"), do: :eq
  defp compare_op_kind("__neq__"), do: :neq
  defp compare_op_kind("__lt__"), do: :lt
  defp compare_op_kind("__lte__"), do: :lte
  defp compare_op_kind("__gt__"), do: :gt
  defp compare_op_kind("__gte__"), do: :gte

  defp operator_call_name("Basics.add"), do: "__add__"
  defp operator_call_name("Basics.sub"), do: "__sub__"
  defp operator_call_name("Basics.mul"), do: "__mul__"
  defp operator_call_name("Basics.fdiv"), do: "__fdiv__"
  defp operator_call_name("Basics.idiv"), do: "__idiv__"
  defp operator_call_name("Basics.pow"), do: "__pow__"
  defp operator_call_name("Basics.eq"), do: "__eq__"
  defp operator_call_name("Basics.neq"), do: "__neq__"
  defp operator_call_name("Basics.lt"), do: "__lt__"
  defp operator_call_name("Basics.lte"), do: "__lte__"
  defp operator_call_name("Basics.gt"), do: "__gt__"
  defp operator_call_name("Basics.gte"), do: "__gte__"
  defp operator_call_name("Basics.append"), do: "__append__"
  defp operator_call_name("Utils.equal"), do: "__eq__"
  defp operator_call_name("Utils.notEqual"), do: "__neq__"
  defp operator_call_name("Utils.lt"), do: "__lt__"
  defp operator_call_name("Utils.le"), do: "__lte__"
  defp operator_call_name("Utils.gt"), do: "__gt__"
  defp operator_call_name("Utils.ge"), do: "__gte__"
  defp operator_call_name("Utils.append"), do: "__append__"

  defp operator_call_name(name)
       when name in ~w(__eq__ __neq__ __lt__ __lte__ __gt__ __gte__ __add__ __sub__ __mul__ __fdiv__ __idiv__ __pow__ __append__),
       do: name

  defp operator_call_name(target) when is_binary(target) do
    case String.split(target, ".") |> List.last() do
      name when name in ~w(__eq__ __neq__ __lt__ __lte__ __gt__ __gte__) -> name
      _ -> nil
    end
  end

  defp denormalize_kernel_shorthand("Elm.Kernel." <> rest) do
    case String.split(rest, ".", parts: 2) do
      ["JsArray", name] ->
        "Array." <> name

      ["Json", name] ->
        Map.get(@kernel_json_to_decode, name, "Elm.Kernel.Json." <> name)

      [mod, name] ->
        if MapSet.member?(@stdlib_kernel_modules, mod) do
          mod <> "." <> name
        else
          "Elm.Kernel." <> rest
        end

      _ ->
        "Elm.Kernel." <> rest
    end
  end

  defp denormalize_kernel_shorthand(target), do: target

  defp denormalize_utils_alias("Utils.compare"), do: "Basics.compare"
  defp denormalize_utils_alias(target), do: target

  @spec denormalize_module_name(String.t()) :: String.t()
  def denormalize_module_name("Elm.Kernel.JsArray"), do: "Array"

  def denormalize_module_name("Elm.Kernel.Platform"), do: "Platform"

  def denormalize_module_name("Elm.Kernel." <> rest) do
    case String.split(rest, ".") do
      [mod] ->
        if MapSet.member?(@stdlib_kernel_modules, mod), do: mod, else: "Elm.Kernel." <> rest

      _ ->
        "Elm.Kernel." <> rest
    end
  end

  def denormalize_module_name(module_name), do: module_name

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
