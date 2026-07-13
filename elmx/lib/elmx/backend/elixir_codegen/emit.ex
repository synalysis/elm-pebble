defmodule Elmx.Backend.ElixirCodegen.Emit do
  @moduledoc false

  alias Elmx.Backend.ElixirCodegen.Emit.Calls
  alias Elmx.Backend.ElixirCodegen.Emit.Constructor
  alias Elmx.Backend.ElixirCodegen.Emit.Expr
  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Backend.ElixirCodegen.Emit.Patterns
  alias Elmx.Backend.ElixirCodegen.Emit.Records
  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Types

  @rt_values CodegenRefs.values()

  @type env :: Types.emit_env()

  @spec function_env(String.t(), list()) :: env()
  def function_env(module_name, args) when is_binary(module_name) and is_list(args) do
    Enum.reduce(args, %{module: module_name}, fn arg, acc ->
      Map.put(acc, String.to_atom(param_name(arg)), true)
    end)
  end

  @spec compile_expr(Types.ir_expr(), env(), Types.emit_counter()) :: Types.compile_expr_result()
  def compile_expr(expr, env, counter) when is_map(expr) do
    case Map.get(expr, :op) do
      :int_literal ->
        {Expr.compile_int_literal(expr, env), env, counter}

      :float_literal ->
        {inspect(expr.value), env, counter}

      :string_literal ->
        {inspect(expr.value), env, counter}

      :char_literal ->
        codepoint =
          case expr.value do
            v when is_integer(v) -> v
            <<c::utf8>> -> c
            v when is_binary(v) -> v |> String.to_charlist() |> hd()
          end

        {["#{CodegenRefs.core()}.new_char(", Integer.to_string(codepoint), ")"], env, counter}

      :bool_literal ->
        {to_string(expr.value == true), env, counter}

      :cmd_none ->
        {[@rt_values, ".cmd_none()"], env, counter}

      :var ->
        name = expr.name || expr[:name]

        case Constructor.compile_var(name, env, counter) do
          {:ok, code, env, c} -> {code, env, c}
          :error -> {Helpers.var_ref(name, env), env, counter}
        end

      :add_const ->
        Expr.compile_add_const(expr, env, counter)

      :add_vars ->
        Expr.compile_add_vars(expr, env, counter)

      :sub_const ->
        Expr.compile_sub_const(expr, env, counter)

      :compare ->
        Expr.compile_compare(expr, env, counter)

      :tuple2 ->
        Expr.compile_tuple2(expr, env, counter)

      :list_literal ->
        Expr.compile_list(expr, env, counter)

      :record_literal ->
        Records.compile_record(expr, env, counter)

      :record_update ->
        Records.compile_record_update(expr, env, counter)

      :field_access ->
        Records.compile_field_access(expr, env, counter)

      :field_call ->
        Records.compile_field_call(expr, env, counter)

      :lambda ->
        Expr.compile_lambda(expr, env, counter)

      :call ->
        Calls.compile_call(expr, env, counter)

      :call1 ->
        Calls.compile_call1(expr, env, counter)

      :qualified_call ->
        Calls.compile_qualified_call(expr, env, counter)

      :qualified_call1 ->
        Calls.compile_qualified_call1(expr, env, counter)

      :qualified_ref ->
        Calls.compile_qualified_call1(%{target: expr.target}, env, counter)

      :pipe_chain ->
        Calls.compile_pipe_chain(expr, env, counter)

      :constructor_call ->
        Constructor.compile_constructor(expr, env, counter)

      :constructor_ref ->
        target = Map.get(expr, :target) || Map.get(expr, :name)
        args = Map.get(expr, :args, [])
        Constructor.compile_constructor(%{name: target, args: args}, env, counter)

      :partial_constructor ->
        Constructor.compile_partial_constructor(expr, env, counter)

      :runtime_call ->
        Expr.compile_runtime_call(expr, env, counter)

      :let_in ->
        Expr.compile_let_in(expr, env, counter)

      :if ->
        Expr.compile_if(expr, env, counter)

      :case ->
        Patterns.compile_case(expr, env, counter)

      :tuple_first ->
        Expr.compile_tuple_accessor(expr, env, counter, 0)

      :tuple_second ->
        Expr.compile_tuple_accessor(expr, env, counter, 1)

      :tuple_first_expr ->
        Expr.compile_tuple_accessor(expr, env, counter, 0)

      :tuple_second_expr ->
        Expr.compile_tuple_accessor(expr, env, counter, 1)

      :string_length_expr ->
        Expr.compile_string_length(expr, env, counter)

      :char_from_code_expr ->
        Expr.compile_char_from_code(expr, env, counter)

      :unsupported ->
        raise Elmx.Backend.UnsupportedOpError, op: :unsupported, expr: expr

      op ->
        raise Elmx.Backend.UnsupportedOpError, op: op, expr: expr
    end
  end

  @spec param_name(Types.ir_expr() | Types.ir_pattern() | atom() | String.t()) :: String.t()
  defdelegate param_name(arg), to: Helpers

  @spec referenced_binding_names(Types.ir_tree()) :: MapSet.t(String.t())
  defdelegate referenced_binding_names(expr), to: Expr
end
