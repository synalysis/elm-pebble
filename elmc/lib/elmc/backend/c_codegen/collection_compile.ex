defmodule Elmc.Backend.CCodegen.CollectionCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Types

  @spec compile(Types.ir_collection_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :tuple2, left: left, right: right}, env, counter) do
    if NativeInt.expr?(left, env) and NativeInt.expr?(right, env) do
      {left_code, left_ref, counter} = Host.compile_native_int_expr(left, env, counter)
      {right_code, right_ref, counter} = Host.compile_native_int_expr(right, env, counter)
      next = counter + 1
      out = "tmp_#{next}"

      code = """
      #{left_code}
        #{right_code}
        ElmcValue *#{out} = elmc_tuple2_ints(#{left_ref}, #{right_ref});
      """

      {code, out, next}
    else
      {left_code, left_var, counter} = Host.compile_expr(left, env, counter)
      {right_code, right_var, counter} = Host.compile_expr(right, env, counter)
      next = counter + 1
      out = "tmp_#{next}"

      code = """
      #{left_code}
        #{right_code}
          ElmcValue *#{out} = elmc_tuple2_take(#{left_var}, #{right_var});
      """

      {code, out, next}
    end
  end

  def compile(%{op: :list_literal, items: items}, env, counter) do
    {item_code, item_vars, counter} =
      Enum.reduce(items, {"", [], counter}, fn item, {acc_code, vars, c} ->
        {code, var, c1} = Host.compile_expr(item, env, c)
        {acc_code <> "\n  " <> code, vars ++ [var], c1}
      end)

    next = counter + 1
    out = "tmp_#{next}"
    count = length(item_vars)
    array_name = "list_items_#{next}"
    item_list = Enum.join(item_vars, ", ")
    list_probe = DebugProbes.list_literal_probe(env, out, next)

    code =
      if count == 0 do
        """
        ElmcValue *#{out} = elmc_list_nil();
          #{list_probe}
        """
      else
        """
        #{item_code}
          ElmcValue *#{array_name}[#{count}] = { #{item_list} };
          ElmcValue *#{out} = elmc_list_from_values_take(#{array_name}, #{count});
          #{list_probe}
        """
      end

    {code, out, next}
  end

  def compile(%{op: :tuple_second, arg: arg}, env, counter) when is_binary(arg) do
    compile_bound_tuple_second(env, arg, counter)
  end

  def compile(%{op: :tuple_second_expr, arg: %{op: :var, name: name}}, env, counter) do
    compile_bound_tuple_second(env, name, counter)
  end

  def compile(%{op: :tuple_second_expr, arg: arg_expr}, env, counter) do
    compile_expr_tuple_access(arg_expr, "elmc_tuple_second", env, counter)
  end

  def compile(%{op: :tuple_first, arg: arg}, env, counter) when is_binary(arg) do
    compile_bound_tuple_first(env, arg, counter)
  end

  def compile(%{op: :tuple_first, arg: arg_expr}, env, counter) when is_map(arg_expr) do
    compile(%{op: :tuple_first_expr, arg: arg_expr}, env, counter)
  end

  def compile(%{op: :tuple_first_expr, arg: %{op: :var, name: name}}, env, counter) do
    compile_bound_tuple_first(env, name, counter)
  end

  def compile(%{op: :tuple_first_expr, arg: arg_expr}, env, counter) do
    compile_expr_tuple_access(arg_expr, "elmc_tuple_first", env, counter)
  end

  def compile(%{op: :string_length, arg: arg}, env, counter) when is_binary(arg) do
    compile_bound_string_length(env, arg, counter)
  end

  def compile(%{op: :string_length_expr, arg: %{op: :var, name: name}}, env, counter) do
    compile_bound_string_length(env, name, counter)
  end

  def compile(%{op: :string_length_expr, arg: arg_expr}, env, counter) do
    compile_expr_unary(arg_expr, "elmc_new_int(elmc_string_length", env, counter)
  end

  def compile(%{op: :char_from_code, arg: arg}, env, counter) when is_binary(arg) do
    compile_bound_char_from_code(env, arg, counter)
  end

  def compile(%{op: :char_from_code_expr, arg: arg_expr}, env, counter) do
    compile_expr_unary(arg_expr, "elmc_new_char(elmc_as_int", env, counter)
  end

  @spec env_source_ref(Types.compile_env(), String.t()) :: Types.env_source_ref()
  defp env_source_ref(env, name), do: Map.get(env, name, name)

  @spec compile_bound_tuple_second(Types.compile_env(), String.t(), Types.compile_counter()) ::
          Types.compile_result()
  defp compile_bound_tuple_second(env, name, counter) do
    source = env_source_ref(env, name)
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_tuple_second(#{source});", var, next}
  end

  @spec compile_bound_tuple_first(Types.compile_env(), String.t(), Types.compile_counter()) ::
          Types.compile_result()
  defp compile_bound_tuple_first(env, name, counter) do
    source = env_source_ref(env, name)
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_tuple_first(#{source});", var, next}
  end

  @spec compile_bound_string_length(Types.compile_env(), String.t(), Types.compile_counter()) ::
          Types.compile_result()
  defp compile_bound_string_length(env, name, counter) do
    source = env_source_ref(env, name)
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_int(elmc_string_length(#{source}));", var, next}
  end

  @spec compile_bound_char_from_code(Types.compile_env(), String.t(), Types.compile_counter()) ::
          Types.compile_result()
  defp compile_bound_char_from_code(env, name, counter) do
    source = env_source_ref(env, name)
    next = counter + 1
    var = "tmp_#{next}"
    {"ElmcValue *#{var} = elmc_new_char(elmc_as_int(#{source}));", var, next}
  end

  @spec compile_expr_tuple_access(
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_expr_tuple_access(arg_expr, c_fn, env, counter) do
    {arg_code, arg_var, counter} = Host.compile_expr(arg_expr, env, counter)
    next = counter + 1
    var = "tmp_#{next}"

    code = """
    #{arg_code}
      ElmcValue *#{var} = #{c_fn}(#{arg_var});
      elmc_release(#{arg_var});
    """

    {code, var, next}
  end

  @spec compile_expr_unary(
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_expr_unary(arg_expr, c_expr_prefix, env, counter) do
    {arg_code, arg_var, counter} = Host.compile_expr(arg_expr, env, counter)
    next = counter + 1
    var = "tmp_#{next}"

    code = """
    #{arg_code}
      ElmcValue *#{var} = #{c_expr_prefix}(#{arg_var}));
      elmc_release(#{arg_var});
    """

    {code, var, next}
  end
end
