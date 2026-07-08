defmodule Elmc.Backend.CCodegen.LetRecCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.VarAnalysis

  @type let_binding :: {String.t(), Types.ir_expr()}

  @spec cyclic_bindings?([let_binding()]) :: boolean()
  def cyclic_bindings?(bindings) when is_list(bindings) do
    names = MapSet.new(Enum.map(bindings, &elem(&1, 0)))

    graph =
      Map.new(bindings, fn {name, value_expr} ->
        deps =
          value_expr
          |> VarAnalysis.used_vars()
          |> MapSet.intersection(names)
          |> MapSet.to_list()

        {name, deps}
      end)

    graph
    |> Map.keys()
    |> Enum.any?(&reachable_cycle?(&1, graph, MapSet.new()))
  end

  def cyclic_bindings?(_), do: false

  @spec compile(
          [let_binding()],
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  def compile(bindings, body_expr, env, counter) do
    group_id = counter + 1

    ref_entries =
      Enum.map(bindings, fn {name, _} ->
        {name, "letrec_ref_#{Util.safe_c_suffix(name)}_#{group_id}"}
      end)

    decl_code =
      ref_entries
      |> Enum.map_join("\n  ", fn {_name, ref} -> "ElmcForwardRef *#{ref} = elmc_forward_ref_new();" end)

    forward_env =
      Enum.reduce(ref_entries, env, fn {name, ref}, acc ->
        Map.put(acc, name, {:forward_ref, ref})
      end)

    {assign_code, counter} =
      Enum.reduce(bindings, {"", forward_env, group_id}, fn {name, value_expr},
                                                           {code_acc, fenv, c} ->
        ref = ref_for(ref_entries, name)
        slot = "letrec_slot_#{Util.safe_c_suffix(name)}_#{group_id}"

        {value_code, value_var, c2} =
          Host.compile_expr(value_expr, RcRuntimeEmit.strip_function_tail_scope(fenv), c)

        value_ref = RcRuntimeEmit.value_expr(value_var)

        release_step =
          if RcRuntimeEmit.function_out_ref?(value_var),
            do: "",
            else: "elmc_release(#{value_var});"

        step = """
        #{value_code}
          elmc_forward_ref_set(#{ref}, #{value_ref});
          #{release_step}
          ElmcValue *#{slot} = elmc_forward_ref_get(#{ref});
        """

        fenv = Map.put(fenv, name, slot)
        {code_acc <> "\n  " <> step, fenv, c2}
      end)
      |> then(fn {code, _fenv, c} -> {code, c} end)

    body_env =
      Enum.reduce(ref_entries, env, fn {name, ref}, acc ->
        slot = "letrec_slot_#{Util.safe_c_suffix(name)}_#{group_id}"

        acc
        |> Map.put(name, slot)
        |> Map.put(:__letrec_forward_refs__, Map.get(acc, :__letrec_forward_refs__, %{}) |> Map.put(name, ref))
      end)

    {body_code, body_var, counter} = Host.compile_expr(body_expr, body_env, counter)

    free_code =
      ref_entries
      |> Enum.map_join("\n  ", fn {name, ref} ->
        slot = Map.get(body_env, name)
        "elmc_release(#{slot});\n  elmc_forward_ref_free(#{ref});"
      end)

    code = """
    #{decl_code}
      #{assign_code}
      #{body_code}
      #{free_code}
    """

    {code, body_var, counter}
  end

  defp ref_for(ref_entries, name) do
    case Enum.find(ref_entries, fn {binding, _} -> binding == name end) do
      {^name, ref} -> ref
      _ -> raise ArgumentError, "missing letrec ref for #{inspect(name)}"
    end
  end

  defp reachable_cycle?(start, graph, visiting) do
    if MapSet.member?(visiting, start) do
      true
    else
      visiting = MapSet.put(visiting, start)

      graph
      |> Map.get(start, [])
      |> Enum.any?(&reachable_cycle?(&1, graph, visiting))
    end
  end
end
