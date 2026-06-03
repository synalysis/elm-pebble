defmodule Elmc.Backend.CCodegen.Native.FunctionCall do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec call?({String.t(), String.t()}, Types.compile_env()) :: boolean()
  def call?({module_name, name}, env) do
    env
    |> Map.get(:__program_decls__, %{})
    |> Map.get({module_name, name})
    |> case do
      nil -> false
      decl -> native_args?(decl, module_name, Map.get(env, :__program_decls__, %{}))
    end
  end

  @spec compile(String.t(), String.t(), [Types.ir_expr()], Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(module_name, name, args, env, counter) do
    decl = env |> Map.get(:__program_decls__, %{}) |> Map.fetch!({module_name, name})
    decl_map = Map.get(env, :__program_decls__, %{})
    arg_kinds = arg_kinds(decl, module_name, decl_map)

    {arg_code, arg_refs, release_refs, counter} =
      args
      |> Enum.zip(arg_kinds)
      |> Enum.reduce({"", [], [], counter}, fn {arg_expr, kind},
                                               {code_acc, refs_acc, releases_acc, c} ->
        case kind do
          :native_int ->
            {code, ref, c2} = Host.compile_native_int_expr(arg_expr, env, c)
            {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc, c2}

          :native_bool ->
            {code, ref, c2} = Host.compile_native_bool_expr(arg_expr, env, c)
            {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc, c2}

          :boxed ->
            {code, ref, c2} = Host.compile_expr(arg_expr, env, c)
            {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc ++ [ref], c2}
        end
      end)

    next = counter + 1
    out = "tmp_#{next}"
    c_name = Util.module_fn_name(module_name, name)
    arg_list = Enum.join(arg_refs, ", ")

    releases =
      release_refs
      |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

    code = """
    #{arg_code}
      ElmcValue *#{out} = #{c_name}_native(#{arg_list});
      #{releases}
    """

    {code, out, next}
  end

  @spec native_args?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def native_args?(decl, module_name, decl_map) do
    decl
    |> arg_kinds(module_name, decl_map)
    |> Enum.any?(&(&1 in [:native_int, :native_bool]))
  end

  @spec params(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          String.t()
  def params(decl, module_name, decl_map) do
    Host.c_arg_bindings(decl.args || [])
    |> Enum.zip(arg_kinds(decl, module_name, decl_map))
    |> Enum.map_join(", ", fn {{_arg, c_arg, _index}, kind} ->
      case kind do
        :native_int -> "const elmc_int_t #{c_arg}"
        :native_bool -> "const elmc_int_t #{c_arg}"
        :boxed -> "ElmcValue * const #{c_arg}"
      end
    end)
  end

  @spec arg_kinds(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          [Types.native_function_arg_kind()]
  def arg_kinds(%{args: args, type: type, expr: expr}, module_name, decl_map)
      when is_list(args) and is_binary(type) do
    arg_types = Host.function_arg_types(type)

    args
    |> Enum.with_index()
    |> Enum.map(fn {arg, index} ->
      case Enum.at(arg_types, index) |> Host.normalize_type_name() do
        "Int" ->
          if int_arg_safe?(arg, expr) do
            :native_int
          else
            :boxed
          end

        "Bool" ->
          if bool_arg_safe?(arg, expr, module_name, decl_map) do
            :native_bool
          else
            :boxed
          end

        _other ->
          :boxed
      end
    end)
  end

  def arg_kinds(%{args: args, type: type}, _module_name, _decl_map)
      when is_list(args) and is_binary(type) do
    arg_types = Host.function_arg_types(type)

    args
    |> Enum.with_index()
    |> Enum.map(fn {_arg, index} ->
      case Enum.at(arg_types, index) |> Host.normalize_type_name() do
        "Int" -> :native_int
        "Bool" -> :native_bool
        _other -> :boxed
      end
    end)
  end

  def arg_kinds(%{args: args}, _module_name, _decl_map) when is_list(args),
    do: Enum.map(args, fn _ -> :boxed end)

  def arg_kinds(_decl, _module_name, _decl_map), do: []

  @spec int_arg_safe?(Types.binding_name(), Types.ir_expr() | nil) :: boolean()
  defp int_arg_safe?(arg, expr) do
    usage = Host.native_int_usage(arg, expr || %{op: :int_literal, value: 0}, nil, %{})
    (usage.total == 0 or usage.boxed == 0) and not Host.binding_used_in_lambda?(arg, expr)
  end

  @spec bool_arg_safe?(String.t(), Types.ir_expr() | nil, String.t(), Types.function_decl_map()) ::
          boolean()
  defp bool_arg_safe?(arg, expr, module_name, decl_map) do
    usage = Host.native_bool_usage(arg, expr || %{op: :int_literal, value: 0}, module_name, decl_map)
    (usage.total == 0 or usage.boxed == 0) and not Host.binding_used_in_lambda?(arg, expr)
  end
end
