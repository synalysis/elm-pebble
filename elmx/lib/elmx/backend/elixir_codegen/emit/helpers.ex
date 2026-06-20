defmodule Elmx.Backend.ElixirCodegen.Emit.Helpers do
  @moduledoc false

  alias Elmx.Backend.ConstructorEmit
  alias Elmx.Backend.ConstructorLookup
  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Types

  @type env :: Types.emit_env()
  @type compile_result :: {iodata(), env(), non_neg_integer()}
  @type ctor_ref_result :: {:ok, iodata(), env(), non_neg_integer()} | :error

  def compile_arg_list(args, env, counter) when is_list(args) do
    {parts, env, counter} = compile_arg_parts(args, env, counter)
    {Enum.intersperse(parts, ", "), env, counter}
  end

  def compile_arg_parts(args, env, counter) when is_list(args) do
    Enum.map_reduce(args, {env, counter}, fn arg, {env, c} ->
      {code, env, c} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(arg, env, c)
      {code, {env, c}}
    end)
    |> then(fn {parts, {env, c}} -> {parts, env, c} end)
  end

  def arg_code_string(arg_code), do: inspect(IO.iodata_to_binary(arg_code))

  def compile_record_field_value(field, expr, env, counter) do
    {code, env, c} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(expr, env, counter)

    code =
      case {expr, maybe_field_type(env, field)} do
        {%{op: :int_literal, value: 0}, "Maybe " <> _} -> ":Nothing"
        _ -> code
      end

    {code, env, c}
  end

  def maybe_field_type(env, field) when is_binary(field) do
    env
    |> Map.get(:record_field_types, %{})
    |> Map.values()
    |> Enum.find_value(fn types -> Map.get(types, field) end)
  end

  def var_ref(name, env) when is_binary(name) do
    if parameter_binding?(name, env) do
      binding_ref(name, env)
    else
      case Map.get(env, :module) do
        module when is_binary(module) -> function_reference(module, name, env)
        _ -> name
      end
    end
  end

  def parameter_binding?(name, env) when is_binary(name) and is_map(env) do
    Map.get(env, String.to_atom(name)) == true
  end

  def function_reference(module, name, env) do
    if parameter_binding?(name, env) do
      binding_ref(name, env)
    else
      function_reference_uncurried(module, name, env)
    end
  end

  def function_reference_uncurried(_module, "identity", _env), do: "fn x -> x end"

  def function_reference_uncurried(module, name, env) do
    fn_sym = module_fn(module, name)
    zero_arity = Map.get(env, :zero_arity_fns, MapSet.new())

    case function_arity(env, name) do
      :unresolved ->
        name

      0 ->
        if MapSet.member?(zero_arity, name) do
          "#{fn_sym}()"
        else
          "&#{fn_sym}/0"
        end

      arity when is_integer(arity) and arity > 0 ->
        "&#{fn_sym}/#{arity}"
    end
  end

  def function_arity(env, name) when is_binary(name) do
    case Map.get(Map.get(env, :explicit_function_arities, %{}), name) do
      nil ->
        case Map.get(Map.get(env, :function_arities, %{}), name) do
          nil -> :unresolved
          arity when is_integer(arity) -> arity
        end

      arity when is_integer(arity) ->
        arity
    end
  end

  def partial_application_fun(module, name, fixed_parts, 1) do
    fn_sym = module_fn(module, name)
    param = let_emit_name("__p1")

    [
      "fn ",
      param,
      " -> ",
      fn_sym,
      "(",
      Enum.intersperse(fixed_parts ++ [param], ", "),
      ")",
      " end"
    ]
  end

  def partial_application_fun(module, name, fixed_parts, remaining) when remaining > 1 do
    fn_sym = module_fn(module, name)
    param_names = Enum.map(1..remaining, &let_emit_name("__p#{&1}"))
    all_args = fixed_parts ++ param_names
    inner = [fn_sym, "(", Enum.intersperse(all_args, ", "), ")"]

    Enum.reduce(Enum.reverse(param_names), inner, fn param, body ->
      ["fn ", param, " -> ", body, " end"]
    end)
  end

  def compile_constructor_reference(name, env, counter) when is_binary(name) do
    case compile_record_alias_constructor_reference(name, env, counter) do
      {:ok, code, env, c} ->
        {:ok, code, env, c}

      :error ->
        compile_union_constructor_reference(name, env, counter)
    end
  end

  defp compile_union_constructor_reference(name, env, counter) when is_binary(name) do
    lookup = Map.get(env, :constructor_lookup)
    module = Map.get(env, :module)

    with lookup when is_map(lookup) <- lookup,
         entry when is_map(entry) <- ConstructorLookup.resolve(lookup, name, module),
         {:ok, rewritten} <- ConstructorEmit.rewrite(entry) do
      {code, env, c} = Emit.compile_expr(rewritten, env, counter)
      {:ok, code, env, c}
    else
      _ -> :error
    end
  end

  @spec compile_record_alias_constructor_reference(String.t(), map(), non_neg_integer()) ::
          {:ok, iodata(), map(), non_neg_integer()} | :error
  def compile_record_alias_constructor_reference(name, env, counter) when is_binary(name) do
    case record_alias_constructor_code(name, env) do
      {:ok, code} -> {:ok, code, env, counter}
      :error -> :error
    end
  end

  @spec record_alias_constructor_code(String.t(), map()) :: {:ok, iodata()} | :error
  def record_alias_constructor_code(name, env) when is_binary(name) do
    case Map.get(env, :record_field_types, %{}) |> Map.get(name) do
      fields when is_map(fields) and map_size(fields) > 0 ->
        field_names = Enum.map(Map.to_list(fields), fn {field, _} -> to_string(field) end)
        params = Enum.map(0..(length(field_names) - 1), &let_emit_name("__alias_#{&1}"))

        body =
          field_names
          |> Enum.zip(params)
          |> Enum.map(fn {field, param} -> [inspect(field), " => ", param] end)
          |> then(fn parts -> ["%{", Enum.intersperse(parts, ", "), "}"] end)

        code =
          Enum.reduce(Enum.reverse(params), body, fn param, acc ->
            ["fn ", param, " -> ", acc, " end"]
          end)

        {:ok, code}

      _ ->
        :error
    end
  end

  @operator_vars ~w(__add__ __sub__ __mul__ __fdiv__ __idiv__ __append__ __pow__ __eq__ __neq__ __lt__ __lte__ __gt__ __gte__)

  @spec operator_var_code(String.t()) :: String.t() | nil
  def operator_var_code(name) when name in @operator_vars do
    case name do
      "__add__" -> "fn a, b -> a + b end"
      "__sub__" -> "fn a, b -> a - b end"
      "__mul__" -> "fn a, b -> a * b end"
      "__fdiv__" -> "fn a, b -> a / b end"
      "__idiv__" -> "fn a, b -> Elmx.Runtime.Core.basics_idiv(a, b) end"
      "__append__" -> "fn a, b -> Elmx.Runtime.Core.append(a, b) end"
      "__pow__" -> "fn a, b -> trunc(Elmx.Runtime.Core.Math.pow(a, b)) end"
      "__eq__" -> "fn a, b -> a == b end"
      "__neq__" -> "fn a, b -> a != b end"
      "__lt__" -> "fn a, b -> a < b end"
      "__lte__" -> "fn a, b -> a <= b end"
      "__gt__" -> "fn a, b -> a > b end"
      "__gte__" -> "fn a, b -> a >= b end"
    end
  end

  def operator_var_code(_), do: nil

  # Elm record-update bases like `{ model.player | ... }` lower to a var named `"model.player"`.
  # Compiler-generated names must not start with `_` in emitted Elixir (unused-var / underscore rules).
  @elixir_reserved ~w(
    after alias and catch cond def defdelegate defexception defmacro defmacrop defmodule defp defprotocol
    defstruct do else end false fn for if import in nil not or quote raise receive require reraise
    rescue super throw true try unquote unquote_splicing use when while
  )

  def let_emit_name("__tupleBind_" <> rest), do: "tupleBind_" <> rest
  def let_emit_name("__" <> rest), do: "elmx_" <> rest

  def let_emit_name(name) when is_binary(name) do
    if name in @elixir_reserved, do: "elmx_" <> name, else: name
  end

  @spec param_var_name(String.t(), map()) :: String.t()
  def param_var_name(name, _env) when is_binary(name), do: let_emit_name(name)

  def binding_ref(name, env) when is_binary(name) do
    case Map.get(env, String.to_atom(name)) do
      true -> Macro.var(String.to_atom(param_var_name(name, env)), nil) |> Macro.to_string()
      _ -> var_ref(name, env)
    end
  end

  def binding_ref(name, _env), do: inspect(name)

  def put_lambda_params(env, args) do
    Enum.reduce(args, env, fn arg, acc -> Map.put(acc, String.to_atom(param_name(arg)), true) end)
  end

  def record_update_field({name, value}) when is_binary(name), do: {name, value}
  def record_update_field(%{name: name, expr: value}), do: {to_string(name), value}
  def record_update_field(%{field: name, value: value}), do: {to_string(name), value}
  def record_update_field(%{field: name, expr: value}), do: {to_string(name), value}

  @spec pattern_ctor_name(String.t()) :: String.t()
  def pattern_ctor_name(name) when is_binary(name) do
    name |> String.split(".") |> List.last()
  end

  @spec record_pattern_key(String.t() | atom()) :: String.t()
  def record_pattern_key(name) when is_binary(name) or is_atom(name), do: inspect(name)

  @spec param_name(Types.ir_expr() | atom() | String.t() | map()) :: String.t()
  def param_name(arg) when is_binary(arg), do: arg
  def param_name(arg) when is_atom(arg), do: Atom.to_string(arg)
  def param_name(%{name: name}), do: to_string(name)
  def param_name(name), do: to_string(name)

  def qualified_fn_name(target) when is_binary(target) do
    target |> String.split(".") |> List.last()
  end

  def module_fn(module, function) do
    "elmx_fn_#{safe_module(module)}_#{function}"
  end

  def safe_module(name), do: name |> String.replace(".", "_")

  def normalize_record_fields(fields) when is_list(fields) do
    Enum.map(fields, fn
      {name, value} when is_binary(name) -> {name, value}
      %{field: name, value: value} -> {to_string(name), value}
      %{field: name, expr: value} -> {to_string(name), value}
      %{name: name, value: value} -> {to_string(name), value}
      %{name: name, expr: value} -> {to_string(name), value}
      other -> raise "unsupported record field #{inspect(other)}"
    end)
  end

end
