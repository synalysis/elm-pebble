defmodule Elmx.Backend.ElixirCodegen.Emit.Constructor do
  @moduledoc false

  alias Elmx.Backend.ConstructorLookup
  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Types

  @type env :: Types.emit_env()
  @type compile_result :: {iodata(), env(), non_neg_integer()}
  @type var_result :: {:ok, iodata(), env(), non_neg_integer()} | :error

  def compile_constructor(%{target: target, args: args}, env, counter) when is_binary(target) do
    compile_constructor(%{name: target, args: args}, env, counter)
  end

  def compile_constructor(%{name: name, args: args} = _expr, env, counter) when is_binary(name) do
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
            _ -> "Elmx.Runtime.Values.ctor(#{inspect(ctor_name)}, [#{arg_str}])"
          end
      end

    {code, env, c1}
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
  def ide_runtime_constructor_code(ctor, args, arg_str, _name, _env)
       when is_list(args) and length(args) <= 4 do
    "{:#{ctor}, #{arg_str}}"
  end

  def ide_runtime_constructor_code(ctor, _args, arg_str, _name, _env) do
    "Elmx.Runtime.Values.ctor(#{inspect(ctor)}, [#{arg_str}])"
  end

  def zero_arg_constructor_code_library(name, ctor, env) do
    case Map.get(env, :constructor_lookup) do
      lookup when is_map(lookup) ->
        case ConstructorLookup.resolve(lookup, name, Map.get(env, :module)) do
          %{tag: tag} when is_integer(tag) -> Integer.to_string(tag)
          _ -> ":#{ctor}"
        end

      _ ->
        ":#{ctor}"
    end
  end

  def compile_var(name, env, counter) when is_binary(name) do
    case String.split(name, ".") do
      [^name] ->
        case Helpers.compile_constructor_reference(name, env, counter) do
          {:ok, code, env, c} -> {:ok, code, env, c}
          :error -> :error
        end

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
