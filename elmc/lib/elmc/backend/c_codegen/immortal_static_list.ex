defmodule Elmc.Backend.CCodegen.ImmortalStaticList do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.Host
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
    case zero_arg_decl_list_literal(module_name, name, env) do
      {:ok, items} -> {:ok, length(items)}
      :error -> :error
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
          String.t()
        ) :: String.t()
  def compile_static_int_list_nth_boxed(spec, index_code, index_ref, default_code, default_ref, out) do
    count = length(spec.values)
    index_use = native_index_use(index_ref)

    """
    #{index_code}#{default_code}
      /* #{spec.module}.#{spec.name}[n] static table */
      ElmcValue *#{out} =
        (#{index_use} >= 0 && #{index_use} < #{count})
          ? elmc_new_int_take(#{spec.sym}_values[#{index_use}])
          : elmc_retain(#{default_ref});
    """
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
          boolean()
        ) :: {:ok, String.t(), String.t()} | :error
  def try_emit_function_prelude_and_body(module_name, fun_name, expr, direct_args?) do
    with true <- match?(%{op: :list_literal, items: _}, expr),
         {:ok, prelude, return_expr} <- emit_list(module_name, fun_name, expr) do
      body =
        emit_function_body(direct_args?, return_expr)

      {:ok, prelude, body}
    else
      _ -> :error
    end
  end

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
    last = count - 1

    """
    static const elmc_int_t #{sym}_values[#{count}] = { #{values_str} };

    static struct {
      ElmcValue int_heads[#{count}];
      ElmcValue list_cells[#{count}];
      ElmcCons cons[#{count}];
    } #{sym}_storage;

    static ElmcValue *#{sym}_ptr;
    static int #{sym}_ready;

    static ElmcValue *#{sym}_get(void) {
      if (!#{sym}_ready) {
        for (int i = #{last}; i >= 0; i--) {
          ElmcValue *head = &#{sym}_storage.int_heads[i];
          ElmcCons *cell_cons = &#{sym}_storage.cons[i];
          ElmcValue *cell_value = &#{sym}_storage.list_cells[i];
          head->rc = ELMC_RC_IMMORTAL;
          head->tag = ELMC_TAG_INT;
          head->payload = NULL;
          head->scalar = #{sym}_values[i];
          cell_cons->head = head;
          cell_cons->tail = (i == #{last}) ? elmc_list_nil() : &#{sym}_storage.list_cells[i + 1];
          cell_value->rc = ELMC_RC_IMMORTAL;
          cell_value->tag = ELMC_TAG_LIST;
          cell_value->payload = cell_cons;
          cell_value->scalar = ELMC_LIST_CELL_SCALAR;
        }
        #{sym}_ptr = &#{sym}_storage.list_cells[0];
        #{sym}_ready = 1;
      }
      return #{sym}_ptr;
    }
    """
    |> String.trim_trailing()
  end

  defp emit_function_body(direct_args?, return_expr) do
    prologue = if direct_args?, do: [], else: ["(void)args;", "(void)argc;"]

    prologue
    |> Kernel.++(["return elmc_retain(#{return_expr});"])
    |> Enum.join("\n")
    |> CSource.format_block(2)
  end
end
