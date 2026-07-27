defmodule Elmc.Backend.CCodegen.StackEstimate do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias Elmc.Backend.CCodegen.Util

  @risk_runtime_calls %{
    "elmc_list_all" => :list_hof_runtime,
    "elmc_list_any" => :list_hof_runtime,
    "elmc_list_map" => :list_hof_runtime,
    "elmc_list_filter" => :list_hof_runtime,
    "elmc_list_filter_map" => :list_hof_runtime,
    "elmc_list_drop" => :list_drop
  }

  alias Elmc.Backend.CCodegen.Types.LinkedBinary, as: LinkedBinaryTypes
  alias Elmc.Backend.CCodegen.Types.StackEstimate, as: StackEstimateTypes
  alias Elmc.Backend.CCodegen.Types

  @spec report(ElmEx.IR.t(), String.t()) :: StackEstimateTypes.t()
  def report(ir, c_source) do
    ir_entries = ir_entries(ir)
    c_entries = c_entries(c_source)
    body_cache = function_body_cache(c_source)

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
        |> adjust_cursor_loop_entry(name, c_source, body_cache)
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

  @spec code_size_indicators(String.t()) :: Types.ir_expr()

  defp code_size_indicators(source) do
    %{
      generated_c_bytes: byte_size(source),
      generated_c_lines: source |> String.split("\n") |> length(),
      generic_function_defs:
        Regex.scan(~r/(?:^|\n)(?:static\s+)?(?:RC\s+|ElmcValue\s+\*|elmc_int_t)\s+elmc_fn_/, source)
        |> length(),
      direct_command_defs:
        Regex.scan(~r/(?:^|\n)static\s+RC\s+elmc_fn_[A-Za-z0-9_]+_commands_append/, source)
        |> length(),
      commands_append_bytes: commands_append_body_bytes(source),
      fusion_native_count:
        Regex.scan(~r/(?:^|\n)static\s+(?:RC\s+)?elmc_fn_[A-Za-z0-9_]+_native\(/, source)
        |> length(),
      plan_function_count:
        Regex.scan(~r/plan_native_int_\d+/, source) |> Enum.uniq() |> length(),
      owned_slot_max: owned_slot_max(source),
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

  @spec commands_append_body_bytes(String.t()) :: Types.ir_expr()

  defp commands_append_body_bytes(source) do
    ~r/static RC elmc_fn_[A-Za-z0-9_]+_commands_append\([^{]*\{([\s\S]*?)\n\}/
    |> Regex.scan(source)
    |> Enum.map(fn [_, body] -> byte_size(body) end)
    |> Enum.sum()
  end

  @spec owned_slot_max(String.t()) :: Types.ir_expr()

  defp owned_slot_max(source) do
    case Regex.scan(~r/owned\[(\d+)\]/, source) do
      [] ->
        0

      matches ->
        matches
        |> Enum.map(fn [_, n] -> String.to_integer(n) end)
        |> Enum.max()
        |> Kernel.+(1)
    end
  end

  @spec put_linked_binary(StackEstimateTypes.wire_map(), LinkedBinaryTypes.wire_map()) ::
          StackEstimateTypes.wire_map()
  def put_linked_binary(report, linked) when is_map(report) and is_map(linked) do
    indicators =
      report
      |> Map.get("code_size_indicators", report[:code_size_indicators] || %{})
      |> Map.put("linked_binary", linked)

    Map.put(report, "code_size_indicators", indicators)
  end

  @spec runtime_call_counts(String.t()) :: Types.ir_expr()

  defp runtime_call_counts(source) do
    @risk_runtime_calls
    |> Map.keys()
    |> Enum.map(fn call ->
      {call, Regex.scan(~r/\b#{Regex.escape(call)}\b/, source) |> length()}
    end)
    |> Map.new()
  end

  @spec ir_entries(Types.t()) :: Types.ir_expr()

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

  @spec score_expr(Types.expr(), String.t()) :: Types.ir_expr()

  defp score_expr(expr, function_name), do: score_node(expr, function_name, 0)

  @spec score_node(map() | list() | integer(), String.t(), non_neg_integer()) :: Types.ir_expr()

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

  @spec score_many(Types.ir_expr(), String.t(), non_neg_integer()) :: Types.ir_expr()

  defp score_many(values, function_name, depth) do
    values
    |> List.wrap()
    |> Enum.reduce({0, []}, fn value, {score_acc, reasons_acc} ->
      {score, reasons} = score_node(value, function_name, depth)
      {score_acc + score, reasons ++ reasons_acc}
    end)
  end

  @spec depth_score(non_neg_integer()) :: Types.ir_expr()

  defp depth_score(depth) when depth >= 6, do: 1
  defp depth_score(_depth), do: 0

  @spec c_entries(String.t()) :: Types.ir_expr()

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

  @spec function_body(String.t(), Types.ir_expr()) :: Types.ir_expr()

  defp function_body(source, offset) do
    source
    |> binary_part(offset, byte_size(source) - offset)
    |> String.split("\n}", parts: 2)
    |> hd()
  end

  @spec c_entry(String.t(), Types.expr()) :: Types.ir_expr()

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

  @spec maybe_reason(Types.ir_expr(), Types.ir_expr(), integer()) :: Types.ir_expr() | nil

  defp maybe_reason(reasons, true, reason), do: [reason | reasons]
  defp maybe_reason(reasons, false, _reason), do: reasons

  @spec level(Types.ir_expr()) :: Types.ir_expr()

  defp level(score) when score >= 10, do: :risk
  defp level(score) when score >= 5, do: :warn
  defp level(_score), do: :ok

  @doc false
  @spec ir_function_score(Types.function_declaration()) :: non_neg_integer()
  def ir_function_score(%{expr: expr, name: name}) when is_map(expr) do
    {score, _} = score_expr(expr, name)
    score
  end

  def ir_function_score(_decl), do: 0

  @spec base_entry(String.t()) :: Types.ir_expr()

  defp base_entry(name), do: %{function: name, score: 0, reasons: []}

  @spec adjust_fused_ir_entry(Types.ir_expr(), String.t(), String.t()) :: Types.ir_expr()

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

  @spec fused_native_defined?(String.t(), integer(), String.t()) :: boolean()

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

  @spec adjust_cursor_loop_entry(Types.ir_expr(), String.t(), String.t(), Types.ir_expr()) :: Types.ir_expr()

  defp adjust_cursor_loop_entry(entry, name, _c_source, body_cache) do
    c_fn =
      case String.split(name, ".", parts: 2) do
        [module, function] -> "elmc_fn_#{Util.safe_c_suffix(module)}_#{Util.safe_c_suffix(function)}"
        _ -> nil
      end

    with c_fn when is_binary(c_fn) <- c_fn,
         true <- Map.has_key?(body_cache, c_fn),
         body when is_binary(body) <- Map.get(body_cache, c_fn),
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

  @spec function_body_cache(String.t()) :: Types.ir_expr()

  defp function_body_cache(source) do
    pattern =
      Regex.compile!(
        "(?:static\\s+)?(?:RC|ElmcValue\\s*\\*+\\s*|elmc_int_t|const char\\s*\\*|void|int|bool)\\s*(elmc_fn_[A-Za-z0-9_]+)\\s*\\((?:const\\s+)?[^;{]*\\)\\s*\\{"
      )

    Regex.scan(pattern, source, return: :index)
    |> Enum.reduce(%{}, fn
      [{start, len}, {name_start, name_len}], acc ->
        name = binary_part(source, name_start, name_len)
        open_idx = start + len - 1

        case find_matching_brace(source, open_idx) do
          {:ok, end_idx} ->
            Map.put(acc, name, binary_part(source, open_idx + 1, end_idx - open_idx - 1))

          _ ->
            acc
        end

      _, acc ->
        acc
    end)
  end

  @spec find_matching_brace(String.t(), Types.ir_expr()) :: Types.ir_expr()

  defp find_matching_brace(source, open_idx) do
    do_find_matching_brace(source, open_idx + 1, byte_size(source), 1)
  end

  @spec do_find_matching_brace(String.t(), Types.ir_expr(), Types.ir_expr(), non_neg_integer()) :: Types.ir_expr()

  defp do_find_matching_brace(_source, idx, size, _depth) when idx >= size, do: {:error, :unbalanced}

  defp do_find_matching_brace(source, idx, size, depth) do
    ch = :binary.at(source, idx)

    cond do
      ch == ?" ->
        case skip_c_string(source, idx + 1, size) do
          {:ok, next} -> do_find_matching_brace(source, next, size, depth)
          :error -> {:error, :unbalanced}
        end

      ch == ?' ->
        case skip_c_char_literal(source, idx + 1, size) do
          {:ok, next} -> do_find_matching_brace(source, next, size, depth)
          :error -> {:error, :unbalanced}
        end

      ch == ?/ and idx + 1 < size ->
        case :binary.at(source, idx + 1) do
          ?/ ->
            do_find_matching_brace(source, skip_line_comment(source, idx + 2, size), size, depth)

          ?* ->
            case skip_block_comment(source, idx + 2, size) do
              {:ok, next} -> do_find_matching_brace(source, next, size, depth)
              :error -> {:error, :unbalanced}
            end

          _ ->
            scan_brace_token(source, idx, size, depth)
        end

      true ->
        scan_brace_token(source, idx, size, depth)
    end
  end

  @spec scan_brace_token(String.t(), Types.ir_expr(), Types.ir_expr(), non_neg_integer()) :: Types.ir_expr()

  defp scan_brace_token(source, idx, size, depth) do
    ch = :binary.at(source, idx)

    cond do
      ch == ?{ ->
        do_find_matching_brace(source, idx + 1, size, depth + 1)

      ch == ?} and depth == 1 ->
        {:ok, idx}

      ch == ?} and depth > 1 ->
        do_find_matching_brace(source, idx + 1, size, depth - 1)

      true ->
        do_find_matching_brace(source, idx + 1, size, depth)
    end
  end

  @spec skip_c_string(String.t(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp skip_c_string(_source, idx, size) when idx >= size, do: :error

  defp skip_c_string(source, idx, size) do
    case :binary.at(source, idx) do
      ?" -> {:ok, idx + 1}
      ?\\ when idx + 1 < size -> skip_c_string(source, idx + 2, size)
      _ -> skip_c_string(source, idx + 1, size)
    end
  end

  @spec skip_c_char_literal(String.t(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp skip_c_char_literal(_source, idx, size) when idx >= size, do: :error

  defp skip_c_char_literal(source, idx, size) do
    case :binary.at(source, idx) do
      ?' -> {:ok, idx + 1}
      ?\\ when idx + 1 < size -> skip_c_char_literal(source, idx + 2, size)
      _ -> skip_c_char_literal(source, idx + 1, size)
    end
  end

  @spec skip_line_comment(String.t(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp skip_line_comment(source, idx, size) do
    case :binary.match(source, "\n", [{:scope, {idx, size - idx}}]) do
      {rel, _} -> rel + 1
      :nomatch -> size
    end
  end

  @spec skip_block_comment(String.t(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp skip_block_comment(_source, idx, size) when idx >= size, do: :error

  defp skip_block_comment(source, idx, size) do
    case :binary.match(source, "*/", [{:scope, {idx, size - idx}}]) do
      {rel, len} -> {:ok, rel + len}
      :nomatch -> :error
    end
  end

  @spec cursor_loop_optimized?(Types.expr()) :: boolean()

  defp cursor_loop_optimized?(body) do
    Enum.any?(@cursor_loop_markers, &String.contains?(body, &1)) and
      not Enum.any?(Map.keys(@risk_runtime_calls), &String.contains?(body, &1))
  end
end
