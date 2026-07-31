defmodule Elmc.Backend.Plan.Tuple2IntsUnbox do
  @moduledoc false

  # Scalar-replace local heap pairs:
  # - `tuple2_ints` (`(Int, Int)`) when projections are native-int-only uses
  # - `tuple2` (e.g. `(List Int, Int)`) when projections are only borrowed (not
  #   consumed), so list/int operands stay in their original regs
  # - `:native_int_pair` `call_fn` results when projections are native-int-only
  #   (call-site SROA: keep dual `elmc_int_t` outs, skip `elmc_tuple2_ints`)
  # - `:native_list_int_pair` `call_fn` results when every projection is only
  #   passed into later `call_fn` args or used as a native int (not record
  #   fields / other boxed sinks). List stays in the call dest owned slot.
  # Box at escape remains via other uses of the pair reg (return, call args, …).
  # Passthrough dual-out (caller also `:native_list_int_pair`) skips the pack.

  alias Elmc.Backend.C.Lower.NativeReturn
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.Plan.RuntimeBuiltins
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @type rewrite :: %{
          pair: non_neg_integer(),
          proj: non_neg_integer(),
          src: non_neg_integer(),
          drop_pair?: boolean()
        }

  @spec run(FunctionPlan.t()) :: FunctionPlan.t()
  def run(%FunctionPlan{blocks: blocks} = plan) do
    instrs = Enum.flat_map(blocks, & &1.instrs)
    terms = Enum.map(blocks, & &1.terminator)
    max_reg = max_reg_index(blocks)

    heap_rewrites = heap_pair_rewrites(instrs, terms)

    {call_rewrites, native_pair_out, native_list_int_pair_out, _} =
      native_pair_call_rewrites(instrs, terms, max_reg + 1)

    rewrites = heap_rewrites ++ call_rewrites

    case rewrites do
      [] ->
        plan

      rewrites ->
        alias_map = Map.new(rewrites, &{&1.proj, &1.src})
        drop_projs = MapSet.new(rewrites, & &1.proj)

        drop_pairs =
          rewrites
          |> Enum.filter(& &1.drop_pair?)
          |> MapSet.new(& &1.pair)

        blocks =
          blocks
          |> Enum.map(&rewrite_block(&1, alias_map, drop_projs, drop_pairs))
          |> Enum.map(&annotate_native_pair_calls(&1, native_pair_out))
          |> Enum.map(&annotate_native_list_int_pair_calls(&1, native_list_int_pair_out))

        %{plan | blocks: blocks}
    end
  end

  @spec heap_pair_rewrites([map()], [term()]) :: [rewrite()]
  defp heap_pair_rewrites(instrs, terms) do
    instrs
    |> Enum.flat_map(fn
      %{op: :call_runtime, dest: pair, args: %{builtin: builtin, args: [a, b]}}
      when builtin in [:tuple2_ints, :tuple2] and is_integer(pair) and is_integer(a) and
             is_integer(b) ->
        case pair_use_shape(pair, a, b, builtin, instrs, terms) do
          {:unbox, proj_aliases} ->
            Enum.map(proj_aliases, fn {proj, src} ->
              %{pair: pair, proj: proj, src: src, drop_pair?: true}
            end)

          :keep ->
            []
        end

      _ ->
        []
    end)
  end

  @spec native_pair_call_rewrites([map()], [term()], non_neg_integer()) ::
          {[rewrite()], %{non_neg_integer() => {non_neg_integer(), non_neg_integer()}},
           %{non_neg_integer() => non_neg_integer()}, non_neg_integer()}
  defp native_pair_call_rewrites(instrs, terms, next_reg) do
    Enum.reduce(
      instrs,
      {[], %{}, %{}, next_reg},
      fn
        %{op: :call_fn, dest: pair, args: %{module: mod, name: name}},
        {rewrites, int_out, list_int_out, next}
        when is_integer(pair) ->
          cond do
            native_int_pair_callee?(mod, name) ->
              case pair_use_shape(pair, nil, nil, :tuple2_ints, instrs, terms) do
                {:unbox, proj_aliases} ->
                  first_reg = next
                  second_reg = next + 1

                  new_rewrites =
                    Enum.map(proj_aliases, fn {proj, which} ->
                      src =
                        case which do
                          :first -> first_reg
                          :second -> second_reg
                          other when is_integer(other) -> other
                        end

                      %{pair: pair, proj: proj, src: src, drop_pair?: true}
                    end)

                  {rewrites ++ new_rewrites, Map.put(int_out, pair, {first_reg, second_reg}),
                   list_int_out, second_reg + 1}

                :keep ->
                  {rewrites, int_out, list_int_out, next}
              end

            native_list_int_pair_callee?(mod, name) ->
              case pair_use_shape(pair, pair, nil, :list_int_pair_call, instrs, terms) do
                {:unbox, proj_aliases} ->
                  if sroa_proj_aliases_safe?(proj_aliases, instrs) do
                    int_reg = next

                    new_rewrites =
                      Enum.map(proj_aliases, fn {proj, which} ->
                        src =
                          case which do
                            :first -> pair
                            :second -> int_reg
                            other when is_integer(other) -> other
                          end

                        %{pair: pair, proj: proj, src: src, drop_pair?: false}
                      end)

                    {rewrites ++ new_rewrites, int_out, Map.put(list_int_out, pair, int_reg),
                     int_reg + 1}
                  else
                    {rewrites, int_out, list_int_out, next}
                  end

                :keep ->
                  {rewrites, int_out, list_int_out, next}
              end

            true ->
              {rewrites, int_out, list_int_out, next}
          end

        _, acc ->
          acc
      end
    )
  end

  defp native_list_int_pair_callee?(mod, name) when is_binary(mod) and is_binary(name) do
    NativeReturn.cached_kind({mod, name}) == :native_list_int_pair
  end

  @spec native_int_pair_callee?(String.t(), String.t()) :: boolean()
  defp native_int_pair_callee?(mod, name) when is_binary(mod) and is_binary(name) do
    case NativeReturn.cached_kind({mod, name}) do
      :native_int_pair ->
        true

      _ ->
        decl_map = Process.get(:elmc_program_decls, %{})

        case Map.get(decl_map, {mod, name}) do
          %{type: type} when is_binary(type) ->
            case Host.function_return_type(type) do
              ret when is_binary(ret) -> NativeInt.int_tuple2_type?(ret)
              _ -> false
            end

          _ ->
            false
        end
    end
  end

  defp pair_use_shape(pair, first_src, second_src, builtin, instrs, terms) do
    if Enum.any?(terms, &terminator_uses_reg?(&1, pair)) do
      :keep
    else
      uses = Enum.filter(instrs, &instr_references_reg?(&1, pair))

      {allowed, other} =
        Enum.split_with(uses, fn
          %{op: :tuple_proj, args: %{base: ^pair}} -> true
          %{op: :release, args: %{reg: ^pair}} -> true
          %{op: :call_runtime, args: %{builtin: :retain, args: [^pair]}} -> true
          _ -> false
        end)

      if other != [] do
        :keep
      else
        proj_aliases =
          allowed
          |> Enum.filter(&match?(%{op: :tuple_proj}, &1))
          |> Enum.map(fn
            %{dest: dest, args: %{which: :first}} when is_integer(dest) ->
              {dest, if(is_integer(first_src), do: first_src, else: :first)}

            %{dest: dest, args: %{which: :second}} when is_integer(dest) ->
              {dest, if(is_integer(second_src), do: second_src, else: :second)}

            _ ->
              nil
          end)
          |> Enum.reject(&is_nil/1)

        ok? =
          proj_aliases != [] and
            Enum.all?(proj_aliases, fn {proj, _src} ->
              proj_dest_ok?(proj, builtin, instrs, terms)
            end)

        if ok?, do: {:unbox, proj_aliases}, else: :keep
      end
    end
  end

  defp proj_dest_ok?(dest, :tuple2_ints, instrs, terms),
    do: native_only_proj_dest?(dest, instrs, terms)

  defp proj_dest_ok?(dest, :tuple2, instrs, terms),
    do: borrow_only_proj_dest?(dest, instrs, terms) or native_only_proj_dest?(dest, instrs, terms)

  # Strict: only later `call_fn` args or native-int ops — never record fields.
  defp proj_dest_ok?(dest, :list_int_pair_call, instrs, terms),
    do: native_only_proj_dest?(dest, instrs, terms) or call_fn_arg_only_proj_dest?(dest, instrs, terms)

  defp call_fn_arg_only_proj_dest?(dest, instrs, terms) do
    not Enum.any?(terms, &terminator_uses_reg?(&1, dest)) and
      (instrs
       |> Enum.filter(&instr_references_reg?(&1, dest))
       |> Enum.reject(fn
         %{dest: d} when d == dest -> true
         %{op: :release, args: %{reg: r}} when r == dest -> true
         _ -> false
       end)
       |> case do
         [] ->
           false

         uses ->
           Enum.all?(uses, fn
             %{op: :call_fn, args: %{args: args}} when is_list(args) -> dest in args
             other -> native_int_operand_use?(other, dest)
           end)
       end)
  end

  defp native_only_proj_dest?(dest, instrs, terms) do
    not Enum.any?(terms, &terminator_uses_reg?(&1, dest)) and
      (instrs
       |> Enum.filter(&instr_references_reg?(&1, dest))
       |> Enum.reject(fn
         %{dest: d} when d == dest -> true
         %{op: :release, args: %{reg: r}} when r == dest -> true
         _ -> false
       end)
       |> case do
         [] -> false
         uses -> Enum.all?(uses, &native_int_operand_use?(&1, dest))
       end)
  end

  defp borrow_only_proj_dest?(dest, instrs, terms) do
    not Enum.any?(terms, &terminator_uses_reg?(&1, dest)) and
      (instrs
       |> Enum.filter(&instr_references_reg?(&1, dest))
       |> Enum.reject(fn
         %{dest: d} when d == dest -> true
         %{op: :release, args: %{reg: r}} when r == dest -> true
         _ -> false
       end)
       |> case do
         [] ->
           false

         uses ->
           Enum.all?(uses, fn instr ->
             effects = Map.get(instr, :effects) || %{}
             consumes = Map.get(effects, :consumes) || []
             dest not in consumes
           end)
       end)
  end

  defp native_int_operand_use?(%{op: :int_arith, args: args}, reg) do
    Map.get(args, :lhs) == reg or Map.get(args, :rhs) == reg
  end

  defp native_int_operand_use?(%{op: :compare, args: %{left: left, right: right}}, reg) do
    left == reg or right == reg
  end

  defp native_int_operand_use?(%{op: :publish, dest: :fn_out, args: %{source: source}}, reg),
    do: source == reg

  defp native_int_operand_use?(%{op: :call_runtime, args: %{builtin: id, args: args}}, reg)
       when is_list(args) do
    args
    |> Enum.with_index()
    |> Enum.any?(fn
      {^reg, idx} -> RuntimeBuiltins.native_int_arg?(id, idx)
      _ -> false
    end)
  end

  defp native_int_operand_use?(%{op: :record_get_int, args: %{base: base}}, reg), do: base == reg

  defp native_int_operand_use?(_, _), do: false

  defp annotate_native_pair_calls(%Block{instrs: instrs} = block, native_pair_out) do
    instrs =
      Enum.map(instrs, fn
        %{op: :call_fn, dest: dest} = instr when is_integer(dest) ->
          case Map.get(native_pair_out, dest) do
            {first, second} when is_integer(first) and is_integer(second) ->
              instr
              |> put_in([Access.key!(:args), :native_pair_out], {first, second})
              |> Map.update!(:effects, fn
                %{produces: {:owned, ^dest}} = effects -> %{effects | produces: nil}
                effects -> effects
              end)

            _ ->
              instr
          end

        other ->
          other
      end)

    %{block | instrs: instrs}
  end

  defp annotate_native_list_int_pair_calls(%Block{instrs: instrs} = block, list_int_out) do
    instrs =
      Enum.map(instrs, fn
        %{op: :call_fn, dest: dest} = instr when is_integer(dest) ->
          case Map.get(list_int_out, dest) do
            int_reg when is_integer(int_reg) ->
              put_in(instr, [Access.key!(:args), :native_list_int_pair_out], int_reg)

            _ ->
              instr
          end

        other ->
          other
      end)

    %{block | instrs: instrs}
  end

  defp rewrite_block(%Block{instrs: instrs, terminator: term} = block, alias_map, drop_projs, drop_pairs) do
    instrs =
      instrs
      |> Enum.reject(fn
        %{op: :call_runtime, dest: dest, args: %{builtin: builtin}}
        when builtin in [:tuple2_ints, :tuple2] ->
          MapSet.member?(drop_pairs, dest)

        %{op: :tuple_proj, dest: dest} ->
          MapSet.member?(drop_projs, dest)

        %{op: :release, args: %{reg: reg}} ->
          MapSet.member?(drop_projs, reg) or MapSet.member?(drop_pairs, reg)

        %{op: :call_runtime, dest: dest, args: %{builtin: :retain, args: [src]}} ->
          MapSet.member?(drop_pairs, src) or MapSet.member?(drop_projs, src) or
            MapSet.member?(drop_projs, dest) or MapSet.member?(drop_pairs, dest)

        _ ->
          false
      end)
      |> Enum.map(&subst_instr(&1, alias_map))

    %{block | instrs: instrs, terminator: subst_terminator(term, alias_map)}
  end

  defp subst_instr(instr, alias_map) when map_size(alias_map) == 0, do: instr

  defp subst_instr(%{op: :int_arith, args: %{lhs: lhs, rhs: rhs} = args} = instr, alias_map) do
    subst_effects(
      %{instr | args: %{args | lhs: map_reg(alias_map, lhs), rhs: map_reg(alias_map, rhs)}},
      alias_map
    )
  end

  defp subst_instr(%{op: :compare, args: %{left: left, right: right} = args} = instr, alias_map) do
    subst_effects(
      %{instr | args: %{args | left: map_reg(alias_map, left), right: map_reg(alias_map, right)}},
      alias_map
    )
  end

  defp subst_instr(%{op: :call_runtime, args: %{args: args} = call_args} = instr, alias_map)
       when is_list(args) do
    subst_effects(
      %{instr | args: %{call_args | args: Enum.map(args, &map_reg(alias_map, &1))}},
      alias_map
    )
  end

  defp subst_instr(%{op: :call_fn, args: %{args: args} = call_args} = instr, alias_map)
       when is_list(args) do
    subst_effects(
      %{instr | args: %{call_args | args: Enum.map(args, &map_reg(alias_map, &1))}},
      alias_map
    )
  end

  defp subst_instr(%{op: :record_update, args: %{base: base, value: value} = args} = instr, alias_map) do
    subst_effects(
      %{instr | args: %{args | base: map_reg(alias_map, base), value: map_reg(alias_map, value)}},
      alias_map
    )
  end

  defp subst_instr(%{op: :tuple_proj, args: %{base: base} = args} = instr, alias_map) do
    subst_effects(%{instr | args: %{args | base: map_reg(alias_map, base)}}, alias_map)
  end

  defp subst_instr(%{op: :release, args: %{reg: reg} = args} = instr, alias_map) do
    subst_effects(%{instr | args: %{args | reg: map_reg(alias_map, reg)}}, alias_map)
  end

  defp subst_instr(%{op: :publish, args: %{source: source} = args} = instr, alias_map) do
    subst_effects(%{instr | args: %{args | source: map_reg(alias_map, source)}}, alias_map)
  end

  defp subst_instr(instr, alias_map), do: subst_effects(instr, alias_map)

  defp subst_effects(%{effects: effects} = instr, alias_map) when is_map(effects) do
    borrows = Enum.map(effects[:borrows] || [], &map_reg(alias_map, &1))
    consumes = Enum.map(effects[:consumes] || [], &map_reg(alias_map, &1))
    %{instr | effects: %{effects | borrows: borrows, consumes: consumes}}
  end

  defp subst_effects(instr, _), do: instr

  defp map_reg(alias_map, reg) when is_integer(reg), do: Map.get(alias_map, reg, reg)
  defp map_reg(_alias_map, other), do: other

  defp subst_terminator({:br_if, t, e, cond}, alias_map),
    do: {:br_if, t, e, Map.get(alias_map, cond, cond)}

  defp subst_terminator({:switch_tag, subject, arms, default}, alias_map),
    do: {:switch_tag, Map.get(alias_map, subject, subject), arms, default}

  defp subst_terminator({:ret, reg}, alias_map) when is_integer(reg),
    do: {:ret, Map.get(alias_map, reg, reg)}

  defp subst_terminator(term, _), do: term

  defp instr_references_reg?(instr, reg), do: reg in operand_regs(instr)

  defp terminator_uses_reg?({:br_if, _, _, cond}, reg), do: cond == reg
  defp terminator_uses_reg?({:switch_tag, subject, _, _}, reg), do: subject == reg
  defp terminator_uses_reg?({:ret, r}, reg), do: r == reg
  defp terminator_uses_reg?(_, _), do: false

  # Prefer op-specific operand walks before the effects catch-all so field
  # writes / call args are visible even when effects omit a borrow/consume.
  defp operand_regs(%{op: :tuple_proj, args: %{base: base}}) when is_integer(base), do: [base]

  defp operand_regs(%{op: :int_arith, args: %{lhs: lhs, rhs: rhs}}) do
    Enum.filter([lhs, rhs], &is_integer/1)
  end

  defp operand_regs(%{op: :compare, args: %{left: left, right: right}}) do
    Enum.filter([left, right], &is_integer/1)
  end

  defp operand_regs(%{op: :release, args: %{reg: reg}}) when is_integer(reg), do: [reg]

  defp operand_regs(%{op: :record_update, args: %{base: base, value: value}}) do
    Enum.filter([base, value], &is_integer/1)
  end

  defp operand_regs(%{op: :call_fn, args: %{args: args}}) when is_list(args),
    do: Enum.filter(args, &is_integer/1)

  defp operand_regs(%{op: :call_runtime, args: %{builtin: :retain, args: [src]}})
       when is_integer(src),
       do: [src]

  defp operand_regs(%{op: :call_runtime, args: %{args: args}}) when is_list(args),
    do: Enum.filter(args, &is_integer/1)

  defp operand_regs(%{effects: %{borrows: borrows, consumes: consumes}}) do
    ((borrows || []) ++ (consumes || []))
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
  end

  defp operand_regs(_), do: []

  defp sroa_proj_aliases_safe?(proj_aliases, instrs) do
    # After dropping projs, every aliased proj reg must not still appear as a
    # record_update/call_runtime value that we failed to classify as a use.
    drop = MapSet.new(proj_aliases, fn {proj, _} -> proj end)

    not Enum.any?(instrs, fn
      %{op: :record_update, args: %{value: v}} -> MapSet.member?(drop, v)
      %{op: :record_update, args: %{base: b}} -> MapSet.member?(drop, b)
      _ -> false
    end)
  end

  defp max_reg_index(blocks) do
    blocks
    |> Enum.flat_map(fn %Block{instrs: instrs, terminator: term} ->
      dests = Enum.flat_map(instrs, fn %{dest: d} when is_integer(d) -> [d]; _ -> [] end)

      term_regs =
        case term do
          {:ret, r} when is_integer(r) -> [r]
          {:br_if, _, _, cond} when is_integer(cond) -> [cond]
          {:switch_tag, subject, _, _} when is_integer(subject) -> [subject]
          _ -> []
        end

      dests ++ term_regs
    end)
    |> case do
      [] -> -1
      regs -> Enum.max(regs)
    end
  end
end
