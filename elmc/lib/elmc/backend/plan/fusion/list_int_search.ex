defmodule Elmc.Backend.Plan.Fusion.ListIntSearch do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{EnvBindings, Host, Util}
  alias Elmc.Backend.CCodegen.Native.ListIntSearch
  alias Elmc.Backend.Plan.Fusion.{Helper, Tuple2CaseTable}
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @spec try_plan(String.t(), Types.function_decl(), Types.function_decl_map(), keyword()) ::
          {:ok, FunctionPlan.t()} | :error
  def try_plan(module_name, decl, decl_map, _opts)
      when is_binary(module_name) and is_map(decl) and is_map(decl_map) do
    name = Map.get(decl, :name, "")

    with true <- Host.function_return_type(Map.get(decl, :type, "")) == "Int",
         {:ok, helper_c, native_scalar?} <- emit_helper(module_name, decl, decl_map) do
      base_plan = Tuple2CaseTable.build_fusion_plan(module_name, name, decl, helper_c)
      marked_plan = maybe_mark_native_scalar(base_plan, native_scalar?)
      plan = attach_list_int_search_fusion(marked_plan, module_name, decl, decl_map)

      {:ok, plan}
    else
      _ -> :error
    end
  end

  defp emit_helper(module_name, decl, decl_map) do
    env = fusion_env(module_name, decl, decl_map)

    cond do
      match?({:ok, _}, ListIntSearch.recognize(decl, module_name, decl_map)) ->
        with {:ok, spec} <- ListIntSearch.recognize(decl, module_name, decl_map),
             {:ok, code, result_var} <-
               ListIntSearch.compile(spec, env, :native_int, &compile_not_found_literal/4) do
          {:ok, wrap_native_helper(module_name, decl, decl_map, code, result_var), {:native_int, :helper}}
        end

      match?({:ok, _}, ListIntSearch.recognize_delegate(decl, module_name, decl_map)) ->
        with {:ok, spec} <- ListIntSearch.recognize_delegate(decl, module_name, decl_map),
             {:ok, code, result_var} <- ListIntSearch.compile_delegate(spec, env) do
          forward = delegate_help_forward_decl(spec, decl_map, module_name, decl)

          {:ok,
           forward <>
             wrap_native_helper(module_name, decl, decl_map, code, result_var, ""),
           {:native_int, :delegate}}
        end

      true ->
        :error
    end
  end

  defp maybe_mark_native_scalar(%FunctionPlan{} = plan, {:native_int, :delegate}) do
    %FunctionPlan{
      plan
      | native_scalar_return: :native_int,
        native_scalar_value_return: true,
        fusion_emit: :public_native
    }
  end

  defp maybe_mark_native_scalar(%FunctionPlan{} = plan, {:native_int, :helper}) do
    %FunctionPlan{
      plan
      | native_scalar_return: :native_int,
        native_scalar_value_return: true,
        fusion_emit: :helper_only
    }
  end

  defp fusion_env(module_name, decl, decl_map) do
    args = Map.get(decl, :args, [])

    kinds =
      case ListIntSearch.arg_kinds(decl, module_name, decl_map) do
        {:ok, kinds} -> kinds
        :error -> List.duplicate(:boxed, length(args))
      end

    args
    |> Enum.zip(kinds)
    |> Enum.reduce(%{__module__: module_name, __function_name__: Map.get(decl, :name, "")}, fn
      {arg, :native_int}, acc ->
        acc
        |> Map.put(arg, arg)
        |> EnvBindings.put_native_int_binding(arg, arg)

      {arg, _}, acc ->
        Map.put(acc, arg, arg)
    end)
  end

  defp wrap_native_helper(module_name, decl, decl_map, code, result_var, name_suffix \\ "_native") do
    c_prefix = Util.module_fn_name(module_name, decl.name)
    params = native_param_decls(decl, module_name, decl_map)
    fname = if name_suffix == "", do: c_prefix, else: "#{c_prefix}#{name_suffix}"

    """
    static elmc_int_t #{fname}(#{params}) {
    #{String.trim_leading(code)}
      return #{result_var};
    }
    """
  end

  defp native_param_decls(decl, module_name, decl_map) do
    args = Map.get(decl, :args, [])
    types = Host.function_arg_types(Map.get(decl, :type, ""))

    kinds =
      case ListIntSearch.arg_kinds(decl, module_name, decl_map) do
        {:ok, kinds} -> kinds
        :error -> List.duplicate(:boxed, length(args))
      end

    args
    |> Enum.with_index()
    |> Enum.map_join(", ", fn {arg, idx} ->
      type = Enum.at(types, idx)
      kind = Enum.at(kinds, idx)

      cond do
        kind == :native_int or type == "Int" -> "const elmc_int_t #{arg}"
        true -> "ElmcValue * const #{arg}"
      end
    end)
  end

  defp compile_not_found_literal(%{op: :int_literal, value: value}, _env, :native_int, _counter)
       when is_integer(value) do
    {"", Integer.to_string(value), 0}
  end

  defp compile_not_found_literal(%{op: :c_int_expr, value: value}, _env, :native_int, _counter)
       when is_binary(value) do
    {"", value, 0}
  end

  defp compile_not_found_literal(_, _, _, _), do: {"", "0", 0}

  defp attach_list_int_search_fusion(%FunctionPlan{} = plan, module_name, decl, decl_map) do
    case fusion_bytecode_data(module_name, decl, decl_map) do
      {:ok, data} -> Helper.attach_bytecode_fusion(plan, :list_int_search, data)
      :error -> plan
    end
  end

  defp fusion_bytecode_data(module_name, decl, decl_map) do
    case ListIntSearch.recognize(decl, module_name, decl_map) do
      {:ok, spec} ->
        {:ok, %{mode: :help, not_found: not_found_literal(spec.not_found)}}

      :error ->
        case ListIntSearch.recognize_delegate(decl, module_name, decl_map) do
          {:ok, spec} ->
            {:ok, %{mode: :delegate, help: {spec.help_module, spec.help_name}}}

          :error ->
            :error
        end
    end
  end

  defp not_found_literal(%{op: :int_literal, value: value}) when is_integer(value), do: value
  defp not_found_literal(%{op: :c_int_expr, value: value}) when is_binary(value), do: String.to_integer(value)
  defp not_found_literal(_), do: -1

  defp delegate_help_forward_decl(
         %{help_module: help_module, help_name: help_name},
         decl_map,
         _module_name,
         _decl
       ) do
    case Map.fetch(decl_map, {help_module, help_name}) do
      {:ok, help_decl} ->
        c_prefix = Util.module_fn_name(help_module, help_name)
        params = native_param_decls(help_decl, help_module, decl_map)
        "static elmc_int_t #{c_prefix}_native(#{params});\n\n"

      :error ->
        ""
    end
  end
end
