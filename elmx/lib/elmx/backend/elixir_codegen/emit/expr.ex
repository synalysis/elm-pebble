defmodule Elmx.Backend.ElixirCodegen.Emit.Expr do
  @moduledoc false

  @let_iife_threshold 32

  alias Elmx.Backend.ConstructorLookup
  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Constructor
  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Generator
  alias Elmx.Runtime.Stdlib
  alias Elmx.Types

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

  def compile_tuple2(%{left: %{op: :int_literal, value: _tag, union_ctor: qualified} = left, right: right}, env, counter)
       when is_binary(qualified) do
    ctor = union_ctor_emit_name(qualified, env)

    cond do
      ctor in ["Ok", "Err", "Just"] ->
        compile_flat_tagged_ctor(ctor, right, env, counter, qualified)

      match?(%{op: :tuple2}, right) and union_ctor_payload_atoms_only?(right) ->
        {l, env, c1} = Emit.compile_expr(left, env, counter)
        {r, env, c2} = Emit.compile_expr(right, env, c1)
        {["{", l, ", ", r, "}"], env, c2}

      true ->
        compile_flat_tagged_ctor(ctor, right, env, counter, qualified)
    end
  end

  def compile_tuple2(%{left: left, right: right}, env, counter) do
    {l, env, c1} = Emit.compile_expr(left, env, counter)
    {r, env, c2} = Emit.compile_expr(right, env, c1)
    {["{", l, ", ", r, "}"], env, c2}
  end

  def compile_flat_tagged_ctor(ctor, right, env, counter, qualified \\ nil)

  def compile_flat_tagged_ctor("()", _right, env, counter, _qualified) do
    {"nil", env, counter}
  end

  def compile_flat_tagged_ctor(ctor, right, env, counter, _qualified)
      when ctor in ["Ok", "Err", "Just"] do
    {code, env, c1} = Emit.compile_expr(right, env, counter)
    {["{:", ctor, ", ", code, "}"], env, c1}
  end

  def compile_flat_tagged_ctor(ctor, right, env, counter, qualified) do
    lookup = Map.get(env, :constructor_lookup)
    module = Map.get(env, :module)
    ctor_name = qualified || ctor

    case flatten_ctor_payload_exprs(right) do
      [single] ->
        {code, env, c1} = Emit.compile_expr(single, env, counter)
        {["{:", ctor, ", ", code, "}"], env, c1}

      args ->
        {arg_code, env, c1} = Helpers.compile_arg_list(args, env, counter)

        payload =
          if ConstructorLookup.wrap_flattened_payload?(lookup, ctor_name, module, length(args)) do
            ["{", arg_code, "}"]
          else
            arg_code
          end

        {["{:", ctor, ", ", payload, "}"], env, c1}
    end
  end

  def flatten_ctor_payload_exprs(%{op: :tuple2, left: %{union_ctor: qualified}, right: _right} = expr)
       when is_binary(qualified),
       do: [expr]

  def flatten_ctor_payload_exprs(%{op: :tuple2, left: left, right: right}) do
    flatten_ctor_payload_exprs(left) ++ flatten_ctor_payload_exprs(right)
  end

  def flatten_ctor_payload_exprs(other), do: [other]

  defp union_ctor_payload_atoms_only?(expr) do
    expr
    |> flatten_ctor_payload_exprs()
    |> Enum.all?(fn
      %{op: :int_literal, union_ctor: qualified} when is_binary(qualified) -> true
      %{op: :var, name: _} -> false
      _ -> false
    end)
  end

  def compile_int_literal(expr, env) do
    case Map.get(expr, :union_ctor) do
      qualified when is_binary(qualified) ->
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

  def compile_let_in(%{op: :let_in} = expr, env, counter) do
    {bindings, body} = collect_let_bindings(expr)

    cond do
      function_letrec?(bindings) ->
        compile_function_letrec_block(bindings, body, env, counter)

      length(bindings) >= @let_iife_threshold ->
        compile_sequential_let_block(bindings, body, env, counter)

      true ->
        compile_single_let_in(expr, env, counter)
    end
  end

  defp collect_let_bindings(%{op: :let_in, name: name, value_expr: value, in_expr: inner}) do
    {rest, body} = collect_let_bindings(inner)
    {[{name, value} | rest], body}
  end

  defp collect_let_bindings(body), do: {[], body}

  defp function_letrec?(bindings) do
    bindings != [] and
      letrec_like_bindings?(bindings) and
      Enum.all?(bindings, fn {_name, value} -> function_like?(value) end)
  end

  defp letrec_like_bindings?(bindings) do
    Enum.any?(bindings, fn {_name, value} ->
      match?(%{op: :lambda}, value) or match?(%{op: :qualified_call, args: []}, value)
    end)
  end

  defp function_like?(%{op: :lambda}), do: true

  defp function_like?(%{op: :qualified_call, args: []}), do: true

  defp function_like?(%{op: :var}), do: true

  defp function_like?(_), do: false

  defp compile_function_letrec_block(bindings, body, env, counter) do
    sorted = order_letrec_bindings(bindings)

    {binding_lines, body_env, final_counter} =
      Enum.reduce(sorted, {[], env, counter}, fn {name, value}, {lines, acc_env, c} ->
        {value_code, c2} = letrec_binding_value(name, value, acc_env, c)
        emit_name = Helpers.let_emit_name(name)
        var = Macro.to_string(Macro.var(String.to_atom(emit_name), nil))
        line = [var, " = ", value_code, "\n"]
        {[line | lines], Map.put(acc_env, String.to_atom(name), true), c2}
      end)

    binding_lines = Enum.reverse(binding_lines)

    {body_code, _, c1} = Emit.compile_expr(body, body_env, final_counter)

    code = ["(fn ->\n", binding_lines, body_code, "\nend).()"]

    {code, env, c1}
  end

  defp compile_sequential_let_block(bindings, body, env, counter) do
    used_names = used_let_binding_names(bindings, body)

    {binding_lines, body_env, final_counter} =
      Enum.reduce(bindings, {[], env, counter}, fn {name, value}, {lines, acc_env, c} ->
        if MapSet.member?(used_names, name) do
          {value_code, _, c2} = Emit.compile_expr(value, acc_env, c)
          emit_name = Helpers.let_emit_name(name)
          var = Macro.to_string(Macro.var(String.to_atom(emit_name), nil))
          line = [var, " = ", value_code, "\n"]
          {[line | lines], Map.put(acc_env, String.to_atom(name), true), c2}
        else
          {lines, acc_env, c}
        end
      end)

    binding_lines = Enum.reverse(binding_lines)
    {body_code, _, c1} = Emit.compile_expr(body, body_env, final_counter)
    code = ["(fn ->\n", binding_lines, body_code, "\nend).()"]
    {code, env, c1}
  end

  defp order_letrec_bindings(bindings) do
    names = MapSet.new(Enum.map(bindings, &elem(&1, 0)))

    deps =
      Map.new(bindings, fn {name, value} ->
        refs =
          value
          |> referenced_binding_names()
          |> MapSet.intersection(names)
          |> MapSet.delete(name)

        {name, refs}
      end)

    topo_sort_letrec_bindings(bindings, deps)
  end

  defp topo_sort_letrec_bindings(bindings, deps) do
    binding_map = Map.new(bindings)

    {sorted, _} =
      Enum.reduce(1..length(bindings), {[], MapSet.new()}, fn _, {acc, done} ->
        case Enum.find(bindings, fn {name, _} ->
               name not in acc and MapSet.subset?(Map.get(deps, name, MapSet.new()), done)
             end) do
          {name, _} ->
            {[name | acc], MapSet.put(done, name)}

          nil ->
            {acc, done}
        end
      end)

    sorted_reversed = Enum.reverse(sorted)
    remainder = Enum.map(bindings, &elem(&1, 0)) -- sorted_reversed

    Enum.map(sorted_reversed ++ remainder, fn name ->
      {name, Map.fetch!(binding_map, name)}
    end)
  end

  @spec referenced_binding_names(Types.ir_expr() | map() | list() | tuple()) :: MapSet.t(String.t())
  def referenced_binding_names({:apply_saturated, call, _arity}) when is_map(call),
    do: referenced_binding_names(call)

  def referenced_binding_names(expr) when is_map(expr) or is_list(expr),
    do: referenced_binding_names(expr, MapSet.new())

  def referenced_binding_names(_expr), do: MapSet.new()

  defp referenced_binding_names(%{op: :call} = map, acc) do
    acc =
      case Map.get(map, :name) do
        name when is_binary(name) -> MapSet.put(acc, name)
        _ -> acc
      end

    referenced_binding_names(Map.get(map, :args) || [], acc)
  end

  defp referenced_binding_names(%{op: :qualified_call} = map, acc),
    do: referenced_binding_names(Map.get(map, :args) || [], acc)

  defp referenced_binding_names(%{op: :var, name: name}, acc) when is_binary(name),
    do: MapSet.put(acc, name)

  defp referenced_binding_names(%{op: :field_access, arg: arg}, acc) when is_binary(arg),
    do: MapSet.put(acc, arg)

  defp referenced_binding_names(%{op: :field_call} = map, acc) do
    acc =
      case Map.get(map, :arg) || Map.get(map, :target) do
        name when is_binary(name) -> MapSet.put(acc, name)
        expr when is_map(expr) -> referenced_binding_names(expr, acc)
        _ -> acc
      end

    referenced_binding_names(Map.get(map, :args) || [], acc)
  end

  defp referenced_binding_names(%{op: :case} = map, acc) do
    acc =
      case Map.get(map, :subject) do
        subject when is_binary(subject) -> MapSet.put(acc, subject)
        subject when is_map(subject) -> referenced_binding_names(subject, acc)
        _ -> acc
      end

    referenced_binding_names(Map.get(map, :branches, []), acc)
  end

  defp referenced_binding_names(%{op: op, arg: arg}, acc)
       when op in [:tuple_first_expr, :tuple_second_expr] and is_map(arg),
       do: referenced_binding_names(arg, acc)

  defp referenced_binding_names(%{op: op, var: name}, acc)
       when op in [:add_const, :sub_const] and is_binary(name),
       do: MapSet.put(acc, name)

  defp referenced_binding_names(%{op: op, left: left, right: right}, acc)
       when op in [:add_vars, :sub_vars] do
    acc
    |> referenced_binding_name(left)
    |> referenced_binding_name(right)
  end

  defp referenced_binding_names(map, acc) when is_map(map) do
    Enum.reduce(map, acc, fn {_k, v}, a -> referenced_binding_names(v, a) end)
  end

  defp referenced_binding_names(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &referenced_binding_names/2)
  end

  defp referenced_binding_names(_, acc), do: acc

  defp referenced_binding_name(acc, name) when is_binary(name), do: MapSet.put(acc, name)
  defp referenced_binding_name(acc, expr) when is_map(expr), do: referenced_binding_names(expr, acc)
  defp referenced_binding_name(acc, _), do: acc

  defp used_let_binding_names(bindings, body) do
    Enum.reduce(Enum.reverse(bindings), referenced_binding_names(body, MapSet.new()), fn
      {name, value}, acc ->
        if MapSet.member?(acc, name) do
          referenced_binding_names(value, acc)
        else
          acc
        end
    end)
  end

  defp letrec_binding_value(name, %{op: :lambda} = value, env, counter) do
    self_ref? = self_references?(name, value)

    env_for_value =
      if self_ref?, do: Map.put(env, String.to_atom(name), true), else: env

    {value_code, _, c} = Emit.compile_expr(value, env_for_value, counter)

    code =
      if self_ref? do
        param = Helpers.let_emit_name(name)
        var = Macro.to_string(Macro.var(String.to_atom(param), nil))
        ["Elmx.Runtime.Core.Apply.fix(fn ", var, " -> ", value_code, " end)"]
      else
        value_code
      end

    {code, c}
  end

  defp letrec_binding_value(_name, value, env, counter) do
    {value_code, _, c} = Emit.compile_expr(value, env, counter)
    {value_code, c}
  end

  defp self_references?(name, expr), do: ir_references_name?(expr, name)

  defp ir_references_name?(%{op: :call, name: n} = map, target) when is_binary(target) do
    n == target or ir_references_name?(Map.get(map, :args) || [], target)
  end

  defp ir_references_name?(%{op: :var, name: n}, target) when is_binary(n) and is_binary(target),
    do: n == target

  defp ir_references_name?(map, name) when is_map(map) do
    map |> Map.values() |> Enum.any?(&ir_references_name?(&1, name))
  end

  defp ir_references_name?(list, name) when is_list(list),
    do: Enum.any?(list, &ir_references_name?(&1, name))

  defp ir_references_name?(_, _), do: false

  defp compile_single_let_in(%{name: name, value_expr: value, in_expr: body}, env, counter) do
    used? = MapSet.member?(referenced_binding_names(body, MapSet.new()), name)
    {value_code, env, c1} = Emit.compile_expr(value, env, counter)

    if used? do
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
    else
      {body_code, _, c2} = Emit.compile_expr(body, env, c1)

      {[
         "(fn -> _ = ",
         value_code,
         "\n",
         body_code,
         "\nend).()"
       ], env, c2}
    end
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
    mod = CodegenRefs.core()
    {[mod, ".new_char(", a, ")"], env, c1}
  end

end
