defmodule Elmc.Backend.Wasm.ImportCollect do
  @moduledoc false

  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}
  alias Elmc.Backend.Wasm.{ImportSignatures, RuntimeImports}

  @type arity_map :: %{String.t() => non_neg_integer()}

  @spec collect(FunctionPlan.t()) :: {MapSet.t(String.t()), arity_map()}
  def collect(%FunctionPlan{} = plan) do
    blocks = plan.blocks ++ Enum.flat_map(Map.get(plan, :lambdas) || [], & &1.blocks)

    blocks
    |> Enum.reduce({MapSet.new(), %{}}, fn %Block{instrs: instrs}, acc ->
      Enum.reduce(instrs, acc, &collect_instr/2)
    end)
    |> collect_native_scalar_return(plan)
  end

  defp collect_native_scalar_return({imports, arities}, %{native_scalar_return: :native_int}) do
    put_import(imports, arities, RuntimeImports.import_name(:new_int), 2)
  end

  defp collect_native_scalar_return({imports, arities}, %{native_scalar_return: :native_bool}) do
    put_import(imports, arities, RuntimeImports.import_name(:new_bool), 2)
  end

  defp collect_native_scalar_return(acc, _plan), do: acc

  @spec merge([{MapSet.t(String.t()), arity_map()}]) :: {MapSet.t(String.t()), arity_map()}
  def merge(pairs) when is_list(pairs) do
    Enum.reduce(pairs, {MapSet.new(), %{}}, fn {imports, arities}, {acc_imports, acc_arities} ->
      imports = MapSet.union(acc_imports, imports)

      arities =
        Enum.reduce(arities, acc_arities, fn {name, arity}, merged ->
          Map.update(merged, name, arity, &max(&1, arity))
        end)

      {imports, arities}
    end)
  end

  defp collect_instr(%{op: :call_runtime, args: %{builtin: :retain, view_peel: peel_id} = args_map}, {imports, arities}) do
    peel_args_map = %{args: Map.get(args_map, :view_peel_args, [])}
    peel_name = RuntimeImports.import_name(peel_id)
    peel_arity = ImportSignatures.call_runtime_param_count(peel_id, peel_args_map)
    put_import(imports, arities, peel_name, peel_arity)
  end

  defp collect_instr(%{op: :call_runtime, args: %{builtin: builtin} = args_map}, {imports, arities}) do
    name = RuntimeImports.import_name(builtin)
    arity = ImportSignatures.call_runtime_param_count(builtin, args_map)
    put_import(imports, arities, name, arity)
  end

  defp collect_instr(%{op: :const_static_list, args: args}, acc) do
    case Map.get(args, :kind) do
      :int_array ->
        count = args |> Map.get(:values, []) |> length()
        collect_const_static_list_count(acc, count, :list_from_int_array)

      kind when kind in [:values, :record_array] ->
        regs = Map.get(args, :regs, []) |> List.wrap()

        acc =
          regs
          |> Enum.with_index()
          |> Enum.reduce(acc, fn {reg, idx}, acc_inner ->
            prior = Enum.take(regs, idx)
            if reg in prior, do: put_import_elem(acc_inner, RuntimeImports.import_name(:retain), 2), else: acc_inner
          end)

        collect_const_static_list_count(acc, length(regs), :list_from_values)

      _ ->
        put_import_elem(acc, RuntimeImports.import_name(:list_nil), 1)
    end
  end

  defp collect_instr(%{op: :const_immortal_string}, acc),
    do: put_import_elem(acc, RuntimeImports.import_name(:new_immortal_string), 2)

  defp collect_instr(%{op: op}, acc) when op in [:record_get, :record_get_int],
    do: put_import_elem(acc, RuntimeImports.import_name(:record_get), 3)

  defp collect_instr(%{op: :record_update}, acc),
    do: put_import_elem(acc, RuntimeImports.import_name(:record_update), 4)

  defp collect_instr(%{op: :tuple_proj}, acc),
    do: put_import_elem(acc, RuntimeImports.import_name(:tuple_proj), 3)

  defp collect_instr(%{op: :test_maybe_nothing}, acc),
    do: put_import_elem(acc, RuntimeImports.import_name(:maybe_is_nothing), 2)

  defp collect_instr(%{op: :test_list_empty}, acc),
    do: put_import_elem(acc, RuntimeImports.import_name(:list_is_empty), 2)

  defp collect_instr(%{op: :bool_and}, acc),
    do: put_import_elem(acc, "runtime.as_bool", 1)

  defp collect_instr(%{op: :test_ctor_tag}, acc),
    do: put_import_elem(acc, RuntimeImports.import_name(:union_tag_matches), 3)

  defp collect_instr(%{op: :compare, args: %{mode: :string} = args}, acc) do
    acc = put_import_elem(acc, RuntimeImports.import_name(:string_equals), 3)

    if Map.get(args, :kind) == :neq do
      put_import_elem(acc, RuntimeImports.import_name(:basics_not), 2)
    else
      acc
    end
  end

  defp collect_instr(%{op: :test_string_literal}, acc),
    do: put_import_elem(acc, RuntimeImports.import_name(:string_equals_literal), 3)

  defp collect_instr(%{op: :boxed_tag_peel}, acc),
    do: put_import_elem(acc, RuntimeImports.import_name(:boxed_tag_peel), 2)

  defp collect_instr(%{op: :forward_ref_set}, acc),
    do: put_import_elem(acc, RuntimeImports.import_name(:forward_ref_set), 2)

  defp collect_instr(%{op: :forward_ref_load}, acc),
    do: put_import_elem(acc, RuntimeImports.import_name(:forward_ref_load), 2)

  defp collect_instr(%{op: :forward_ref_capture}, acc),
    do: put_import_elem(acc, RuntimeImports.import_name(:forward_ref_capture), 2)

  defp collect_instr(%{op: :forward_ref_load_captured}, acc),
    do: put_import_elem(acc, RuntimeImports.import_name(:forward_ref_load_captured), 2)

  defp collect_instr(%{op: :list_cursor_map}, acc),
    do: put_import_elem(acc, RuntimeImports.import_name(:list_cursor_map), 3)

  defp collect_instr(%{op: :html_cmd, args: %{params: params}}, {imports, arities}) do
    argc = params |> List.wrap() |> length()
    # (out_ptr, kind, ...params)
    put_import(imports, arities, "runtime.html_cmd", 2 + argc)
  end

  defp collect_instr(%{op: :browser_cmd, args: %{params: params}}, {imports, arities}) do
    argc = params |> List.wrap() |> length()
    put_import(imports, arities, "runtime.browser_cmd", 2 + argc)
  end

  defp collect_instr(%{op: :json_cmd, args: %{params: params}}, {imports, arities}) do
    argc = params |> List.wrap() |> length()
    put_import(imports, arities, "runtime.json_cmd", 2 + argc)
  end

  defp collect_instr(%{op: :bytes_cmd, args: %{params: params}}, {imports, arities}) do
    argc = params |> List.wrap() |> length()
    put_import(imports, arities, "runtime.bytes_cmd", 2 + argc)
  end

  defp collect_instr(%{op: :dom_sub, args: %{params: params}}, {imports, arities}) do
    argc = params |> List.wrap() |> length()
    # (out_ptr, kind, ...params)
    put_import(imports, arities, "runtime.dom_sub", 2 + argc)
  end

  defp collect_instr(%{op: :make_closure, args: args}, acc) do
    caps = Map.get(args, :captures, []) |> List.wrap() |> length()
    put_import_elem(acc, RuntimeImports.import_name(:make_closure), 3 + caps)
  end

  defp collect_instr(%{op: :call_closure, args: args}, acc) do
    argc = Map.get(args, :args, []) |> List.wrap() |> length()
    put_import_elem(acc, RuntimeImports.import_name(:call_closure), 3 + argc)
  end

  defp collect_instr(%{op: :boxed_binop, args: %{op: op}}, acc) do
    acc = put_import_elem(acc, "runtime.as_int", 1)

    if op == :fdiv do
      acc
      |> put_import_elem("runtime.as_float", 1)
      |> put_import_elem("runtime.float_div_bits", 2)
      |> put_import_elem(RuntimeImports.import_name(:new_float), 2)
    else
      put_import_elem(acc, RuntimeImports.import_name(:new_int), 2)
    end
  end

  defp collect_instr(%{op: :load_local, dest: dest}, acc) when dest in [:fn_out, :branch_out],
    do: put_import_elem(acc, RuntimeImports.import_name(:new_int), 2)

  defp collect_instr(%{op: :int_arith}, acc),
    do: put_import_elem(acc, "runtime.as_int", 1)

  defp collect_instr(%{op: :publish, dest: :fn_out}, acc),
    do: put_import_elem(acc, RuntimeImports.import_name(:new_int), 2)

  defp collect_instr(_, acc), do: acc

  defp collect_const_static_list_count(acc, count, builtin) when count > 0,
    do: put_import_elem(acc, RuntimeImports.import_name(builtin), 3)

  defp collect_const_static_list_count(acc, _count, _builtin),
    do: put_import_elem(acc, RuntimeImports.import_name(:list_nil), 1)

  defp put_import_elem({imports, arities}, name, arity), do: put_import(imports, arities, name, arity)

  defp put_import(imports, arities, name, arity) do
    merged = Map.update(arities, name, arity, &max(&1, arity))
    {MapSet.put(imports, name), merged}
  end
end
