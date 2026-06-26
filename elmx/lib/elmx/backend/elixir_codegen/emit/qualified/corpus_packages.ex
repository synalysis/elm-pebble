defmodule Elmx.Backend.ElixirCodegen.Emit.Qualified.CorpusPackages do
  @moduledoc false

  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Context
  alias Elmx.Runtime.CodegenRefs

  @type env :: Context.env()
  @type emit_counter :: Context.emit_counter()
  @type ir_arg_list :: Context.ir_arg_list()
  @type qualified_result :: Context.qualified_result()

  @rt_task CodegenRefs.core_task()

  def compile("Binary.FixedWidth.and", [left, right], env, counter) do
    bitwise_binop("band", left, right, env, counter)
  end

  def compile("Binary.FixedWidth.xor", [left, right], env, counter) do
    bitwise_binop("bxor", left, right, env, counter)
  end

  def compile("Binary.FixedWidth.or", [left, right], env, counter) do
    bitwise_binop("bor", left, right, env, counter)
  end

  def compile("Bytes.width", [], env, counter) do
    {:ok, "fn elmx_bytes -> byte_size(elmx_bytes) end", env, counter}
  end

  def compile("Bytes.width", [bytes], env, counter) do
    {code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(bytes, env, counter)
    {:ok, ["byte_size(", code, ")"], Map.put(env, :uses_bitwise, Map.get(env, :uses_bitwise, false)), c1}
  end

  def compile("Actor.send", [_pid, _msg], env, counter) do
    {:ok, [@rt_task, ".succeed(nil)"], env, counter}
  end

  def compile("Cli.println", [_console, message], env, counter) do
    {msg_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(message, env, counter)
    {:ok, ["IO.puts(", msg_code, ")"], env, c1}
  end

  def compile("Cli.exit", [_code], env, counter) do
    {:ok, "0", env, counter}
  end

  def compile("Cli.program", [spec], env, counter) do
    {spec_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(spec, env, counter)
    {:ok, spec_code, env, c1}
  end

  def compile(_target, _args, _env, _counter), do: :error

  defp bitwise_binop(op, left, right, env, counter) do
    {left_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(left, env, counter)
    {right_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(right, env, c1)
    env = Map.put(env, :uses_bitwise, true)
    {:ok, ["Bitwise.", op, "(", left_code, ", ", right_code, ")"], env, c2}
  end
end
