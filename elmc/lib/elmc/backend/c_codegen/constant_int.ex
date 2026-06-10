defmodule Elmc.Backend.CCodegen.ConstantInt do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.UnionMacros

  @int_binops ~w(__add__ __sub__ __mul__ __idiv__)

  @spec literal_value(Types.ir_expr(), Types.compile_env()) :: {:ok, integer()} | :error
  def literal_value(%{op: :int_literal, value: value}, _env) when is_integer(value),
    do: {:ok, value}

  def literal_value(%{op: :char_literal, value: value}, _env) when is_integer(value),
    do: {:ok, value}

  def literal_value(%{op: :var, name: name}, env) do
    bindings = Map.get(env, :__literal_int_bindings__, %{})

    case Map.get(bindings, EnvBindings.binding_key(name)) do
      value when is_integer(value) ->
        {:ok, value}

      _ ->
        literal_from_decl(Map.get(env, :__module__, "Main"), name, env)
    end
  end

  def literal_value(%{op: :sub_const, var: name, value: value}, env) when is_integer(value) do
    with {:ok, base} <- literal_from_decl(Map.get(env, :__module__, "Main"), name, env) do
      {:ok, base - value}
    end
  end

  def literal_value(%{op: :add_const, var: name, value: value}, env) when is_integer(value) do
    with {:ok, base} <- literal_from_decl(Map.get(env, :__module__, "Main"), name, env) do
      {:ok, base + value}
    end
  end

  def literal_value(%{op: :call, name: name, args: []}, env) do
    literal_from_decl(Map.get(env, :__module__, "Main"), name, env)
  end

  def literal_value(%{op: :qualified_call, target: target, args: []}, env) do
    case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
      {module, name} -> literal_from_decl(module, name, env)
      _ -> :error
    end
  end

  def literal_value(%{op: :call, name: name, args: [left, right]}, env)
      when name in @int_binops do
    with {:ok, left_value} <- literal_value(left, env),
         {:ok, right_value} <- literal_value(right, env) do
      {:ok, apply_binop(name, left_value, right_value)}
    end
  end

  def literal_value(%{op: :qualified_call, target: target, args: [left, right]}, env) do
    case Host.qualified_builtin_operator_name(target) do
      op when op in @int_binops ->
        literal_value(%{op: :call, name: op, args: [left, right]}, env)

      _ ->
        :error
    end
  end

  def literal_value(
        %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]},
        env
      ) do
    literal_value(%{op: :call, name: "modBy", args: [base, value]}, env)
  end

  def literal_value(%{op: :call, name: "modBy", args: [base, value]}, env) do
    with {:ok, base_value} <- literal_value(base, env),
         {:ok, value_value} <- literal_value(value, env),
         true <- base_value != 0 do
      {:ok, elmc_mod_by(value_value, base_value)}
    else
      _ -> :error
    end
  end

  def literal_value(%{op: :call, name: "remainderBy", args: [base, value]}, env) do
    with {:ok, base_value} <- literal_value(base, env),
         {:ok, value_value} <- literal_value(value, env),
         true <- base_value != 0 do
      {:ok, rem(value_value, base_value)}
    else
      _ -> :error
    end
  end

  def literal_value(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}, env)
      when is_binary(name) or is_atom(name) do
    with {:ok, value} <- literal_value(value_expr, env) do
      bindings =
        env
        |> Map.get(:__literal_int_bindings__, %{})
        |> Map.put(EnvBindings.binding_key(name), value)

      literal_value(in_expr, Map.put(env, :__literal_int_bindings__, bindings))
    end
  end

  def literal_value(%{op: :case, subject: subject, branches: branches}, env) do
    subject_expr = CaseCompile.subject_expr(subject)

    with {:ok, subject_value} <- literal_value(subject_expr, env) do
      literal_case_select(branches, subject_value, env)
    end
  end

  def literal_value(_expr, _env), do: :error

  @spec literal_binop(String.t(), Types.ir_expr(), Types.ir_expr(), Types.compile_env()) ::
          {:ok, integer()} | :error
  def literal_binop(operator, left, right, env)
      when operator in @int_binops or operator in ["+", "-", "*"] do
    with {:ok, left_value} <- literal_value(left, env),
         {:ok, right_value} <- literal_value(right, env) do
      {:ok, apply_binop(normalize_binop(operator), left_value, right_value)}
    end
  end

  @spec normalize_binop(String.t()) :: String.t()
  defp normalize_binop("+"), do: "__add__"
  defp normalize_binop("-"), do: "__sub__"
  defp normalize_binop("*"), do: "__mul__"
  defp normalize_binop(operator) when operator in @int_binops, do: operator

  @spec literal_from_decl(String.t(), String.t(), Types.compile_env()) ::
          {:ok, integer()} | :error
  def literal_from_decl(module_name, name, env) do
    decl_map = Map.get(env, :__program_decls__, %{})

    case Map.get(decl_map, {module_name, name}) do
      %{expr: expr} when is_map(expr) -> literal_value(expr, env)
      _ -> :error
    end
  end

  @spec native_let_value?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def native_let_value?(expr, env) do
    case literal_value(expr, env) do
      {:ok, _} -> true
      :error -> false
    end
  end

  @spec emit_native_let_binding(String.t(), Types.ir_expr(), Types.compile_env()) ::
          {:ok, String.t()} | :error
  def emit_native_let_binding(native_var, value_expr, env) do
    case literal_value(value_expr, env) do
      {:ok, value} -> {:ok, "const elmc_int_t #{native_var} = #{value};\n"}
      :error -> :error
    end
  end

  @spec compile_native_operand(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  def compile_native_operand(expr, env, counter) do
    cond do
      NativeInt.expr?(expr, env) ->
        {code, ref, c} = NativeInt.compile_expr(expr, env, counter)
        {:ok, code, ref, c}

      true ->
        case native_ref(expr, env) do
          {:ok, ref} -> {:ok, "", ref, counter}
          :error -> :error
        end
    end
  end

  @spec native_ref(Types.ir_expr(), Types.compile_env()) :: {:ok, String.t()} | :error
  def native_ref(expr, env) do
    case literal_value(expr, env) do
      {:ok, value} -> {:ok, Integer.to_string(value)}
      :error -> :error
    end
  end

  @spec compile_boxed(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  def compile_boxed(expr, env, counter) do
    case literal_value(expr, env) do
      {:ok, value} ->
        counter = counter + 1
        out = "tmp_#{counter}"
        ref = UnionMacros.literal_ref(expr, env) || Integer.to_string(value)
        {:ok, "ElmcValue *#{out} = elmc_new_int(#{ref});\n", out, counter}

      :error ->
        :error
    end
  end

  @spec compile_boxed_call(
          String.t(),
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  def compile_boxed_call(module_name, name, args, env, counter) do
    compile_boxed(%{op: :call, name: name, args: args}, %{env | __module__: module_name}, counter)
  end

  defp apply_binop("__add__", left, right), do: left + right
  defp apply_binop("__sub__", left, right), do: left - right
  defp apply_binop("__mul__", left, right), do: left * right
  defp apply_binop("__idiv__", _left, 0), do: 0
  defp apply_binop("__idiv__", left, right), do: div(left, right)

  defp elmc_mod_by(value, base) do
    rem = rem(value, base)

    if rem < 0 do
      rem + abs(base)
    else
      rem
    end
  end

  defp literal_case_select(branches, subject_value, env) do
    Enum.reduce_while(branches, :error, fn branch, _ ->
      case branch.pattern do
        %{kind: :int, value: ^subject_value} ->
          {:halt, literal_value(branch.expr, env)}

        %{kind: :wildcard} ->
          {:halt, literal_value(branch.expr, env)}

        %{kind: :int} ->
          {:cont, :error}
      end
    end)
  end
end
