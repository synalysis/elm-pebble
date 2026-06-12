defmodule Elmc.Backend.CCodegen.Native.FunctionCall do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.ListIntReduce
  alias Elmc.Backend.CCodegen.Native.ListIntSearch
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @type native_return_kind :: :native_int | :native_bool | :boxed

  @spec call?({String.t(), String.t()}, Types.compile_env()) :: boolean()
  def call?({module_name, name}, env) do
    env
    |> Map.get(:__program_decls__, %{})
    |> Map.get({module_name, name})
    |> case do
      nil -> false
      decl -> native_scalar_fn?(decl, module_name, Map.get(env, :__program_decls__, %{}))
    end
  end

  @spec compile(
          String.t(),
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          Types.compile_result()
  def compile(module_name, name, args, env, counter) do
    decl = env |> Map.get(:__program_decls__, %{}) |> Map.fetch!({module_name, name})
    decl_map = Map.get(env, :__program_decls__, %{})
    return_kind = return_kind(decl, module_name, decl_map)

    case compile_native_result(module_name, name, args, env, counter, decl, decl_map, return_kind) do
      {code, ref, counter, :boxed} ->
        {code, ref, counter}

      {code, ref, counter, :native_int} ->
        next = counter + 1
        out = "tmp_#{next}"

        {
          """
          #{code}
            #{RcRuntimeEmit.assign_call(env, out, "elmc_new_int", ref)}
          """,
          out,
          next
        }

      {code, ref, counter, :native_bool} ->
        next = counter + 1
        out = "tmp_#{next}"

        {
          """
          #{code}
            #{RcRuntimeEmit.assign_call(env, out, "elmc_new_bool", ref)}
          """,
          out,
          next
        }
    end
  end

  @spec compile_scalar(
          String.t(),
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter(),
          :native_int | :native_bool
        ) :: Types.native_scalar_compile_result() | :error
  def compile_scalar(module_name, name, args, env, counter, expected_kind)
      when expected_kind in [:native_int, :native_bool] do
    decl = env |> Map.get(:__program_decls__, %{}) |> Map.get({module_name, name})
    decl_map = Map.get(env, :__program_decls__, %{})

    if decl && return_kind(decl, module_name, decl_map) == expected_kind do
      {code, ref, counter, ^expected_kind} =
        compile_native_result(
          module_name,
          name,
          args,
          env,
          counter,
          decl,
          decl_map,
          expected_kind
        )

      {code, ref, counter}
    else
      :error
    end
  end

  @spec compile_native_result(
          String.t(),
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter(),
          Types.function_declaration(),
          Types.function_decl_map(),
          native_return_kind()
        ) :: {String.t(), String.t(), Types.compile_counter(), native_return_kind()}
  defp compile_native_result(module_name, name, args, env, counter, decl, decl_map, return_kind) do
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
            borrow_args? = :borrow_arg in List.wrap(decl.ownership)

            {code, ref, c2, passthrough?} =
              FunctionCallCompile.compile_call_operand_inner(arg_expr, env, c,
                borrow_args?: borrow_args?
              )

            releases_acc =
              if passthrough? or EnvBindings.borrowed_arg_ref?(env, ref),
                do: releases_acc,
                else: releases_acc ++ [ref]

            {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc, c2}
        end
      end)

    next = counter + 1
    out = native_call_out(return_kind, next)
    c_name = Util.module_fn_name(module_name, name)
    arg_list = Enum.join(arg_refs, ", ")

    releases =
      release_refs
      |> Enum.map_join("\n  ", fn var -> "elmc_release(#{var});" end)

    code = """
    #{arg_code}
      #{native_call_decl(return_kind)}#{out} = #{c_name}_native(#{arg_list});
      #{releases}
    """

    {code, out, next, return_kind}
  end

  @spec native_args?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def native_args?(decl, module_name, decl_map) do
    decl
    |> arg_kinds(module_name, decl_map)
    |> Enum.any?(&(&1 in [:native_int, :native_bool]))
  end

  @spec native_scalar_fn?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def native_scalar_fn?(decl, module_name, decl_map) do
    native_args?(decl, module_name, decl_map) or
      ListIntSearch.recognized?(decl, module_name, decl_map) or
      match?({:ok, _}, ListIntReduce.recognize(decl, module_name, decl_map)) or
      native_scalar_return?(decl, module_name, decl_map)
  end

  # Bool/Int helpers over boxed records (for example Model -> Bool field checks) that
  # only need a native return when the body already lowers to native scalar code.
  @spec native_scalar_return?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def native_scalar_return?(%{type: type, expr: expr} = decl, module_name, decl_map)
      when is_binary(type) do
    env = callee_env(decl, module_name, decl_map)

    case Host.function_return_type(type) do
      "Bool" -> Host.native_bool_expr?(expr || %{op: :int_literal, value: 0}, env)
      "Int" -> Host.native_int_expr?(expr || %{op: :int_literal, value: 0}, env)
      _ -> false
    end
  end

  def native_scalar_return?(_decl, _module_name, _decl_map), do: false

  @spec return_kind(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          native_return_kind()
  def return_kind(%{type: type, expr: expr} = decl, module_name, decl_map) when is_binary(type) do
    if native_scalar_fn?(decl, module_name, decl_map) do
      scalar_return_kind(decl, module_name, decl_map, type, expr)
    else
      :boxed
    end
  end

  def return_kind(_decl, _module_name, _decl_map), do: :boxed

  defp scalar_return_kind(decl, module_name, decl_map, type, expr) do
    env = callee_env(decl, module_name, decl_map)

    case Host.function_return_type(type) do
      "Int" ->
        cond do
          Host.native_int_expr?(expr || %{op: :int_literal, value: 0}, env) ->
            :native_int

          ListIntSearch.recognized?(decl, module_name, decl_map) ->
            :native_int

          match?({:ok, _}, ListIntReduce.recognize(decl, module_name, decl_map)) ->
            :native_int

          true ->
            :boxed
        end

      "Bool" ->
        if Host.native_bool_expr?(expr || %{op: :int_literal, value: 0}, env),
          do: :native_bool,
          else: :boxed

      _other ->
        :boxed
    end
  end

  @spec c_return_type(native_return_kind()) :: String.t()
  def c_return_type(:native_int), do: "elmc_int_t"
  def c_return_type(:native_bool), do: "bool"
  def c_return_type(:boxed), do: "ElmcValue *"

  @spec params(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          String.t()
  def params(decl, module_name, decl_map) do
    Host.c_arg_bindings(decl.args || [])
    |> Enum.zip(arg_kinds(decl, module_name, decl_map))
    |> Enum.map_join(", ", fn {{_arg, c_arg, _index}, kind} ->
      case kind do
        :native_int -> "const elmc_int_t #{c_arg}"
        :native_bool -> "const bool #{c_arg}"
        :boxed -> "ElmcValue * const #{c_arg}"
      end
    end)
  end

  @spec arg_kinds(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          [Types.native_function_arg_kind()]
  def arg_kinds(decl, module_name, decl_map) do
    case ListIntSearch.arg_kinds(decl, module_name, decl_map) do
      {:ok, kinds} -> kinds
      :error -> default_arg_kinds(decl, module_name, decl_map)
    end
  end

  defp default_arg_kinds(%{args: args, type: type, expr: expr}, module_name, decl_map)
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

  defp default_arg_kinds(%{args: args, type: type}, _module_name, _decl_map)
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

  defp default_arg_kinds(%{args: args}, _module_name, _decl_map) when is_list(args),
    do: Enum.map(args, fn _ -> :boxed end)

  defp default_arg_kinds(_decl, _module_name, _decl_map), do: []

  @spec int_arg_safe?(Types.binding_name(), Types.ir_expr() | nil) :: boolean()
  defp int_arg_safe?(arg, expr) do
    usage = Host.native_int_usage(arg, expr || %{op: :int_literal, value: 0}, nil, %{})
    (usage.total == 0 or usage.boxed == 0) and not Host.binding_used_in_lambda?(arg, expr)
  end

  @spec bool_arg_safe?(String.t(), Types.ir_expr() | nil, String.t(), Types.function_decl_map()) ::
          boolean()
  defp bool_arg_safe?(arg, expr, module_name, decl_map) do
    usage =
      Host.native_bool_usage(arg, expr || %{op: :int_literal, value: 0}, module_name, decl_map)

    (usage.total == 0 or usage.boxed == 0) and not Host.binding_used_in_lambda?(arg, expr)
  end

  defp native_call_out(:native_int, next), do: "native_call_#{next}"
  defp native_call_out(:native_bool, next), do: "native_bool_call_#{next}"
  defp native_call_out(:boxed, next), do: "tmp_#{next}"

  defp native_call_decl(:native_int), do: "const elmc_int_t "
  defp native_call_decl(:native_bool), do: "const bool "
  defp native_call_decl(:boxed), do: "ElmcValue *"

  defp callee_env(decl, module_name, decl_map) do
    arg_names = decl.args || []
    arg_types = if is_binary(decl.type), do: Host.function_arg_types(decl.type), else: []

    Host.c_arg_bindings(arg_names)
    |> Enum.zip(arg_kinds(decl, module_name, decl_map))
    |> Enum.zip(arg_types)
    |> Enum.reduce(
      %{__module__: module_name, __program_decls__: decl_map, __function_name__: decl.name},
      fn {{{source_arg, c_arg, _index}, kind}, arg_type}, acc ->
        acc =
          case kind do
            :native_int -> EnvBindings.put_native_int_binding(acc, source_arg, c_arg)
            :native_bool -> EnvBindings.put_native_bool_binding(acc, source_arg, c_arg)
            :boxed -> Map.put(acc, source_arg, c_arg)
          end

        case Host.normalize_type_name(arg_type) do
          "Int" -> EnvBindings.put_boxed_int_binding(acc, source_arg, true)
          "Bool" -> EnvBindings.put_boxed_bool_binding(acc, source_arg, true)
          _other -> acc
        end
      end
    )
  end
end
