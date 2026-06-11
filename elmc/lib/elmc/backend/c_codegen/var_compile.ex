defmodule Elmc.Backend.CCodegen.VarCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.Types

  @spec compile(Types.ir_var_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :var, name: name} = expr, env, counter) when is_binary(name) do
    if RecordCompile.subexpr_cache_active?(env) and top_level_zero_arg_var?(name, env) do
      {code, ref, counter, _env} =
        RecordCompile.compile_expr_cached(expr, env, counter, &compile_var_expr/3)

      {code, ref, counter}
    else
      compile_var_expr(expr, env, counter)
    end
  end

  defp compile_var_expr(%{op: :var, name: name}, env, counter) when is_binary(name) do
    case String.split(name, ".", parts: 2) do
      [base, field] when field != "" ->
        Host.compile_expr(%{op: :field_access, arg: base, field: field}, env, counter)

      _ ->
        FunctionCallCompile.compile_var(name, env, counter)
    end
  end

  defp top_level_zero_arg_var?(name, env) when is_binary(name) do
    module_name = Map.get(env, :__module__, "Main")

    not Map.has_key?(env, name) and
      EnvBindings.function_arity(env, module_name, name, []) == 0
  end
end
