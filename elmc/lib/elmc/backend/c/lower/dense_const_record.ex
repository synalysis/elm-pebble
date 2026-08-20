defmodule Elmc.Backend.C.Lower.DenseConstRecord do
  @moduledoc false

  # Enum `case` that returns a record of compile-time ints/strings
  # (`fontInfo`, `staticBitmapInfo`, similar `*Info` helpers). One LUT +
  # one `record_new_values_take` instead of a near-copy of the record
  # constructor on every arm.

  alias Elmc.Backend.C.Lower.{DenseIntTable, TagRefs}
  alias Elmc.Backend.CCodegen.{ImmortalStringLiteral, Util}
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @min_arms 3
  @max_span 256
  @max_fields 8

  @type field :: {:int, String.t()} | {:string, String.t()}

  @spec emit_body(FunctionPlan.t()) :: {:ok, String.t()} | :error
  def emit_body(%FunctionPlan{} = plan) do
    case extract(plan) do
      {:ok, table} -> {:ok, emit_table(plan, table)}
      :error -> :error
    end
  end

  @spec extract(FunctionPlan.t()) :: {:ok, map()} | :error
  def extract(%FunctionPlan{} = plan) do
    with {:ok, switch} <- DenseIntTable.match_switch(plan),
         {:ok, table} <- dense_rows(plan, switch.arms, switch.default_id) do
      {:ok,
       Map.merge(table, %{
         subject: switch.subject,
         rc?: plan.rc_required == true
       })}
    else
      _ -> :error
    end
  end

  defp dense_rows(plan, arms, default_id) do
    tagged =
      Enum.reduce_while(arms, [], fn arm, acc ->
        tag = TagRefs.switch_arm_tag(arm)
        target = TagRefs.switch_arm_target(arm)

        with true <- is_integer(tag) and tag >= 0,
             {:ok, fields} <- block_record_fields(plan, target) do
          {:cont, [{tag, fields} | acc]}
        else
          _ -> {:halt, :error}
        end
      end)

    with rows when is_list(rows) <- tagged,
         {:ok, default} <- optional_default(plan, default_id, rows),
         true <- schema_ok?(rows, default),
         {:ok, table} <- fill_dense(rows, default) do
      {:ok, table}
    else
      _ -> :error
    end
  end

  defp optional_default(plan, default_id, rows) do
    case block_record_fields(plan, default_id) do
      {:ok, fields} ->
        {:ok, fields}

      :error ->
        case List.last(Enum.sort_by(rows, &elem(&1, 0))) do
          {_tag, fields} -> {:ok, fields}
          _ -> {:ok, nil}
        end
    end
  end

  defp schema_ok?(rows, default) do
    schemas =
      (Enum.map(rows, fn {_tag, fields} -> field_kinds(fields) end) ++
         if(is_list(default), do: [field_kinds(default)], else: []))
      |> Enum.uniq()

    case schemas do
      [kinds] when is_list(kinds) and kinds != [] and length(kinds) <= @max_fields ->
        true

      _ ->
        false
    end
  end

  defp field_kinds(fields) when is_list(fields) do
    Enum.map(fields, fn
      {:int, _} -> :int
      {:string, _} -> :string
    end)
  end

  defp fill_dense(rows, default) do
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
                  {:ok, fields} -> fields
                  :error -> default
                end
              end)

            if Enum.any?(filled, &is_nil/1) do
              :error
            else
              {:ok, %{min: min, rows: filled, default: default || List.last(filled)}}
            end
        end
    end
  end

  defp block_record_fields(plan, block_id) do
    case Enum.find(plan.blocks, &(&1.id == block_id)) do
      %Block{instrs: [], terminator: {:br, next}} ->
        block_record_fields(plan, next)

      %Block{instrs: [], terminator: {:ret, _}} ->
        :error

      %Block{instrs: instrs, terminator: term} ->
        if exit_term?(term) and Enum.all?(instrs, &const_record_instr?/1) do
          instrs_record_fields(plan, instrs)
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

  defp const_record_instr?(%{op: op})
       when op in [:const_int, :const_c_expr, :const_immortal_string, :publish],
       do: true

  defp const_record_instr?(%{op: :call_runtime, args: %{builtin: builtin}})
       when builtin in [:retain, :record_new, :record_new_take, :record_new_values_ints],
       do: true

  defp const_record_instr?(_), do: false

  defp instrs_record_fields(plan, instrs) do
    case record_new_instr(instrs) do
      %{args: %{args: field_regs}} when is_list(field_regs) and field_regs != [] ->
        field_regs
        |> Enum.reduce_while([], fn reg, acc ->
          case field_from_local(plan, instrs, reg) do
            {:ok, field} -> {:cont, [field | acc]}
            :error -> {:halt, :error}
          end
        end)
        |> case do
          list when is_list(list) -> {:ok, Enum.reverse(list)}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  defp record_new_instr(instrs) do
    Enum.find(instrs, fn
      %{op: :call_runtime, args: %{builtin: builtin}}
      when builtin in [:record_new, :record_new_take, :record_new_values_ints] ->
        true

      _ ->
        false
    end)
  end

  defp field_from_local(plan, instrs, reg) do
    case local_instr(instrs, reg) do
      %{op: :call_runtime, args: %{builtin: :retain, args: [src]}} when is_integer(src) ->
        field_from_local(plan, instrs, src)

      instr when is_map(instr) ->
        field_from_instr(plan, instr)

      nil ->
        field_from_plan(plan, reg)
    end
  end

  defp local_instr(instrs, reg) do
    Enum.find(instrs, fn
      %{dest: ^reg} -> true
      _ -> false
    end)
  end

  defp field_from_plan(plan, reg) when is_integer(reg) do
    plan.blocks
    |> Enum.find_value(fn %Block{instrs: instrs} ->
      Enum.find(instrs, fn
        %{dest: ^reg} -> true
        _ -> false
      end)
    end)
    |> case do
      instr when is_map(instr) -> field_from_instr(plan, instr)
      _ -> :error
    end
  end

  defp field_from_plan(_plan, _reg), do: :error

  defp field_from_instr(plan, instr) do
    case instr do
      %{op: :const_int} ->
        case const_int_c_expr(plan, instr) do
          {:ok, expr} -> {:ok, {:int, expr}}
          :error -> :error
        end

      %{op: :const_c_expr, args: %{value: value}} when is_binary(value) and value != "" ->
        {:ok, {:int, value}}

      %{op: :const_immortal_string, args: %{value: value}} when is_binary(value) ->
        {:ok, {:string, value}}

      %{op: :call_runtime, args: %{builtin: :retain, args: [src]}} when is_integer(src) ->
        field_from_plan(plan, src)

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
        {:ok, TagRefs.const_int_ref(value, Map.get(args, :union_ctor), plan.module)}

      true ->
        :error
    end
  end

  defp emit_table(plan, %{subject: subject, min: min, rows: rows, default: default} = table) do
    rc? = Map.get(table, :rc?, true)
    prefix = lut_prefix(plan)
    count = length(rows)
    max = min + count - 1
    kinds = field_kinds(hd(rows))

    decls =
      0..(length(kinds) - 1)
      |> Enum.map(&field_lut_decl(prefix, &1, rows))
      |> Enum.join("\n")

    default_index =
      rows
      |> Enum.find_index(&(&1 == default))
      |> Kernel.||(count - 1)

    oob =
      if min == 0 do
        "(uint32_t)__dense_i >= #{count}u"
      else
        "(uint32_t)__dense_i < #{min}u || (uint32_t)__dense_i > #{max}u"
      end

    dest = if rc?, do: "out", else: "&__dense_out"
    build_lut = build_record_stmt(prefix, kinds, "__dense_j", dest, rc?)

    lookup = """
    elmc_int_t __dense_i = #{subject};
    elmc_int_t __dense_j = #{if min == 0, do: "__dense_i", else: "__dense_i - #{min}"};
    if (#{oob}) {
      __dense_j = #{default_index};
    }
    #{build_lut}
    """

    body =
      if rc? do
        lookup
      else
        "ElmcValue *__dense_out = NULL;\n#{lookup}\nreturn __dense_out;"
      end

    String.trim("""
    #{decls}
    #{body}
    """)
  end

  defp field_lut_decl(prefix, index, rows) do
    name = "#{prefix}_f#{index}"

    case Enum.map(rows, &Enum.at(&1, index)) do
      [{:int, _} | _] = cells ->
        values = Enum.map_join(cells, ", ", fn {:int, expr} -> expr end)
        "static const elmc_int_t #{name}[#{length(cells)}] = { #{values} };"

      [{:string, _} | _] = cells ->
        ImmortalStringLiteral.array_decl(name, Enum.map(cells, fn {:string, value} -> value end))
    end
  end

  defp build_record_stmt(prefix, kinds, index_expr, dest, rc?) do
    field_count = length(kinds)

    assigns =
      kinds
      |> Enum.with_index()
      |> Enum.map(fn {kind, index} ->
        field_assign(kind, prefix, index, "[#{index_expr}]", rc?)
      end)
      |> Enum.join("\n")

    take = record_take_stmt(dest, field_count, rc?)

    """
    ElmcValue *__dense_fields[#{field_count}] = {0};
    #{assigns}
    #{take}
    """
    |> String.trim()
  end

  defp field_assign(:int, prefix, index, subscript, true) do
    "Rc = elmc_new_int(&__dense_fields[#{index}], #{prefix}_f#{index}#{subscript});\nCHECK_RC(Rc);"
  end

  defp field_assign(:int, prefix, index, subscript, false) do
    "(void)elmc_new_int(&__dense_fields[#{index}], #{prefix}_f#{index}#{subscript});"
  end

  defp field_assign(:string, prefix, index, subscript, _rc?) do
    "__dense_fields[#{index}] = elmc_retain(&#{prefix}_f#{index}#{subscript});"
  end

  defp lut_prefix(%FunctionPlan{module: module, name: name}) do
    "elmc_dense_rec_#{Util.safe_c_suffix(module)}_#{Util.safe_c_suffix(name)}"
  end

  defp record_take_stmt(dest, field_count, true) do
    "Rc = elmc_record_new_values_take(#{dest}, #{field_count}, __dense_fields);\nCHECK_RC(Rc);"
  end

  defp record_take_stmt(dest, field_count, false) do
    "(void)elmc_record_new_values_take(#{dest}, #{field_count}, __dense_fields);"
  end
end
