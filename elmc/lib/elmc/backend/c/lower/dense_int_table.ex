defmodule Elmc.Backend.C.Lower.DenseIntTable do
  @moduledoc false

  # Native `Int` / `(Int, Int)` switches already lower to a const LUT.
  # The boxed path covers the same IR shape when the result is a boxed int:
  # Color palette codes (`ELMC_COLOR_*`), nullary enum tags, or a single
  # passthrough parameter. That is the `caseColor` / theme-map pattern.

  alias Elmc.Backend.C.Lower.{Instr, TagRefs}
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @min_arms 8
  @max_span 256

  @type pair :: {integer(), integer()}
  @type width :: 1 | 2
  @type cell :: {:const, String.t()} | {:alias, String.t()}

  @spec emit_body(FunctionPlan.t()) :: {:ok, String.t()} | :error
  def emit_body(%FunctionPlan{} = plan) do
    case extract(plan) do
      {:ok, table} -> {:ok, emit_table(plan, table)}
      :error -> :error
    end
  end

  # Shared by boxed scalar LUTs and const-record tables (`fontInfo`-style helpers).
  @spec match_switch(FunctionPlan.t()) :: {:ok, map()} | :error
  def match_switch(%FunctionPlan{} = plan) do
    with {:ok, switch_block, subject_reg, arms, default_id} <- unique_int_switch(plan),
         true <- prelude_ok?(switch_block),
         true <- table_blocks_only?(plan, switch_block.id, arms, default_id),
         {:ok, subject_c} <- switch_subject_c(plan, subject_reg, arms) do
      {:ok,
       %{
         switch_block: switch_block,
         subject: subject_c,
         arms: arms,
         default_id: default_id
       }}
    else
      _ -> :error
    end
  end

  @spec extract(FunctionPlan.t()) ::
          {:ok, map()} | :error
  def extract(%FunctionPlan{native_scalar_return: kind} = plan)
      when kind in [:native_int, :native_int_pair] do
    width = if kind == :native_int_pair, do: 2, else: 1

    with {:ok, switch_block, subject_reg, arms, default_id} <- unique_int_switch(plan),
         true <- prelude_ok?(switch_block),
         true <- table_blocks_only?(plan, switch_block.id, arms, default_id),
         {:ok, subject_c} <- native_int_c(plan, subject_reg),
         {:ok, rows} <- dense_rows(plan, subject_reg, arms, default_id, width) do
      in_range? = modulus(plan, subject_reg) == length(rows)

      {:ok,
       %{
         kind: :native,
         subject: subject_c,
         rows: rows,
         width: width,
         in_range?: in_range?
       }}
    else
      _ -> :error
    end
  end

  def extract(%FunctionPlan{} = plan) do
    with {:ok, switch_block, subject_reg, arms, default_id} <- unique_int_switch(plan),
         true <- prelude_ok?(switch_block),
         true <- table_blocks_only?(plan, switch_block.id, arms, default_id),
         {:ok, subject_c} <- switch_subject_c(plan, subject_reg, arms),
         {:ok, table} <- boxed_rows(plan, arms, default_id) do
      {:ok,
       Map.merge(table, %{
         kind: :boxed,
         subject: subject_c,
         width: 1,
         rc?: plan.rc_required == true
       })}
    else
      _ -> :error
    end
  end

  defp unique_int_switch(%FunctionPlan{blocks: blocks}) do
    switches =
      Enum.flat_map(blocks, fn
        %Block{id: id, terminator: {:switch_tag, subject, arms, default_id}}
        when is_integer(subject) and is_list(arms) and is_integer(default_id) ->
          [{id, subject, arms, default_id}]

        _ ->
          []
      end)

    case switches do
      [{id, subject, arms, default_id}] ->
        case Enum.find(blocks, &(&1.id == id)) do
          %Block{} = block -> {:ok, block, subject, arms, default_id}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp prelude_ok?(%Block{instrs: instrs}) do
    Enum.all?(instrs, &prelude_instr?/1)
  end

  defp prelude_instr?(%{op: op})
       when op in [:const_int, :const_c_expr, :load_param, :int_arith, :boxed_tag_peel],
       do: true

  defp prelude_instr?(_), do: false

  defp table_blocks_only?(plan, switch_id, arms, default_id) do
    arm_ids =
      arms
      |> Enum.map(&TagRefs.switch_arm_target/1)
      |> Enum.reject(&is_nil/1)

    allowed = MapSet.new([switch_id, default_id | arm_ids])

    Enum.all?(plan.blocks, fn %Block{id: id} = block ->
      MapSet.member?(allowed, id) or empty_exit_block?(block) or merge_passthrough_block?(block)
    end)
  end

  defp empty_exit_block?(%Block{instrs: instrs, terminator: term}) do
    publish_only?(instrs) and (match?({:ret, _}, term) or match?({:br, _}, term))
  end

  # Wildcard defaults keep a separate merge that only retains the arm result.
  defp merge_passthrough_block?(%Block{instrs: instrs, terminator: term}) do
    exit_term?(term) and
      Enum.all?(instrs, fn
        %{op: :publish} -> true
        %{op: :call_runtime, args: %{builtin: :retain}} -> true
        _ -> false
      end)
  end

  defp publish_only?(instrs) do
    Enum.all?(instrs, fn
      %{op: :publish} -> true
      _ -> false
    end)
  end

  defp modulus(plan, reg) do
    case defining_instr(plan, reg) do
      %{op: :int_arith, args: %{kind: :mod_vars, lhs: base}} ->
        case const_int_value(plan, base) do
          {:ok, mod} when is_integer(mod) and mod > 0 and mod <= @max_span -> mod
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp dense_rows(plan, subject_reg, arms, default_id, width) do
    tagged =
      Enum.reduce_while(arms, [], fn arm, acc ->
        tag = TagRefs.switch_arm_tag(arm)
        target = TagRefs.switch_arm_target(arm)

        with true <- is_integer(tag) and tag >= 0,
             {:ok, value} <- block_const_result(plan, target, width) do
          {:cont, [{tag, value} | acc]}
        else
          _ -> {:halt, :error}
        end
      end)

    with rows when is_list(rows) <- tagged,
         {:ok, default} <- optional_default(plan, default_id, width),
         {:ok, filled} <- fill_dense(rows, default, modulus(plan, subject_reg)) do
      {:ok, filled}
    else
      _ -> :error
    end
  end

  defp optional_default(plan, default_id, width) do
    case block_const_result(plan, default_id, width) do
      {:ok, value} -> {:ok, value}
      :error -> {:ok, nil}
    end
  end

  defp fill_dense(rows, default, modulus) do
    by_tag = Map.new(rows)
    tags = Map.keys(by_tag)
    min = if tags == [], do: nil, else: Enum.min(tags)
    max = if tags == [], do: nil, else: Enum.max(tags)

    span =
      cond do
        is_integer(modulus) and is_integer(max) and modulus >= max + 1 -> modulus
        is_integer(max) -> max + 1
        true -> 0
      end

    cond do
      length(tags) < @min_arms ->
        :error

      min != 0 ->
        :error

      span < 1 or span > @max_span ->
        :error

      default == nil and map_size(by_tag) != span ->
        :error

      true ->
        filled =
          Enum.map(0..(span - 1), fn i ->
            case Map.fetch(by_tag, i) do
              {:ok, value} -> value
              :error -> default
            end
          end)

        if Enum.any?(filled, &is_nil/1), do: :error, else: {:ok, filled}
    end
  end

  defp boxed_rows(plan, arms, default_id) do
    tagged =
      Enum.reduce_while(arms, [], fn arm, acc ->
        tag = TagRefs.switch_arm_tag(arm)
        target = TagRefs.switch_arm_target(arm)

        with true <- is_integer(tag) and tag >= 0,
             {:ok, cell} <- block_boxed_cell(plan, target) do
          {:cont, [{tag, cell} | acc]}
        else
          _ -> {:halt, :error}
        end
      end)

    with rows when is_list(rows) <- tagged,
         {:ok, default} <- optional_boxed_default(plan, default_id, rows),
         true <- alias_consistent?(rows, default),
         {:ok, table} <- fill_boxed(rows, default) do
      {:ok, table}
    else
      _ -> :error
    end
  end

  defp optional_boxed_default(plan, default_id, rows) do
    case block_boxed_cell(plan, default_id) do
      {:ok, cell} ->
        {:ok, cell}

      :error ->
        case last_const_cell(rows) do
          {:ok, cell} -> {:ok, cell}
          :error -> {:ok, nil}
        end
    end
  end

  defp last_const_cell(rows) do
    rows
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reverse()
    |> Enum.find_value(fn
      {_tag, {:const, _} = cell} -> {:ok, cell}
      _ -> nil
    end)
    |> case do
      {:ok, cell} -> {:ok, cell}
      nil -> :error
    end
  end

  defp alias_consistent?(rows, default) do
    names =
      (Enum.map(rows, fn {_tag, cell} -> cell end) ++ List.wrap(default))
      |> Enum.flat_map(fn
        {:alias, name} -> [name]
        _ -> []
      end)
      |> Enum.uniq()

    length(names) <= 1
  end

  defp fill_boxed(rows, default) do
    by_tag = Map.new(rows)
    tags = Map.keys(by_tag)

    cond do
      tags == [] or length(tags) < @min_arms ->
        :error

      true ->
        min = Enum.min(tags)
        max = Enum.max(tags)
        span = max - min + 1

        cond do
          span < 1 or span > @max_span ->
            :error

          default == nil and map_size(by_tag) != span ->
            :error

          true ->
            filled =
              Enum.map(min..max, fn i ->
                case Map.fetch(by_tag, i) do
                  {:ok, cell} -> cell
                  :error -> default
                end
              end)

            if Enum.any?(filled, &is_nil/1) do
              :error
            else
              {:ok, %{min: min, rows: filled, default: default}}
            end
        end
    end
  end

  defp block_const_result(plan, block_id, width) do
    case Enum.find(plan.blocks, &(&1.id == block_id)) do
      %Block{instrs: [], terminator: {:br, next}} ->
        block_const_result(plan, next, width)

      %Block{instrs: [], terminator: {:ret, _}} ->
        :error

      %Block{instrs: instrs, terminator: term} ->
        if exit_term?(term) do
          instrs_const_result(plan, instrs, width)
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp block_boxed_cell(plan, block_id) do
    case Enum.find(plan.blocks, &(&1.id == block_id)) do
      %Block{instrs: [], terminator: {:br, next}} ->
        block_boxed_cell(plan, next)

      %Block{instrs: [], terminator: {:ret, _}} ->
        :error

      %Block{instrs: instrs, terminator: term} ->
        if exit_term?(term) do
          instrs_boxed_cell(plan, instrs)
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp exit_term?({:ret, _}), do: true
  defp exit_term?({:br, _}), do: true
  defp exit_term?(_), do: false

  defp instrs_const_result(plan, instrs, 2) do
    case List.last(pair_result_instrs(instrs)) do
      %{op: :call_runtime, args: %{builtin: builtin, args: [left, right]}}
      when builtin in [:tuple2, :tuple2_ints] ->
        with {:ok, a} <- const_int_value(plan, left),
             {:ok, b} <- const_int_value(plan, right) do
          {:ok, {a, b}}
        end

      _ ->
        :error
    end
  end

  defp instrs_const_result(plan, instrs, 1) do
    case List.last(scalar_result_instrs(instrs)) do
      %{op: :const_int, dest: dest} when is_integer(dest) ->
        const_int_value(plan, dest)

      %{dest: dest} when is_integer(dest) ->
        const_int_value(plan, dest)

      _ ->
        case Enum.reverse(instrs) do
          [%{op: :const_int, dest: dest} | _] -> const_int_value(plan, dest)
          _ -> :error
        end
    end
  end

  defp instrs_boxed_cell(plan, instrs) do
    case result_reg_from_instrs(instrs) do
      {:ok, reg} -> cell_from_local_or_plan(plan, instrs, reg)
      :error -> :error
    end
  end

  defp result_reg_from_instrs(instrs) do
    case List.last(instrs) do
      %{op: :call_runtime, args: %{builtin: :retain, args: [src]}} when is_integer(src) ->
        {:ok, src}

      %{op: :publish, args: %{source: src}} when is_integer(src) ->
        {:ok, src}

      %{op: op, dest: dest}
      when op in [:const_int, :const_c_expr, :load_param] and is_integer(dest) ->
        {:ok, dest}

      %{dest: dest} when is_integer(dest) ->
        {:ok, dest}

      _ ->
        :error
    end
  end

  # Arm blocks reuse dest regs. Read the constant from this block first so a
  # later White arm is not reported as the first arm's Black.
  defp cell_from_local_or_plan(plan, instrs, reg) do
    case local_instr(instrs, reg) do
      %{op: :call_runtime, args: %{builtin: :retain, args: [src]}} when is_integer(src) ->
        cell_from_local_or_plan(plan, instrs, src)

      instr when is_map(instr) ->
        cell_from_instr(plan, instr)

      nil ->
        cell_from_reg(plan, reg)
    end
  end

  defp local_instr(instrs, reg) do
    Enum.find(instrs, fn
      %{dest: ^reg} -> true
      _ -> false
    end)
  end

  defp cell_from_reg(plan, reg) when is_integer(reg) do
    case defining_instr(plan, reg) do
      instr when is_map(instr) -> cell_from_instr(plan, instr)
      _ -> :error
    end
  end

  defp cell_from_instr(plan, instr) do
    case instr do
      %{op: :const_int} ->
        case const_int_c_expr(plan, instr) do
          {:ok, expr} -> {:ok, {:const, expr}}
          :error -> :error
        end

      %{op: :const_c_expr, args: %{value: value}} when is_binary(value) and value != "" ->
        {:ok, {:const, value}}

      %{op: :load_param, args: %{index: index}} ->
        case param_c_name(plan, index) do
          {:ok, name} -> {:ok, {:alias, name}}
          :error -> :error
        end

      %{op: :call_runtime, args: %{builtin: :retain, args: [src]}} when is_integer(src) ->
        cell_from_reg(plan, src)

      _ ->
        :error
    end
  end

  defp const_int_c_expr(plan, %{op: :const_int, args: args}) do
    value = Map.get(args, :value)

    cond do
      Map.get(args, :bool_lit) == true ->
        :error

      is_integer(value) ->
        ctor = Map.get(args, :union_ctor)
        {:ok, TagRefs.const_int_ref(value, ctor, plan.module)}

      true ->
        :error
    end
  end

  defp pair_result_instrs(instrs) do
    Enum.filter(instrs, fn
      %{op: :call_runtime, args: %{builtin: builtin}} when builtin in [:tuple2, :tuple2_ints] ->
        true

      _ ->
        false
    end)
  end

  defp scalar_result_instrs(instrs) do
    Enum.reject(instrs, fn
      %{op: op} when op in [:const_int, :load_param] -> true
      _ -> false
    end)
  end

  defp switch_subject_c(plan, subject_reg, arms) do
    union_switch? = Enum.any?(arms, &(is_binary(TagRefs.switch_arm_ctor(&1))))

    case defining_instr(plan, subject_reg) do
      %{op: :boxed_tag_peel, args: %{subject: src}} when is_integer(src) ->
        with {:ok, src_c} <- boxed_subject_operand_c(plan, src) do
          {:ok, "elmc_union_tag_as_int(#{src_c})"}
        end

      %{op: :load_param, args: %{index: index}} ->
        with {:ok, name} <- param_c_name(plan, index) do
          if union_switch? do
            {:ok, "elmc_union_tag_as_int(#{name})"}
          else
            {:ok, name}
          end
        end

      _ ->
        native_int_c(plan, subject_reg)
    end
  end

  defp boxed_subject_operand_c(plan, reg) do
    case defining_instr(plan, reg) do
      %{op: :load_param, args: %{index: index}} -> param_c_name(plan, index)
      _ -> native_int_c(plan, reg)
    end
  end

  defp native_int_c(plan, reg) when is_integer(reg) do
    case defining_instr(plan, reg) do
      %{op: :const_int, args: %{value: value}} when is_integer(value) ->
        {:ok, Integer.to_string(value)}

      %{op: :load_param, args: %{index: index}} ->
        param_c_name(plan, index)

      %{op: :boxed_tag_peel, args: %{subject: src}} when is_integer(src) ->
        with {:ok, src_c} <- boxed_subject_operand_c(plan, src) do
          {:ok, "elmc_union_tag_as_int(#{src_c})"}
        end

      %{op: :int_arith, args: %{kind: :mod_vars, lhs: lhs, rhs: rhs}} ->
        with {:ok, left_c} <- native_int_c(plan, lhs),
             {:ok, right_c} <- native_int_c(plan, rhs) do
          {:ok, Instr.elm_mod_by_c_expr(left_c, right_c)}
        end

      %{op: :int_arith, args: %{kind: :rem_vars, lhs: lhs, rhs: rhs}} ->
        with {:ok, left_c} <- native_int_c(plan, lhs),
             {:ok, right_c} <- native_int_c(plan, rhs) do
          {:ok, "(#{left_c} == 0 ? 0 : #{right_c} % #{left_c})"}
        end

      _ ->
        :error
    end
  end

  defp native_int_c(_plan, _reg), do: :error

  defp const_int_value(plan, reg) when is_integer(reg) do
    case defining_instr(plan, reg) do
      %{op: :const_int, args: %{bool_lit: true}} ->
        :error

      %{op: :const_int, args: %{value: value}} when is_integer(value) ->
        {:ok, value}

      _ ->
        :error
    end
  end

  defp const_int_value(_plan, _reg), do: :error

  defp param_c_name(%FunctionPlan{params: params}, index) when is_list(params) do
    case Enum.at(params, index) do
      %{name: name} when is_binary(name) and name != "" -> {:ok, name}
      _ -> :error
    end
  end

  defp param_c_name(_, _), do: :error

  defp defining_instr(%FunctionPlan{blocks: blocks}, reg) do
    Enum.find_value(blocks, fn %Block{instrs: instrs} ->
      Enum.find(instrs, fn
        %{dest: ^reg} -> true
        _ -> false
      end)
    end)
  end

  defp emit_table(plan, %{kind: :boxed} = table) do
    emit_boxed_table(plan, table)
  end

  defp emit_table(plan, %{subject: subject, rows: rows, width: width, in_range?: in_range?}) do
    lut = lut_name(plan)
    count = length(rows)

    table_def =
      case width do
        2 ->
          cells =
            Enum.map_join(rows, ", ", fn {a, b} -> "{#{a}, #{b}}" end)

          "static const elmc_int_t #{lut}[#{count}][2] = { #{cells} };"

        1 ->
          cells = Enum.map_join(rows, ", ", &Integer.to_string/1)
          "static const elmc_int_t #{lut}[#{count}] = { #{cells} };"
      end

    assigns =
      case width do
        2 ->
          "*out0 = #{lut}[__dense_i][0];\n*out1 = #{lut}[__dense_i][1];"

        1 ->
          "*out = #{lut}[__dense_i];"
      end

    lookup =
      if in_range? do
        """
        elmc_int_t __dense_i = #{subject};
        #{assigns}
        """
      else
        fallback = fallback_assigns(width, List.last(rows), lut)

        """
        elmc_int_t __dense_i = #{subject};
        if ((uint32_t)__dense_i >= #{count}u) {
          #{fallback}
        } else {
          #{assigns}
        }
        """
      end

    String.trim("""
    #{table_def}
    #{lookup}
    """)
  end

  defp emit_boxed_table(plan, %{subject: subject, min: min, rows: rows, default: default} = table) do
    rc? = Map.get(table, :rc?, true)
    lut = lut_name(plan)
    count = length(rows)
    max = min + count - 1

    lut_cells =
      Enum.map_join(rows, ", ", fn
        {:const, expr} -> expr
        {:alias, _} -> "0"
      end)

    alias_tags =
      rows
      |> Enum.with_index(min)
      |> Enum.flat_map(fn
        {{:alias, _}, tag} -> [tag]
        _ -> []
      end)

    table_def = "static const elmc_int_t #{lut}[#{count}] = { #{lut_cells} };"
    index_expr = if min == 0, do: "__dense_i", else: "__dense_i - #{min}"

    oob =
      if min == 0 do
        "(uint32_t)__dense_i >= #{count}u"
      else
        "(uint32_t)__dense_i < #{min}u || (uint32_t)__dense_i > #{max}u"
      end

    dest = if rc?, do: "out", else: "&__dense_out"
    assign = if rc?, do: "*out", else: "__dense_out"
    default_stmt = boxed_cell_stmt(default || List.last(rows), dest, assign, rc?)
    const_stmt = boxed_const_lookup_stmt(lut, index_expr, dest, rc?)

    lookup =
      case alias_tags do
        [] ->
          """
          elmc_int_t __dense_i = #{subject};
          if (#{oob}) {
            #{default_stmt}
          } else {
            #{const_stmt}
          }
          """

        tags ->
          alias_name = alias_name!(rows, default)
          alias_cond = Enum.map_join(tags, " || ", fn tag -> "__dense_i == #{tag}" end)

          """
          elmc_int_t __dense_i = #{subject};
          if (#{oob}) {
            #{default_stmt}
          } else if (#{alias_cond}) {
            #{assign} = elmc_retain(#{alias_name});
          } else {
            #{const_stmt}
          }
          """
      end

    body =
      if rc? do
        lookup
      else
        "ElmcValue *__dense_out = NULL;\n#{lookup}\nreturn __dense_out;"
      end

    String.trim("""
    #{table_def}
    #{body}
    """)
  end

  defp alias_name!(rows, default) do
    (rows ++ List.wrap(default))
    |> Enum.find_value(fn
      {:alias, name} -> name
      _ -> nil
    end)
  end

  defp boxed_const_lookup_stmt(lut, index_expr, dest, true) do
    "Rc = elmc_new_int(#{dest}, #{lut}[#{index_expr}]);\nCHECK_RC(Rc);"
  end

  defp boxed_const_lookup_stmt(lut, index_expr, dest, false) do
    "(void)elmc_new_int(#{dest}, #{lut}[#{index_expr}]);"
  end

  defp boxed_cell_stmt({:const, expr}, dest, _assign, true) do
    "Rc = elmc_new_int(#{dest}, #{expr});\nCHECK_RC(Rc);"
  end

  defp boxed_cell_stmt({:const, expr}, dest, _assign, false) do
    "(void)elmc_new_int(#{dest}, #{expr});"
  end

  defp boxed_cell_stmt({:alias, name}, _dest, assign, _rc?) do
    "#{assign} = elmc_retain(#{name});"
  end

  defp boxed_cell_stmt(_, _dest, _assign, true), do: "Rc = RC_ERR_UNSUPPORTED;"
  defp boxed_cell_stmt(_, _dest, _assign, false), do: "__dense_out = NULL;"

  defp fallback_assigns(2, {a, b}, _lut) do
    "*out0 = #{a};\n  *out1 = #{b};"
  end

  defp fallback_assigns(1, value, _lut) when is_integer(value) do
    "*out = #{value};"
  end

  defp lut_name(%FunctionPlan{module: module, name: name}) do
    "elmc_dense_lut_#{Util.safe_c_suffix(module)}_#{Util.safe_c_suffix(name)}"
  end
end
