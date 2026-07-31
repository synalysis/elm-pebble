defmodule Elmc.Backend.Plan.Fusion.Matchers.TailRecursiveLoop do
  @moduledoc """
  Whole-function fusion for simple self-tail-recursive `if` loops.

  Covers Int/Bool scalar params (e.g. StackTailRec) and boxed params such as
  `List` accumulators (e.g. BigListGC / DecTest `buildList`). Plan-primary CFG
  emission would otherwise recurse until stack overflow; classic codegen already
  lowers matching shapes to `while (1)`.

  Emits a complete `static RC …_native(ElmcValue **out, …)` helper so plan-primary
  can `store_generic_helper_c` and wrap with a thin RC entry.
  """
  alias Elmc.Backend.CCodegen.{
    FunctionEmit,
    Host,
    Native.FunctionCall,
    TailRecursiveLoopEmit,
    Util,
    ValueSlots
  }

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [], :rc_native} | :error
  def try_emit(module_name, name, expr, decl_map)
      when is_binary(module_name) and is_binary(name) and is_map(decl_map) do
    # Fusion probes run while another function may be mid-emit (e.g. direct-render
    # `commands_append` analyzing callees). Resetting owned slots without restore
    # reuses indices still referenced by already-emitted C (blank Tangram dial).
    ValueSlots.with_isolated_probe(fn ->
      with %{expr: _} = decl <- fetch_decl(decl_map, module_name, name, expr),
           true <- supported_return?(decl),
           arg_kinds when is_list(arg_kinds) and arg_kinds != [] <-
             FunctionCall.arg_kinds(decl, module_name, decl_map),
           true <- tail_loop_arg_kinds?(arg_kinds, decl),
           env <- fusion_env(module_name, decl, decl_map),
           :ok <- ValueSlots.reset(epilogue_lifo: true),
           {:ok, code, result_var} <-
             TailRecursiveLoopEmit.compile_fusion(
               decl,
               module_name,
               env,
               arg_kinds,
               :boxed
             ) do
        helper = wrap_rc_native_helper(module_name, decl, decl_map, arg_kinds, code, result_var)
        {:ok, helper, [], :rc_native}
      else
        _ -> :error
      end
    end)
  end

  defp wrap_rc_native_helper(module_name, decl, decl_map, arg_kinds, code, result_var) do
    c_name = Util.module_fn_name(module_name, Map.get(decl, :name, ""))
    params = native_param_decls(decl, module_name, decl_map, arg_kinds)
    owned = ValueSlots.owned_declaration()
    slot_n = ValueSlots.slot_count()

    owned_transfer =
      if ValueSlots.owned_ref?(result_var), do: ValueSlots.transfer_and_null(result_var), else: ""

    epilogue =
      if slot_n > 0 do
        "elmc_release_array_lifo(owned, #{slot_n});"
      else
        ""
      end

    """
    static RC #{c_name}_native(ElmcValue **out, #{params}) {
      RC Rc = RC_SUCCESS;
      #{owned}
      CATCH_BEGIN
    #{indent(String.trim(code), 2)}
        *out = #{result_var};
        #{owned_transfer}
      CATCH_END
      #{epilogue}
      return Rc;
    }
    """
    |> String.trim()
  end

  defp native_param_decls(decl, module_name, decl_map, arg_kinds) do
    args = Map.get(decl, :args, [])
    bindings = FunctionEmit.c_arg_bindings(args)
    types = Host.function_arg_types(Map.get(decl, :type, ""))
    direct_kinds = FunctionCall.arg_kinds(decl, module_name, decl_map)

    bindings
    |> Enum.map_join(", ", fn {_arg, c_name, idx} ->
      type = types |> Enum.at(idx) |> Host.normalize_type_name()
      kind = Enum.at(arg_kinds, idx)
      direct = Enum.at(direct_kinds, idx)

      cond do
        direct == :native_int or (kind == :native_int and type == "Int") ->
          "const elmc_int_t #{c_name}"

        direct == :native_bool or (kind == :native_bool and type == "Bool") ->
          "const bool #{c_name}"

        kind == :native_int and type == "Int" ->
          "const elmc_int_t #{c_name}"

        true ->
          "ElmcValue * const #{c_name}"
      end
    end)
  end

  defp indent(text, n) when is_binary(text) and is_integer(n) do
    pad = String.duplicate(" ", n)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> pad <> line
    end)
  end

  defp fetch_decl(decl_map, module_name, name, expr) do
    case Map.get(decl_map, {module_name, name}) do
      %{expr: _} = decl when is_map(expr) ->
        %{decl | expr: expr}

      %{expr: _} = decl ->
        decl

      _ when is_map(expr) ->
        %{name: name, expr: expr, args: [], type: ""}

      _ ->
        nil
    end
  end

  # Int/Bool scalar returns plus List builders (BigListGC). Reject Array/JsArray/
  # function/record returns so helpers like Array.initializeHelp stay on plan CFG.
  defp supported_return?(decl) do
    case Host.function_return_type(Map.get(decl, :type, "")) do
      ret when ret in ["Int", "Bool"] -> true
      ret when is_binary(ret) -> list_type?(ret)
    end
  end

  defp tail_loop_arg_kinds?(arg_kinds, decl) do
    arg_types =
      if is_binary(Map.get(decl, :type)) do
        Host.function_arg_types(decl.type)
      else
        []
      end

    arg_kinds != [] and
      length(arg_kinds) == length(Map.get(decl, :args, [])) and
      Enum.with_index(arg_kinds)
      |> Enum.all?(fn {kind, index} ->
        type = arg_types |> Enum.at(index) |> Host.normalize_type_name()

        case {kind, type} do
          {:native_int, _} -> true
          {:native_bool, _} -> true
          {:boxed, "Int"} -> true
          {:boxed, "Bool"} -> true
          {:boxed, ty} -> collection_loop_type?(ty)
          _ -> false
        end
      end)
  end

  # Boxed accumulators / worksets that TailRecursiveLoop can own across iterations.
  # List builders (BigListGC) plus Set/Dict worksets (BenchSetIntWorkset).
  # Still reject Array/JsArray/function/record — those stay on plan CFG.
  @spec collection_loop_type?(String.t()) :: boolean()
  defp collection_loop_type?(type) when is_binary(type) do
    type = Host.normalize_type_name(type)

    list_type?(type) or
      type == "Set" or String.starts_with?(type, "Set ") or String.starts_with?(type, "Set.") or
      type == "Dict" or String.starts_with?(type, "Dict ") or String.starts_with?(type, "Dict.")
  end

  @spec list_type?(String.t()) :: boolean()
  defp list_type?(type) when is_binary(type) do
    type = Host.normalize_type_name(type)
    type == "List" or String.starts_with?(type, "List ") or String.starts_with?(type, "List.")
  end

  defp fusion_env(module_name, decl, decl_map) do
    args = Map.get(decl, :args, [])
    bindings = FunctionEmit.c_arg_bindings(args)

    base = %{
      __module__: module_name,
      __module_name__: module_name,
      __function_name__: Map.get(decl, :name, ""),
      __program_decls__: decl_map,
      __rc_required__: true,
      __rc_catch__: true,
      __epilogue_lifo__: true
    }

    Enum.reduce(bindings, base, fn {arg, c_name, _idx}, acc ->
      Map.put(acc, arg, c_name)
    end)
  end
end
