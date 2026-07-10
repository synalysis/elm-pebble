defmodule Elmc.Backend.CCodegen.Native.AngleMinute do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @idiv_ops ~w(__idiv__ // idiv)
  @mul_ops ~w(__mul__ *)
  @sub_ops ~w(__sub__ -)

  defp op_name?(name, ops) when is_binary(name), do: name in ops
  defp op_name?(name, ops) when is_atom(name), do: Atom.to_string(name) in ops
  defp op_name?(_, _), do: false

  @spec compile_mod_by_65536(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  def compile_mod_by_65536(
        %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]},
        env,
        counter
      ) do
    compile_mod_by_65536(base, value, env, counter)
  end

  def compile_mod_by_65536(
        %{op: :call, name: "modBy", args: [base, value]},
        env,
        counter
      ) do
    compile_mod_by_65536(base, value, env, counter)
  end

  def compile_mod_by_65536(
        %{op: :qualified_call, target: target, args: [base, value]},
        env,
        counter
      ) do
    if mod_by_target?(target) do
      compile_mod_by_65536(base, value, env, counter)
    else
      :error
    end
  end

  def compile_mod_by_65536(base, value, env, counter) do
    with {:ok, minute_expr} <- minute_expr_from_angle_numerator(value),
         true <- mod_by_65536_base?(base) do
      {code, minute_ref, counter} = Host.compile_native_int_expr(minute_expr, env, counter)
      {:ok, code, "elmc_angle_from_minute(#{minute_ref})", counter}
    else
      _ -> :error
    end
  end

  def compile_mod_by_65536(_, _, _, _), do: :error

  @spec body_expr?(Types.ir_expr()) :: boolean()
  def body_expr?(expr) do
    case expr do
      %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]} ->
        mod_by_65536_base?(base) and match?({:ok, _}, minute_expr_from_angle_numerator(value))

      %{op: :call, name: "modBy", args: [base, value]} ->
        mod_by_65536_base?(base) and match?({:ok, _}, minute_expr_from_angle_numerator(value))

      %{op: :qualified_call, target: target, args: [base, value]} ->
        mod_by_target?(target) and
          mod_by_65536_base?(base) and match?({:ok, _}, minute_expr_from_angle_numerator(value))

      _ ->
        false
    end
  end

  defp mod_by_target?(target) when is_binary(target) do
    target in ["modBy", "Basics.modBy", "Elm.Kernel.modBy"]
  end

  defp mod_by_target?(_), do: false

  @spec compile_call(Types.ir_expr(), Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  def compile_call(body, minute_arg, env, counter) do
    if body_expr?(body) do
      {code, minute_ref, counter} = Host.compile_native_int_expr(minute_arg, env, counter)
      {:ok, code, "elmc_angle_from_minute(#{minute_ref})", counter}
    else
      :error
    end
  end

  @spec minute_expr_from_angle_numerator(Types.ir_expr()) :: {:ok, Types.ir_expr()} | :error
  def minute_expr_from_angle_numerator(expr) do
    with {:ok, num} <- idiv_numerator(expr, 1440),
         {:ok, minute_expr} <- minute_expr_from_scaled(num) do
      {:ok, minute_expr}
    else
      _ -> :error
    end
  end

  defp mod_by_65536_base?(%{op: :int_literal, value: 65_536}), do: true
  defp mod_by_65536_base?(_), do: false

  defp idiv_numerator(%{op: :call, name: name, args: [num, %{op: :int_literal, value: denom}]}, denom) do
    if op_name?(name, @idiv_ops), do: {:ok, num}, else: :error
  end

  defp idiv_numerator(
         %{op: :runtime_call, function: "elmc_int_idiv", args: [num, %{op: :int_literal, value: denom}]},
         denom
       ),
       do: {:ok, num}

  defp idiv_numerator(_, _), do: :error

  defp minute_expr_from_scaled(%{op: :call, name: name, args: [left, %{op: :int_literal, value: 65_536}]}) do
    if op_name?(name, @mul_ops), do: minute_expr_from_minus_720(left), else: :error
  end

  defp minute_expr_from_scaled(%{op: :runtime_call, function: "elmc_int_mul", args: [left, %{op: :int_literal, value: 65_536}]}),
    do: minute_expr_from_minus_720(left)

  defp minute_expr_from_scaled(_), do: :error

  defp minute_expr_from_minus_720(%{op: :call, name: name, args: [minute, %{op: :int_literal, value: 720}]}) do
    if op_name?(name, @sub_ops), do: {:ok, minute}, else: :error
  end

  defp minute_expr_from_minus_720(%{op: :sub_const, var: var, value: 720}) when is_binary(var),
    do: {:ok, %{op: :var, name: var}}

  defp minute_expr_from_minus_720(%{op: :runtime_call, function: "elmc_int_sub", args: [minute, %{op: :int_literal, value: 720}]}),
    do: {:ok, minute}

  defp minute_expr_from_minus_720(_), do: :error
end
