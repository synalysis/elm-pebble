defmodule Elmc.Backend.CCodegen.IfCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.String, as: NativeString
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec compile(Types.ir_if_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(
        %{
          op: :if,
          cond: %{op: :int_literal, value: value},
          then_expr: then_expr,
          else_expr: else_expr
        },
        env,
        counter
      ) do
    Host.compile_expr(if(value != 0, do: then_expr, else: else_expr), env, counter)
  end

  def compile(%{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr}, env, counter) do
    compile_branches(cond_expr, then_expr, else_expr, env, counter)
  end

  @spec compile_branches(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_branches(cond_expr, then_expr, else_expr, env, counter) do
    cond do
      Host.native_bool_expr?(cond_expr, env) and Host.native_int_expr?(then_expr, env) and
          Host.native_int_expr?(else_expr, env) ->
        compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter)

      Host.native_bool_expr?(cond_expr, env) and NativeString.boxed_expr?(then_expr, env) and
          NativeString.boxed_expr?(else_expr, env) ->
        compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter)

      Host.native_bool_expr?(cond_expr, env) and NativeString.boxed_non_null_expr?(then_expr, env) and
          NativeString.boxed_non_null_expr?(else_expr, env) ->
        compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter)

      Host.native_bool_expr?(cond_expr, env) ->
        compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter)

      true ->
        compile_boxed_cond(cond_expr, then_expr, else_expr, env, counter)
    end
  end

  @spec compile_native_bool_branches(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter) do
    {cond_code, cond_ref, counter} = Host.compile_native_bool_expr(cond_expr, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    {then_code, then_assignment, counter} =
      CaseCompile.branch_assignment(then_expr, out, env, next)

    {else_code, else_assignment, counter} =
      CaseCompile.branch_assignment(else_expr, out, env, counter)

    code = """
    #{cond_code}
      ElmcValue *#{out};
      if (#{cond_ref}) {
    #{Util.indent(then_code, 4)}
          #{then_assignment}
      } else {
    #{Util.indent(else_code, 4)}
          #{else_assignment}
      }
    """

    {code, out, counter}
  end

  @spec compile_boxed_cond(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_boxed_cond(cond_expr, then_expr, else_expr, env, counter) do
    {cond_code, cond_var, counter} = Host.compile_expr(cond_expr, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    {then_code, then_assignment, counter} =
      CaseCompile.branch_assignment(then_expr, out, env, next)

    {else_code, else_assignment, counter} =
      CaseCompile.branch_assignment(else_expr, out, env, counter)

    code = """
    #{cond_code}
          ElmcValue *#{out};
      if (elmc_as_int(#{cond_var}) != 0) {
    #{Util.indent(then_code, 4)}
              #{then_assignment}
      } else {
    #{Util.indent(else_code, 4)}
              #{else_assignment}
      }
      elmc_release(#{cond_var});
    """

    {code, out, counter}
  end
end
