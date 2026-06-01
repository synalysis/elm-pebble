defmodule Elmx.Backend.ElixirCodegen.Emit do
  @moduledoc false

  alias Elmx.Backend.ConstructorEmit
  alias Elmx.Backend.ConstructorLookup
  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Backend.ElixirCodegen.Emit.Patterns
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified, as: QualifiedEmit
  alias Elmx.Runtime.Generator
  alias Elmx.Runtime.Stdlib

  alias Elmx.Types

  @type env :: Types.emit_env()

  @spec function_env(String.t(), list()) :: env()
  def function_env(module_name, args) when is_binary(module_name) and is_list(args) do
    Enum.reduce(args, %{module: module_name}, fn arg, acc ->
      Map.put(acc, String.to_atom(param_name(arg)), true)
    end)
  end

  @spec compile_expr(map(), env(), Types.emit_counter()) :: Types.compile_expr_result()
  def compile_expr(expr, env, counter) when is_map(expr) do
    case Map.get(expr, :op) do
      :int_literal ->
        {compile_int_literal(expr, env), env, counter}

      :float_literal ->
        {inspect(expr.value), env, counter}

      :string_literal ->
        {inspect(expr.value), env, counter}

      :char_literal ->
        {inspect(expr.value), env, counter}

      :bool_literal ->
        {to_string(expr.value == true), env, counter}

      :cmd_none ->
        {"Elmx.Runtime.Values.cmd_none()", env, counter}

      :var ->
        name = expr.name || expr[:name]

        case compile_var(name, env, counter) do
          {:ok, code, env, c} -> {code, env, c}
          :error -> {var_ref(name, env), env, counter}
        end

      :add_const ->
        compile_add_const(expr, env, counter)

      :add_vars ->
        compile_add_vars(expr, env, counter)

      :sub_const ->
        compile_sub_const(expr, env, counter)

      :compare ->
        compile_compare(expr, env, counter)

      :tuple2 ->
        compile_tuple2(expr, env, counter)

      :list_literal ->
        compile_list(expr, env, counter)

      :record_literal ->
        compile_record(expr, env, counter)

      :record_update ->
        compile_record_update(expr, env, counter)

      :field_access ->
        compile_field_access(expr, env, counter)

      :field_call ->
        compile_field_call(expr, env, counter)

      :lambda ->
        compile_lambda(expr, env, counter)

      :call ->
        compile_call(expr, env, counter)

      :call1 ->
        compile_call1(expr, env, counter)

      :qualified_call ->
        compile_qualified_call(expr, env, counter)

      :qualified_call1 ->
        compile_qualified_call1(expr, env, counter)

      :constructor_call ->
        compile_constructor(expr, env, counter)

      :runtime_call ->
        compile_runtime_call(expr, env, counter)

      :let_in ->
        compile_let_in(expr, env, counter)

      :if ->
        compile_if(expr, env, counter)

      :case ->
        Patterns.compile_case(expr, env, counter)

      :tuple_first ->
        compile_tuple_accessor(expr, env, counter, 0)

      :tuple_second ->
        compile_tuple_accessor(expr, env, counter, 1)

      :tuple_first_expr ->
        compile_tuple_accessor(expr, env, counter, 0)

      :tuple_second_expr ->
        compile_tuple_accessor(expr, env, counter, 1)

      :string_length_expr ->
        compile_string_length(expr, env, counter)

      :char_from_code_expr ->
        compile_char_from_code(expr, env, counter)

      :unsupported ->
        raise Elmx.Backend.UnsupportedOpError, op: :unsupported, expr: expr

      op ->
        raise Elmx.Backend.UnsupportedOpError, op: op, expr: expr
    end
  end

  defp compile_add_const(%{var: name, value: value}, env, counter) do
    ref = binding_ref(name, env)
    {["(", ref, " + ", Integer.to_string(value), ")"], env, counter}
  end

  defp compile_add_vars(%{left: left, right: right}, env, counter) do
    {["(", binding_ref(left, env), " + ", binding_ref(right, env), ")"], env, counter}
  end

  defp compile_sub_const(%{var: name, value: value}, env, counter) do
    ref = binding_ref(name, env)
    {["(", ref, " - ", Integer.to_string(value), ")"], env, counter}
  end

  defp compile_compare(%{left: left, kind: kind, right: right}, env, counter) do
    compile_compare(%{left: left, op: kind, right: right}, env, counter)
  end

  defp compile_compare(%{left: left, op: cmp, right: right}, env, counter) do
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

    {l, env, c1} = compile_expr(left, env, counter)
    {r, env, c2} = compile_expr(right, env, c1)
    {["(", l, " ", op, " ", r, ")"], env, c2}
  end

  defp compile_tuple2(%{left: %{op: :int_literal, value: _tag, union_ctor: qualified}, right: right}, env, counter)
       when is_binary(qualified) do
    ctor = union_ctor_emit_name(qualified, env)
    compile_flat_tagged_ctor(ctor, right, env, counter)
  end

  defp compile_tuple2(%{left: left, right: right}, env, counter) do
    {l, env, c1} = compile_expr(left, env, counter)
    {r, env, c2} = compile_expr(right, env, c1)
    {["{", l, ", ", r, "}"], env, c2}
  end

  defp compile_flat_tagged_ctor("()", _right, env, counter) do
    {"nil", env, counter}
  end

  defp compile_flat_tagged_ctor(ctor, right, env, counter) do
    case flatten_ctor_payload_exprs(right) do
      [single] ->
        {code, env, c1} = compile_expr(single, env, counter)
        {["{:", ctor, ", ", code, "}"], env, c1}

      args ->
        {arg_code, env, c1} = compile_arg_list(args, env, counter)
        {["{:", ctor, ", ", arg_code, "}"], env, c1}
    end
  end

  defp flatten_ctor_payload_exprs(%{op: :tuple2, left: left, right: right}) do
    flatten_ctor_payload_exprs(left) ++ flatten_ctor_payload_exprs(right)
  end

  defp flatten_ctor_payload_exprs(other), do: [other]

  defp compile_int_literal(expr, env) do
    case {Map.get(env, :emit_mode), Map.get(expr, :union_ctor)} do
      {:ide_runtime, qualified} when is_binary(qualified) ->
        ide_runtime_ctor_atom(union_ctor_emit_name(qualified, env))

      _ ->
        Integer.to_string(expr.value)
    end
  end

  defp union_ctor_emit_name(qualified, env) when is_binary(qualified) do
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

  defp compile_list(%{items: elements}, env, counter) when is_list(elements) do
    compile_list(%{elements: elements}, env, counter)
  end

  defp compile_list(%{elements: elements}, env, counter) when is_list(elements) do
    {parts, {env, counter}} =
      Enum.map_reduce(elements, {env, counter}, fn elem, {env, c} ->
        {code, env, c} = compile_expr(elem, env, c)
        {code, {env, c}}
      end)

    {["[", Enum.intersperse(parts, ", "), "]"], env, counter}
  end

  defp compile_record(%{fields: fields}, env, counter) when is_list(fields) do
    {parts, {env, counter}} =
      Enum.map_reduce(normalize_record_fields(fields), {env, counter}, fn {name, value}, {env, c} ->
        {code, env, c} = compile_record_field_value(name, value, env, c)
        {[inspect(name), " => ", code], {env, c}}
      end)

    field_strs = Enum.map(parts, &IO.iodata_to_binary/1)
    {["%{", Enum.intersperse(field_strs, ", "), "}"], env, counter}
  end

  defp compile_record_update(%{base: base, fields: fields}, env, counter) when is_list(fields) do
    {acc, env, counter} =
      Enum.reduce(fields, {nil, env, counter}, fn field, {acc, env, c} ->
        {name, value} = record_update_field(field)
        {code, env, c} = compile_expr(value, env, c)

        next =
          if acc do
            ["Map.put(", acc, ", ", inspect(name), ", ", code, ")"]
          else
            {base_code, _env, _c} = compile_expr(base, env, c)
            ["Map.put(", base_code, ", ", inspect(name), ", ", code, ")"]
          end

        {next, env, c}
      end)

    {acc, env, counter}
  end

  defp compile_record_update(%{base: base, field: field, value: value}, env, counter) do
    {base_code, env, c1} = compile_expr(base, env, counter)
    {value_code, env, c2} = compile_expr(value, env, c1)
    {["Map.put(", base_code, ", ", inspect(field), ", ", value_code, ")"], env, c2}
  end

  defp compile_field_access(%{target: target, field: field}, env, counter) do
    {t, env, c1} = compile_expr(target, env, counter)
    {["Map.get(", t, ", ", inspect(field), ")"], env, c1}
  end

  defp compile_field_access(%{record: record, field: field}, env, counter) do
    compile_field_access(%{target: record, field: field}, env, counter)
  end

  defp compile_field_access(%{arg: arg, field: field}, env, counter) when is_binary(arg) do
    ref = binding_ref(arg, env)
    {["Map.get(", ref, ", ", inspect(field), ")"], env, counter}
  end

  defp compile_field_access(%{arg: arg, field: field}, env, counter) do
    compile_field_access(%{target: arg, field: field}, env, counter)
  end

  defp compile_field_call(%{target: target, field: field, args: args}, env, counter) do
    {t, env, c1} = compile_expr(target, env, counter)
    {arg_code, env, c2} = compile_arg_list(args, env, c1)
    {["Elmx.Runtime.Values.field_call(", t, ", ", inspect(field), ", [", arg_code, "])"], env, c2}
  end

  defp compile_field_call(%{arg: arg, field: field, args: args}, env, counter) do
    compile_field_call(%{target: arg, field: field, args: args}, env, counter)
  end

  defp compile_field_call(%{record: record, field: field, args: args}, env, counter) do
    compile_field_call(%{target: record, field: field, args: args}, env, counter)
  end

  defp compile_lambda(%{body: body} = expr, env, counter) do
    args = Map.get(expr, :args) || Map.get(expr, :params) || []
    name = :"elmx_lambda_#{counter}"
    counter = counter + 1
    lambda_env = put_lambda_params(env, args)

    {body_code, _, _} = compile_expr(body, lambda_env, 0)

    param_refs =
      Enum.map_join(args, ", ", fn arg ->
        binding_ref(param_name(arg), lambda_env)
      end)

    {[
       "fn ",
       param_refs,
       " -> ",
       body_code,
       " end"
     ], Map.put(env, name, true), counter}
  end

  @comparison_ops ~w(__eq__ __neq__ __lt__ __lte__ __gt__ __gte__)

  defp compile_call(%{name: name, args: [left, right]}, env, counter)
       when name in ["__append__", "__add__", "__sub__", "__mul__", "__fdiv__", "__idiv__" | @comparison_ops] do
    {l, env, c1} = compile_expr(left, env, counter)
    {r, env, c2} = compile_expr(right, env, c1)

    code =
      case name do
        "__append__" -> ["Elmx.Runtime.Core.append(", l, ", ", r, ")"]
        "__idiv__" -> ["div(", l, ", ", r, ")"]
        "__fdiv__" -> ["(", l, " / ", r, ")"]
        other -> ["(", l, " ", operator_symbol(other), " ", r, ")"]
      end

    {code, env, c2}
  end

  defp compile_call(%{name: name, args: [arg]}, env, counter) when name in @comparison_ops do
    {fixed, env, c1} = compile_expr(arg, env, counter)
    op = operator_symbol(name)
    rhs = Helpers.let_emit_name("__rhs")
    {["fn ", rhs, " -> (", fixed, " ", op, " ", rhs, ") end"], env, c1}
  end

  defp compile_call(%{name: "__add__", args: [arg]}, env, counter) do
    {fixed, env, c1} = compile_expr(arg, env, counter)
    rhs = Helpers.let_emit_name("__rhs")
    {["fn ", rhs, " -> (", fixed, " + ", rhs, ") end"], env, c1}
  end

  defp compile_call(%{name: "__mul__", args: [arg]}, env, counter) do
    {fixed, env, c1} = compile_expr(arg, env, counter)
    rhs = Helpers.let_emit_name("__rhs")
    {["fn ", rhs, " -> (", fixed, " * ", rhs, ") end"], env, c1}
  end

  defp compile_call(%{name: "__sub__", args: [arg]}, env, counter) do
    {fixed, env, c1} = compile_expr(arg, env, counter)
    rhs = Helpers.let_emit_name("__rhs")
    {["fn ", rhs, " -> (", rhs, " - ", fixed, ") end"], env, c1}
  end

  defp compile_call(%{name: "__fdiv__", args: [arg]}, env, counter) do
    {fixed, env, c1} = compile_expr(arg, env, counter)
    rhs = Helpers.let_emit_name("__rhs")
    {["fn ", rhs, " -> (", rhs, " / ", fixed, ") end"], env, c1}
  end

  defp compile_call(%{name: "__idiv__", args: [arg]}, env, counter) do
    {fixed, env, c1} = compile_expr(arg, env, counter)
    rhs = Helpers.let_emit_name("__rhs")
    {["fn ", rhs, " -> div(", rhs, ", ", fixed, ") end"], env, c1}
  end

  defp compile_call(%{name: "__append__", args: [arg]}, env, counter) do
    {fixed, env, c1} = compile_expr(arg, env, counter)
    rhs = Helpers.let_emit_name("__rhs")
    {["fn ", rhs, " -> Elmx.Runtime.Core.append(", fixed, ", ", rhs, ") end"], env, c1}
  end

  defp compile_call(%{name: name, args: args}, env, counter) when is_list(args) do
    if operator_call?(name) do
      {arg_code, env, c1} = compile_arg_list(args, env, counter)
      {Stdlib.call(name, IO.iodata_to_binary(arg_code)), env, c1}
    else
      compile_user_call(name, args, env, counter)
    end
  end

  defp compile_call(%{name: name}, env, counter) do
    compile_call1(%{name: name}, env, counter)
  end

  defp operator_symbol("__append__"), do: "++"
  defp operator_symbol("__add__"), do: "+"
  defp operator_symbol("__sub__"), do: "-"
  defp operator_symbol("__mul__"), do: "*"
  defp operator_symbol("__fdiv__"), do: "/"
  defp operator_symbol("__eq__"), do: "=="
  defp operator_symbol("__neq__"), do: "!="
  defp operator_symbol("__lt__"), do: "<"
  defp operator_symbol("__lte__"), do: "<="
  defp operator_symbol("__gt__"), do: ">"
  defp operator_symbol("__gte__"), do: ">="

  defp operator_call?(name) when is_binary(name),
    do: String.starts_with?(name, "__")

  defp compile_call1(%{name: name}, env, counter) do
    compile_user_call(name, [], env, counter)
  end

  defp compile_user_call("clamp", [lo, hi, value], env, counter) do
    {lo_code, env, c1} = compile_expr(lo, env, counter)
    {hi_code, env, c2} = compile_expr(hi, env, c1)
    {val_code, env, c3} = compile_expr(value, env, c2)
    {["max(", lo_code, ", min(", hi_code, ", ", val_code, "))"], env, c3}
  end

  defp compile_user_call(name, args, env, counter) when is_binary(name) and is_list(args) do
  if Map.get(env, String.to_atom(name)) == true do
    {arg_parts, env, c1} = compile_arg_parts(args, env, counter)
    {[binding_ref(name, env), ".(", Enum.intersperse(arg_parts, ", "), ")"], env, c1}
  else
    case compile_basics_unqualified(name, args, env, counter) do
      {:ok, code, env, c} ->
        {code, env, c}

      :error ->
        {arg_parts, env, c1} = compile_arg_parts(args, env, counter)
        {compile_module_call(name, arg_parts, env), env, c1}
    end
  end
  end

  defp compile_basics_unqualified("max", args, env, counter),
    do: QualifiedEmit.compile_basics_qualified("Basics.max", args, env, counter)

  defp compile_basics_unqualified("min", args, env, counter),
    do: QualifiedEmit.compile_basics_qualified("Basics.min", args, env, counter)

  defp compile_basics_unqualified("modBy", args, env, counter),
    do: QualifiedEmit.compile_basics_qualified("Basics.modBy", args, env, counter)

  defp compile_basics_unqualified("remainderBy", args, env, counter),
    do: QualifiedEmit.compile_basics_qualified("Basics.remainderBy", args, env, counter)

  defp compile_basics_unqualified("not", args, env, counter),
    do: QualifiedEmit.compile_basics_qualified("Basics.not", args, env, counter)

  defp compile_basics_unqualified("abs", args, env, counter),
    do: QualifiedEmit.compile_basics_qualified("Basics.abs", args, env, counter)

  defp compile_basics_unqualified("negate", args, env, counter),
    do: QualifiedEmit.compile_basics_qualified("Basics.negate", args, env, counter)

  defp compile_basics_unqualified(_, _, _, _), do: :error

  defp compile_module_call("none", [], %{module: "Pebble.Cmd"}),
    do: "Elmx.Runtime.Values.cmd_none()"

  defp compile_module_call(name, arg_parts, %{module: "Pebble.Ui"}) when is_binary(name) do
    fun = name |> Macro.underscore() |> String.to_atom()
    ["Elmx.Runtime.Pebble.Ui.", Atom.to_string(fun), "(", Enum.intersperse(arg_parts, ", "), ")"]
  end

  defp compile_module_call(name, arg_parts, env) do
    module = Map.get(env, :module, "Main")
    arity = Helpers.function_arity(env, name)
    given = length(arg_parts)

    cond do
      arity == :unresolved ->
        if given == 0, do: name, else: [name, "(", Enum.intersperse(arg_parts, ", "), ")"]

      given == 0 and arity == 0 ->
        "#{module_fn(module, name)}()"

      given == 0 ->
        function_reference(module, name, env)

      given >= arity ->
        [module_fn(module, name), "(", Enum.intersperse(arg_parts, ", "), ")"]

      true ->
        partial_application_fun(module, name, arg_parts, arity - given)
    end
  end

  defp compile_qualified_call1(expr, env, counter),
    do: QualifiedEmit.compile_qualified_call1(expr, env, counter)

  defp compile_qualified_call(expr, env, counter),
    do: QualifiedEmit.compile_qualified_call(expr, env, counter)

  defp compile_constructor(%{target: target, args: args}, env, counter) when is_binary(target) do
    compile_constructor(%{name: target, args: args}, env, counter)
  end

  defp compile_constructor(%{name: name, args: args} = _expr, env, counter) when is_binary(name) do
    ctor_name = constructor_emit_name(name, env)
    {arg_code, env, c1} = compile_arg_list(args, env, counter)
    arg_str = IO.iodata_to_binary(arg_code)

    code =
      case Map.get(env, :emit_mode) do
        :ide_runtime ->
          ide_runtime_constructor_code(ctor_name, args, arg_str, name, env)

        _ ->
          case args do
            [] -> zero_arg_constructor_code(name, env)
            _ -> "Elmx.Runtime.Values.ctor(#{inspect(ctor_name)}, [#{arg_str}])"
          end
      end

    {code, env, c1}
  end

  defp constructor_emit_name(name, env) do
    case Map.get(env, :constructor_lookup) do
      lookup when is_map(lookup) ->
        case ConstructorLookup.resolve(lookup, name, Map.get(env, :module)) do
          %{constructor: ctor} when is_binary(ctor) -> ctor
          _ -> Helpers.pattern_ctor_name(name)
        end

      _ ->
        Helpers.pattern_ctor_name(name)
    end
  end

  defp zero_arg_constructor_code(name, env) do
    ctor = constructor_emit_name(name, env)

    case Map.get(env, :emit_mode) do
      :ide_runtime ->
        ide_runtime_zero_arg_code(ctor)

      _ ->
        zero_arg_constructor_code_library(name, ctor, env)
    end
  end

  defp ide_runtime_zero_arg_code("True"), do: "true"
  defp ide_runtime_zero_arg_code("False"), do: "false"
  defp ide_runtime_zero_arg_code("()"), do: "nil"
  defp ide_runtime_zero_arg_code(ctor), do: ":#{ctor}"

  defp ide_runtime_ctor_atom("()"), do: "nil"
  defp ide_runtime_ctor_atom(ctor), do: ":#{ctor}"

  defp ide_runtime_constructor_code(_ctor, [], _arg_str, name, env),
    do: zero_arg_constructor_code(name, env)

  # Tagged tuples match `case` patterns (`{:Just, x}`, `{:Ctor, a, b}`).
  defp ide_runtime_constructor_code(ctor, args, arg_str, _name, _env)
       when is_list(args) and length(args) <= 4 do
    "{:#{ctor}, #{arg_str}}"
  end

  defp ide_runtime_constructor_code(ctor, _args, arg_str, _name, _env) do
    "Elmx.Runtime.Values.ctor(#{inspect(ctor)}, [#{arg_str}])"
  end

  defp zero_arg_constructor_code_library(name, ctor, env) do
    case Map.get(env, :constructor_lookup) do
      lookup when is_map(lookup) ->
        case ConstructorLookup.resolve(lookup, name, Map.get(env, :module)) do
          %{tag: tag} when is_integer(tag) -> Integer.to_string(tag)
          _ -> ":#{ctor}"
        end

      _ ->
        ":#{ctor}"
    end
  end

  defp compile_runtime_call(%{function: function, args: args}, env, counter) do
    {parts, {env, c1}} =
      Enum.map_reduce(args, {env, counter}, fn arg, {env, c} ->
        {code, env, c} = compile_expr(arg, env, c)
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

  defp compile_let_in(%{name: name, value_expr: value, in_expr: body}, env, counter) do
    {value_code, env, c1} = compile_expr(value, env, counter)
    emit_name = Helpers.let_emit_name(name)
    body_env = Map.put(env, String.to_atom(name), true)
    {body_code, _, c2} = compile_expr(body, body_env, c1)

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

  defp compile_var(name, env, counter) when is_binary(name) do
    case String.split(name, ".") do
      [^name] ->
        compile_var_simple(name, env, counter)

      [base | fields] ->
        with {:ok, base_code, env, c} <- compile_var_simple(base, env, counter) do
          code =
            Enum.reduce(fields, base_code, fn field, acc ->
              ["Map.get(", acc, ", ", inspect(field), ")"]
            end)

          {:ok, code, env, c}
        end
    end
  end

  defp compile_var_simple(name, env, counter) when is_binary(name) do
    case compile_constructor_reference(name, env, counter) do
      {:ok, code, env, c} ->
        {:ok, code, env, c}

      :error ->
        if Map.get(env, String.to_atom(name)) == true do
          {:ok, binding_ref(name, env), env, counter}
        else
          :error
        end
    end
  end

  defp compile_if(%{cond: condition, then_expr: then_expr, else_expr: else_expr}, env, counter) do
    compile_if(%{condition: condition, then_expr: then_expr, else_expr: else_expr}, env, counter)
  end

  defp compile_if(%{condition: condition, then_expr: then_expr, else_expr: else_expr}, env, counter) do
    {c, env, c1} = compile_expr(condition, env, counter)
    {t, env, c2} = compile_expr(then_expr, env, c1)
    {e, env, c3} = compile_expr(else_expr, env, c2)
    {["(if ", c, " do\n    ", t, "\n  else\n    ", e, "\n  end)"], env, c3}
  end

  defp compile_tuple_accessor(%{target: target}, env, counter, index) do
    {t, env, c1} = compile_expr(target, env, counter)
    {["elem(", t, ", ", Integer.to_string(index), ")"], env, c1}
  end

  defp compile_tuple_accessor(%{arg: arg}, env, counter, index) do
    compile_tuple_accessor(%{target: arg}, env, counter, index)
  end

  defp compile_string_length(%{arg: arg}, env, counter) do
    {a, env, c1} = compile_expr(arg, env, counter)
    {["String.length(", a, ")"], env, c1}
  end

  defp compile_char_from_code(%{arg: arg}, env, counter) do
    {a, env, c1} = compile_expr(arg, env, counter)
    {["<<", a, "::utf8>>"], env, c1}
  end

  defp compile_arg_list(args, env, counter) when is_list(args) do
    {parts, env, counter} = compile_arg_parts(args, env, counter)
    {Enum.intersperse(parts, ", "), env, counter}
  end

  defp compile_arg_parts(args, env, counter) when is_list(args) do
    Enum.map_reduce(args, {env, counter}, fn arg, {env, c} ->
      {code, env, c} = compile_expr(arg, env, c)
      {code, {env, c}}
    end)
    |> then(fn {parts, {env, c}} -> {parts, env, c} end)
  end

  defp compile_record_field_value(field, expr, env, counter) do
    {code, env, c} = compile_expr(expr, env, counter)

    code =
      case {expr, maybe_field_type(env, field)} do
        {%{op: :int_literal, value: 0}, "Maybe " <> _} -> ":Nothing"
        _ -> code
      end

    {code, env, c}
  end

  defp maybe_field_type(env, field) when is_binary(field) do
    env
    |> Map.get(:record_field_types, %{})
    |> Map.values()
    |> Enum.find_value(fn types -> Map.get(types, field) end)
  end

  defp var_ref(name, env) when is_binary(name) do
    if parameter_binding?(name, env) do
      binding_ref(name, env)
    else
      case Map.get(env, :module) do
        module when is_binary(module) -> function_reference(module, name, env)
        _ -> name
      end
    end
  end

  defp parameter_binding?(name, env) when is_binary(name) and is_map(env) do
    Map.get(env, String.to_atom(name)) == true
  end

  defp function_reference(module, name, env) do
    if parameter_binding?(name, env) do
      binding_ref(name, env)
    else
      function_reference_uncurried(module, name, env)
    end
  end

  defp function_reference_uncurried(_module, "identity", _env), do: "fn x -> x end"

  defp function_reference_uncurried(module, name, env) do
    fn_sym = module_fn(module, name)
    zero_arity = Map.get(env, :zero_arity_fns, MapSet.new())

    case function_arity(env, name) do
      :unresolved ->
        name

      0 ->
        if MapSet.member?(zero_arity, name) do
          "#{fn_sym}()"
        else
          "&#{fn_sym}/0"
        end

      arity when is_integer(arity) and arity > 0 ->
        "&#{fn_sym}/#{arity}"
    end
  end

  defp function_arity(env, name) when is_binary(name) do
    case Map.get(Map.get(env, :function_arities, %{}), name) do
      nil -> :unresolved
      arity when is_integer(arity) -> arity
    end
  end

  defp partial_application_fun(module, name, fixed_parts, 1) do
    fn_sym = module_fn(module, name)

    ["&", fn_sym, "(", Enum.intersperse(fixed_parts, ", "), ", &1)"]
  end

  defp partial_application_fun(module, name, fixed_parts, remaining) when remaining > 1 do
    fn_sym = module_fn(module, name)
    param_names = Enum.map(1..remaining, &Helpers.let_emit_name("__p#{&1}"))
    all_args = fixed_parts ++ param_names
    inner = [fn_sym, "(", Enum.intersperse(all_args, ", "), ")"]

    Enum.reduce(Enum.reverse(param_names), inner, fn param, body ->
      ["fn ", param, " -> ", body, " end"]
    end)
  end

  defp compile_constructor_reference(name, env, counter) when is_binary(name) do
    lookup = Map.get(env, :constructor_lookup)
    module = Map.get(env, :module)

    with lookup when is_map(lookup) <- lookup,
         entry when is_map(entry) <- ConstructorLookup.resolve(lookup, name, module),
         {:ok, rewritten} <- ConstructorEmit.rewrite(entry) do
      {code, env, c} = compile_expr(rewritten, env, counter)
      {:ok, code, env, c}
    else
      _ -> :error
    end
  end

  defp binding_ref(name, env), do: Helpers.binding_ref(name, env)

  defp put_lambda_params(env, args) do
    Enum.reduce(args, env, fn arg, acc -> Map.put(acc, String.to_atom(param_name(arg)), true) end)
  end

  defp record_update_field({name, value}) when is_binary(name), do: {name, value}
  defp record_update_field(%{name: name, expr: value}), do: {to_string(name), value}
  defp record_update_field(%{field: name, value: value}), do: {to_string(name), value}
  defp record_update_field(%{field: name, expr: value}), do: {to_string(name), value}

  @spec param_name(term()) :: String.t()
  def param_name(arg) when is_binary(arg), do: arg
  def param_name(arg) when is_atom(arg), do: Atom.to_string(arg)
  def param_name(%{name: name}), do: to_string(name)
  def param_name(name), do: to_string(name)

  defp module_fn(module, function) do
    "elmx_fn_#{safe_module(module)}_#{function}"
  end

  defp safe_module(name), do: name |> String.replace(".", "_")

  defp normalize_record_fields(fields) when is_list(fields) do
    Enum.map(fields, fn
      {name, value} when is_binary(name) -> {name, value}
      %{field: name, value: value} -> {to_string(name), value}
      %{field: name, expr: value} -> {to_string(name), value}
      %{name: name, value: value} -> {to_string(name), value}
      %{name: name, expr: value} -> {to_string(name), value}
      other -> raise "unsupported record field #{inspect(other)}"
    end)
  end
end
