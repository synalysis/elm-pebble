defmodule Elmc.Backend.CCodegen.ImmortalStaticList do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.CodegenListHelpers
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @min_items 1

  @type static_int_list_spec :: %{
          module: String.t(),
          name: String.t(),
          sym: String.t(),
          values: [integer()]
        }

  @spec static_length(Types.ir_expr(), Types.compile_env()) ::
          {:ok, non_neg_integer()} | :error
  def static_length(expr, env) do
    case list_literal_length(expr) do
      {:ok, count} -> {:ok, count}
      :error -> zero_arg_function_list_length(expr, env)
    end
  end

  defp list_literal_length(%{op: :list_literal, items: items}) when is_list(items),
    do: {:ok, length(items)}

  defp list_literal_length(_expr), do: :error

  defp zero_arg_function_list_length(%{op: :var, name: name}, env) when is_binary(name) do
    zero_arg_decl_list_length(Map.get(env, :__module__, "Main"), name, env)
  end

  defp zero_arg_function_list_length(%{op: :call, name: name, args: []}, env)
       when is_binary(name) do
    zero_arg_decl_list_length(Map.get(env, :__module__, "Main"), name, env)
  end

  defp zero_arg_function_list_length(%{op: :qualified_call, target: target, args: []}, env) do
    case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
      {module, name} -> zero_arg_decl_list_length(module, name, env)
      _ -> :error
    end
  end

  defp zero_arg_function_list_length(_expr, _env), do: :error

  defp zero_arg_decl_list_length(module_name, name, env) do
    case Map.get(env, :__program_decls__, %{}) do
      %{} = decl_map ->
        case Map.get(decl_map, {module_name, name}) do
          %{args: args, expr: %{op: :list_literal, items: items}}
          when args in [[], nil] and is_list(items) ->
            {:ok, length(items)}

          %{args: args, expr: expr} when args in [[], nil] ->
            repeat_zero_literal_count(expr)

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  @spec static_immortal_int_list(Types.ir_expr(), Types.compile_env()) ::
          {:ok, static_int_list_spec()} | :error
  def static_immortal_int_list(expr, env) do
    with {:ok, module, name, items} <- zero_arg_function_list_source(expr, env),
         {:ok, :int, values} <- static_int_items(items) do
      {:ok, %{module: module, name: name, sym: immortal_symbol(module, name), values: values}}
    end
  end

  @spec length_heritage_comment(Types.ir_expr(), Types.compile_env()) :: String.t() | nil
  def length_heritage_comment(expr, env) do
    case static_list_length_source(expr, env) do
      {:ok, module, name} -> "/* List.length #{module}.#{name} */"
      :error -> nil
    end
  end

  @spec format_static_length(integer(), Types.ir_expr(), Types.compile_env()) :: String.t()
  def format_static_length(count, source_expr, env) do
    case length_heritage_comment(source_expr, env) do
      nil -> Integer.to_string(count)
      comment -> "#{count} #{comment}"
    end
  end

  @spec compile_static_int_list_nth_native(
          static_int_list_spec(),
          String.t(),
          String.t(),
          String.t()
        ) :: String.t()
  def compile_static_int_list_nth_native(spec, index_ref, default_ref, out) do
    count = length(spec.values)
    index_use = native_index_use(index_ref)

    """
    /* #{spec.module}.#{spec.name}[n] static table */
    const elmc_int_t #{out} =
      (#{index_use} >= 0 && #{index_use} < #{count})
        ? #{spec.sym}_values[#{index_use}]
        : #{default_ref};
    """
  end

  @spec compile_static_int_list_nth_boxed(
          static_int_list_spec(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          keyword()
        ) :: String.t()
  def compile_static_int_list_nth_boxed(
        spec,
        index_code,
        index_ref,
        default_code,
        default_ref,
        out,
        opts \\ []
      ) do
    count = length(spec.values)
    index_use = native_index_use(index_ref)
    table_comment = "/* #{spec.module}.#{spec.name}[n] static table */"
    _env = Keyword.get(opts, :env, %{})

    take_block = """
    ElmcValue *#{out} = NULL;
    if (#{index_use} >= 0 && #{index_use} < #{count}) {
      #{RcRuntimeEmit.check_rc_take(out, "elmc_new_int", "#{spec.sym}_values[#{index_use}]")}
    } else {
      #{out} = elmc_retain(#{default_ref});
    }
    """

    cond do
      Keyword.get(opts, :fn_out?, false) and RcRuntimeEmit.function_out_ref?(out) ->
        """
        #{index_code}#{default_code}
          #{table_comment}
          if (#{index_use} >= 0 && #{index_use} < #{count}) {
            #{RcRuntimeEmit.check_rc_take(out, "elmc_new_int", "#{spec.sym}_values[#{index_use}]")}
          } else {
            #{RcRuntimeEmit.function_out_deref()} = elmc_retain(#{default_ref});
          }
        """

      true ->
        """
        #{index_code}#{default_code}
          #{table_comment}
          #{take_block}
        """
    end
  end

  defp native_index_use(index_ref) when is_binary(index_ref) do
    case Integer.parse(index_ref) do
      {_, ""} -> index_ref
      :error -> if(String.starts_with?(index_ref, "native_"), do: index_ref, else: "elmc_as_int(#{index_ref})")
    end
  end

  defp static_list_length_source(expr, env) do
    case expr do
      %{op: :runtime_call, function: "elmc_list_length", args: [list]} ->
        zero_arg_function_ref(list, env)

      %{op: :qualified_call, target: target, args: [list]}
      when target in ["List.length", "Elm.Kernel.List.length"] ->
        zero_arg_function_ref(list, env)

      %{op: :call, name: "length", args: [list]} ->
        zero_arg_function_ref(list, env)

      other ->
        zero_arg_function_ref(other, env)
    end
  end

  defp zero_arg_function_ref(expr, env) do
    case expr do
      %{op: :var, name: name} when is_binary(name) ->
        {:ok, Map.get(env, :__module__, "Main"), name}

      %{op: :call, name: name, args: []} when is_binary(name) ->
        {:ok, Map.get(env, :__module__, "Main"), name}

      %{op: :qualified_call, target: target, args: []} ->
        case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
          {module, name} -> {:ok, module, name}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp zero_arg_decl_list_literal(module_name, name, env) do
    case Map.get(env, :__program_decls__, %{}) do
      %{} = decl_map ->
        case Map.get(decl_map, {module_name, name}) do
          %{args: args, expr: %{op: :list_literal, items: items}}
          when args in [[], nil] and is_list(items) ->
            {:ok, items}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp zero_arg_function_list_source(expr, env) do
    with {:ok, module, name} <- zero_arg_function_ref(expr, env),
         {:ok, items} <- zero_arg_decl_list_literal(module, name, env) do
      {:ok, module, name, items}
    end
  end

  @spec zero_arg_function?(Types.function_declaration()) :: boolean()
  def zero_arg_function?(decl) do
    (decl.args || []) == []
  end

  @spec try_emit_function_prelude_and_body(
          String.t(),
          String.t(),
          Types.ir_expr(),
          boolean(),
          boolean()
        ) :: {:ok, String.t(), String.t()} | :error
  def try_emit_function_prelude_and_body(module_name, fun_name, expr, direct_args?, rc_required?) do
    with {:ok, prelude, return_expr} <- emit_static_body_expr(module_name, fun_name, expr) do
      body = emit_function_body(direct_args?, return_expr, rc_required?)
      {:ok, prelude, body}
    else
      _ -> :error
    end
  end

  defp emit_static_body_expr(module_name, fun_name, %{op: :list_literal, items: items}) do
    emit_list(module_name, fun_name, %{op: :list_literal, items: items})
  end

  defp emit_static_body_expr(module_name, fun_name, expr) do
    with {:ok, count} <- repeat_zero_literal_count(expr) do
      sym = immortal_symbol(module_name, fun_name)
      {:ok, CodegenListHelpers.emit_zero_repeat_prelude(sym, count), "(ElmcValue *)&#{sym}_value"}
    end
  end

  defp repeat_zero_literal_count(%{
         op: :qualified_call,
         target: target,
         args: [n, %{op: :int_literal, value: 0}]
       })
       when target in ["List.repeat", "Elm.Kernel.List.repeat"] do
    case n do
      %{op: :int_literal, value: count} when is_integer(count) and count > 0 and count <= 32 ->
        {:ok, count}

      _ ->
        :error
    end
  end

  defp repeat_zero_literal_count(_expr), do: :error

  defp emit_list(_module_name, _fun_name, %{op: :list_literal, items: []}) do
    {:ok, "", "elmc_list_nil()"}
  end

  defp emit_list(module_name, fun_name, %{op: :list_literal, items: items})
       when length(items) >= @min_items do
    with {:ok, :int, values} <- static_int_items(items) do
      sym = immortal_symbol(module_name, fun_name)
      {:ok, emit_int_prelude(sym, values), "#{sym}_get()"}
    end
  end

  defp emit_list(_module_name, _fun_name, _expr), do: :error

  defp static_int_items(items) do
    if Enum.all?(items, &static_int_literal?/1) do
      {:ok, :int, Enum.map(items, & &1.value)}
    else
      :error
    end
  end

  defp static_int_literal?(%{op: :int_literal, value: value}) when is_integer(value), do: true
  defp static_int_literal?(_), do: false

  defp immortal_symbol(module_name, fun_name) do
    "elmc_immortal_list_#{Util.safe_c_suffix(module_name)}_#{Util.safe_c_suffix(fun_name)}"
  end

  defp emit_int_prelude(sym, values) do
    count = length(values)
    values_str = Enum.join(values, ", ")

    """
    #{Elmc.Runtime.IntList.emit_immortal_static_prelude(sym, values_str, count)}

    static ElmcValue *#{sym}_get(void) {
      return (ElmcValue *)&#{sym}_value;
    }
    """
    |> String.trim_trailing()
  end

  defp emit_function_body(direct_args?, return_expr, rc_required?) do
    prologue = if direct_args?, do: [], else: ["(void)args;", "(void)argc;"]

    return_lines =
      if rc_required? do
        ["*out = elmc_retain(#{return_expr});", "return RC_SUCCESS;"]
      else
        ["return elmc_retain(#{return_expr});"]
      end

    prologue
    |> Kernel.++(return_lines)
    |> Enum.join("\n")
    |> CSource.format_block(2)
  end
end
