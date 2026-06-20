defmodule Elmx.Backend.ElixirCodegen.Emit.Calls do
  @moduledoc false

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified, as: QualifiedEmit
  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Stdlib

  @rt_core CodegenRefs.core()
  @rt_values CodegenRefs.values()
  @rt_pebble_ui CodegenRefs.pebble_ui()

@comparison_ops ~w(__eq__ __neq__ __lt__ __lte__ __gt__ __gte__)

  def compile_call(%{name: "__apply__", args: [fun, arg]}, env, counter) do
    case fun do
      %{op: :var, name: name} when is_binary(name) ->
        compile_apply_to_target(name, [arg], env, counter)

      _ ->
        {fun_code, env, c1} = Emit.compile_expr(fun, env, counter)
        {arg_code, env, c2} = Emit.compile_expr(arg, env, c1)
        {["Elmx.Runtime.Core.Apply.apply1(", fun_code, ", ", arg_code, ")"], env, c2}
    end
  end

  def compile_call(%{name: "__apply__", args: args}, env, counter) when is_list(args) and length(args) >= 2 do
    [fun | rest] = args

    case fun do
      %{op: :var, name: name} when is_binary(name) ->
        compile_apply_to_target(name, rest, env, counter)

      _ ->
        {fun_code, env, c} = Emit.compile_expr(fun, env, counter)

        {code, env, final_c} =
          Enum.reduce(rest, {fun_code, env, c}, fn arg, {acc, acc_env, acc_c} ->
            {arg_code, acc_env, next_c} = Emit.compile_expr(arg, acc_env, acc_c)
            {["Elmx.Runtime.Core.Apply.apply1(", acc, ", ", arg_code, ")"], acc_env, next_c}
          end)

        {code, env, final_c}
    end
  end

  def compile_call(%{name: "__pow__", args: [left, right]}, env, counter) do
    {l, env, c1} = Emit.compile_expr(left, env, counter)
    {r, env, c2} = Emit.compile_expr(right, env, c1)
    {["trunc(Elmx.Runtime.Core.Math.pow(", l, ", ", r, "))"], env, c2}
  end

  def compile_call(%{name: name, args: [left, right]}, env, counter)
       when name in ["__append__", "__add__", "__sub__", "__mul__", "__fdiv__", "__idiv__" | @comparison_ops] do
    {l, env, c1} = Emit.compile_expr(left, env, counter)
    {r, env, c2} = Emit.compile_expr(right, env, c1)

    code =
      case name do
        "__append__" -> [@rt_core, ".append(", l, ", ", r, ")"]
        "__idiv__" -> [@rt_core, ".basics_idiv(", l, ", ", r, ")"]
        "__fdiv__" -> ["Elmx.Runtime.Core.Math.fdiv(", l, ", ", r, ")"]
        other -> ["(", l, " ", operator_symbol(other), " ", r, ")"]
      end

    {code, env, c2}
  end

  def compile_call(%{name: name, args: [arg]}, env, counter) when name in @comparison_ops do
    {fixed, env, c1} = Emit.compile_expr(arg, env, counter)
    op = operator_symbol(name)
    rhs = Helpers.let_emit_name("__rhs")
    {["fn ", rhs, " -> (", fixed, " ", op, " ", rhs, ") end"], env, c1}
  end

  def compile_call(%{name: "__add__", args: [arg]}, env, counter) do
    {fixed, env, c1} = Emit.compile_expr(arg, env, counter)
    rhs = Helpers.let_emit_name("__rhs")
    {["fn ", rhs, " -> (", fixed, " + ", rhs, ") end"], env, c1}
  end

  def compile_call(%{name: "__mul__", args: [arg]}, env, counter) do
    {fixed, env, c1} = Emit.compile_expr(arg, env, counter)
    rhs = Helpers.let_emit_name("__rhs")
    {["fn ", rhs, " -> (", fixed, " * ", rhs, ") end"], env, c1}
  end

  def compile_call(%{name: "__sub__", args: [arg]}, env, counter) do
    {fixed, env, c1} = Emit.compile_expr(arg, env, counter)
    rhs = Helpers.let_emit_name("__rhs")
    {["fn ", rhs, " -> (", rhs, " - ", fixed, ") end"], env, c1}
  end

  def compile_call(%{name: "__fdiv__", args: [arg]}, env, counter) do
    {fixed, env, c1} = Emit.compile_expr(arg, env, counter)
    rhs = Helpers.let_emit_name("__rhs")
    {["fn ", rhs, " -> Elmx.Runtime.Core.Math.fdiv(", rhs, ", ", fixed, ") end"], env, c1}
  end

  def compile_call(%{name: "__idiv__", args: [arg]}, env, counter) do
    {fixed, env, c1} = Emit.compile_expr(arg, env, counter)
    rhs = Helpers.let_emit_name("__rhs")
    {["fn ", rhs, " -> ", @rt_core, ".basics_idiv(", rhs, ", ", fixed, ") end"], env, c1}
  end

  def compile_call(%{name: "__append__", args: [arg]}, env, counter) do
    {fixed, env, c1} = Emit.compile_expr(arg, env, counter)
    rhs = Helpers.let_emit_name("__rhs")
    {["fn ", rhs, " -> ", @rt_core, ".append(", fixed, ", ", rhs, ") end"], env, c1}
  end

  def compile_call(%{name: name, args: args}, env, counter) when is_list(args) do
    if operator_call?(name) do
      {arg_code, env, c1} = Helpers.compile_arg_list(args, env, counter)
      {Stdlib.call(name, IO.iodata_to_binary(arg_code)), env, c1}
    else
      compile_user_call(name, args, env, counter)
    end
  end

  def compile_call(%{name: name}, env, counter) do
    compile_call1(%{name: name}, env, counter)
  end

  defp compile_apply_to_target(name, args, env, counter) when is_binary(name) and is_list(args) do
    compile_user_call(name, args, env, counter)
  end

  def operator_symbol("__append__"), do: "++"
  def operator_symbol("__add__"), do: "+"
  def operator_symbol("__sub__"), do: "-"
  def operator_symbol("__mul__"), do: "*"
  def operator_symbol("__fdiv__"), do: "/"
  def operator_symbol("__eq__"), do: "=="
  def operator_symbol("__neq__"), do: "!="
  def operator_symbol("__lt__"), do: "<"
  def operator_symbol("__lte__"), do: "<="
  def operator_symbol("__gt__"), do: ">"
  def operator_symbol("__gte__"), do: ">="

  def operator_call?(name) when is_binary(name),
    do: String.starts_with?(name, "__")

  def compile_call1(%{name: name}, env, counter) do
    compile_user_call(name, [], env, counter)
  end

  def compile_user_call("clamp", [lo, hi, value], env, counter) do
    {lo_code, env, c1} = Emit.compile_expr(lo, env, counter)
    {hi_code, env, c2} = Emit.compile_expr(hi, env, c1)
    {val_code, env, c3} = Emit.compile_expr(value, env, c2)
    {["max(", lo_code, ", min(", hi_code, ", ", val_code, "))"], env, c3}
  end

  def compile_user_call(name, args, env, counter) when is_binary(name) and is_list(args) do
    if Map.get(env, String.to_atom(name)) == true do
      {arg_parts, env, c1} = Helpers.compile_arg_parts(args, env, counter)
      ref = Helpers.binding_ref(name, env)

      code =
        case arg_parts do
          [] ->
            ref

          [arg] ->
            [ref, ".(", arg, ")"]

          parts ->
            apply_call(ref, parts)
        end

      {[code], env, c1}
    else
      case compile_basics_unqualified(name, args, env, counter) do
        {:ok, code, env, c} ->
          {code, env, c}

        :error ->
          {arg_parts, env, c1} = Helpers.compile_arg_parts(args, env, counter)
          {compile_module_call(name, arg_parts, env), env, c1}
      end
    end
  end

  def compile_basics_unqualified(name, args, env, counter)
       when name in ["max", "min", "modBy", "remainderBy", "not", "abs", "negate"] do
    QualifiedEmit.compile_stdlib_qualified_ir("Basics.#{name}", args, env, counter)
  end

  def compile_basics_unqualified(_, _, _, _), do: :error

  def compile_module_call("none", [], %{module: "Pebble.Cmd"}),
    do: [@rt_values, ".cmd_none()"]

  def compile_module_call(name, arg_parts, %{module: "Pebble.Ui"}) when is_binary(name) do
    fun = name |> Macro.underscore() |> String.to_atom()
    [@rt_pebble_ui, ".", Atom.to_string(fun), "(", Enum.intersperse(arg_parts, ", "), ")"]
  end

  def compile_module_call(name, arg_parts, env) do
    module = Map.get(env, :module, "Main")

    if port_signature?(env, module, name) do
      compile_port_call(module, name, arg_parts)
    else
      compile_module_call_body(name, arg_parts, env, module)
    end
  end

  defp compile_module_call_body(name, arg_parts, env, module) do
    arity = Helpers.function_arity(env, name)
    given = length(arg_parts)

    cond do
      Map.get(env, :emit_partial_value) == true and given < arity ->
        [Helpers.module_fn(module, name), "(", Enum.intersperse(arg_parts, ", "), ")"]

      arity == :unresolved ->
        if given == 0, do: name, else: [name, "(", Enum.intersperse(arg_parts, ", "), ")"]

      given == 0 and arity == 0 ->
        "#{Helpers.module_fn(module, name)}()"

      given == 0 ->
        Helpers.function_reference(module, name, env)

      given > arity ->
        explicit = arity
        callable = Map.get(Map.get(env, :function_arities, %{}), name, explicit)

        if explicit == 0 and given == callable do
          [Helpers.module_fn(module, name), "(", Enum.intersperse(arg_parts, ", "), ")"]
        else
          {fixed, extra} = Enum.split(arg_parts, explicit)

          base =
            if fixed == [] do
              Helpers.function_reference(module, name, env)
            else
              [Helpers.module_fn(module, name), "(", Enum.intersperse(fixed, ", "), ")"]
            end

          Enum.reduce(extra, base, fn arg, acc ->
            ["Elmx.Runtime.Core.Apply.apply1(", acc, ", ", arg, ")"]
          end)
        end

      given == arity ->
        [Helpers.module_fn(module, name), "(", Enum.intersperse(arg_parts, ", "), ")"]

      true ->
        Helpers.partial_application_fun(module, name, arg_parts, arity - given)
    end
  end

  def compile_qualified_call1(expr, env, counter),
    do: QualifiedEmit.compile_qualified_call1(expr, env, counter)

  def compile_qualified_call(expr, env, counter),
    do: QualifiedEmit.compile_qualified_call(expr, env, counter)

  defp apply_call(ref, parts) when is_list(parts) and length(parts) > 1 do
    n = length(parts)
    [@rt_core, ".apply#{n}(", ref, ", ", Enum.intersperse(parts, ", "), ")"]
  end

  defp port_signature?(env, module, name) do
    Map.get(Map.get(env, :port_signatures, %{}), {module, name}) == true
  end

  defp compile_port_call(module, "outgoing", [payload]) do
    [@rt_values, ".port_outgoing(", inspect("#{module}.outgoing"), ", ", payload, ")"]
  end

  defp compile_port_call(module, "incoming", [callback]) do
    [@rt_values, ".port_incoming_sub(", inspect("#{module}.incoming"), ", ", callback, ")"]
  end

  defp compile_port_call(_module, _name, arg_parts) do
  [@rt_values, ".port_outgoing(", inspect("unknown.port"), ", ", Enum.at(arg_parts, 0, "nil"), ")"]
  end

end
