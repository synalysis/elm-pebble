defmodule Elmc.Backend.Plan.Fusion.ListIndexedReplace do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{FusionSupport, Host, Util}
  alias Elmc.Backend.Plan.Fusion.Tuple2CaseTable

  @indexed_map_targets ~w(List.indexedMap Elm.Kernel.List.indexedMap)

  @spec try_plan(String.t(), map(), map(), keyword()) ::
          {:ok, Elmc.Backend.Plan.Types.FunctionPlan.t()} | :error
  def try_plan(module_name, decl, _decl_map, _opts) do
    name = Map.get(decl, :name, "")

    with [index_arg, value_arg, list_arg] <- Map.get(decl, :args, []),
         true <- list_int_return?(Map.get(decl, :type, "")),
         {:ok, index_param, value_param} <-
           parse_indexed_replace(Map.get(decl, :expr), index_arg, value_arg, list_arg),
         true <- index_param == index_arg,
         true <- value_param == value_arg do
      FusionSupport.ok_rc(
        emit(module_name, name, index_arg, value_arg, list_arg),
        []
      )
      |> case do
        {:ok, c_body, _, :rc_native} ->
          {:ok, Tuple2CaseTable.build_fusion_plan(module_name, name, decl, c_body)}
      end
    else
      _ -> :error
    end
  end

  defp parse_indexed_replace(
         %{
           op: :qualified_call,
           target: target,
           args: [lambda, %{op: :var, name: list_arg}]
         },
         index_arg,
         value_arg,
         list_arg
       )
       when target in @indexed_map_targets and is_binary(index_arg) and is_binary(value_arg) and
              is_binary(list_arg) do
    parse_replace_lambda(lambda, index_arg, value_arg)
  end

  defp parse_indexed_replace(
         %{
           op: :runtime_call,
           function: "elmc_list_indexed_map",
           args: [lambda, %{op: :var, name: list_arg}]
         },
         index_arg,
         value_arg,
         list_arg
       )
       when is_binary(index_arg) and is_binary(value_arg) and is_binary(list_arg) do
    parse_replace_lambda(lambda, index_arg, value_arg)
  end

  defp parse_indexed_replace(_, _, _, _), do: :error

  defp list_int_return?(type) when is_binary(type) do
    Host.normalize_type_name(Host.function_return_type(type)) == "List Int"
  end

  defp list_int_return?(_), do: false

  defp parse_replace_lambda(
         %{op: :lambda, args: [index_param, item_param], body: body},
         index_arg,
         value_arg
       )
       when is_binary(index_param) and is_binary(item_param) do
    parse_replace_lambda_body(body, index_param, item_param, index_arg, value_arg)
  end

  defp parse_replace_lambda(
         %{op: :lambda, args: [index_param], body: %{op: :lambda, args: [item_param], body: body}},
         index_arg,
         value_arg
       )
       when is_binary(index_param) and is_binary(item_param) do
    parse_replace_lambda_body(body, index_param, item_param, index_arg, value_arg)
  end

  defp parse_replace_lambda(_, _, _), do: :error

  defp parse_replace_lambda_body(body, index_param, item_param, index_arg, value_arg) do
    case body do
      %{
        op: :if,
        cond: %{op: :compare, kind: :eq, left: left, right: right},
        then_expr: then_expr,
        else_expr: %{op: :var, name: else_name}
      }
      when else_name == item_param ->
        match_replace_target(index_param, left, right, then_expr, index_arg, value_arg)

      %{
        op: :if,
        cond: %{op: :compare, kind: :eq, left: left, right: right},
        then_expr: %{op: :var, name: then_name},
        else_expr: else_expr
      }
      when then_name == item_param ->
        match_replace_target(index_param, left, right, else_expr, index_arg, value_arg)

      _ ->
        :error
    end
  end

  defp parse_replace_lambda_body(_, _, _, _, _), do: :error

  defp match_replace_target(index_param, left, right, value_expr, index_arg, value_arg) do
    if compare_is_index_replace?(left, right, index_param, index_arg) and
         match_value?(value_expr, value_arg) do
      {:ok, index_arg, value_arg}
    else
      :error
    end
  end

  defp compare_is_index_replace?(left, right, index_param, index_arg) do
    (var_name?(left, index_param) and var_name?(right, index_arg)) or
      (var_name?(right, index_param) and var_name?(left, index_arg))
  end

  defp var_name?(%{op: :var, name: name}, expected), do: name == expected
  defp var_name?(_, _), do: false

  defp match_value?(%{op: :var, name: name}, value_arg), do: name == value_arg
  defp match_value?(_, _), do: false

  defp emit(module_name, name, index_arg, value_arg, list_arg) do
    c_prefix = Util.module_fn_name(module_name, name)

    """
    static RC #{c_prefix}_native(ElmcValue **out, const elmc_int_t #{index_arg}, const elmc_int_t #{value_arg}, ElmcValue * const #{list_arg}) {
      RC Rc = RC_SUCCESS;
      CATCH_BEGIN
        ElmcValue *result = elmc_list_replace_nth_int(#{list_arg}, #{index_arg}, #{value_arg});
        if (!result) {
          Rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(Rc);
        }
        *out = result;
      CATCH_END
      return Rc;
    }
    """
  end
end
