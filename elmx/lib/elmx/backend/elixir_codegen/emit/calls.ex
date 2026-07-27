defmodule Elmx.Backend.ElixirCodegen.Emit.Calls do
  @moduledoc false
  alias Elmx.Types, as: Types


  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified, as: QualifiedEmit
  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Stdlib

  @rt_core CodegenRefs.core()
  @rt_values CodegenRefs.values()
  @rt_pebble_ui CodegenRefs.pebble_ui()

@comparison_ops ~w(__eq__ __neq__ __lt__ __lte__ __gt__ __gte__)
  @pipeline_flatten_threshold 16

  @spec compile_call(map(), Types.compile_env(), Types.elm_value()) :: Types.elm_value()

  def compile_call(%{name: "__apply__", args: [fun, arg]}, env, counter) do
    case fun do
      %{op: :var, name: name} when is_binary(name) ->
        compile_apply_to_target(name, [arg], env, counter)

      _ ->
        {fun_code, env, c1} = Emit.compile_expr(fun, env, counter)
        {arg_code, env, c2} = Emit.compile_expr(arg, env, c1)
        {["Elmx.Runtime.Core.Apply.call1(", fun_code, ", ", arg_code, ")"], env, c2}
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
            {["Elmx.Runtime.Core.Apply.call1(", acc, ", ", arg_code, ")"], acc_env, next_c}
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

  def compile_call(%{name: "<|", args: [fun, arg]}, env, counter) do
    {fun_code, env, c1} = Emit.compile_expr(fun, env, counter)
    {arg_code, env, c2} = Emit.compile_expr(arg, env, c1)
    {["Elmx.Runtime.Core.Apply.call1(", fun_code, ", ", arg_code, ")"], env, c2}
  end

  def compile_call(%{name: "|>", args: [arg, fun]}, env, counter) do
    expr = %{op: :call, name: "|>", args: [arg, fun]}

    case unwrap_pipe_pipeline(expr) do
      {:ok, steps, base} when length(steps) >= @pipeline_flatten_threshold ->
        if homogeneous_pipe_steps?(steps) do
          compile_homogeneous_pipe_block(hd(steps), length(steps), base, env, counter)
        else
          compile_pipe_pipeline_block(steps, base, env, counter)
        end

      _ ->
        {fun_code, env, c1} = Emit.compile_expr(fun, env, counter)
        {arg_code, env, c2} = Emit.compile_expr(arg, env, c1)
        {["Elmx.Runtime.Core.Apply.call1(", fun_code, ", ", arg_code, ")"], env, c2}
    end
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

  @spec compile_apply_to_target(String.t(), list(), Types.compile_env(), Types.elm_value()) :: Types.elm_value()

  defp compile_apply_to_target(name, args, env, counter) when is_binary(name) and is_list(args) do
    compile_user_call(name, args, env, counter)
  end

  @spec operator_symbol(Types.elm_value()) :: Types.elm_value()

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

  @spec operator_call?(String.t()) :: boolean()

  def operator_call?(name) when is_binary(name),
    do: String.starts_with?(name, "__")

  @spec compile_call1(map(), Types.compile_env(), Types.elm_value()) :: Types.elm_value()

  def compile_call1(%{name: name}, env, counter) do
    compile_user_call(name, [], env, counter)
  end

  @spec compile_user_call(Types.elm_value() | String.t(), term() | list(), Types.compile_env(), Types.elm_value()) :: Types.elm_value()

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
            # Use call1 so multi-arity Elixir captures (`&fn/2`) curried-apply correctly.
            ["Elmx.Runtime.Core.Apply.call1(", ref, ", ", arg, ")"]

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

  @spec compile_basics_unqualified(String.t() | term(), [String.t()] | term(), Types.compile_env() | term(), Types.elm_value() | term()) :: Types.elm_value()

  def compile_basics_unqualified(name, args, env, counter)
       when name in ["max", "min", "modBy", "remainderBy", "not", "abs", "negate"] do
    QualifiedEmit.compile_stdlib_qualified_ir("Basics.#{name}", args, env, counter)
  end

  def compile_basics_unqualified(_, _, _, _), do: :error

  @spec compile_module_call(Types.elm_value() | String.t(), term() | Types.elm_value(), map() | Types.compile_env()) :: Types.elm_value()

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

  @spec compile_module_call_body(String.t(), Types.elm_value(), Types.compile_env(), String.t()) :: Types.elm_value()

  defp compile_module_call_body(name, arg_parts, env, module) do
    arity = Helpers.function_arity(env, name)
    given = length(arg_parts)

    cond do
      Map.get(env, :emit_partial_value) == true and given < arity ->
        [Helpers.module_fn(module, name), "(", Enum.intersperse(arg_parts, ", "), ")"]

      # Effect-manager leaf (`effect module Task where { command = MyCmd }`):
      # IR lowers `command payload` as a bare call with no declared local.
      arity == :unresolved and name in ~w(command subscription) ->
        effect_manager_leaf(arg_parts)

      arity == :unresolved ->
        emit_name = Helpers.let_emit_name(name)
        if given == 0, do: emit_name, else: [emit_name, "(", Enum.intersperse(arg_parts, ", "), ")"]

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
            ["Elmx.Runtime.Core.Apply.call1(", acc, ", ", arg, ")"]
          end)
        end

      given == arity ->
        [Helpers.module_fn(module, name), "(", Enum.intersperse(arg_parts, ", "), ")"]

      true ->
        Helpers.partial_application_fun(module, name, arg_parts, arity - given)
    end
  end

  # Platform.command / effect `command` and `subscription` are identity wrappers in elmx.
  @spec effect_manager_leaf(term()) :: Types.elm_value()

  defp effect_manager_leaf([]), do: "fn elmx_leaf -> elmx_leaf end"
  defp effect_manager_leaf([arg]), do: arg

  defp effect_manager_leaf([arg | rest]) do
    Enum.reduce(rest, arg, fn next, acc ->
      ["Elmx.Runtime.Core.Apply.call1(", acc, ", ", next, ")"]
    end)
  end

  @spec compile_qualified_call1(Types.expr(), Types.compile_env(), Types.elm_value()) :: Types.elm_value()

  def compile_qualified_call1(expr, env, counter),
    do: QualifiedEmit.compile_qualified_call1(expr, env, counter)

  @spec compile_qualified_call(Types.expr(), Types.compile_env(), Types.elm_value()) :: Types.elm_value()

  def compile_qualified_call(expr, env, counter),
    do: QualifiedEmit.compile_qualified_call(expr, env, counter)

  @spec compile_pipe_chain(map(), Types.compile_env(), Types.elm_value()) :: Types.elm_value()

  def compile_pipe_chain(%{steps: steps, base: base}, env, counter) when is_list(steps) do
    {homogeneous_prefix, rest} = split_homogeneous_prefix_steps(steps)

    if length(homogeneous_prefix) >= @pipeline_flatten_threshold do
      compile_homogeneous_pipe_steps(hd(homogeneous_prefix), length(homogeneous_prefix), base, rest, env, counter)
    else
      compile_pipe_steps_iterative(steps, base, env, counter)
    end
  end

  @spec split_homogeneous_prefix_steps(term()) :: Types.elm_value()

  defp split_homogeneous_prefix_steps([]), do: {[], []}

  defp split_homogeneous_prefix_steps([first | rest]) do
    {same, other} = Enum.split_while(rest, &(&1 == first))
    {[first | same], other}
  end

  @spec compile_homogeneous_pipe_steps(Types.elm_value(), non_neg_integer(), Types.elm_value(), Types.elm_value(), Types.compile_env(), Types.elm_value()) :: Types.elm_value()

  defp compile_homogeneous_pipe_steps(step, count, base, rest, env, counter) do
    {base_code, env, c0} = Emit.compile_expr(base, env, counter)
    {step_code, env, c1} = Emit.compile_expr(step, env, c0)

    reduce_code = [
      "Elmx.Runtime.Core.Apply.repeat1(",
      step_code,
      ", ",
      Integer.to_string(count),
      ", ",
      base_code,
      ")"
    ]

    {final_code, env, c} =
      case rest do
        [] ->
          {reduce_code, env, c1}

        _ ->
          compile_step = fn rest_step, prev_slot, c ->
            step_env = Map.put(env, String.to_atom(prev_slot), true)
            {step_code, _, c1} = compile_pipe_step(rest_step, prev_slot, step_env, c)
            {step_code, c1}
          end

          {code, _, c} = Helpers.compile_pipe_iife(reduce_code, rest, compile_step, c1)
          {code, env, c}
      end

    {final_code, env, c}
  end

  @spec compile_pipe_step(Types.elm_value(), String.t(), Types.compile_env(), Types.elm_value()) :: Types.elm_value()

  defp compile_pipe_step(step, acc_name, env, counter) do
    acc_expr = %{op: :var, name: acc_name}
    Emit.compile_expr(append_pipe_arg(step, acc_expr), env, counter)
  end

  @spec append_pipe_arg(map() | Types.elm_value(), Types.elm_value()) :: Types.elm_value()

  defp append_pipe_arg(%{op: :qualified_call, target: target, args: args}, arg) when is_list(args) do
    %{op: :qualified_call, target: target, args: args ++ [arg]}
  end

  defp append_pipe_arg(%{op: :call, name: name, args: args}, arg) when is_binary(name) and is_list(args) do
    %{op: :call, name: name, args: args ++ [arg]}
  end

  defp append_pipe_arg(%{op: :var, name: name}, arg) when is_binary(name) do
    %{op: :call, name: name, args: [arg]}
  end

  defp append_pipe_arg(%{op: :qualified_ref, target: target}, arg) do
    %{op: :qualified_call, target: target, args: [arg]}
  end

  defp append_pipe_arg(step, arg) do
    %{op: :call, name: "|>", args: [arg, step]}
  end

  @spec compile_pipe_steps_iterative(Types.elm_value(), Types.elm_value(), Types.compile_env(), Types.elm_value()) :: Types.elm_value()

  defp compile_pipe_steps_iterative(steps, base, env, counter) do
    {base_code, env, c0} = Emit.compile_expr(base, env, counter)

    compile_step = fn step, prev_slot, c ->
      step_env = Map.put(env, String.to_atom(prev_slot), true)
      {step_code, _, c1} = compile_pipe_step(step, prev_slot, step_env, c)
      {step_code, c1}
    end

    {code, _, c} = Helpers.compile_pipe_iife(base_code, steps, compile_step, c0)
    {code, env, c}
  end

  @spec apply_call(Types.elm_value(), list()) :: Types.elm_value()

  defp apply_call(ref, parts) when is_list(parts) and length(parts) > 1 do
    n = length(parts)
    [@rt_core, ".apply#{n}(", ref, ", ", Enum.intersperse(parts, ", "), ")"]
  end

  @spec port_signature?(Types.compile_env(), String.t(), String.t()) :: boolean()

  defp port_signature?(env, module, name) do
    Map.get(Map.get(env, :port_signatures, %{}), {module, name}) == true
  end

  @spec compile_port_call(String.t(), Types.elm_value() | String.t(), term() | Types.elm_value()) :: Types.elm_value()

  defp compile_port_call(module, "outgoing", [payload]) do
    [@rt_values, ".port_outgoing(", inspect("#{module}.outgoing"), ", ", payload, ")"]
  end

  defp compile_port_call(module, "incoming", [callback]) do
    [@rt_values, ".port_incoming_sub(", inspect("#{module}.incoming"), ", ", callback, ")"]
  end

  defp compile_port_call(_module, _name, arg_parts) do
  [@rt_values, ".port_outgoing(", inspect("unknown.port"), ", ", Enum.at(arg_parts, 0, "nil"), ")"]
  end

  @spec unwrap_pipe_pipeline(Types.expr() | map(), term()) :: Types.elm_value()

  defp unwrap_pipe_pipeline(expr), do: unwrap_pipe_pipeline(expr, [])

  defp unwrap_pipe_pipeline(%{op: :call, name: "|>", args: [left, fun]}, acc) do
    case left do
      %{op: :call, name: "|>", args: [inner_left, inner_fun]} ->
        unwrap_pipe_pipeline(%{op: :call, name: "|>", args: [inner_left, inner_fun]}, [fun | acc])

      base ->
        {:ok, Enum.reverse([fun | acc]), base}
    end
  end

  defp unwrap_pipe_pipeline(_expr, _acc), do: :error

  @spec homogeneous_pipe_steps?(term()) :: boolean()

  defp homogeneous_pipe_steps?([step | rest]), do: Enum.all?(rest, &(&1 == step))

  @spec compile_homogeneous_pipe_block(Types.elm_value(), non_neg_integer(), Types.elm_value(), Types.compile_env(), Types.elm_value()) :: Types.elm_value()

  defp compile_homogeneous_pipe_block(step, count, base, env, counter) do
    {base_code, env, c0} = Emit.compile_expr(base, env, counter)
    {step_code, env, c1} = Emit.compile_expr(step, env, c0)

    code = [
      "Elmx.Runtime.Core.Apply.repeat1(",
      step_code,
      ", ",
      Integer.to_string(count),
      ", ",
      base_code,
      ")"
    ]

    {code, env, c1}
  end

  @spec compile_pipe_pipeline_block(Types.elm_value(), Types.elm_value(), Types.compile_env(), Types.elm_value()) :: Types.elm_value()

  defp compile_pipe_pipeline_block(steps, base, env, counter) do
    {base_code, env, c0} = Emit.compile_expr(base, env, counter)

    compile_step = fn step, prev_slot, c ->
      {step_code, _, c1} = Emit.compile_expr(step, env, c)
      {["Elmx.Runtime.Core.Apply.call1(", step_code, ", ", prev_slot, ")"], c1}
    end

    {code, _, c} = Helpers.compile_pipe_iife(base_code, steps, compile_step, c0)
    {code, env, c}
  end

end
