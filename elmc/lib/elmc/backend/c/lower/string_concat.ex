defmodule Elmc.Backend.C.Lower.StringConcat do
  @moduledoc false

  alias Elmc.Backend.C.Lower.Instr
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @buf_size 96

  @spec analyze(FunctionPlan.t(), keyword()) :: %{
          roots: %{non_neg_integer() => [segment()]},
          skip_regs: MapSet.t()
        }
  def analyze(%FunctionPlan{} = plan, opts) do
    _operand_regs = append_operand_regs(plan)

    roots =
      plan
      |> append_chain_roots()
      |> Enum.flat_map(fn dest ->
        case classify_chain(plan, dest, opts) do
          {:ok, segments} when length(segments) >= 2 ->
            if fused_buf_size(segments) == :error, do: [], else: [{dest, segments}]

          _ ->
            []
        end
      end)
      |> Map.new()

    skip =
      roots
      |> Map.keys()
      |> Enum.flat_map(&chain_skip_regs(plan, &1))
      |> MapSet.new()

    %{roots: roots, skip_regs: skip}
  end

  @type segment :: {:literal, String.t()} | {:int, String.t()}

  @spec emit([segment()], String.t(), boolean(), keyword()) :: String.t()
  def emit(segments, dest, rc?, _opts) do
    if Enum.all?(segments, &match?({:literal, _}, &1)) do
      emit_literal_concat(segments, dest, rc?)
    else
      emit_snprintf_concat(segments, dest, rc?)
    end
  end

  defp emit_literal_concat(segments, dest, rc?) do
    literal =
      segments
      |> Enum.map(fn {:literal, text} -> text end)
      |> IO.iodata_to_binary()

    escaped = Util.escape_c_string(literal)

    if rc? do
      dest_ref = if String.starts_with?(dest, "*"), do: "out", else: dest
      ptr = if String.starts_with?(dest, "owned["), do: "&#{dest}", else: "&#{dest_ref}"
      "Rc = elmc_new_string(#{ptr}, \"#{escaped}\");\nCHECK_RC(Rc);"
    else
      "#{dest} = elmc_new_string_take(\"#{escaped}\");"
    end
    |> String.trim()
  end

  defp emit_snprintf_concat(segments, dest, rc?) do
    buf_size = fused_buf_size(segments)
    id = System.unique_integer([:positive])
    buffer = "native_string_buf_#{id}"
    format = fused_format(segments)

    args_line =
      segments
      |> Enum.flat_map(fn
        {:literal, _} -> []
        {:int, ref} -> ["(long long)(#{ref})"]
      end)
      |> Enum.join(", ")

    snprintf =
      if args_line == "" do
        "snprintf(#{buffer}, sizeof(#{buffer}), #{format});"
      else
        "snprintf(#{buffer}, sizeof(#{buffer}), #{format}, #{args_line});"
      end

    assign =
      if rc? do
        dest_ref = if String.starts_with?(dest, "*"), do: "out", else: dest
        ptr = if String.starts_with?(dest, "owned["), do: "&#{dest}", else: "&#{dest_ref}"
        "Rc = elmc_new_string(#{ptr}, #{buffer});\nCHECK_RC(Rc);"
      else
        "#{dest} = elmc_new_string_take(#{buffer});"
      end

    """
    char #{buffer}[#{buf_size}];
    #{snprintf}
    #{assign}
    """
    |> String.trim()
  end

  defp append_operand_regs(%FunctionPlan{} = plan) do
    plan
    |> all_instrs()
    |> Enum.flat_map(fn
      %{op: :call_runtime, args: %{builtin: :string_append, args: [l, r]}} ->
        [l, r]

      _ ->
        []
    end)
    |> Enum.filter(&is_integer/1)
    |> MapSet.new()
  end

  defp append_chain_roots(%FunctionPlan{} = plan) do
    append_instrs =
      plan
      |> all_instrs()
      |> Enum.filter(&match?(%{op: :call_runtime, args: %{builtin: :string_append}}, &1))

    operand_regs =
      append_instrs
      |> Enum.flat_map(fn %{args: %{args: [l, r]}} -> [l, r] end)
      |> Enum.filter(&is_integer/1)
      |> MapSet.new()

    append_instrs
    |> Enum.map(& &1.dest)
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(operand_regs, &1))
  end

  defp classify_chain(plan, reg, opts) do
    case defining_instr(plan, reg) do
      %{op: :call_runtime, args: %{builtin: :string_append, args: [left, right]}} ->
        with {:ok, left_segs} <- classify_chain(plan, left, opts),
             {:ok, right_seg} <- classify_segment(plan, right, opts) do
          {:ok, left_segs ++ [right_seg]}
        end

      _ ->
        case classify_segment(plan, reg, opts) do
          {:ok, seg} -> {:ok, [seg]}
          :error -> :error
        end
    end
  end

  defp classify_segment(plan, reg, opts) do
    case defining_instr(plan, reg) do
      %{op: :const_immortal_string, args: %{value: value}} ->
        {:ok, {:literal, value}}

      %{op: :call_runtime, args: %{builtin: :string_from_int, args: [int_reg]}} ->
        classify_int_operand(plan, int_reg, opts)

      %{op: :call_runtime, args: %{builtin: :new_string, args: [str_reg]}} ->
        classify_segment(plan, str_reg, opts)

      _ ->
        :error
    end
  end

  defp classify_int_operand(plan, reg, opts) when is_integer(reg) do
    case int_operand_inline_expr(plan, reg, opts) do
      {:ok, expr} ->
        {:ok, {:int, expr}}

      :error ->
        if MapSet.member?(Keyword.get(opts, :native_int_only_regs, MapSet.new()), reg) do
          {:ok, {:int, Instr.int_operand_ref(reg, Keyword.get(opts, :slots, %{}), opts)}}
        else
          :error
        end
    end
  end

  defp     int_operand_inline_expr(plan, reg, opts) when is_integer(reg) do

    case defining_instr(plan, reg) do
      %{op: :record_get_int, args: args} ->
        {:ok, record_get_int_expr(args, opts)}

      %{op: :const_int, args: %{value: value}} ->
        {:ok, Integer.to_string(value)}

      %{op: :call_runtime, args: %{builtin: :new_int, args: [inner]}} when is_integer(inner) ->
        int_operand_inline_expr(plan, inner, opts)

      %{op: :int_arith, args: args} ->
        case int_arith_c_expr(args, plan, opts) do
          nil -> :error
          expr -> {:ok, expr}
        end

      %{op: :call_runtime, args: %{builtin: :new_int, literal: value}} when is_integer(value) ->
        {:ok, Integer.to_string(value)}

      %{op: :call_runtime, args: %{builtin: :new_int, c_expr: expr}} when is_binary(expr) ->
        {:ok, expr}

      _ ->
        :error
    end
  end

  defp int_arith_c_expr(%{kind: kind, lhs: lhs, rhs: rhs}, plan, opts)
       when kind in [:add_vars, :sub_vars, :mul_vars, :idiv_vars, :min_vars, :max_vars] do
    with {:ok, {:int, l}} <- classify_int_operand(plan, lhs, opts),
         {:ok, {:int, r}} <- classify_int_operand(plan, rhs, opts) do
      op =
        case kind do
          :add_vars -> "+"
          :sub_vars -> "-"
          :mul_vars -> "*"
          :idiv_vars -> "/"
          :min_vars -> "min"
          :max_vars -> "max"
        end

      if kind in [:min_vars, :max_vars] do
        "(#{l} <= #{r}) ? #{l} : #{r}"
      else
        if kind == :idiv_vars, do: "(#{r} == 0 ? 0 : #{l} / #{r})", else: "(#{l} #{op} #{r})"
      end
    else
      _ -> nil
    end
  end

  defp int_arith_c_expr(%{kind: :add_const, lhs: lhs, value: value}, plan, opts) do
    with {:ok, {:int, l}} <- classify_int_operand(plan, lhs, opts) do
      "#{l} + #{value}"
    else
      _ -> nil
    end
  end

  defp int_arith_c_expr(%{kind: :sub_const, lhs: lhs, value: value}, plan, opts) do
    with {:ok, {:int, l}} <- classify_int_operand(plan, lhs, opts) do
      "#{l} - #{value}"
    else
      _ -> nil
    end
  end

  defp int_arith_c_expr(_, _, _), do: nil

  defp record_get_int_expr(args, opts) do
    slots = Keyword.get(opts, :slots, %{})
    base = slot_ref(Map.fetch!(args, :base), slots, opts)
    field = Map.fetch!(args, :field)
    index = Map.get(args, :field_index, "0")
    index_s = record_get_index_ref(field, index)
    "ELMC_RECORD_GET_INDEX_INT(#{base}, #{index_s})"
  end

  defp slot_ref(reg, slots, opts) when is_integer(reg) do
    case Map.get(Keyword.get(opts, :borrow_param_regs, %{}), reg) do
      c_arg when is_binary(c_arg) ->
        c_arg

      _ ->
        case Map.get(slots, reg) do
          i when is_integer(i) -> "owned[#{i}]"
          nil -> "arg#{reg}"
          _ -> "tmp_#{reg}"
        end
    end
  end

  defp record_get_index_ref(field, index) when is_binary(field) and is_binary(index) do
    case Integer.parse(index) do
      {_, ""} -> "#{index} /* #{Util.escape_c_comment(field)} */"
      _ -> index
    end
  end

  defp fused_format(segments) do
    segments
    |> Enum.map_join("", fn
      {:literal, text} -> escape_snprintf_literal(text)
      {:int, _} -> "%lld"
    end)
    |> then(&"\"#{&1}\"")
  end

  defp fused_buf_size(segments) do
    size =
      segments
      |> Enum.map(fn
        {:literal, text} -> byte_size(text)
        {:int, _} -> 21
      end)
      |> Enum.sum()

    if size > @buf_size, do: :error, else: size
  end

  defp escape_snprintf_literal(""), do: ""

  defp escape_snprintf_literal(literal) do
    literal
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("%", "%%")
    |> String.replace("\n", "\\n")
  end

  defp chain_skip_regs(plan, root) do
    collect_chain_regs(plan, root) |> List.delete(root)
  end

  defp collect_chain_regs(plan, reg) do
    case defining_instr(plan, reg) do
      %{op: :call_runtime, args: %{builtin: :string_append, args: [left, right]}} ->
        collect_chain_regs(plan, left) ++ collect_chain_regs(plan, right) ++ [reg]

      %{op: :call_runtime, args: %{builtin: :string_from_int, args: [int_reg]}} ->
        [reg, int_reg]

      %{op: :const_immortal_string} ->
        [reg]

      _ ->
        [reg]
    end
  end

  defp all_instrs(%FunctionPlan{blocks: blocks}) do
    Enum.flat_map(blocks, & &1.instrs)
  end

  defp defining_instr(%FunctionPlan{blocks: blocks}, reg) when is_integer(reg) do
    Enum.find_value(blocks, fn %{instrs: instrs} ->
      Enum.find(instrs, fn
        %{dest: ^reg} = instr -> instr
        _ -> nil
      end)
    end)
  end
end
