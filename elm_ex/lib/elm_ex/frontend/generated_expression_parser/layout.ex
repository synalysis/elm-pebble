defmodule ElmEx.Frontend.GeneratedExpressionParser.Layout do
  @moduledoc false

  @type source() :: String.t()
  @type line() :: String.t()
  @type lines() :: [line()]

  @spec normalize(source()) :: source()
  def normalize(source) when is_binary(source) do
    source
    |> preflight_unglue_layout_lines()
    |> collapse_binding_rhs_starts()
    |> collapse_multiline_if_else_before_in_case()
    |> normalize_let_source()
    |> normalize_case_source()
    |> normalize_post_case()
  end

  @spec normalize_post_case(source()) :: source()
  defp normalize_post_case(source) when is_binary(source) do
    apply_post_case_steps(source, post_case_steps())
  end

  defp post_case_steps do
    [
      {:ensure_multiline_case_arm_separators, &ensure_multiline_case_arm_separators/1},
      {:collapse_let_in_before_case, &collapse_let_in_before_case/1},
      {:fix_inline_let_multiple_bindings, &fix_inline_let_multiple_bindings/1},
      {:insert_glued_inline_case_arm_separators, &insert_glued_inline_case_arm_separators/1},
      {:ensure_inline_case_list_arm_separators, &ensure_inline_case_list_arm_separators/1},
      {:normalize_inline_case_branch_separators, &normalize_inline_case_branch_separators/1},
      {:normalize_inline_case_arm_bodies, &normalize_inline_case_arm_bodies/1},
      {:strip_of_double_semicolon, &String.replace(&1, ~r/\bof\s*;;\s*/u, "of ")},
      {:join_dangling_case_wrapper_close, &join_dangling_case_wrapper_close/1},
      {:unwrap_spurious_case_arm_let_parens, &unwrap_spurious_case_arm_let_parens/1},
      {:split_arrow_inline_case_headers, &split_arrow_inline_case_headers/1},
      {:repair_misclosed_inline_case_headers, &repair_misclosed_inline_case_headers/1},
      {:close_paren_let_before_inner_wildcard_arm, &close_paren_let_before_inner_wildcard_arm/1},
      {:repair_premature_close_in_let_case_arm, &repair_premature_close_in_let_case_arm/1},
      {:fix_misplaced_in_before_tuple_binding, &fix_misplaced_in_before_tuple_binding/1},
      {:ensure_triple_case_arm_separators, &ensure_triple_case_arm_separators/1},
      {:split_inline_let_in_lines, &split_inline_let_in_lines/1},
      {:postflight_split_glued_cases, &postflight_split_glued_cases/1},
      {:join_orphan_case_arm_separators, &join_orphan_case_arm_separators/1},
      {:collapse_duplicate_case_arm_separators, &collapse_duplicate_case_arm_separators/1}
    ]
  end

  defp apply_post_case_steps(source, steps) do
    Enum.reduce(steps, source, fn {_name, fun}, acc -> fun.(acc) end)
  end

  @spec collapse_duplicate_case_arm_separators(source()) :: source()
  defp collapse_duplicate_case_arm_separators(source) when is_binary(source) do
    source
    |> String.replace(~r/;{3,}/u, ";;")
    |> String.replace(~r/\);;/u, ") ;;")
    |> String.replace(~r/;;\s*\)\s*;;/u, ") ;;")
    |> String.replace(~r/;;\s*;;+/u, ";; ")
    |> String.replace(~r/;;(?=_\s*->)/u, ";; ")
    |> String.replace(~r/\bof\s*;;/u, "of ")
    |> String.replace(~r/;;(?=[A-Z][A-Za-z0-9_.']*\s)/u, ";; ")
  end

  @spec join_orphan_case_arm_separators(source()) :: source()
  defp join_orphan_case_arm_separators(source) when is_binary(source) do
    {lines, _pending_sep?} =
      source
      |> String.split("\n")
      |> Enum.reduce({[], false}, fn line, {acc, pending_sep?} ->
        trimmed = String.trim(line)

        cond do
          trimmed == ";;" ->
            {acc, true}

          pending_sep? and acc != [] ->
            [prev | tail] = acc
            next = String.replace(trimmed, ~r/^\);\;/u, ") ;;")
            {[prev <> " ;; " <> next | tail], false}

          Regex.match?(~r/^;;+\s+\S/u, trimmed) and acc != [] ->
            [prev | tail] = acc
            {[prev <> " " <> trimmed | tail], false}

          true ->
            {[line | acc], false}
        end
      end)

    lines |> Enum.reverse() |> Enum.join("\n")
  end

  @doc false
  @spec normalize_through_let(source()) :: source()
  def normalize_through_let(source) when is_binary(source) do
    source
    |> collapse_binding_rhs_starts()
    |> collapse_multiline_if_else_before_in_case()
    |> normalize_let_source()
  end

  # Case normalization can flatten record/url fields onto one line; split and re-run
  # the line-based normalizer so each embedded `++ (case …)` and `body = case` is handled.
  @spec postflight_split_glued_cases(source()) :: source()
  defp postflight_split_glued_cases(source) when is_binary(source) do
    if Enum.any?(String.split(source, "\n"), &preflight_glued_layout_line?/1) do
      source
      |> repair_glued_layout_lines()
      |> normalize_case_source()
      |> join_dangling_case_wrapper_close()
    else
      source
    end
  end

  @spec preflight_unglue_layout_lines(source()) :: source()
  defp preflight_unglue_layout_lines(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> Enum.flat_map(&preflight_unglue_line/1)
    |> Enum.join("\n")
  end

  defp preflight_unglue_line(line) when is_binary(line) do
    if preflight_glued_layout_line?(line) do
      line
      |> String.replace(~r/\s(\+\+\s*\(case\b)/u, "\n\\1")
      |> String.replace(
        ~r/(\))\s*(,\s*(?:body|expect|url|method|headers|tracker|timeout|encoder)\s*=)/u,
        "\\1\n\\2"
      )
      |> maybe_split_outer_constructor_arms(line)
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(fn seg ->
        if line_needs_case_reflow?(seg), do: expand_case_of_to_newline(seg), else: seg
      end)
    else
      [line]
    end
  end

  defp maybe_split_outer_constructor_arms(text, original_line) when is_binary(text) do
    if String.contains?(original_line, "loadDataAndUpdateUrl") or
         String.contains?(original_line, "Http.request") do
      String.replace(
        text,
        ~r/(\))\s*;;\s*([A-Z][A-Za-z0-9_.']*\s+[a-z_][A-Za-z0-9_']*)/u,
        "\\1\n;; \\2"
      )
    else
      text
    end
  end

  defp preflight_glued_layout_line?(line) when is_binary(line) do
    trimmed = String.trim(line)

    # Flattened outer `update`-style case bodies can mention `loadDataAndUpdateUrl`
    # and record `body =` fields on one line without being glued Http.request literals.
    # Re-running case normalization there double-wraps earlier arms (`((let …`) and
    # emits `(case subject of);;` arm separators.
    not Regex.match?(~r/^case\s+[a-z][A-Za-z0-9_']*\s+of\b/u, trimmed) and
      String.length(line) > 250 and String.contains?(line, ";;") and
      (String.contains?(line, "Http.request") or
         load_data_record_fields_glued?(line) or
         (String.contains?(line, "++ (case") and
            Regex.match?(~r/,\s*body\s*=\s*case\b/u, line)))
  end

  defp load_data_record_fields_glued?(line) when is_binary(line) do
    String.contains?(line, "loadDataAndUpdateUrl") and
      Regex.match?(
        ~r/loadDataAndUpdateUrl[\s\S]{0,160},\s*(?:body|expect|url|method|headers|tracker|timeout|encoder)\s*=/u,
        line
      )
  end

  defp line_needs_case_reflow?(line) when is_binary(line) do
    String.contains?(line, "case ") and String.contains?(line, " of ") and
      String.contains?(line, "->") and not String.contains?(line, " of\n")
  end

  @spec repair_glued_layout_lines(source()) :: source()
  defp repair_glued_layout_lines(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> Enum.flat_map(&repair_glued_layout_segments/1)
    |> Enum.join("\n")
  end

  defp repair_glued_layout_segments(line) when is_binary(line) do
    line
    |> preflight_unglue_line()
    |> Enum.map(fn seg ->
      seg
      |> repair_append_case_missing_close()
      |> repair_wildcard_case_before_record_field()
    end)
  end

  defp repair_append_case_missing_close(line) when is_binary(line) do
    case Regex.run(
           ~r/(\+\+\s*\(case\b.*?\bof\b.*?;;(?:(?!\s*\+\+).)*?)(\s*\+\+\s*\(case\b)/u,
           line,
           capture: :all_but_first
         ) do
      [case1, case2] ->
        trimmed = String.trim_trailing(case1)
        needle = case1 <> case2

        if String.ends_with?(trimmed, ")") or not String.contains?(line, needle) do
          line
        else
          String.replace(line, needle, trimmed <> ") " <> case2)
        end

      _ ->
        line
    end
  end

  defp repair_wildcard_case_before_record_field(line) when is_binary(line) do
    if Regex.match?(~r/\)\s*;;\s*_\s*->/u, line) do
      line
      |> String.replace(
        ~r/(\)\s*;;\s*_\s*->\s*[^,;]+?)\)\s*,\s*([a-z_][A-Za-z0-9_']*\s*=)/u,
        "\\1\n, \\2"
      )
      |> String.replace(
        ~r/(\)\s*;;\s*_\s*->\s*[^,;]+?)\s*,\s*([a-z_][A-Za-z0-9_']*\s*=)/u,
        "\\1\n, \\2"
      )
    else
      line
    end
  end

  @spec join_dangling_case_wrapper_close(source()) :: source()
  defp join_dangling_case_wrapper_close(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> join_dangling_case_wrapper_close_lines([])
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp join_dangling_case_wrapper_close_lines([], acc), do: acc

  defp join_dangling_case_wrapper_close_lines([line | rest], acc) do
    case rest do
      [next | tail] ->
        trimmed = String.trim(line)
        trimmed_next = String.trim(next)

        cond do
          dangling_case_wrapper_close_line?(line, trimmed_next) ->
            join_dangling_case_wrapper_close_lines(
              tail,
              [String.trim_trailing(line) <> " " <> trimmed_next | acc]
            )

          redundant_close_paren_line?(trimmed, trimmed_next) ->
            join_dangling_case_wrapper_close_lines([line | tail], acc)

          true ->
            join_dangling_case_wrapper_close_lines(rest, [line | acc])
        end

      _ ->
        [line | acc]
    end
  end

  defp redundant_close_paren_line?(trimmed, trimmed_next) do
    trimmed_next == ")" and String.ends_with?(trimmed, ")") and
      (String.contains?(trimmed, "(case") or String.contains?(trimmed, "++")) and
      not tuple_embedded_case_line?(trimmed)
  end

  defp tuple_embedded_case_line?(trimmed) when is_binary(trimmed) do
    Regex.match?(~r/,\s*\(case\b/u, trimmed)
  end

  defp dangling_case_wrapper_close_line?(line, trimmed_next) when is_binary(line) do
    trimmed = String.trim(line)

    Regex.match?(~r/\(\s*case\b/u, trimmed) and String.contains?(trimmed, ";;") and
      not String.ends_with?(trimmed, ")") and trimmed_next == ")"
  end

  @spec unwrap_spurious_case_arm_let_parens(source()) :: source()
  defp unwrap_spurious_case_arm_let_parens(source) when is_binary(source) do
    unwrap_spurious_case_arm_let_parens_loop(source)
  end

  defp unwrap_spurious_case_arm_let_parens_loop(source) when is_binary(source) do
    case :binary.match(source, "-> (let ") do
      :nomatch ->
        source

      {pos, _} ->
        prefix = String.slice(source, 0, pos + 3)
        rest = String.slice(source, pos + 3, String.length(source) - pos - 3)

        case unwrap_leading_let_paren_wrap(rest) do
          {:ok, unwrapped, suffix} ->
            prefix <> unwrapped <> unwrap_spurious_case_arm_let_parens_loop(suffix)

          :error ->
            source
        end
    end
  end

  defp unwrap_leading_let_paren_wrap(source) when is_binary(source) do
    trimmed = String.trim_leading(source)

    if String.starts_with?(trimmed, "(let ") do
      case take_balanced_parens(trimmed) do
        {:ok, wrapped, remainder} ->
          inner = wrapped |> String.slice(1, String.length(wrapped) - 2) |> String.trim()

          if String.starts_with?(inner, "let ") and not nested_inline_case_with_arms?(inner) do
            {:ok, inner, remainder}
          else
            :error
          end

        :error ->
          :error
      end
    else
      :error
    end
  end

  defp take_balanced_parens(source) when is_binary(source) do
    case String.graphemes(source) do
      ["(" | rest] ->
        case scan_balanced_close(rest, 1, :code, false, 1) do
          {:ok, idx} ->
            wrapped = String.slice(source, 0, idx + 1)
            remainder = String.slice(source, idx + 1, String.length(source))
            {:ok, wrapped, remainder}

          :error ->
            :error
        end

      _ ->
        :error
    end
  end

  defp scan_balanced_close([], _idx, _mode, _escaped, _depth), do: :error

  defp scan_balanced_close([ch | rest], idx, mode, escaped, depth) do
    cond do
      depth == 0 ->
        {:ok, idx}

      mode == :string ->
        next_mode = if not escaped and ch == "\"", do: :code, else: :string
        next_escaped = ch == "\\" and not escaped
        scan_balanced_close(rest, idx + 1, next_mode, next_escaped, depth)

      mode == :char ->
        next_mode = if not escaped and ch == "'", do: :code, else: :char
        next_escaped = ch == "\\" and not escaped
        scan_balanced_close(rest, idx + 1, next_mode, next_escaped, depth)

      ch == "\"" ->
        scan_balanced_close(rest, idx + 1, :string, false, depth)

      ch == "'" ->
        scan_balanced_close(rest, idx + 1, :char, false, depth)

      ch == "(" ->
        scan_balanced_close(rest, idx + 1, :code, false, depth + 1)

      ch == ")" ->
        scan_balanced_close(rest, idx + 1, :code, false, depth - 1)

      true ->
        scan_balanced_close(rest, idx + 1, :code, false, depth)
    end
  end

  defp nested_inline_case_with_arms?(body) when is_binary(body) do
    String.contains?(body, " case ") and String.contains?(body, " of") and
      String.contains?(body, "->") and
      (String.contains?(body, ";;") or glued_inline_case_second_arm?(body) or
         Regex.match?(~r/\bin\s+case\b/su, body))
  end

  defp glued_inline_case_second_arm?(body) when is_binary(body) do
    Regex.match?(
      ~r/\bcase\s+\S+\s+of\b.+(?:\)\s+|[^\s])\s+(?:_|'|\"|[A-Z][A-Za-z0-9_.']*(?:\s+[a-z_][A-Za-z0-9_']*)*)\s*->/su,
      body
    )
  end

  @spec repair_misclosed_inline_case_headers(source()) :: source()
  defp repair_misclosed_inline_case_headers(source) when is_binary(source) do
    Regex.replace(~r/(\bcase\s+[^\n;]+?\s+of)\)+;;/u, source, "\\1 ")
  end

  defp separate_multiline_case_arms_after_in(source) when is_binary(source) do
    String.replace(
      source,
      ~r/(\n\s+in\n\s+[^\n]+)(\n)(\s+)([A-Z][A-Za-z0-9_.']*(?:\s+[a-z_][A-Za-z0-9_']*)?\s*->)/u,
      "\\1\\2\\3;; \\4"
    )
  end

  @spec ensure_multiline_case_arm_separators(source()) :: source()
  defp ensure_multiline_case_arm_separators(source) when is_binary(source) do
    source
    |> String.replace(
      ~r/(\n\s+[^\n]+->[^\n]*\n\s+[^\n]+)(\n)(\s+)(_\s*->)/u,
      "\\1\\2\\3;; \\4"
    )
    |> separate_multiline_case_sibling_arms()
    |> separate_multiline_case_arms_after_in()
  end

  defp separate_multiline_case_sibling_arms(source) when is_binary(source) do
    if String.contains?(source, " of\n") do
      source
      |> String.replace(
        ~r/(\n\s+[^\n]+->\n(?:(?:\s+(?!\[\s[^\n]*\]\s*->)[^\n]+\n)+))(\s+)(\[\s[^\n]*\]\s*->)/u,
        "\\1\\2;; \\3"
      )
      |> String.replace(
        ~r/(\n\s+\]\n)(\s+)([A-Z][A-Za-z0-9_]*(?:\s+[a-z_][A-Za-z0-9_]*)?\s*->)/u,
        "\\1;; \\2\\3"
      )
      |> String.replace(
        ~r/(\n\s+[^\n]+\]\s*\n)(\s+)([A-Z][A-Za-z0-9_]*(?:\s+[a-z_][A-Za-z0-9_]*)?\s*->)/u,
        "\\1;; \\2\\3"
      )
      |> String.replace(
        ~r/(\n\s+[^\n]+->\n(?:(?:\s+[^\n]+\n)+?))(\n)(\s+)((?:Just|Nothing|Err|Ok)\b[^\n]*->)/u,
        "\\1\\2\\3;; \\4"
      )
      |> String.replace(
        ~r/(\n\s+[^\n]+->\n(?:(?:\s+(?!\s+_\s*->)[^\n]+\n)+))(\s+)(_\s*->)/u,
        "\\1;; \\2\\3"
      )
    else
      source
    end
  end

  @spec collapse_binding_rhs_starts(source()) :: source()
  defp collapse_binding_rhs_starts(source) when is_binary(source) do
    # Many Elm bindings are written as:
    #   name =
    #     case ... of
    # Normalize to:
    #   name = case ... of
    source
    |> then(&Regex.replace(~r/=\s*\n\s*(case\b|if\b|\\)/u, &1, "= \\1"))
    |> collapse_case_branch_rhs_starts()
  end

  @spec collapse_case_branch_rhs_starts(source()) :: source()
  defp collapse_case_branch_rhs_starts(source) when is_binary(source) do
    # Case branches commonly continue with a nested `case` on the next line:
    #   Just x ->
    #     case ... of
    # The layout lexer treats the newline as a branch boundary; keep the nested
    # case on the same line so yecc can parse the branch body.
    Regex.replace(~r/->\s*\n\s*(case\b)/u, source, "-> \\1")
  end

  @spec paren_balance_outside_string_literals(source()) :: integer()
  defp paren_balance_outside_string_literals(source) when is_binary(source) do
    source
    |> String.to_charlist()
    |> count_paren_balance(:code, 0)
  end

  defp count_paren_balance([], _state, acc), do: acc

  defp count_paren_balance([?( | rest], :code, acc),
    do: count_paren_balance(rest, :code, acc + 1)

  defp count_paren_balance([?) | rest], :code, acc),
    do: count_paren_balance(rest, :code, acc - 1)

  defp count_paren_balance([?" | rest], :code, acc),
    do: count_paren_balance(rest, :string, acc)

  defp count_paren_balance([?" | rest], :string, acc),
    do: count_paren_balance(rest, :code, acc)

  defp count_paren_balance([?' | rest], :code, acc),
    do: count_paren_balance(rest, :char, acc)

  defp count_paren_balance([?' | rest], :char, acc),
    do: count_paren_balance(rest, :code, acc)

  defp count_paren_balance([?\\, _ | rest], :string, acc),
    do: count_paren_balance(rest, :string, acc)

  defp count_paren_balance([?\\, _ | rest], :char, acc),
    do: count_paren_balance(rest, :char, acc)

  defp count_paren_balance([_ | rest], state, acc),
    do: count_paren_balance(rest, state, acc)

  @spec fix_inline_let_multiple_bindings(source()) :: source()
  defp fix_inline_let_multiple_bindings(source) when is_binary(source) do
    # The token parser requires `;` between let bindings. After layout/case normalization
    # we sometimes end up with multiple bindings on one line:
    #   let starter = (case ...) introduction = ...
    # Recover by inserting `;` before the second binding.
    source
    |> String.split("\n")
    |> Enum.map(fn line ->
      trimmed = String.trim(line)

      if String.contains?(trimmed, "let ") and String.contains?(trimmed, " in") do
        Regex.replace(~r/\)\s+([a-z][A-Za-z0-9_']*)\s*=/u, line, ") ; \\1 =")
      else
        line
      end
    end)
    |> Enum.join("\n")
  end

  @spec normalize_case_source(source()) :: source()
  defp normalize_case_source(source) when is_binary(source) do
    normalize_case_source(source, 0)
  end

  @spec normalize_case_source(source(), non_neg_integer()) :: source()
  defp normalize_case_source(source, passes) when passes >= 20, do: source

  defp normalize_case_source(source, passes) do
    normalized =
      if String.contains?(source, " of\n") and String.contains?(source, "->") do
        source
        |> ensure_multiline_case_arm_separators()
        |> String.split("\n")
        |> Enum.map(&String.trim_trailing/1)
        |> Enum.reject(&(String.trim(&1) == ""))
        |> normalize_embedded_case()
      else
        source
      end

    if normalized == source do
      normalized
    else
      normalize_case_source(normalized, passes + 1)
    end
  end

  @spec expand_case_of_to_newline(source()) :: source()
  defp expand_case_of_to_newline(source) when is_binary(source) do
    String.replace(source, ~r/\sof\s+(?=[(\[]|_|'|\"|[A-Z]|[a-z])/u, " of\n")
  end

  @spec normalize_let_source(source()) :: source()
  defp normalize_let_source(source) when is_binary(source) do
    normalize_let_source(source, 0)
  end

  @spec normalize_let_source(source(), non_neg_integer()) :: source()
  defp normalize_let_source(source, passes) when passes >= 20, do: source

  defp normalize_let_source(source, passes) do
    normalize_let_source(source, passes, MapSet.new())
  end

  defp normalize_let_source(source, passes, _excluded) when passes >= 20, do: source

  defp normalize_let_source(source, passes, excluded) do
    lines = String.split(source, "\n")

    case find_rewritable_let_block(lines, excluded) do
      nil ->
        source

      %{index: index, bindings: bindings, in_lines: in_lines} ->
        let_line = Enum.at(lines, index)
        indent = leading_indent_count(let_line)
        pad = String.duplicate(" ", indent)
        {in_body, after_in} = partition_let_in_lines(in_lines, indent)

        rewritten =
          Enum.take(lines, index) ++
            [
              pad <> "let " <> Enum.join(bindings, " ; "),
              pad <> "in",
              indent_in_lines(in_body, indent)
            ] ++
            after_in

        joined = Enum.join(rewritten, "\n")

        if joined == Enum.join(lines, "\n") do
          # Already normalized; keep searching for other lets (e.g. outer bare `let`).
          normalize_let_source(source, passes + 1, MapSet.put(excluded, index))
        else
          normalize_let_source(joined, passes + 1, MapSet.new())
        end
    end
  end

  @inline_let_in_line ~r/\blet\s+.+\s+in(\s+|$)/u

  @spec split_inline_let_in_lines(source()) :: source()
  defp split_inline_let_in_lines(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> Enum.flat_map(&split_line_inline_let_in/1)
    |> Enum.join("\n")
  end

  @spec split_line_inline_let_in(line()) :: lines()
  defp split_line_inline_let_in(line) when is_binary(line) do
    trimmed = String.trim(line)

    if Regex.match?(@inline_let_in_line, trimmed) do
      # Case flattening can put `pat -> let … in body` on one line. Splitting `in`
      # out would detach the body from the branch; keep it inline (LetLayout allows
      # this form when `let` follows `->`).
      if case_branch_inline_let?(trimmed) do
        [line]
      else
        case split_rightmost_inline_let_in(trimmed) do
          {:ok, before, in_expr} ->
            split_line_inline_let_in(before) ++ ["in" | split_line_inline_let_in(in_expr)]

          :error ->
            [line]
        end
      end
    else
      [line]
    end
  end

  defp case_branch_inline_let?(line) when is_binary(line) do
    trimmed = String.trim(line)

    # Top-level `let … in …` can contain nested `case` branches with `->` after
    # layout normalization; only preserve inline let/in for `pat -> let … in …`.
    not String.starts_with?(trimmed, "let ") and String.contains?(trimmed, "->") and
      String.contains?(trimmed, "let ")
  end

  @spec split_rightmost_inline_let_in(source()) :: {:ok, source(), source()} | :error
  defp split_rightmost_inline_let_in(line) when is_binary(line) do
    trimmed = String.trim_trailing(line)

    cond do
      String.ends_with?(trimmed, " in") ->
        before = trimmed |> String.slice(0, String.length(trimmed) - 3) |> String.trim_trailing()

        if String.contains?(before, "let ") do
          {:ok, before, ""}
        else
          :error
        end

      true ->
        case :binary.matches(trimmed, " in ") do
          [] ->
            :error

          matches ->
            {pos, len} = List.last(matches)
            before = trimmed |> String.slice(0, pos) |> String.trim_trailing()

            rest_len = String.length(trimmed) - pos - len

            if rest_len < 0 do
              :error
            else
              in_expr =
                trimmed
                |> String.slice(pos + len, rest_len)
                |> String.trim_leading()

              if String.contains?(before, "let ") do
                {:ok, before, in_expr}
              else
                :error
              end
            end
        end
    end
  end

  @spec split_let_lines(lines(), lines(), non_neg_integer()) :: {lines(), lines()}
  defp split_let_lines([], acc, _depth), do: {Enum.reverse(acc), []}

  defp split_let_lines([line | rest], acc, depth) do
    trimmed = String.trim(line)

    cond do
      depth == 1 and trimmed == "in" ->
        {Enum.reverse(acc), rest}

      depth == 1 and String.starts_with?(trimmed, "in ") ->
        in_expr = String.trim_leading(String.slice(trimmed, 2..-1//1))
        {Enum.reverse(acc), [in_expr | rest]}

      true ->
        next_depth = next_let_depth(depth, line)
        split_let_lines(rest, [line | acc], next_depth)
    end
  end

  @spec partition_let_in_lines(lines(), non_neg_integer()) :: {lines(), lines()}
  defp partition_let_in_lines(in_lines, in_indent) when is_list(in_lines) do
    Enum.split_while(in_lines, fn line ->
      trimmed = String.trim(line)
      trimmed == "" or leading_indent_count(line) >= in_indent
    end)
  end

  defp find_rewritable_let_block(lines, excluded) when is_list(lines) do
    # Prefer innermost lets first. If the outermost `let` is rewritten first, later
    # passes keep rematching that same outer block (`let name = ...`) and nested
    # multi-binding lets never receive `;` separators — case flattening then crushes
    # `let a = … b = …` onto one line and yecc fails.
    lines
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn {line, index} ->
      if MapSet.member?(excluded, index) do
        nil
      else
        cond do
          String.trim(line) == "let" ->
            rest = Enum.drop(lines, index + 1)
            {binding_lines, in_lines} = split_let_lines(rest, [], 1)
            bindings = collect_let_bindings(binding_lines)

            if in_lines != [] and length(bindings) > 1 do
              %{index: index, bindings: bindings, in_lines: in_lines}
            else
              nil
            end

          Regex.match?(~r/^\s*let\s+[a-z][A-Za-z0-9_']*(?:\s+[a-z_][A-Za-z0-9_']*)*\s*=\s+.+/u, line) and
              not partial_inline_let_header_line?(line) ->
            rest = Enum.drop(lines, index + 1)
            first_line_rest = line |> String.trim() |> String.replace_prefix("let ", "")
            first_line = align_first_let_binding_indent(first_line_rest, rest)
            {binding_lines, in_lines} = split_let_lines(rest, [first_line], 1)
            bindings = collect_let_bindings(binding_lines)

            if in_lines != [] and length(bindings) > 1 do
              %{index: index, bindings: bindings, in_lines: in_lines}
            else
              nil
            end

          true ->
            nil
        end
      end
    end)
  end

  defp partial_inline_let_header_line?(line) when is_binary(line) do
    trimmed = String.trim(line)

    String.starts_with?(trimmed, "let ") and String.contains?(trimmed, " in") and
      not String.ends_with?(trimmed, " in")
  end

  @spec align_first_let_binding_indent(String.t(), lines()) :: String.t()
  defp align_first_let_binding_indent(first_line_rest, binding_lines) do
    case infer_let_binding_indent(binding_lines) do
      indent when is_integer(indent) and indent > 0 ->
        String.duplicate(" ", indent) <> first_line_rest

      _ ->
        first_line_rest
    end
  end

  @spec infer_let_binding_indent(lines()) :: non_neg_integer() | nil
  defp infer_let_binding_indent(lines) do
    Enum.find_value(lines, fn line ->
      if let_binding_start_line?(line), do: leading_indent_count(line)
    end)
  end

  @spec collect_let_bindings(lines()) :: [String.t()]
  defp collect_let_bindings(lines) do
    expanded_lines = expand_top_level_semicolon_lines(lines)

    {bindings, current, _let_depth, _base_indent} =
      Enum.reduce(expanded_lines, {[], nil, 0, nil}, fn line,
                                                        {acc, current, let_depth, base_indent} ->
        trimmed = String.trim(line)
        indent = leading_indent_count(line)
        binding_start = let_binding_start_line?(line)

        starts_binding =
          let_depth == 0 and binding_start and (is_nil(base_indent) or indent == base_indent) and
            (not is_binary(current) or
               delimiter_balance_outside_string_literals(current) == 0)

        cond do
          trimmed == "" ->
            {acc, current, let_depth, base_indent}

          starts_binding ->
            flushed =
              if is_binary(current),
                do: acc ++ [normalize_binding_for_separator(current)],
                else: acc

            new_depth = next_let_depth(let_depth, line)
            {flushed, trimmed, new_depth, base_indent || indent}

          is_binary(current) ->
            new_depth = next_let_depth(let_depth, line)
            continuation = String.trim_trailing(line)
            {acc, current <> "\n" <> continuation, new_depth, base_indent}

          true ->
            new_depth = next_let_depth(let_depth, line)
            {acc, trimmed, new_depth, base_indent}
        end
      end)

    if is_binary(current),
      do: bindings ++ [normalize_binding_for_separator(current)],
      else: bindings
  end

  @spec expand_top_level_semicolon_lines(lines()) :: lines()
  defp expand_top_level_semicolon_lines(lines) when is_list(lines) do
    {expanded, _let_depth} =
      Enum.map_reduce(lines, 0, fn line, let_depth ->
        # Semicolons from nested `let a = … ; b = …` must not be treated as outer
        # binding separators when collecting an enclosing let.
        segments =
          if let_depth > 0 do
            [line]
          else
            split_line_top_level_semicolons(line)
          end

        {segments, next_let_depth(let_depth, line)}
      end)

    List.flatten(expanded)
  end

  @spec split_line_top_level_semicolons(line()) :: lines()
  defp split_line_top_level_semicolons(line) when is_binary(line) do
    {segments, current, _depth, _mode, _escaped} =
      line
      |> String.graphemes()
      |> Enum.reduce({[], "", 0, :code, false}, fn ch,
                                                   {segments, current, depth, mode, escaped} ->
        cond do
          mode == :string ->
            next_mode = if not escaped and ch == "\"", do: :code, else: :string
            next_escaped = ch == "\\" and not escaped
            {segments, current <> ch, depth, next_mode, next_escaped}

          mode == :char ->
            next_mode = if not escaped and ch == "'", do: :code, else: :char
            next_escaped = ch == "\\" and not escaped
            {segments, current <> ch, depth, next_mode, next_escaped}

          ch == "\"" ->
            {segments, current <> ch, depth, :string, false}

          ch == "'" ->
            {segments, current <> ch, depth, :char, false}

          ch in ["(", "[", "{"] ->
            {segments, current <> ch, depth + 1, :code, false}

          ch in [")", "]", "}"] ->
            {segments, current <> ch, max(depth - 1, 0), :code, false}

          ch == ";" and depth == 0 ->
            {segments ++ [current], "", depth, :code, false}

          true ->
            {segments, current <> ch, depth, :code, false}
        end
      end)

    (segments ++ [current])
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  @spec let_binding_start_line?(line()) :: boolean()
  defp let_binding_start_line?(line) when is_binary(line) do
    trimmed = String.trim(line)

    # `let crossed = …` matches the generic `name args =` shape unless we exclude the
    # `let` / `in` keywords — otherwise outer `collect_let_bindings` treats nested let
    # headers as sibling bindings and emits `-> ; let crossed = …`.
    if trimmed in ["let", "in"] or String.starts_with?(trimmed, "let ") or
         String.starts_with?(trimmed, "in ") do
      false
    else
      binding_name = "(?:_|[a-z][A-Za-z0-9_]*)"

      Regex.match?(
        ~r/^[a-z][A-Za-z0-9_']*(?:\s+[a-z][A-Za-z0-9_']*|\s+_|\s+\([^\)]*\))*\s*=(?!=)/u,
        trimmed
      ) or
        Regex.match?(
          ~r/^\(\s*#{binding_name}(?:\s*,\s*#{binding_name}){1,2}\s*\)\s*=(?!=)/u,
          trimmed
        ) or
        Regex.match?(
          ~r/^\(\s*[A-Z][A-Za-z0-9_]*(?:\s+[^=()]+)?\s*\)\s*=(?!=)/u,
          trimmed
        )
    end
  end
  @spec delimiter_balance_outside_string_literals(source()) :: integer()
  defp delimiter_balance_outside_string_literals(source) when is_binary(source) do
    {balance, _mode, _escaped} =
      source
      |> String.graphemes()
      |> Enum.reduce({0, :code, false}, fn ch, {balance, mode, escaped} ->
        cond do
          mode == :string ->
            next_mode = if not escaped and ch == "\"", do: :code, else: :string
            next_escaped = ch == "\\" and not escaped
            {balance, next_mode, next_escaped}

          mode == :char ->
            next_mode = if not escaped and ch == "'", do: :code, else: :char
            next_escaped = ch == "\\" and not escaped
            {balance, next_mode, next_escaped}

          ch == "\"" ->
            {balance, :string, false}

          ch == "'" ->
            {balance, :char, false}

          ch == "(" ->
            {balance + 1, :code, false}

          ch == ")" ->
            {balance - 1, :code, false}

          ch == "{" ->
            {balance + 1, :code, false}

          ch == "}" ->
            {balance - 1, :code, false}

          ch == "[" ->
            {balance + 1, :code, false}

          ch == "]" ->
            {balance - 1, :code, false}

          true ->
            {balance, :code, false}
        end
      end)

    balance
  end

  @spec normalize_embedded_case(lines()) :: source()
  defp normalize_embedded_case(lines) do
    case find_embedded_case_start(lines) do
      nil ->
        Enum.join(lines, "\n")

      idx ->
        {before, case_and_after} = Enum.split(lines, idx)

        case case_and_after do
          case_lines when is_list(case_lines) and case_lines != [] ->
            {case_header_lines, branches} = split_case_header_lines(case_lines)

            prefix =
              before
              |> trim_layout_line_edges()
              |> Enum.join("\n")
              |> String.trim_trailing()

            {branches_text, remaining_lines} = normalize_case_branches(branches)
            case_expr = build_embedded_case_expr(Enum.join(case_header_lines, "\n"), branches_text)

            trailing =
              remaining_lines
              |> trim_layout_line_edges()
              |> Enum.join("\n")
              |> String.trim_trailing()

            combined =
              if prefix == "" do
                case_expr
              else
                prefix <> "\n" <> case_expr
              end

            if trailing == "" do
              combined
            else
              combined <> "\n" <> trailing
            end

          _ ->
            Enum.join(lines, "\n")
        end
    end
  end

  @spec find_embedded_case_start(lines()) :: non_neg_integer() | nil
  defp find_embedded_case_start(lines) when is_list(lines) do
    Enum.find_value(Enum.with_index(lines), fn {line, idx} ->
      trimmed = String.trim(line)

      cond do
        embedded_case_header_line?(trimmed) and String.contains?(trimmed, " of") ->
          idx

        embedded_case_header_line?(trimmed) ->
          rest = Enum.slice(lines, idx + 1, 40)

          if Enum.any?(rest, fn next_line ->
               t = String.trim(next_line)
               t == "of" or Regex.match?(~r/^of\b/u, t)
             end) do
            idx
          end

        true ->
          nil
      end
    end)
  end

  defp embedded_case_header_line?(trimmed) when is_binary(trimmed) do
    cond do
      let_binding_rhs_case_line?(trimmed) ->
        true

      String.contains?(trimmed, "let ") ->
        false

      flattened_outer_case_line?(trimmed) ->
        false

      Regex.match?(~r/->\s+case\b/u, trimmed) and String.contains?(trimmed, " of") ->
        true

      Regex.match?(~r/,\s*[a-z_][A-Za-z0-9_']*\s*=\s*case\b/u, trimmed) and
          String.contains?(trimmed, " of") ->
        true

      true ->
        Regex.match?(~r/^(?:\(?\s*|\[\s*|,?\s*)?case\b/u, trimmed) or
          Regex.match?(~r/\+\+\s*(?:\(?\s*)?case\b/u, trimmed)
    end
  end

  defp flattened_outer_case_line?(trimmed) when is_binary(trimmed) do
    Regex.match?(~r/\bcase\b[^\n]*\bof\b.*->/u, trimmed)
  end

  @spec trim_layout_line_edges(lines()) :: lines()
  defp trim_layout_line_edges(lines) when is_list(lines) do
    lines
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
  end

  defp let_binding_rhs_case_line?(trimmed) when is_binary(trimmed) do
    Regex.match?(
      ~r/^[a-z_][A-Za-z0-9_']*(?:\s+[a-z_][A-Za-z0-9_']*|\s+_|\s+\([^\)]*\))*\s*=\s*case\b/u,
      trimmed
    )
  end

  @spec split_case_header_lines(lines()) :: {lines(), lines()}
  defp split_case_header_lines([first | rest]) do
    trimmed = String.trim(first)

    if String.contains?(trimmed, " of") do
      {[first], rest}
    else
      case Enum.split_while(rest, fn line ->
             t = String.trim(line)
             t != "of" and not Regex.match?(~r/^of\b/u, t)
           end) do
        {prefix, [of_line | branches]} ->
          {[first | prefix] ++ [of_line], branches}

        {prefix, []} ->
          {[first | prefix], []}
      end
    end
  end

  @spec normalize_case_branches(lines()) :: {source(), lines()}
  defp normalize_case_branches(lines) when is_list(lines) do
    if leading_case_branch_lines?(lines) do
      {items, current, _branch_indent, _let_depth, rest} =
        consume_case_branches(lines, [], nil, nil, 0)

      normalized_items =
        if is_binary(current), do: items ++ [String.trim(current)], else: items

      normalized_items =
        normalized_items
        |> Enum.map(&normalize_nested_case_in_branch/1)
        |> Enum.map(&wrap_branch_case_expression/1)

      {Enum.join(normalized_items, ";;"), rest}
    else
      {Enum.join(lines, "\n"), []}
    end
  end

  defp leading_case_branch_lines?(lines) when is_list(lines) do
    Enum.any?(lines, &case_branch_start_line?/1)
  end

  # Outer case normalization leaves nested `case ... of` bodies as raw multiline
  # text inside a branch RHS. Re-run case normalization so sibling arms like
  # `( Just _, Err _ )` survive when embedded under a large outer arm body.
  @spec normalize_nested_case_in_branch(source()) :: source()
  defp normalize_nested_case_in_branch(branch) when is_binary(branch) do
    case String.split(branch, "->", parts: 2) do
      [pattern, expr] ->
        trimmed = String.trim(expr)
        reflowed = reflow_inline_case_arms(trimmed)

        normalized =
          if reflowed != trimmed do
            reflowed
            |> collapse_layout_newlines_to_spaces()
            |> normalize_case_source()
          else
            normalize_case_source(trimmed)
          end

        String.trim(pattern) <> " -> " <> normalized

      _ ->
        branch
    end
  end

  @spec collapse_layout_newlines_to_spaces(source()) :: source()
  defp collapse_layout_newlines_to_spaces(source) when is_binary(source) do
    source
    |> String.replace(~r/\s*\n\s*/u, " ")
    |> String.replace(~r/\s{2,}/u, " ")
    |> String.trim()
  end

  @spec reflow_inline_case_arms(source()) :: source()
  defp reflow_inline_case_arms(source) when is_binary(source) do
    if String.contains?(source, ";;") and not String.contains?(source, " of\n") do
      source
      |> expand_case_of_to_newline()
      |> split_triple_case_sibling_arms()
      |> Enum.map(&wrap_triple_case_reflow_fragment/1)
      |> Enum.join("\n")
    else
      source
    end
  end

  @spec split_triple_case_sibling_arms(source()) :: [source()]
  defp split_triple_case_sibling_arms(source) when is_binary(source) do
    source
    |> String.split(~r/;;\s*(?=\(\s*[^,()]+\s*,\s*[^,()]+\s*,\s*[^)]+\)\s*->)/u)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(&split_triple_case_wildcard_tail/1)
  end

  # Parenthesize 3-tuple case arm bodies that still contain `;;` so sibling arms
  # are not swallowed by yecc. Only touch triple-case headers/arms — never generic
  # `pattern -> body` lines (nested 2-arm cases must keep their `;;` separators).
  @spec wrap_triple_case_reflow_fragment(source()) :: source()
  defp wrap_triple_case_reflow_fragment(fragment) when is_binary(fragment) do
    fragment
    |> wrap_triple_case_header_first_arm()
    |> wrap_triple_tuple_arm_if_leaking()
  end

  @spec wrap_triple_case_header_first_arm(source()) :: source()
  defp wrap_triple_case_header_first_arm(fragment) when is_binary(fragment) do
    case Regex.run(
           ~r/^(?<prefix>\(?\s*case\s+\(\s*[^)]+\)\s+of\s+)(\(\s*[^,()]+\s*,\s*[^,()]+\s*,\s*[^)]+\)\s*->)\s*(?<body>.*)$/su,
           fragment
         ) do
      [_, prefix, first_arm, body] ->
        prefix <> first_arm <> " " <> wrap_arm_body_if_leaking(body)

      _ ->
        fragment
    end
  end

  @spec wrap_triple_tuple_arm_if_leaking(source()) :: source()
  defp wrap_triple_tuple_arm_if_leaking(fragment) when is_binary(fragment) do
    case Regex.run(
           ~r/^(\(\s*[^,()]+\s*,\s*[^,()]+\s*,\s*[^)]+\)\s*->)\s*(.*)$/su,
           String.trim(fragment)
         ) do
      [_, pattern, body] ->
        pattern <> " " <> wrap_arm_body_if_leaking(body)

      _ ->
        fragment
    end
  end

  @spec wrap_arm_body_if_leaking(source()) :: source()
  defp wrap_arm_body_if_leaking(body) when is_binary(body) do
    trimmed = String.trim(body)

    if arm_body_needs_wrap?(trimmed) do
      "(" <> trimmed <> ")"
    else
      trimmed
    end
  end

  @spec arm_body_needs_wrap?(source()) :: boolean()
  defp arm_body_needs_wrap?(body) when is_binary(body) do
    String.contains?(body, ";;") and
      not (String.starts_with?(body, "(") and paren_balance_outside_string_literals(body) == 0)
  end

  # Pull the triple-case wildcard `_ -> …` off an Err arm fragment. Inner nested
  # cases may also contain `_ ->` arms, so split at the last `;; _ ->` separator.
  @spec split_triple_case_wildcard_tail(source()) :: [source()]
  defp split_triple_case_wildcard_tail(part) when is_binary(part) do
    trimmed = String.trim(part)

    if Regex.match?(~r/^\(\s*[^,()]+\s*,\s*[^,()]+\s*,\s*Err\s+_\s*\)\s*->/u, trimmed) do
      case :binary.matches(part, ";; _ ->") do
        [] ->
          [part]

        [_single] ->
          # Only an inner nested wildcard is present; the outer triple-case
          # wildcard is still on the following layout line without `;;` yet.
          [part]

        matches ->
          {pos, _} = List.last(matches)
          err_part = part |> String.slice(0, pos) |> String.trim()
          wildcard = part |> String.slice(pos + 2, String.length(part)) |> String.trim_leading()
          [err_part, wildcard]
      end
    else
      [part]
    end
  end

  @spec wrap_branch_case_expression(source()) :: source()
  defp wrap_branch_case_expression(branch) when is_binary(branch) do
    case String.split(branch, "->", parts: 2) do
      [pattern, expr] ->
        trimmed_expr = String.trim(expr)

        if branch_rhs_needs_parens?(trimmed_expr) do
          String.trim(pattern) <> " -> (" <> trimmed_expr <> ")"
        else
          branch
        end

      _ ->
        branch
    end
  end

  defp branch_rhs_needs_parens?(expr) when is_binary(expr) do
    trimmed = String.trim(expr)

    already_wrapped =
      String.starts_with?(trimmed, "(") and paren_balance_outside_string_literals(trimmed) == 0

    not already_wrapped and not plain_let_in_arm_body?(trimmed) and
      (String.contains?(expr, ";;") or
         (String.contains?(expr, " case ") and String.contains?(expr, " of ")) or
         let_body_has_glued_sibling_case_arms?(expr))
  end

  defp plain_let_in_arm_body?(expr) when is_binary(expr) do
    Regex.match?(~r/^let\b/su, expr) and String.contains?(expr, " in ") and
      not String.contains?(expr, " case ")
  end

  defp let_body_has_glued_sibling_case_arms?(expr) when is_binary(expr) do
    String.contains?(expr, "let ") and String.contains?(expr, " in ") and
      String.contains?(expr, " case ") and String.contains?(expr, "->")
  end

  @spec build_embedded_case_expr(source(), source()) :: source()
  defp build_embedded_case_expr(case_header, branches_text)
       when is_binary(case_header) and is_binary(branches_text) do
    branches =
      branches_text
      |> String.trim_leading()
      |> String.replace(~r/^;;\s*/, "")

    header = String.trim_trailing(case_header)

    cond do
      Regex.match?(~r/\+\+\s*\(\s*case\b/u, header) ->
        Regex.replace(
          ~r/^(.*\+\+\s*\()\s*case\b(.*)$/su,
          header,
          fn _, before, rest -> before <> "case" <> rest <> " " <> branches <> ")" end
        )

      String.contains?(header, "++ case ") ->
        case String.split(header, "++ case ", parts: 2) do
          [before_append, case_rest] ->
            before_append <> "++ (case " <> case_rest <> " " <> branches <> ")"

          _ ->
            header <> " " <> branches
        end

      Regex.match?(~r/,\s*case\b/u, header) ->
        Regex.replace(
          ~r/^(.*?,\s*)case\b(.*)$/su,
          header,
          fn _, before, rest -> before <> "(case" <> rest <> " " <> branches <> ")" end
        )

      true ->
        header <> " " <> branches
    end
  end

  @spec consume_case_branches(
          lines(),
          [source()],
          source() | nil,
          non_neg_integer() | nil,
          non_neg_integer()
        ) ::
          {[source()], source() | nil, non_neg_integer() | nil, non_neg_integer(), lines()}
  defp consume_case_branches([], acc, current, branch_indent, let_depth),
    do: {acc, current, branch_indent, let_depth, []}

  defp consume_case_branches([line | rest], acc, current, branch_indent, let_depth) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        consume_case_branches(rest, acc, current, branch_indent, let_depth)

      trimmed == ";;" ->
        consume_case_branches(rest, acc, current, branch_indent, let_depth)

      true ->
        consume_case_branches_line(line, rest, acc, current, branch_indent, let_depth)
    end
  end

  defp consume_case_branches_line(line, rest, acc, current, branch_indent, let_depth) do
    indent = leading_indent_count(line)

    starts_branch =
      (case_branch_start_line?(line) and (is_nil(branch_indent) or indent == branch_indent)) or
        orphan_case_arm_separator_line?(line)

    cond do
      is_binary(current) and is_integer(branch_indent) and indent < branch_indent and
          case_branch_wrapper_close_line?(line, current) ->
        flushed = acc ++ [String.trim(current)]
        {flushed, nil, branch_indent, let_depth, [line | rest]}

      is_binary(current) and is_integer(branch_indent) and indent < branch_indent and
          String.starts_with?(String.trim(line), ",") ->
        flushed = acc ++ [String.trim(current)]
        {flushed, nil, branch_indent, let_depth, [line | rest]}

      is_binary(current) and is_integer(branch_indent) and case_branch_start_line?(line) and
          indent < branch_indent and not orphan_case_arm_separator_line?(line) ->
        flushed = acc ++ [String.trim(current)]
        {flushed, nil, branch_indent, let_depth, [line | rest]}

      is_binary(current) and is_integer(branch_indent) and case_branch_start_line?(line) and
          indent > branch_indent ->
        separator =
          if String.ends_with?(String.trim(current), " of") do
            " "
          else
            " ;; "
          end

        updated = current <> separator <> String.trim(line)
        next_depth = next_let_depth(let_depth, line)
        consume_case_branches(rest, acc, updated, branch_indent, next_depth)

      starts_branch ->
        flushed = if is_binary(current), do: acc ++ [String.trim(current)], else: acc
        next_depth = next_let_depth(0, line)

        consume_case_branches(
          rest,
          flushed,
          line |> String.trim() |> strip_leading_case_arm_separator(),
          branch_indent || indent,
          next_depth
        )

      is_binary(current) and let_depth == 0 and case_branch_terminator_line?(line, current) and
          (is_nil(branch_indent) or indent <= branch_indent) and
          not (Regex.match?(~r/^in\b/u, String.trim(line)) and branch_has_open_let?(current)) ->
        {acc, current, branch_indent, let_depth, [line | rest]}

      is_binary(current) and current != "" ->
        line_body = line |> String.trim() |> strip_leading_case_arm_separator()
        updated = current <> " " <> line_body
        next_depth = next_let_depth(let_depth, line)
        consume_case_branches(rest, acc, updated, branch_indent, next_depth)

      true ->
        next_depth = next_let_depth(let_depth, line)
        consume_case_branches(rest, acc, String.trim(line), branch_indent, next_depth)
    end
  end

  @spec leading_indent_count(line()) :: non_neg_integer()
  defp leading_indent_count(line) when is_binary(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == " " or &1 == "\t"))
    |> length()
  end

  @spec indent_in_lines(lines(), non_neg_integer()) :: source()
  defp indent_in_lines(in_lines, base_indent) when is_list(in_lines) do
    in_lines
    |> Enum.map(fn line ->
      line_indent = leading_indent_count(line)

      if line_indent >= base_indent do
        line
      else
        String.duplicate(" ", base_indent) <> String.trim(line)
      end
    end)
    |> Enum.join("\n")
  end

  @spec case_branch_start_line?(line()) :: boolean()
  defp case_branch_start_line?(line) when is_binary(line) do
    trimmed = line |> String.trim() |> strip_leading_case_arm_separator()

    case first_top_level_arrow(trimmed) do
      nil ->
        false

      {before, _} ->
        not String.contains?(before, "\\") and case_arm_lhs?(String.trim(before))
    end
  end

  defp strip_leading_case_arm_separator(line) when is_binary(line) do
    line |> String.replace(~r/^;;+\s*/u, "")
  end

  defp orphan_case_arm_separator_line?(line) when is_binary(line) do
    trimmed = String.trim(line)

    if Regex.match?(~r/^;;+\s+/u, trimmed) do
      stripped = strip_leading_case_arm_separator(trimmed)
      case_branch_start_line?(stripped)
    else
      false
    end
  end

  @spec first_top_level_arrow(source()) :: {source(), source()} | nil
  defp first_top_level_arrow(line) when is_binary(line) do
    case scan_first_top_level_arrow(String.graphemes(line), 0, :code, false, []) do
      {:ok, before, after_arrow} ->
        {String.trim(before), String.trim(after_arrow)}

      :error ->
        nil
    end
  end

  defp scan_first_top_level_arrow([], _depth, _mode, _esc, _before), do: :error

  defp scan_first_top_level_arrow(["-", ">" | rest], 0, :code, false, before) do
    after_arrow = rest |> IO.iodata_to_binary() |> String.trim_leading()
    {:ok, Enum.reverse(before) |> IO.iodata_to_binary(), after_arrow}
  end

  defp scan_first_top_level_arrow(["-", ch | rest], depth, mode, escaped, before),
    do: scan_first_top_level_arrow([ch | rest], depth, mode, escaped, ["-" | before])

  defp scan_first_top_level_arrow([ch | rest], depth, mode, escaped, before) do
    {next_depth, next_mode, next_escaped} =
      case {mode, ch, escaped} do
        {:string, "\"", false} -> {depth, :code, false}
        {:string, _, _} -> {depth, :string, ch == "\\" and not escaped}
        {:char, "'", false} -> {depth, :code, false}
        {:char, _, _} -> {depth, :char, ch == "\\" and not escaped}
        {:code, "\"", _} -> {depth, :string, false}
        {:code, "'", _} -> {depth, :char, false}
        {:code, "(", _} -> {depth + 1, :code, false}
        {:code, "[", _} -> {depth + 1, :code, false}
        {:code, "{", _} -> {depth + 1, :code, false}
        {:code, ")", _} -> {max(depth - 1, 0), :code, false}
        {:code, "]", _} -> {max(depth - 1, 0), :code, false}
        {:code, "}", _} -> {max(depth - 1, 0), :code, false}
        _ -> {depth, mode, false}
      end

    scan_first_top_level_arrow(rest, next_depth, next_mode, next_escaped, [ch | before])
  end

  defp case_arm_lhs?(before) when is_binary(before) do
    trimmed = String.trim(before)

    trimmed != "" and not Regex.match?(~r/\sof\b/u, trimmed) and
      not Regex.match?(~r/^[a-z][A-Za-z0-9_']*\./u, trimmed) and
      Regex.match?(
        ~r/^(?:_|'[^']*'|\"[^\"]*\"|\[\]|0x[0-9A-Fa-f]+|[0-9]+|\{|\(\s*|\(\s*[^)]+\)|[A-Z][A-Za-z0-9_.']*(?:\s+[^=()]+)*|[a-z][A-Za-z0-9_']*(?:\s+[a-z_][A-Za-z0-9_']*)*)/u,
        trimmed
      )
  end

  @spec case_branch_terminator_line?(line(), source() | nil) :: boolean()
  defp case_branch_terminator_line?(line, current) when is_binary(line) do
    trimmed = String.trim(line)

    case_branch_wrapper_close_line?(line, current) or
      (let_binding_start_line?(line) and not String.starts_with?(trimmed, "let ")) or
      Regex.match?(~r/^in\b/u, trimmed)
  end

  defp case_branch_wrapper_close_line?(line, current)
       when is_binary(line) and is_binary(current) do
    if case_branch_close_line?(line) do
      paren_balance_outside_string_literals(current) <= 0
    else
      false
    end
  end

  defp case_branch_wrapper_close_line?(line, _current) when is_binary(line) do
    case_branch_close_line?(line)
  end

  defp case_branch_close_line?(line) when is_binary(line) do
    trimmed = String.trim(line)

    trimmed == ")" or String.starts_with?(trimmed, ")") or
      Regex.match?(~r/^\)\s*[,;]/u, trimmed)
  end

  # True when an `in` line closes a let that is already open in the branch so far.
  defp branch_has_open_let?(branch_text) when is_binary(branch_text) do
    sanitized = strip_quoted_literals_for_keywords(branch_text)
    lets = Regex.scan(~r/\blet\b/u, sanitized) |> length()
    ins = Regex.scan(~r/\bin\b/u, sanitized) |> length()
    lets > ins
  end

  @spec normalize_binding_for_separator(source()) :: source()
  defp normalize_binding_for_separator(binding) when is_binary(binding) do
    binding
    |> wrap_case_binding_rhs_in_parens()
    |> flatten_case_binding_rhs_layout()
  end

  defp wrap_case_binding_rhs_in_parens(binding) when is_binary(binding) do
    if Regex.match?(~r/=\s*case\b/su, binding) and not Regex.match?(~r/=\s*\(case\b/su, binding) do
      case String.split(binding, "=", parts: 2) do
        [lhs, rhs] ->
          String.trim_trailing(lhs) <> " = (" <> String.trim_leading(rhs) <> ")"

        _ ->
          binding
      end
    else
      binding
    end
  end

  defp flatten_case_binding_rhs_layout(binding) when is_binary(binding) do
    case Regex.run(~r/^(?<lhs>.*?=\s*)(?<rhs>\(?case\b.*)$/su, binding) do
      [_, lhs, rhs] ->
        lhs <> normalize_case_source(String.trim(rhs))

      _ ->
        binding
    end
  end
  @spec next_let_depth(non_neg_integer(), line()) :: non_neg_integer()
  defp next_let_depth(current_depth, line) when is_binary(line) do
    sanitized = strip_quoted_literals_for_keywords(line)
    lets = Regex.scan(~r/\blet\b/u, sanitized) |> length()
    ins = Regex.scan(~r/\bin\b/u, sanitized) |> length()
    max(current_depth + lets - ins, 0)
  end

  @spec strip_quoted_literals_for_keywords(source()) :: source()
  defp strip_quoted_literals_for_keywords(line) when is_binary(line) do
    line
    |> String.replace(~r/\"\"\".*?\"\"\"/u, "\"\"")
    |> String.replace(~r/"(?:[^"\\]|\\.)*"/u, "\"\"")
    |> String.replace(~r/'(?:[^'\\]|\\.)*'/u, "''")
  end

  @spec collapse_multiline_if_else_before_in_case(source()) :: source()
  defp collapse_multiline_if_else_before_in_case(source) when is_binary(source) do
    Regex.replace(
      ~r/\bif\b([^\n;]*?)\bthen\s*\n\s*([^\n;]+?)\s*\n\s*else\s*\n\s*([^\n;]+?)\s+in\s+case\b/su,
      source,
      "if\\1then \\2 else \\3\nin case"
    )
  end

  @spec split_arrow_inline_case_headers(source()) :: source()
  defp split_arrow_inline_case_headers(source) when is_binary(source) do
    source |> String.split("\n") |> Enum.flat_map(&split_arrow_inline_case_line/1) |> Enum.join("\n")
  end

  defp split_arrow_inline_case_line(line) when is_binary(line) do
    trimmed = String.trim(line)

    case first_top_level_arrow(trimmed) do
      nil ->
        [line]

      {before, after_arrow} ->
        after_trimmed = String.trim(after_arrow)

        if case_arm_lhs?(String.trim(before)) and
             Regex.match?(~r/^\(?case\b/u, after_trimmed) do
          indent =
            String.slice(line, 0, max(String.length(line) - String.length(String.trim_leading(line)), 0))

          [String.trim_trailing(indent <> String.trim(before) <> " ->"), indent <> after_trimmed]
        else
          [line]
        end
    end
  end

  @spec collapse_let_in_before_case(source()) :: source()
  defp collapse_let_in_before_case(source) when is_binary(source) do
    source
    |> then(&Regex.replace(~r/\bin\s*\n\s*case\b/u, &1, "in case"))
    |> then(&Regex.replace(~r/\bin\s*;;\s*case\b/u, &1, "in case"))
    |> then(&Regex.replace(~r/\bin\)\s*;;\s*case\b/u, &1, "in case"))
    |> then(&Regex.replace(~r/([A-Za-z0-9_\)\]]);;\)/u, &1, "\\1)"))
  end

  @spec normalize_inline_case_arm_bodies(source()) :: source()
  defp normalize_inline_case_arm_bodies(source) when is_binary(source) do
    if inline_flat_case?(source) do
      case Regex.run(~r/^(\s*case\b[^\n;]*\bof\s+)(.+)$/su, source) do
        [_, header, arms_text] ->
          header <>
            (arms_text
             |> split_inline_case_arms()
             |> Enum.map(&normalize_inline_case_arm/1)
             |> Enum.join(";;"))

        _ ->
          source
      end
    else
      source
    end
  end

  defp inline_flat_case?(source) when is_binary(source) do
    String.contains?(source, "case ") and String.contains?(source, " of") and
      String.contains?(source, ";;") and not String.contains?(source, " of\n")
  end

  defp split_inline_case_arms(arms_text) when is_binary(arms_text) do
    split_at_top_level_double_semicolons(arms_text)
  end

  @spec split_at_top_level_double_semicolons(source()) :: [source()]
  defp split_at_top_level_double_semicolons(source) when is_binary(source) do
    {parts, current, _depth, _mode, _escaped, _prev_semi} =
      source
      |> String.graphemes()
      |> Enum.reduce({[], [], 0, :code, false, false}, fn ch,
                                                           {parts, current, depth, mode, escaped,
                                                            prev_semi} ->
        cond do
          mode == :string ->
            next_mode = if not escaped and ch == "\"", do: :code, else: :string
            next_escaped = ch == "\\" and not escaped
            {parts, [ch | current], depth, next_mode, next_escaped, false}

          mode == :char ->
            next_mode = if not escaped and ch == "'", do: :code, else: :char
            next_escaped = ch == "\\" and not escaped
            {parts, [ch | current], depth, next_mode, next_escaped, false}

          ch == "\"" ->
            {parts, [ch | current], depth, :string, false, false}

          ch == "'" ->
            {parts, [ch | current], depth, :char, false, false}

          ch in ["(", "[", "{"] ->
            {parts, [ch | current], depth + 1, :code, false, false}

          ch in [")", "]", "}"] ->
            {parts, [ch | current], max(depth - 1, 0), :code, false, false}

          ch == ";" and depth == 0 ->
            if prev_semi do
              part = current |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()

              flushed_parts =
                if part == "", do: parts, else: parts ++ [part]

              {flushed_parts, [], depth, :code, false, false}
            else
              {parts, current, depth, :code, false, true}
            end

          true ->
            current =
              if prev_semi do
                [ch, ";" | current]
              else
                [ch | current]
              end

            {parts, current, depth, :code, false, false}
        end
      end)

    part = current |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()
    parts = if part == "", do: parts, else: parts ++ [part]
    Enum.reject(parts, &(&1 == ""))
  end

  defp normalize_inline_case_arm(arm) when is_binary(arm) do
    case String.split(arm, "->", parts: 2) do
      [pattern, body] ->
        trimmed_pattern = String.trim(pattern)
        trimmed_body = String.trim(body)

        if renorm_inline_case_arm_body?(trimmed_body) do
          normalize_nested_case_in_branch(trimmed_pattern <> " -> " <> trimmed_body)
          |> case do
            branch ->
              case String.split(branch, "->", parts: 2) do
                [_, expr] -> trimmed_pattern <> " -> " <> String.trim(expr)
                _ -> trimmed_pattern <> " -> " <> trimmed_body
              end
          end
        else
          trimmed_pattern <> " -> " <> trimmed_body
        end

      _ ->
        arm
    end
  end

  defp renorm_inline_case_arm_body?(body) when is_binary(body) do
    not already_flat_case_branch_body?(body)
  end

  defp already_flat_case_branch_body?(body) when is_binary(body) do
    (String.starts_with?(body, "(case ") or Regex.match?(~r/^\(?case\b/u, body)) and
      String.contains?(body, " of") and String.contains?(body, ";;") and
      not String.contains?(body, " of\n")
  end

  @spec insert_glued_inline_case_arm_separators(source()) :: source()
  defp insert_glued_inline_case_arm_separators(source) when is_binary(source) do
    if String.contains?(source, "case ") and String.contains?(source, " of") and
         String.contains?(source, "->") and not String.contains?(source, " of\n") do
      source
      |> String.split("\n")
      |> Enum.map(&insert_glued_inline_case_arm_separators_line/1)
      |> Enum.join("\n")
    else
      source
    end
  end

  defp insert_glued_inline_case_arm_separators_line(line) when is_binary(line) do
    trimmed = String.trim(line)

    cond do
      String.contains?(trimmed, ";;") ->
        line

      not inline_glued_case_line?(trimmed) ->
        line

      true ->
        case Regex.run(~r/^(.*?\sof\s+)(.+)$/su, trimmed) do
          [_, header, arms] ->
            if arms_need_glued_separators?(arms) do
              header <> insert_glued_case_arm_separators(arms)
            else
              line
            end

          _ ->
            line
        end
    end
  end

  defp arms_need_glued_separators?(arms) when is_binary(arms) do
    String.match?(arms, ~r/\bcase\s+\S+\s+of\b/u) or glued_simple_inline_case_arms?(arms)
  end

  defp glued_simple_inline_case_arms?(arms) when is_binary(arms) do
    case first_top_level_arrow(arms) do
      {_, after_first} ->
        case first_top_level_arrow(after_first) do
          {second_lhs, _} ->
            case :binary.match(after_first, second_lhs <> " ->") do
              {pos, _} ->
                between = String.slice(after_first, 0, pos)
                paren_balance_outside_string_literals(between) == 0 and between != ""

              :nomatch ->
                false
            end

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp inline_glued_case_line?(line) when is_binary(line) do
    String.contains?(line, "case ") and String.contains?(line, " of ") and
      String.contains?(line, "->")
  end

  defp insert_glued_case_arm_separators(arms) when is_binary(arms) do
    arms
    |> then(
      &Regex.replace(
        ~r/(\b[A-Z][A-Za-z0-9_']*)\s+(\[(?:[^\]]*\]\s*->))/u,
        &1,
        "\\1 ;; \\2"
      )
    )
    |> then(
      &Regex.replace(
        ~r/(\))(?!\s*;;)\s+(?=(?:_|'|\"|[A-Z][A-Za-z0-9_.']*(?:\s+[a-z_][A-Za-z0-9_']*)*)\s*->)/u,
        &1,
        "\\1 ;; "
      )
    )
    |> then(
      &Regex.replace(
        ~r/(\))(?!\s*;;)\s+(?=\[\s*(?:\"|'|[A-Za-z_][A-Za-z0-9_']*)[^\]]*\]\s*->|\[\s*\]\s*->)/u,
        &1,
        "\\1 ;; "
      )
    )
    |> then(
      &Regex.replace(
        ~r/(\])(?!\s*;;)\s+(?=_\s*->)/u,
        &1,
        "\\1 ;; "
      )
    )
    |> then(
      &Regex.replace(
        ~r/(\})(?!\s*;;)\s+(?=_\s*->)/u,
        &1,
        "\\1 ;; "
      )
    )
    |> then(
      &Regex.replace(
        ~r/(\])(?!\s*;;)\s+(?=[A-Z][A-Za-z0-9_]*(?:\s+[a-z_][A-Za-z0-9_]*)?\s*->)/u,
        &1,
        "\\1 ;; "
      )
    )
    |> then(
      &Regex.replace(
        ~r/(\})(?!\s*;;)\s+(?=[A-Z][A-Za-z0-9_]*(?:\s+[a-z_][A-Za-z0-9_]*)?\s*->)/u,
        &1,
        "\\1 ;; "
      )
    )
    |> then(
      &Regex.replace(
        ~r/(\bnone)(?!\s*;;)\s+(?=(?:Nothing|Just|Err|Ok|True|False|_|'|\"|[A-Z][A-Za-z0-9_.']*(?:\s+[a-z_][A-Za-z0-9_']*)*)\s*->)/u,
        &1,
        "\\1 ;; "
      )
    )
  end

  @spec ensure_inline_case_list_arm_separators(source()) :: source()
  defp ensure_inline_case_list_arm_separators(source) when is_binary(source) do
    if String.contains?(source, "case ") and String.contains?(source, " of") and
         String.contains?(source, "->") and not String.contains?(source, " of\n") do
      Regex.replace(
        ~r/(\bcase\b[^\n;]*\bof\s+)(.+)$/su,
        source,
        fn _, header, arms ->
          header <>
            (arms
             |> then(
               &Regex.replace(
                 ~r/(\b[A-Z][A-Za-z0-9_']*)\s+(\[(?:[^\]]*\]\s*->))/u,
                 &1,
                 "\\1 ;; \\2"
               )
             )
             |> then(
               &Regex.replace(
                 ~r/(\]\s*->\s+(?:Just|Nothing|Err|Ok)\s+[A-Za-z0-9_.']+)(?!\s*;;)(\s+\[)/u,
                 &1,
                 "\\1 ;; \\2"
               )
             )
             |> then(
               &Regex.replace(
                 ~r/(\))(?!\s*;;)\s+(?=\[\s*(?:\"|'|[A-Za-z_][A-Za-z0-9_']*)[^\]]*\]\s*->|\[\s*\]\s*->)/u,
                 &1,
                 "\\1 ;; "
               )
             )
             |> then(
               &Regex.replace(
                 ~r/(\])(?!\s*;;)\s+(?=_\s*->)/u,
                 &1,
                 "\\1 ;; "
               )
             )
             |> then(
               &Regex.replace(
                 ~r/(\])(?!\s*;;)\s+(?=[A-Z][A-Za-z0-9_]*(?:\s+[a-z_][A-Za-z0-9_]*)?\s*->)/u,
                 &1,
                 "\\1 ;; "
               )
             ))
        end
      )
    else
      source
    end
  end

  @spec normalize_inline_case_branch_separators(source()) :: source()
  defp normalize_inline_case_branch_separators(source) when is_binary(source) do
    if String.contains?(source, "case ") and String.contains?(source, " of") and
         not String.contains?(source, " of\n") do
      Regex.replace(
        ~r/(?<!;)(?<!of);\s*(?=(?:True|False|_|'[^']*'|\"[^\"]*\"|0x[0-9A-Fa-f]+|[0-9]+|\(\)|\[\]|\([^)]+\)|\{[^}]+\}|[A-Z][A-Za-z0-9_.']*|[a-z][A-Za-z0-9_']*)\s*->)/u,
        source,
        ";; "
      )
    else
      source
    end
  end

  @spec ensure_triple_case_arm_separators(source()) :: source()
  defp ensure_triple_case_arm_separators(fragment) when is_binary(fragment) do
    fragment
    |> close_nested_case_before_result_err_arm()
    |> then(fn frag ->
      if Regex.match?(~r/case\s+\(\s*[^)]+\)\s+of/u, frag) do
        frag
        |> ensure_triple_case_newline_arm_separators()
        |> then(
          &Regex.replace(
            ~r/(\))(?!\s*;;)\s*(?=\(\s*[^,()]+\s*,\s*[^,()]+\s*,\s*[^)]+\)\s*->)/u,
            &1,
            "\\1 ;; "
          )
        )
        |> then(&Regex.replace(~r/(\))(?!\s*;;)\s*(?=_\s*->)/u, &1, "\\1 ;; "))
      else
        frag
      end
    end)
  end

  @spec close_nested_case_before_result_err_arm(source()) :: source()
  defp close_nested_case_before_result_err_arm(source) when is_binary(source) do
    Regex.replace(
      ~r/(Ok\s*\([^)]+\)\s*->\s*)case\s+([A-Za-z][A-Za-z0-9_']*)\s+of\s+(ActionResponse\b.*?RedirectResponse\b[^;]*)(;;\s*Err\s+_)/su,
      source,
      "\\1((case \\2 of \\3))\\4"
    )
  end

  @spec ensure_triple_case_newline_arm_separators(source()) :: source()
  defp ensure_triple_case_newline_arm_separators(fragment) when is_binary(fragment) do
    fragment
    |> then(
      &Regex.replace(
        ~r/(->\s*[A-Za-z][A-Za-z0-9_']*)\n(?=\(\s*[^,()]+\s*,\s*[^,()]+\s*,\s*[^)]+\)\s*->)/u,
        &1,
        "\\1 ;; "
      )
    )
    |> then(
      &Regex.replace(
        ~r/(\(\s*[^,()]+\s*,\s*[^,()]+\s*,\s*[^)]+\)\s*->\s*[A-Za-z][A-Za-z0-9_']*)\n(?=_\s*->)/u,
        &1,
        "\\1 ;; "
      )
    )
  end

  @spec close_paren_let_before_inner_wildcard_arm(source()) :: source()
  defp close_paren_let_before_inner_wildcard_arm(source) when is_binary(source) do
    # Only close arm-body wraps written as `-> (let … in <non-case body> … ;; _ ->`.
    Regex.replace(
      ~r/(->\s*\(\s*let\b[^;]*\bin\s+(?!case\b)[^)]*?)(\s*;;\s*_\s*->)/u,
      source,
      "\\1)\\2"
    )
  end

  # When `(let outer in case … of …)` is arm-body wrapped, a premature `)` before
  # the inner wildcard arm leaks that wildcard to the outer case. Parenthesized
  # inner lets (`-> (let inner in …) ;; _ ->`) are left alone.
  @spec repair_premature_close_in_let_case_arm(source()) :: source()
  defp repair_premature_close_in_let_case_arm(source) when is_binary(source) do
    layout_record = ~s/Layout\\s*\\{(?:[^{}]|\\{[^{}]*\\})*\\}/

    source
    |> then(
      &Regex.replace(
        ~r/(\(\s*let\b.*?\bin\s+case\b.*?) (->\s+(?:[A-Za-z_(][^;]*?->\s+)?(?:let\b.*?\bin\s+)?#{layout_record})\s*\)(\s*;;\s*_\s*->\s*[^;]+)/su,
        &1,
        "\\1\\2\\3)"
      )
    )
    |> then(
      &Regex.replace(
        ~r/(in case\s+[^;]+?\sof\s+(?:[A-Za-z_(][^;]*?->\s+)?#{layout_record})\s*\)(\s*;;\s*_\s*->\s*Empty)/su,
        &1,
        "\\1\\2)"
      )
    )
  end

  @spec fix_misplaced_in_before_tuple_binding(source()) :: source()
  defp fix_misplaced_in_before_tuple_binding(source) when is_binary(source) do
    Regex.replace(
      ~r/\bin\s+(\(\s*[a-z_][A-Za-z0-9_']*(?:\s*,\s*[a-z_][A-Za-z0-9_']*)+\s*\)\s*=)/u,
      source,
      "in \\1"
    )
  end
end
