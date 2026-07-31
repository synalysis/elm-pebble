defmodule Elmc.Backend.CCodegen.Native.TypedReturn do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.Types
  alias ElmEx.IR.TypeSignature

  @spec function_return?(
          Types.function_decl_key() | nil,
          Types.compile_env(),
          non_neg_integer(),
          String.t()
        ) :: boolean()
  def function_return?(nil, _env, _arg_count, _return_type), do: false

  def function_return?(target, env, arg_count, return_type) do
    case Map.get(Map.get(env, :__program_decls__, %{}), target) do
      %{type: type} ->
        length(Host.function_arg_types(type)) == arg_count and
          Host.function_return_type(type) == return_type

      _ ->
        false
    end
  end

  @spec string_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def string_expr?(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")
    function_return?({module_name, name}, env, length(args || []), "String")
  end

  def string_expr?(%{op: :qualified_call, target: target, args: args}, env)
      when is_binary(target) do
    target
    |> Host.normalize_special_target()
    |> Host.split_qualified_function_target()
    |> function_return?(env, length(args || []), "String")
  end

  def string_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    module_name = Map.get(env, :__module__, "Main")
    function_return?({module_name, to_string(name)}, env, 0, "String")
  end

  def string_expr?(_expr, _env), do: false

  @spec bool_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def bool_expr?(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")
    function_return?({module_name, name}, env, length(args || []), "Bool")
  end

  def bool_expr?(%{op: :qualified_call, target: target, args: args}, env)
      when is_binary(target) do
    target
    |> Host.normalize_special_target()
    |> Host.split_qualified_function_target()
    |> function_return?(env, length(args || []), "Bool")
  end

  def bool_expr?(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    module_name = Map.get(env, :__module__, "Main")
    function_return?({module_name, to_string(name)}, env, 0, "Bool")
  end

  def bool_expr?(_expr, _env), do: false

  @spec list_int_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def list_int_expr?(expr, env), do: expr_type(expr, env) == "List Int"

  @spec expr_type(Types.ir_expr(), Types.compile_env()) :: String.t() | nil
  def expr_type(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    type_from_env(env, name) ||
      function_return_type({Map.get(env, :__module__, "Main"), to_string(name)}, env, 0)
  end

  def expr_type(%{op: :call, name: name, args: args}, env) when is_binary(name) do
    function_return_type({Map.get(env, :__module__, "Main"), name}, env, length(args || []))
  end

  def expr_type(%{op: :qualified_call, target: target, args: args}, env)
      when is_binary(target) do
    target
    |> Host.normalize_special_target()
    |> Host.split_qualified_function_target()
    |> function_return_type(env, length(args || []))
  end

  def expr_type(%{op: :field_access, arg: arg, field: field}, env) when is_binary(field) do
    case RecordFields.field_type(env, arg, field) do
      type when is_binary(type) ->
        Host.normalize_type_name(type)

      _ ->
        # linear-algebra Kernel.MJS *toRecord fields are always Float. Do not
        # apply this to every untyped `.x`/`.y` (Ui.Point is Int; treating those
        # as Float forced boxed Number arith and broke Rect literal native ints).
        cond do
          mjs_matrix_component_field?(field) ->
            "Float"

          field in ["x", "y", "z", "w"] and mjs_to_record_base?(arg) ->
            "Float"

          true ->
            nil
        end
    end
  end

  def expr_type(%{op: :int_literal, value: value}, _env) when is_integer(value), do: "Int"

  def expr_type(%{op: :float_literal, value: value}, _env) when is_number(value), do: "Float"

  def expr_type(%{op: :bool_literal}, _env), do: "Bool"

  def expr_type(%{op: :string_literal}, _env), do: "String"

  def expr_type(%{op: :char_literal}, _env), do: "Char"

  def expr_type(%{op: :if, then_expr: then_expr, else_expr: else_expr}, env) do
    case {expr_type(then_expr, env), expr_type(else_expr, env)} do
      {type, type} when is_binary(type) -> type
      _ -> nil
    end
  end

  # `let model = Tuple.first patternArg` (performUserMsg) must carry Model so
  # `model.pageData` resolves to Platform.Model @4, not nested Ok-payload @1.
  def expr_type(%{op: op, arg: arg}, env)
      when op in [:tuple_first_expr, :tuple_first, :tuple_second_expr, :tuple_second] do
    case expr_type(arg, env) do
      tuple_type when is_binary(tuple_type) ->
        elems = TypeSignature.tuple_element_types(tuple_type)

        idx =
          if op in [:tuple_first_expr, :tuple_first], do: 0, else: 1

        case Enum.at(elems, idx) do
          type when is_binary(type) and type != "" -> Host.normalize_type_name(type)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def expr_type(_expr, _env), do: nil

  @spec function_return_type(Types.function_decl_key() | nil, Types.compile_env(), non_neg_integer()) ::
          String.t() | nil

  defp function_return_type(nil, _env, _arg_count), do: nil

  defp function_return_type(target, env, arg_count) do
    case Map.get(Map.get(env, :__program_decls__, %{}), target) do
      %{type: type} ->
        if length(Host.function_arg_types(type)) == arg_count do
          Host.function_return_type(type) |> Host.normalize_type_name()
        end

      _ ->
        nil
    end
  end

  @spec type_from_env(Types.compile_env(), String.t() | atom()) :: String.t() | nil

  defp type_from_env(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__var_types__, %{})
    |> Map.get(EnvBindings.binding_key(name))
    |> case do
      type when is_binary(type) -> Host.normalize_type_name(type)
      _ -> nil
    end
  end

  @spec mjs_matrix_component_field?(binary() | term()) :: boolean()

  defp mjs_matrix_component_field?(<<"m", r, c>>) when r in ?1..?4 and c in ?1..?4, do: true
  defp mjs_matrix_component_field?(_), do: false

  @spec mjs_to_record_base?(map() | term()) :: boolean()

  defp mjs_to_record_base?(%{op: :qualified_call, target: target}) when is_binary(target),
    do: mjs_to_record_target?(target)

  defp mjs_to_record_base?(%{op: :call, target: {mod, name}})
       when is_binary(mod) and is_binary(name),
       do: mjs_to_record_target?("#{mod}.#{name}")

  defp mjs_to_record_base?(%{op: :call, name: name}) when is_binary(name),
    do: mjs_to_record_target?(name)

  defp mjs_to_record_base?(%{op: :field_access, arg: inner}) when is_map(inner),
    do: mjs_to_record_base?(inner)

  defp mjs_to_record_base?(_), do: false

  @spec mjs_to_record_target?(String.t()) :: boolean()

  defp mjs_to_record_target?(target) when is_binary(target) do
    short = target |> String.split(".") |> List.last()

    short in ["toRecord", "m4x4toRecord", "v4toRecord", "v3toRecord", "v2toRecord"] and
      (String.contains?(target, "Matrix") or String.contains?(target, "Vector") or
         short in ["m4x4toRecord", "v4toRecord", "v3toRecord", "v2toRecord"])
  end
end
