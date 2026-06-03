defmodule Elmc.Backend.CCodegen.VarArithCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Types

  @spec compile(Types.ir_var_arith_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :add_const, var: name, value: value}, env, counter) do
    if EnvBindings.native_int_binding?(env, name) do
      NativeInt.compile_boxed(
        %{
          op: :call,
          name: "__add__",
          args: [%{op: :var, name: name}, %{op: :int_literal, value: value}]
        },
        env,
        counter
      )
    else
      {prefix, source, counter} = FunctionCallCompile.value_source(env, name, counter)
      next = counter + 1
      var = "tmp_#{next}"

      {prefix <> "ElmcValue *#{var} = elmc_new_int(elmc_as_int(#{source}) + #{value});", var, next}
    end
  end

  def compile(%{op: :add_vars, left: left, right: right}, env, counter) do
    if EnvBindings.native_int_binding?(env, left) or EnvBindings.native_int_binding?(env, right) do
      NativeInt.compile_boxed(
        %{
          op: :call,
          name: "__add__",
          args: [%{op: :var, name: left}, %{op: :var, name: right}]
        },
        env,
        counter
      )
    else
      {left_prefix, left_ref, counter} = FunctionCallCompile.value_source(env, left, counter)
      {right_prefix, right_ref, counter} = FunctionCallCompile.value_source(env, right, counter)
      next = counter + 1
      var = "tmp_#{next}"

      code =
        left_prefix <>
          right_prefix <>
          "ElmcValue *#{var} = elmc_new_int(elmc_as_int(#{left_ref}) + elmc_as_int(#{right_ref}));"

      {code, var, next}
    end
  end

  def compile(%{op: :sub_const, var: name, value: value}, env, counter) do
    if EnvBindings.native_int_binding?(env, name) do
      NativeInt.compile_boxed(
        %{
          op: :call,
          name: "__sub__",
          args: [%{op: :var, name: name}, %{op: :int_literal, value: value}]
        },
        env,
        counter
      )
    else
      {prefix, source, counter} = FunctionCallCompile.value_source(env, name, counter)
      next = counter + 1
      var = "tmp_#{next}"

      {prefix <> "ElmcValue *#{var} = elmc_new_int(elmc_as_int(#{source}) - #{value});", var, next}
    end
  end
end
