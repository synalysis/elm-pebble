defmodule Elmx.Backend.ElixirCodegen.Emit.Qualified.Basics do
  @moduledoc false

  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Stdlib.QualifiedCodegen
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Context

  @type env :: Context.env()
  @type emit_counter :: Context.emit_counter()
  @type ir_arg_list :: Context.ir_arg_list()
  @type qualified_result :: Context.qualified_result()

  @spec compile(String.t(), ir_arg_list(), env(), emit_counter()) :: qualified_result()
  def compile("Basics.fromPolar", [polar], env, counter),
    do: compile_from_polar(polar, env, counter)

  def compile(_target, _args, _env, _counter), do: :error

  defp compile_from_polar(polar, env, counter) do
    case polar do
      %{op: :tuple2, left: mag, right: angle} ->
        compile_math_nary("from_polar", [mag, angle], env, counter)

      _ ->
        {code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(polar, env, counter)
        math = CodegenRefs.core_math()
        bin = IO.iodata_to_binary(code)

        {:ok,
         "#{math}.from_polar(elem(#{bin}, 0), elem(#{bin}, 1))",
         env, c1}
    end
  end

  defp compile_math_nary(fun, args, env, counter) when is_binary(fun) and is_list(args) do
    {parts, env, c} = Elmx.Backend.ElixirCodegen.Emit.Helpers.compile_arg_parts(args, env, counter)
    {:ok, result} = QualifiedCodegen.module_call(Elmx.Runtime.Core.Math, fun, parts)
    {:ok, result, env, c}
  end


end
