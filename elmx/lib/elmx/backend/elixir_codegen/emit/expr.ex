defmodule Elmx.Backend.ElixirCodegen.Emit.Expr do
  @moduledoc false

  alias Elmx.Backend.ConstructorLookup
  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Constructor
  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Runtime.Generator
  alias Elmx.Runtime.Stdlib

  def compile_add_const(%{var: name, value: value}, env, counter) do
    ref = Helpers.binding_ref(name, env)
    {["(", ref, " + ", Integer.to_string(value), ")"], env, counter}
  end

  def compile_add_vars(%{left: left, right: right}, env, counter) do
    {["(", Helpers.binding_ref(left, env), " + ", Helpers.binding_ref(right, env), ")"], env, counter}
  end

  def compile_sub_const(%{var: name, value: value}, env, counter) do
    ref = Helpers.binding_ref(name, env)
    {["(", ref, " - ", Integer.to_string(value), ")"], env, counter}
  end

  def compile_compare(%{left: left, kind: kind, right: right}, env, counter) do
    compile_compare(%{left: left, op: kind, right: right}, env, counter)
  end

  def compile_compare(%{left: left, op: cmp, right: right}, env, counter) do
    op =
      case cmp do
        :eq -> "=="
        :neq -> "!="
        :lt -> "<"
        :gt -> ">"
        :le -> "<="
        :ge -> ">="
        "==" -> "=="
        "/=" -> "!="
        "<" -> "<"
        ">" -> ">"
        "<=" -> "<="
        ">=" -> ">="
        other -> raise "unsupported compare #{inspect(other)}"
      end

    {l, env, c1} = Emit.compile_expr(left, env, counter)
    {r, env, c2} = Emit.compile_expr(right, env, c1)
    {["(", l, " ", op, " ", r, ")"], env, c2}
  end

  def compile_tuple2(%{left: %{op: :int_literal, value: _tag, union_ctor: qualified}, right: right}, env, counter)
       when is_binary(qualified) do
    ctor = union_ctor_emit_name(qualified, env)
    compile_flat_tagged_ctor(ctor, right, env, counter)
  end

  def compile_tuple2(%{left: left, right: right}, env, counter) do
    {l, env, c1} = Emit.compile_expr(left, env, counter)
    {r, env, c2} = Emit.compile_expr(right, env, c1)
    {["{", l, ", ", r, "}"], env, c2}
  end

  def compile_flat_tagged_ctor("()", _right, env, counter) do
    {"nil", env, counter}
  end

  def compile_flat_tagged_ctor(ctor, right, env, counter) do
    case flatten_ctor_payload_exprs(right) do
      [single] ->
        {code, env, c1} = Emit.compile_expr(single, env, counter)
        {["{:", ctor, ", ", code, "}"], env, c1}

      args ->
        {arg_code, env, c1} = Helpers.compile_arg_list(args, env, counter)
        {["{:", ctor, ", ", arg_code, "}"], env, c1}
    end
  end

  def flatten_ctor_payload_exprs(%{op: :tuple2, left: left, right: right}) do
    flatten_ctor_payload_exprs(left) ++ flatten_ctor_payload_exprs(right)
  end

  def flatten_ctor_payload_exprs(other), do: [other]

  def compile_int_literal(expr, env) do
    case {Map.get(env, :emit_mode), Map.get(expr, :union_ctor)} do
      {:ide_runtime, qualified} when is_binary(qualified) ->
        Constructor.ide_runtime_ctor_atom(union_ctor_emit_name(qualified, env))

      _ ->
        Integer.to_string(expr.value)
    end
  end

  def union_ctor_emit_name(qualified, env) when is_binary(qualified) do
    case Map.get(env, :constructor_lookup) do
      lookup when is_map(lookup) ->
        case ConstructorLookup.resolve(lookup, qualified, Map.get(env, :module)) do
          %{constructor: ctor} when is_binary(ctor) -> Helpers.pattern_ctor_name(ctor)
          _ -> qualified |> String.split(".") |> List.last() |> Helpers.pattern_ctor_name()
        end

      _ ->
        qualified |> String.split(".") |> List.last() |> Helpers.pattern_ctor_name()
    end
  end

  def compile_list(%{items: elements}, env, counter) when is_list(elements) do
    compile_list(%{elements: elements}, env, counter)
  end

  def compile_list(%{elements: elements}, env, counter) when is_list(elements) do
    {parts, {env, counter}} =
      Enum.map_reduce(elements, {env, counter}, fn elem, {env, c} ->
        {code, env, c} = Emit.compile_expr(elem, env, c)
        {code, {env, c}}
      end)

    {["[", Enum.intersperse(parts, ", "), "]"], env, counter}
  end

  def compile_lambda(%{body: body} = expr, env, counter) do
    args = Map.get(expr, :args) || Map.get(expr, :params) || []
    name = :"elmx_lambda_#{counter}"
    counter = counter + 1
    lambda_env = Helpers.put_lambda_params(env, args)

    {body_code, _, _} = Emit.compile_expr(body, lambda_env, 0)

    code =
      Enum.reduce(Enum.reverse(args), body_code, fn arg, inner ->
        param = Helpers.binding_ref(Helpers.param_name(arg), lambda_env)
        ["fn ", param, " -> ", inner, " end"]
      end)

    code =
      case args do
        [] -> ["fn _ -> ", body_code, " end"]
        [_ | _] -> code
      end

    {code, Map.put(env, name, true), counter}
  end

  def compile_runtime_call(%{function: function, args: args}, env, counter) do
    {parts, {env, c1}} =
      Enum.map_reduce(args, {env, counter}, fn arg, {env, c} ->
        {code, env, c} = Emit.compile_expr(arg, env, c)
        {code, {env, c}}
      end)

    arg_codes = Enum.map(parts, &IO.iodata_to_binary/1)

    code =
      case Generator.compile_call(function, arg_codes) do
        {:ok, compiled} ->
          compiled

        :error ->
          Stdlib.runtime_call_parts(function, arg_codes)
      end

    {code, env, c1}
  end

  def compile_let_in(%{name: name, value_expr: value, in_expr: body}, env, counter) do
    {value_code, env, c1} = Emit.compile_expr(value, env, counter)
    emit_name = Helpers.let_emit_name(name)
    body_env = Map.put(env, String.to_atom(name), true)
    {body_code, _, c2} = Emit.compile_expr(body, body_env, c1)

    param = Macro.var(String.to_atom(emit_name), nil) |> Macro.to_string()

    {[
       "(fn ",
       param,
       " -> ",
       body_code,
       " end).(",
       value_code,
       ")"
     ], env, c2}
  end

  def compile_if(%{cond: condition, then_expr: then_expr, else_expr: else_expr}, env, counter) do
    compile_if(%{condition: condition, then_expr: then_expr, else_expr: else_expr}, env, counter)
  end

  def compile_if(%{condition: condition, then_expr: then_expr, else_expr: else_expr}, env, counter) do
    {c, env, c1} = Emit.compile_expr(condition, env, counter)
    {t, env, c2} = Emit.compile_expr(then_expr, env, c1)
    {e, env, c3} = Emit.compile_expr(else_expr, env, c2)
    {["(if ", c, " do\n    ", t, "\n  else\n    ", e, "\n  end)"], env, c3}
  end

  def compile_tuple_accessor(%{target: target}, env, counter, index) do
    {t, env, c1} = Emit.compile_expr(target, env, counter)
    {["elem(", t, ", ", Integer.to_string(index), ")"], env, c1}
  end

  def compile_tuple_accessor(%{arg: arg}, env, counter, index) do
    compile_tuple_accessor(%{target: arg}, env, counter, index)
  end

  def compile_string_length(%{arg: arg}, env, counter) do
    {a, env, c1} = Emit.compile_expr(arg, env, counter)
    {["String.length(", a, ")"], env, c1}
  end

  def compile_char_from_code(%{arg: arg}, env, counter) do
    {a, env, c1} = Emit.compile_expr(arg, env, counter)
    {["<<", a, "::utf8>>"], env, c1}
  end

end
