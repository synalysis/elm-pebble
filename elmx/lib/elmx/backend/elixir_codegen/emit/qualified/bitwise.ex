defmodule Elmx.Backend.ElixirCodegen.Emit.Qualified.Bitwise do
  @moduledoc false

  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Runtime.Stdlib.QualifiedCodegen
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Context

  @type env :: Context.env()
  @type emit_counter :: Context.emit_counter()
  @type ir_arg_list :: Context.ir_arg_list()
  @type qualified_result :: Context.qualified_result()

  def compile("Bitwise.and", [left, right], env, counter) do
    compile_bitwise_runtime(:and_, [left, right], env, counter)
  end

  def compile("Bitwise.or", [left, right], env, counter) do
    compile_bitwise_runtime(:or_, [left, right], env, counter)
  end

  def compile("Bitwise.xor", [left, right], env, counter) do
    compile_bitwise_runtime(:xor, [left, right], env, counter)
  end

  def compile("Bitwise.complement", [arg], env, counter) do
    compile_bitwise_runtime(:complement, [arg], env, counter)
  end

  def compile("Bitwise.shiftLeftBy", [bits, arg], env, counter) do
    compile_bitwise_runtime(:shift_left_by, [bits, arg], env, counter)
  end

  def compile("Bitwise.shiftRightBy", [bits, arg], env, counter) do
    compile_bitwise_runtime(:shift_right_by, [bits, arg], env, counter)
  end

  def compile("Bitwise.shiftRightZfBy", [bits, arg], env, counter) do
    compile_bitwise_runtime(:shift_right_zf_by, [bits, arg], env, counter)
  end

  def compile(_, _, _, _), do: :error

  defp compile_bitwise_runtime(fun, args, env, counter) when is_atom(fun) and is_list(args) do
    {parts, env, c} = Helpers.compile_arg_parts(args, env, counter)

    {:ok, result} =
      QualifiedCodegen.module_call(Elmx.Runtime.Core.Bitwise, Atom.to_string(fun), parts)

    {:ok, result, env, c}
  end


end
