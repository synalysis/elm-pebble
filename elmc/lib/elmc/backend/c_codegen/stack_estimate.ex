defmodule Elmc.Backend.CCodegen.StackEstimate do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Util

  @risk_runtime_calls %{
    "elmc_list_all" => :list_hof_runtime,
    "elmc_list_any" => :list_hof_runtime,
    "elmc_list_map" => :list_hof_runtime,
    "elmc_list_filter" => :list_hof_runtime,
    "elmc_list_filter_map" => :list_hof_runtime,
    "elmc_list_drop" => :list_drop
  }

  @spec report(ElmEx.IR.t(), String.t()) :: map()
  def report(ir, c_source) do
    ir_entries = ir_entries(ir)
    c_entries = c_entries(c_source)

    entries =
      (Map.keys(ir_entries) ++ Map.keys(c_entries))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn name ->
        ir_entry = Map.get(ir_entries, name, base_entry(name))
        c_entry = Map.get(c_entries, name, %{})
        score = Map.get(ir_entry, :score, 0) + Map.get(c_entry, :score, 0)

        ir_entry
        |> Map.merge(c_entry)
        |> Map.put(:function, name)
        |> Map.put(:score, score)
        |> adjust_fused_ir_entry(name, c_source)
        |> adjust_cursor_loop_entry(name, c_source)
        |> then(fn entry ->
          score = Map.get(entry, :score, 0)
          entry |> Map.put(:score, score) |> Map.put(:level, level(score))
        end)
        |> Map.update(:reasons, [], &Enum.sort(Enum.uniq(&1)))
      end)

    %{
      summary: %{
        ok: Enum.count(entries, &(&1.level == :ok)),
        warn: Enum.count(entries, &(&1.level == :warn)),
        risk: Enum.count(entries, &(&1.level == :risk))
      },
      code_size_indicators: code_size_indicators(c_source),
      functions: entries
    }
  end

  defp code_size_indicators(source) do
    %{
      generated_c_bytes: byte_size(source),
      generated_c_lines: source |> String.split("\n") |> length(),
      generic_function_defs:
        Regex.scan(~r/(?:^|\n)(?:static\s+)?(?:ElmcValue\s+\*|elmc_int_t)\s+elmc_fn_/, source)
        |> length(),
      direct_command_defs:
        Regex.scan(~r/(?:^|\n)static\s+int\s+elmc_fn_[A-Za-z0-9_]+_commands_append/, source)
        |> length(),
      boxed_tmp_declarations: Regex.scan(~r/ElmcValue\s+\*tmp_/, source) |> length(),
      closure_allocations: Regex.scan(~r/elmc_closure_new\(/, source) |> length(),
      runtime_calls: runtime_call_counts(source),
      linked_binary: %{
        available: false,
        reason:
          "binary size is available after platform or host linking, not during C source generation"
      }
    }
  end

  defp runtime_call_counts(source) do
    @risk_runtime_calls
    |> Map.keys()
    |> Enum.map(fn call ->
      {call, Regex.scan(~r/\b#{Regex.escape(call)}\b/, source) |> length()}
    end)
    |> Map.new()
  end

  defp ir_entries(ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(fn decl ->
        name = "#{mod.name}.#{decl.name}"
        {score, reasons} = score_expr(decl.expr || %{}, decl.name)
        {name, %{function: name, score: score, reasons: reasons}}
      end)
    end)
    |> Map.new()
  end

  defp score_expr(expr, function_name), do: score_node(expr, function_name, 0)

  defp score_node(%{op: :runtime_call, function: function, args: args}, function_name, depth) do
    {child_score, child_reasons} = score_many(args || [], function_name, depth + 1)

    case Map.fetch(@risk_runtime_calls, function) do
      {:ok, reason} -> {child_score + 4 + depth_score(depth), [reason | child_reasons]}
      :error -> {child_score + depth_score(depth), child_reasons}
    end
  end

  defp score_node(%{op: :qualified_call, target: target, args: args}, function_name, depth) do
    {child_score, child_reasons} = score_many(args || [], function_name, depth + 1)

    cond do
      target in ["List.all", "List.any", "List.map", "List.filter", "List.filterMap"] ->
        {child_score + 4 + depth_score(depth), [:list_hof | child_reasons]}

      target in ["List.drop", "drop"] ->
        {child_score + 3 + depth_score(depth), [:list_drop | child_reasons]}

      true ->
        {child_score + depth_score(depth), child_reasons}
    end
  end

  defp score_node(%{op: :call, name: name, args: args}, function_name, depth) do
    {child_score, child_reasons} = score_many(args || [], function_name, depth + 1)

    if name == function_name do
      {child_score + 5 + depth_score(depth), [:self_recursion | child_reasons]}
    else
      {child_score + depth_score(depth), child_reasons}
    end
  end

  defp score_node(%{op: :lambda, body: body}, function_name, depth) do
    {score, reasons} = score_node(body, function_name, depth + 1)
    {score + 3, [:lambda | reasons]}
  end

  defp score_node(%{} = expr, function_name, depth) do
    expr
    |> Map.values()
    |> Enum.filter(&(is_map(&1) or is_list(&1)))
    |> score_many(function_name, depth + 1)
  end

  defp score_node(list, function_name, depth) when is_list(list),
    do: score_many(list, function_name, depth)

  defp score_node(_value, _function_name, _depth), do: {0, []}

  defp score_many(values, function_name, depth) do
    values
    |> List.wrap()
    |> Enum.reduce({0, []}, fn value, {score_acc, reasons_acc} ->
      {score, reasons} = score_node(value, function_name, depth)
      {score_acc + score, reasons ++ reasons_acc}
    end)
  end

  defp depth_score(depth) when depth >= 6, do: 1
  defp depth_score(_depth), do: 0

  defp c_entries(source) do
    ~r/(?:static\s+)?(?:ElmcValue\s+\*|elmc_int_t)\s+(elmc_fn_[A-Za-z0-9_]+)(?:_native)?\([^)]*\)\s*\{/
    |> Regex.scan(source, return: :index)
    |> Enum.map(fn [{start, len}, {name_start, name_len} | _] ->
      name = binary_part(source, name_start, name_len)
      body = function_body(source, start + len)
      {name, c_entry(name, body)}
    end)
    |> Map.new()
  end

  defp function_body(source, offset) do
    source
    |> binary_part(offset, byte_size(source) - offset)
    |> String.split("\n}", parts: 2)
    |> hd()
  end

  defp c_entry(name, body) do
    tmp_count =
      ~r/tmp_(\d+)/
      |> Regex.scan(body, capture: :all_but_first)
      |> Enum.map(fn [value] -> String.to_integer(value) end)
      |> case do
        [] -> 0
        values -> Enum.max(values)
      end

    boxed_locals = Regex.scan(~r/ElmcValue\s+\*/, body) |> length()

    runtime_reasons =
      @risk_runtime_calls
      |> Enum.flat_map(fn {call, reason} ->
        if String.contains?(body, call), do: [reason], else: []
      end)

    reasons =
      []
      |> maybe_reason(tmp_count >= 24, :many_temporaries)
      |> maybe_reason(boxed_locals >= 16, :many_boxed_locals)
      |> Kernel.++(runtime_reasons)

    %{
      function: name,
      c_tmp_max: tmp_count,
      c_boxed_locals: boxed_locals,
      score: div(tmp_count, 8) + div(boxed_locals, 8) + length(runtime_reasons) * 4,
      reasons: reasons
    }
  end

  defp maybe_reason(reasons, true, reason), do: [reason | reasons]
  defp maybe_reason(reasons, false, _reason), do: reasons

  defp level(score) when score >= 10, do: :risk
  defp level(score) when score >= 5, do: :warn
  defp level(_score), do: :ok

  defp base_entry(name), do: %{function: name, score: 0, reasons: []}

  defp adjust_fused_ir_entry(entry, name, c_source) do
    with [module, function] <- String.split(name, ".", parts: 2),
         true <- fused_native_defined?(module, function, c_source) do
      reasons = entry[:reasons] || entry["reasons"] || []
      score = entry[:score] || entry["score"] || 0

      %{
        entry
        | score: max(0, score - 6),
          reasons: reasons -- [:list_hof, :lambda, :list_hof_runtime]
      }
    else
      _ -> entry
    end
  end

  defp fused_native_defined?(module, function, c_source) do
    native = "elmc_fn_#{Util.safe_c_suffix(module)}_#{Util.safe_c_suffix(function)}_native"
    String.contains?(c_source, native)
  end

  @cursor_loop_markers ~w(
    list_map_cursor_
    list_filter_map_cursor_
    list_filter_map_i_
    list_all_cursor_
    list_any_cursor_
    list_filter_cursor_
    list_foldl_cursor_
    list_length_cursor_
    list_repeat_acc_
    list_fwd_head_
    list_concat_acc_
    list_concat_flat_acc_
  )

  defp adjust_cursor_loop_entry(entry, name, c_source) do
    c_fn =
      case String.split(name, ".", parts: 2) do
        [module, function] -> "elmc_fn_#{Util.safe_c_suffix(module)}_#{Util.safe_c_suffix(function)}"
        _ -> nil
      end

    with c_fn when is_binary(c_fn) <- c_fn,
         true <- String.contains?(c_source, c_fn),
         body when is_binary(body) <- function_c_body(c_source, c_fn),
         true <- cursor_loop_optimized?(body) do
      reasons = entry[:reasons] || entry["reasons"] || []
      score = entry[:score] || entry["score"] || 0

      %{
        entry
        | score: max(0, score - 6),
          reasons: reasons -- [:list_hof, :lambda, :list_hof_runtime]
      }
    else
      _ -> entry
    end
  end

  defp function_c_body(source, c_fn) do
    case :binary.match(source, "#{c_fn}(") do
      {start, _} ->
        source
        |> binary_part(start, byte_size(source) - start)
        |> String.split("{", parts: 2)
        |> case do
          [_sig, body] -> String.trim_leading(body)
          _ -> nil
        end

      :nomatch ->
        nil
    end
  end

  defp cursor_loop_optimized?(body) do
    Enum.any?(@cursor_loop_markers, &String.contains?(body, &1)) and
      not Enum.any?(Map.keys(@risk_runtime_calls), &String.contains?(body, &1))
  end
end
