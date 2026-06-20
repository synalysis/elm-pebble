defmodule Elmx.Backend.ElixirCodegen.Emit.Constructor do
  @moduledoc false

  alias Elmx.Backend.ConstructorLookup
  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Types

  @type env :: Types.emit_env()
  @type compile_result :: {iodata(), env(), non_neg_integer()}
  @type var_result :: {:ok, iodata(), env(), non_neg_integer()} | :error

  def compile_constructor(%{target: target, args: args}, env, counter) when is_binary(target) do
    compile_constructor(%{name: target, args: args}, env, counter)
  end

  def compile_constructor(%{name: name, args: args}, env, counter) when is_binary(name) do
    case Helpers.record_alias_constructor_code(name, env) do
      {:ok, ctor_code} ->
        apply_record_alias_constructor(ctor_code, args, env, counter)

      :error ->
        compile_union_constructor(%{name: name, args: args}, env, counter)
    end
  end

  defp apply_record_alias_constructor(ctor_code, args, env, counter) when is_list(args) do
    {arg_code, env, c} = Helpers.compile_arg_list(args, env, counter)

    code =
      Enum.reduce(arg_code, ctor_code, fn arg, fun ->
        [fun, "(", arg, ")"]
      end)

    {code, env, c}
  end

  defp compile_union_constructor(%{name: name, args: args}, env, counter) when is_binary(name) do
    ctor_name = constructor_emit_name(name, env)
    {arg_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.Helpers.compile_arg_list(args, env, counter)
    arg_str = IO.iodata_to_binary(arg_code)

    code =
      case Map.get(env, :emit_mode) do
        :ide_runtime ->
          ide_runtime_constructor_code(ctor_name, args, arg_str, name, env)

        _ ->
          case args do
            [] -> zero_arg_constructor_code(name, env)
            _ -> ide_runtime_constructor_code(ctor_name, args, arg_str, name, env)
          end
      end

    {code, env, c1}
  end

  def compile_partial_constructor(
        %{target: target, args: bound_args, arity: full_arity} = expr,
        env,
        counter
      ) do
    ctor_name = partial_constructor_emit_name(target, expr, env)
    bound_args = bound_args || []
    remaining = max(full_arity - length(bound_args), 0)
    {bound_parts, env, c1} = Helpers.compile_arg_parts(bound_args, env, counter)

    code =
      if remaining == 0 do
        ["{:", ctor_name, ", ", Enum.intersperse(bound_parts, ", "), "}"]
      else
        curried_ctor_closure(ctor_name, bound_parts, remaining)
      end

    {code, env, c1}
  end

  defp partial_constructor_emit_name(target, _expr, env) when is_binary(target) do
    case String.split(target, ".") do
      [_single] -> constructor_emit_name(target, env)
      _parts -> constructor_emit_name(target, env)
    end
  end

  defp curried_ctor_closure(ctor_name, bound_parts, remaining) when remaining > 0 do
    params = Enum.map(1..remaining, &Helpers.let_emit_name("__p#{&1}"))

    body =
      ["{:", ctor_name, ", ", Enum.intersperse(bound_parts ++ params, ", "), "}"]

    Enum.reduce(Enum.reverse(params), body, fn param, inner ->
      ["fn ", param, " -> ", inner, " end"]
    end)
  end

  def constructor_emit_name(name, env) do
    case Map.get(env, :constructor_lookup) do
      lookup when is_map(lookup) ->
        case ConstructorLookup.resolve(lookup, name, Map.get(env, :module)) do
          %{constructor: ctor} when is_binary(ctor) -> ctor
          _ -> Elmx.Backend.ElixirCodegen.Emit.Helpers.pattern_ctor_name(name)
        end

      _ ->
        Elmx.Backend.ElixirCodegen.Emit.Helpers.pattern_ctor_name(name)
    end
  end

  def zero_arg_constructor_code(name, env) do
    ctor = constructor_emit_name(name, env)

    case Map.get(env, :emit_mode) do
      :ide_runtime ->
        ide_runtime_zero_arg_code(ctor)

      _ ->
        zero_arg_constructor_code_library(name, ctor, env)
    end
  end

  def ide_runtime_zero_arg_code("True"), do: "true"
  def ide_runtime_zero_arg_code("False"), do: "false"
  def ide_runtime_zero_arg_code("()"), do: "nil"
  def ide_runtime_zero_arg_code(ctor), do: ":#{ctor}"

  def ide_runtime_ctor_atom("()"), do: "nil"
  def ide_runtime_ctor_atom(ctor), do: ":#{ctor}"

  def ide_runtime_constructor_code(_ctor, [], _arg_str, name, env),
    do: zero_arg_constructor_code(name, env)

  # Tagged tuples match `case` patterns (`{:Just, x}`, `{:Ctor, a, b}`).
  def ide_runtime_constructor_code(ctor, args, arg_str, name, env)
       when is_list(args) and length(args) <= 4 do
    lookup = Map.get(env, :constructor_lookup)

    if ConstructorLookup.wrap_flattened_payload?(lookup, name, Map.get(env, :module), length(args)) do
      "{:#{ctor}, {#{arg_str}}}"
    else
      "{:#{ctor}, #{arg_str}}"
    end
  end

  def ide_runtime_constructor_code(ctor, _args, arg_str, _name, _env) do
    "#{CodegenRefs.values()}.ctor(#{inspect(ctor)}, [#{arg_str}])"
  end

  def zero_arg_constructor_code_library("True", _ctor, _env), do: "true"
  def zero_arg_constructor_code_library("False", _ctor, _env), do: "false"
  def zero_arg_constructor_code_library("()", _ctor, _env), do: "nil"

  def zero_arg_constructor_code_library(_name, ctor, _env), do: ":#{ctor}"

  def compile_var(name, env, counter) when is_binary(name) do
    case String.split(name, ".") do
      [^name] ->
        compile_var_simple(name, env, counter)

      [base | fields] ->
        with {:ok, base_code, env, c} <- compile_var_simple(base, env, counter) do
          code =
            Enum.reduce(fields, base_code, fn field, acc ->
              ["Map.get(", acc, ", ", inspect(field), ")"]
            end)

          {:ok, code, env, c}
        end
    end
  end

  def compile_var_simple(name, env, counter) when is_binary(name) do
    case Helpers.operator_var_code(name) do
      code when is_binary(code) ->
        {:ok, code, env, counter}

      nil ->
        :error
    end
    |> case do
      {:ok, code, env, c} ->
        {:ok, code, env, c}

      :error ->
        compile_var_simple_after_operator(name, env, counter)
    end
  end

  defp compile_var_simple_after_operator(name, env, counter) when is_binary(name) do
    case Helpers.compile_constructor_reference(name, env, counter) do
      {:ok, code, env, c} ->
        {:ok, code, env, c}

      :error ->
        if Map.get(env, String.to_atom(name)) == true do
          {:ok, Elmx.Backend.ElixirCodegen.Emit.Helpers.binding_ref(name, env), env, counter}
        else
          :error
        end
    end
  end

end
