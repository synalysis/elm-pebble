defmodule Elmc.Backend.CCodegen.BuiltinUnion do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @maybe_nothing "Nothing"
  @maybe_just "Just"
  @result_ok "Ok"
  @result_err "Err"

  @payload_ctors %{
    @maybe_just => "elmc_maybe_just",
    @result_ok => "elmc_result_ok",
    @result_err => "elmc_result_err"
  }

  @spec union_ctor_short_name(String.t()) :: String.t()
  def union_ctor_short_name(qualified) when is_binary(qualified) do
    qualified
    |> String.split(".")
    |> List.last()
  end

  @spec maybe_nothing_literal?(Types.ir_expr()) :: boolean()
  def maybe_nothing_literal?(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor) do
    union_ctor_short_name(ctor) == @maybe_nothing
  end

  def maybe_nothing_literal?(_expr), do: false

  @spec compile_maybe_nothing(Types.compile_counter()) :: Types.compile_result()
  def compile_maybe_nothing(counter) do
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_maybe_nothing();", var, next}
  end

  @spec try_compile_tuple2(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          {:ok, Types.compile_result()} | :error
  def try_compile_tuple2(%{op: :tuple2, left: left, right: right}, env, counter) do
    with %{op: :int_literal, union_ctor: ctor} <- left,
         short when is_map_key(@payload_ctors, short) <- union_ctor_short_name(ctor),
         c_name <- Map.fetch!(@payload_ctors, short) do
      {payload_code, payload_var, counter} = Host.compile_expr(right, env, counter)
      next = counter + 1
      out = "tmp_#{next}"

      code = """
      #{payload_code}
        ElmcValue *#{out} = #{c_name}(#{payload_var});
        elmc_release(#{payload_var});
      """

      {:ok, {code, out, next}}
    else
      _ -> :error
    end
  end

  def try_compile_tuple2(_expr, _env, _counter), do: :error
end
