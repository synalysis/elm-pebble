defmodule Elmc.Runtime.Generator do
  @moduledoc """
  Emits the reference-counted C runtime used by generated code.
  """

  alias Elmc.Runtime.JsonSections
  alias Elmc.Runtime.Generator.Types
  alias Elmc.Runtime.RcCodes
  alias Elmc.Runtime.RcMacros
  alias Elmc.Runtime.AllocProbe
  alias Elmc.Runtime.AllocTrack
  alias Elmc.Runtime.RcTrack

  @type write_opts :: [prune_from_dir: String.t() | nil, pebble_int32: boolean()]

  @spec write_runtime(String.t(), write_opts()) :: :ok | {:error, Types.file_error()}
  def write_runtime(runtime_dir, opts \\ []) do
    header = runtime_header(opts)
    source = runtime_source(opts)

    {header, source} =
      maybe_prune_runtime(header, source, Keyword.get(opts, :prune_from_dir), opts)

    with :ok <- File.mkdir_p(runtime_dir),
         :ok <- File.write(Path.join(runtime_dir, "elmc_runtime.h"), header),
         :ok <- File.write(Path.join(runtime_dir, "elmc_runtime.c"), source) do
      :ok
    end
  end

  @spec maybe_prune_runtime(Types.runtime_header(), Types.runtime_source(), String.t() | nil, write_opts()) ::
          Types.prune_pair()
  defp maybe_prune_runtime(header, source, prune_from_dir, opts) when is_binary(prune_from_dir) do
    contents = collect_prune_contents(prune_from_dir)

    source =
      source
      |> maybe_drop_unused_compact_list_runtime(contents)

    with refs when map_size(refs) > 0 <- collect_runtime_references(prune_from_dir),
         source <- maybe_drop_float_runtime(source, refs),
         {:ok, defs} <- parse_function_defs(source),
         true <- defs != [] do
      kept_names =
        defs
        |> transitive_keep_set(refs)
        |> drop_pebble_inline_runtime_symbols(opts)

      if MapSet.size(kept_names) > 0 do
        pruned = prune_source(source, defs, kept_names)

        {header,
         pruned
         |> String.trim_trailing()
         |> Kernel.<>("\n\n")
         |> Kernel.<>(RcMacros.fail_stash_source_impl())
         |> Kernel.<>("\n\n#ifndef ELMC_PEBBLE_PLATFORM\n")
         |> Kernel.<>(RcCodes.name_table_source())
         |> Kernel.<>("\n#endif\n")}
      else
        {header, source}
      end
    else
      _ -> {header, source}
    end
  rescue
    _error -> {header, source}
  end

  defp maybe_prune_runtime(header, source, _, _), do: {header, source}

  defp drop_pebble_inline_runtime_symbols(kept_names, _opts) do
    kept_names
    |> MapSet.delete("elmc_rc_name")
    |> drop_host_alloc_track_runtime_symbols()
  end

  defp drop_host_alloc_track_runtime_symbols(kept_names) do
    Enum.reduce(host_alloc_track_runtime_symbols(), kept_names, &MapSet.delete(&2, &1))
  end

  defp host_alloc_track_runtime_symbols do
    [
      "elmc_alloc_track_register",
      "elmc_alloc_track_unregister",
      "elmc_alloc_track_find",
      "elmc_alloc_track_reset",
      "elmc_alloc_track_live_count",
      "elmc_alloc_track_next_alloc_id",
      "elmc_alloc_track_dump_since",
      "elmc_alloc_track_dump_live",
      "elmc_alloc_track_check_balanced",
      "elmc_free_impl"
    ]
  end

  defp maybe_drop_float_runtime(source, refs) when is_map(refs) do
    float_refs =
      MapSet.new([
        "elmc_new_float",
        "elmc_as_float",
        "elmc_string_from_float",
        "elmc_string_to_float",
        "elmc_basics_to_float",
        "elmc_basics_sqrt",
        "elmc_basics_log_base",
        "elmc_basics_sin",
        "elmc_basics_cos",
        "elmc_basics_tan",
        "elmc_basics_acos",
        "elmc_basics_asin",
        "elmc_basics_atan",
        "elmc_basics_atan2",
        "elmc_basics_degrees",
        "elmc_basics_radians",
        "elmc_basics_turns",
        "elmc_basics_is_nan",
        "elmc_basics_is_infinite",
        "elmc_basics_round",
        "elmc_basics_floor",
        "elmc_basics_ceiling",
        "elmc_basics_truncate",
        "elmc_basics_sqrt_double",
        "elmc_basics_sin_double",
        "elmc_basics_cos_double",
        "elmc_basics_tan_double"
      ])

    referenced = refs |> Map.keys() |> MapSet.new()

    if MapSet.disjoint?(referenced, float_refs) do
      source
      |> String.replace(
        """

            case ELMC_TAG_FLOAT:
              return elmc_as_float(left) == elmc_as_float(right);
        """,
        ""
      )
      |> String.replace(
        """
          if (a && b && (a->tag == ELMC_TAG_FLOAT || b->tag == ELMC_TAG_FLOAT)) {
            double fa = elmc_as_float(a);
            double fb = elmc_as_float(b);
            if (fa < fb) {
              ElmcValue *_elmc_rc_out = NULL;
              if (elmc_new_int(&_elmc_rc_out, -1) != RC_SUCCESS) return NULL;
              return _elmc_rc_out;
            }
            if (fa > fb) {
              ElmcValue *_elmc_rc_out = NULL;
              if (elmc_new_int(&_elmc_rc_out, 1) != RC_SUCCESS) return NULL;
              return _elmc_rc_out;
            }
            return elmc_int_zero();
          }
        """,
        ""
      )
    else
      source
    end
  end

  @spec collect_runtime_references(String.t()) :: Types.runtime_ref_map()
  defp collect_runtime_references(dir) do
    contents = collect_prune_contents(dir)

    macros =
      contents
      |> Enum.reduce(%{}, fn content, acc -> Map.merge(acc, preprocessor_bool_macros(content)) end)

    refs =
      Enum.reduce(contents, %{}, fn content, acc ->
        content
        |> runtime_reference_names(macros)
        |> Enum.reduce(acc, fn name, map -> Map.put(map, name, true) end)
      end)

    refs
    |> expand_runtime_prune_refs(contents)
    |> Map.new(fn name -> {name, true} end)
  end

  defp collect_prune_contents(dir) do
    dir
    |> Path.join("**/*.c")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&String.contains?(&1, "/runtime/"))
    |> Enum.flat_map(fn path ->
      case File.read(path) do
        {:ok, content} -> [content]
        _ -> []
      end
    end)
  end

  @doc false
  def compact_list_runtime_prune(source, contents)
      when is_binary(source) and is_list(contents) do
    maybe_drop_unused_compact_list_runtime(source, contents)
  end

  defp maybe_drop_unused_compact_list_runtime(source, contents) when is_list(contents) do
    joined = Enum.join(contents, "\n")

    source
    |> maybe_drop_float_list_runtime(joined)
    |> maybe_drop_record_seq_runtime(joined)
    |> maybe_drop_int_spine_runtime(joined)
  end

  defp maybe_drop_int_spine_runtime(source, joined) do
    if compact_int_spine_used?(joined) do
      source
    else
      source
      |> String.replace(Elmc.Runtime.IntList.spine_implementation(), int_spine_release_stub())
      |> strip_int_spine_release_branches()
    end
  end

  defp int_spine_release_stub do
    """
    /* elmc_int_spine_release_stub */
    static int elmc_int_spine_cell_release(ElmcValue *value) {
      (void)value;
      return 0;
    }

    int elmc_int_spine_is_empty(ElmcValue *list) {
      (void)list;
      return 1;
    }

    RC elmc_int_spine_head_boxed(ElmcValue **out, ElmcValue *list) {
      (void)out;
      (void)list;
      return RC_ERR_INVALID_ARG;
    }

    RC elmc_int_spine_tail(ElmcValue **out, ElmcValue *list) {
      (void)out;
      (void)list;
      return RC_ERR_INVALID_ARG;
    }
    """
  end

  defp compact_int_spine_used?(joined) do
    String.contains?(joined, "ELMC_TAG_INT_SPINE") or
      String.contains?(joined, "elmc_int_spine_") or
      String.contains?(joined, "elmc_int_list_to_spine")
  end

  defp strip_int_spine_release_branches(source) when is_binary(source) do
    source
    |> then(&Regex.replace(int_spine_release_else_branch(), &1, ""))
    |> then(&Regex.replace(int_spine_release_tail_branch(), &1, ""))
  end

  defp int_spine_release_else_branch do
    ~r/\} else if \(value->tag == ELMC_TAG_INT_SPINE\) \{\s*if \(elmc_int_spine_cell_release\(value\)\) \{\s*#if ELMC_RC_TRACK\s*elmc_rc_track_drop_owned\(value\);\s*#endif\s*ELMC_RELEASED \+= 1;\s*return;\s*\}\s*/s
  end

  defp int_spine_release_tail_branch do
    ~r/if \(value->tag == ELMC_TAG_INT_SPINE && elmc_int_spine_cell_release\(value\)\) \{\s*#if ELMC_RC_TRACK\s*elmc_rc_track_drop_owned\(value\);\s*#endif\s*ELMC_RELEASED \+= 1;\s*return;\s*\}/s
  end

  defp maybe_drop_float_list_runtime(source, joined) do
    if compact_float_list_used?(joined) do
      source
    else
      source
      |> String.replace(Elmc.Runtime.FloatList.implementation(), float_list_release_stub())
      |> strip_float_list_release_branches()
    end
  end

  defp maybe_drop_record_seq_runtime(source, joined) do
    if compact_record_seq_used?(joined) do
      source
    else
      source
      |> String.replace(Elmc.Runtime.RecordSeq.implementation(), record_seq_release_stub())
      |> strip_record_seq_release_branches()
      |> strip_record_seq_list_branches()
    end
  end

  defp float_list_release_stub do
    """
    /* elmc_float_list_release_stub */
    static int elmc_float_list_cell_release(ElmcValue *value) {
      (void)value;
      return 0;
    }
    """
  end

  defp record_seq_release_stub do
    """
    /* elmc_record_seq_release_stub */
    static int elmc_record_seq_cell_release(ElmcValue *value) {
      (void)value;
      return 0;
    }
    """
  end

  defp compact_float_list_used?(joined) do
    String.contains?(joined, "ELMC_TAG_FLOAT_LIST") or
      String.contains?(joined, "elmc_list_from_float_array") or
      String.contains?(joined, "elmc_float_list_")
  end

  defp compact_record_seq_used?(joined) do
    String.contains?(joined, "ELMC_TAG_RECORD_SEQ") or
      String.contains?(joined, "elmc_list_from_record_array") or
      String.contains?(joined, "elmc_record_seq_")
  end

  defp strip_float_list_release_branches(source) when is_binary(source) do
    source
    |> then(&Regex.replace(float_list_release_else_branch(), &1, ""))
    |> then(&Regex.replace(float_list_release_tail_branch(), &1, ""))
  end

  defp strip_record_seq_release_branches(source) when is_binary(source) do
    source
    |> then(&Regex.replace(record_seq_release_else_branch(), &1, ""))
    |> then(&Regex.replace(record_seq_release_tail_branch(), &1, ""))
  end

  defp strip_record_seq_list_branches(source) when is_binary(source) do
    source
    |> then(&Regex.replace(record_seq_materialize_cons_branch(), &1, ""))
    |> then(&Regex.replace(record_seq_list_head_branch(), &1, ""))
    |> then(&Regex.replace(record_seq_list_filter_branch(), &1, ""))
    |> String.replace(
      "if (items && (items->tag == ELMC_TAG_INT_LIST || items->tag == ELMC_TAG_RECORD_SEQ)) {",
      "if (items && items->tag == ELMC_TAG_INT_LIST) {"
    )
  end

  defp record_seq_materialize_cons_branch do
    ~r/\s*if \(list && list->tag == ELMC_TAG_RECORD_SEQ\) \{\s*return elmc_record_seq_to_cons\(out, list\);\s*\}\s*/s
  end

  defp record_seq_list_head_branch do
    ~r/\s*if \(list && list->tag == ELMC_TAG_RECORD_SEQ\) \{\s*if \(elmc_record_seq_is_empty\(list\)\) return elmc_maybe_nothing\(\);\s*\{\s*ElmcValue \*head = elmc_record_seq_get\(list, 0\);\s*ElmcValue \*_elmc_rc_out = NULL;\s*if \(elmc_maybe_just\(&_elmc_rc_out, head\) != RC_SUCCESS\) return NULL;\s*return _elmc_rc_out;\s*\}\s*\}\s*/s
  end

  defp record_seq_list_filter_branch do
    ~r/\s*if \(list && list->tag == ELMC_TAG_RECORD_SEQ\) \{\s*rc = elmc_list_materialize_cons\(&cursor, list\);\s*CHECK_RC\(rc\);\s*owned = cursor;\s*\}\s*/s
  end

  defp float_list_release_else_branch do
    ~r/\} else if \(value->tag == ELMC_TAG_FLOAT_LIST\) \{\s*if \(elmc_float_list_cell_release\(value\)\) \{\s*#if ELMC_RC_TRACK\s*elmc_rc_track_drop_owned\(value\);\s*#endif\s*ELMC_RELEASED \+= 1;\s*return;\s*\}\s*/s
  end

  defp float_list_release_tail_branch do
    ~r/if \(value->tag == ELMC_TAG_FLOAT_LIST && elmc_float_list_cell_release\(value\)\) \{\s*#if ELMC_RC_TRACK\s*elmc_rc_track_drop_owned\(value\);\s*#endif\s*ELMC_RELEASED \+= 1;\s*return;\s*\}/s
  end

  defp record_seq_release_else_branch do
    ~r/\} else if \(value->tag == ELMC_TAG_RECORD_SEQ\) \{\s*if \(elmc_record_seq_cell_release\(value\)\) \{\s*#if ELMC_RC_TRACK\s*elmc_rc_track_drop_owned\(value\);\s*#endif\s*ELMC_RELEASED \+= 1;\s*return;\s*\}\s*/s
  end

  defp record_seq_release_tail_branch do
    ~r/if \(value->tag == ELMC_TAG_RECORD_SEQ && elmc_record_seq_cell_release\(value\)\) \{\s*#if ELMC_RC_TRACK\s*elmc_rc_track_drop_owned\(value\);\s*#endif\s*ELMC_RELEASED \+= 1;\s*return;\s*\}/s
  end

  @spec expand_runtime_prune_refs(Types.runtime_ref_map(), [String.t()]) :: [String.t()]
  defp expand_runtime_prune_refs(refs, contents) do
    seeds = Map.keys(refs)

    expanded =
      seeds
      |> Enum.flat_map(&expand_runtime_prune_ref/1)
      |> Enum.uniq()

    maybe_seed_rc_prune_refs(expanded, contents)
    |> maybe_seed_speaker_serialize_refs(contents)
  end

  defp maybe_seed_speaker_serialize_refs(expanded, contents) do
    joined = Enum.join(contents, "\n")

    if String.contains?(joined, "elmc_serialize_speaker_note") do
      (expanded ++
         [
           "elmc_record_get",
           "elmc_record_get_at",
           "elmc_record_get_int",
           "elmc_record_get_at_int",
           "elmc_as_int"
         ])
      |> Enum.uniq()
    else
      expanded
    end
  end

  defp maybe_seed_rc_prune_refs(expanded, contents) do
    joined = Enum.join(contents, "\n")

    extras =
      []
      |> maybe_seed_rc_ref(joined, "elmc_rc_name(", "elmc_rc_name")
      |> maybe_seed_rc_ref(joined, "elmc_rc_allocated_count(", "elmc_rc_allocated_count")
      |> maybe_seed_rc_ref(joined, "elmc_rc_released_count(", "elmc_rc_released_count")
      |> maybe_seed_rc_ref(joined, "ELMC_WORKER_LOG_RC_FAIL", "elmc_rc_name")
      |> maybe_seed_rc_ref(joined, "elmc_malloc(", "elmc_malloc_impl")
      |> maybe_seed_rc_ref(joined, "elmc_calloc(", "elmc_calloc_impl")

    (expanded ++ extras) |> Enum.uniq()
  end

  defp maybe_seed_rc_ref(extras, joined, needle, name) do
    if String.contains?(joined, needle), do: extras ++ [name], else: extras
  end

  @spec expand_runtime_prune_ref(String.t()) :: [String.t()]
  defp expand_runtime_prune_ref(name) do
    cond do
      String.ends_with?(name, "_take_value") ->
        stem = trim_suffix(name, "_take_value")
        [name, stem <> "_take", stem]

      String.ends_with?(name, "_take") ->
        stem = trim_suffix(name, "_take")
        [name, stem]

      true ->
        [name]
    end
  end

  @spec preprocessor_bool_macros(String.t()) :: %{String.t() => boolean()}
  defp preprocessor_bool_macros(content) do
    ~r/^\s*#define\s+(ELMC_[A-Z0-9_]+)\s+([01])\b/m
    |> Regex.scan(content)
    |> Map.new(fn [_match, name, value] -> {name, value == "1"} end)
  end

  @spec runtime_reference_names(String.t(), %{String.t() => boolean()}) :: [String.t()]
  defp runtime_reference_names(content, macros) do
    content
    |> drop_inactive_preprocessor_blocks(macros)
    |> runtime_reference_names()
  end

  @spec drop_inactive_preprocessor_blocks(String.t(), %{String.t() => boolean()}) :: String.t()
  defp drop_inactive_preprocessor_blocks(content, macros) do
    content
    |> String.split("\n", trim: false)
    |> Enum.reduce({[], [%{parent: true, active: true, matched: false}]}, fn line, {out, stack} ->
      case preprocessor_directive(line) do
        {:if, expr} ->
          parent = List.first(stack).active
          active = parent and preprocessor_expr_true?(expr, macros)
          {out, [%{parent: parent, active: active, matched: active} | stack]}

        {:ifdef, macro} ->
          parent = List.first(stack).active
          active = parent and Map.get(macros, macro, false)
          {out, [%{parent: parent, active: active, matched: active} | stack]}

        {:ifndef, macro} ->
          parent = List.first(stack).active
          active = parent and not Map.get(macros, macro, false)
          {out, [%{parent: parent, active: active, matched: active} | stack]}

        {:elif, expr} ->
          case stack do
            [current | rest] ->
              active =
                current.parent and not current.matched and preprocessor_expr_true?(expr, macros)

              {out, [%{current | active: active, matched: current.matched or active} | rest]}

            [] ->
              {out, stack}
          end

        :else ->
          case stack do
            [current | rest] ->
              active = current.parent and not current.matched
              {out, [%{current | active: active, matched: true} | rest]}

            [] ->
              {out, stack}
          end

        :endif ->
          case stack do
            [_current | rest] when rest != [] -> {out, rest}
            _ -> {out, stack}
          end

        nil ->
          if List.first(stack).active do
            {[line | out], stack}
          else
            {out, stack}
          end
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp preprocessor_directive(line) do
    cond do
      match = Regex.run(~r/^\s*#if\s+(.+)$/, line) ->
        {:if, Enum.at(match, 1)}

      match = Regex.run(~r/^\s*#ifdef\s+([A-Za-z_][A-Za-z0-9_]*)/, line) ->
        {:ifdef, Enum.at(match, 1)}

      match = Regex.run(~r/^\s*#ifndef\s+([A-Za-z_][A-Za-z0-9_]*)/, line) ->
        {:ifndef, Enum.at(match, 1)}

      match = Regex.run(~r/^\s*#elif\s+(.+)$/, line) ->
        {:elif, Enum.at(match, 1)}

      Regex.match?(~r/^\s*#else\b/, line) ->
        :else

      Regex.match?(~r/^\s*#endif\b/, line) ->
        :endif

      true ->
        nil
    end
  end

  defp preprocessor_expr_true?(expr, macros) do
    expr
    |> then(fn expr ->
      Regex.replace(~r/defined\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)/, expr, fn _, macro ->
        if Map.get(macros, macro, false), do: "1", else: "0"
      end)
    end)
    |> then(fn expr ->
      Regex.replace(~r/\b[A-Za-z_][A-Za-z0-9_]*\b/, expr, fn macro ->
        if Map.get(macros, macro, false), do: "1", else: "0"
      end)
    end)
    |> eval_preprocessor_or()
  end

  defp eval_preprocessor_or(expr) do
    expr
    |> String.split("||")
    |> Enum.any?(fn part ->
      part
      |> String.split("&&")
      |> Enum.all?(fn term ->
        term = String.trim(term)

        cond do
          String.starts_with?(term, "!") ->
            not term_truthy?(String.trim_leading(term, "!"))

          true ->
            term_truthy?(term)
        end
      end)
    end)
  end

  defp term_truthy?(term) do
    term =
      term
      |> String.replace(~r/[()]/, "")
      |> String.trim()

    case Integer.parse(term) do
      {0, _} -> false
      {_value, _} -> true
      :error -> false
    end
  end

  @spec runtime_reference_names(String.t()) :: [String.t()]
  defp runtime_reference_names(content) do
    direct =
      Regex.scan(~r/\belmc_[A-Za-z0-9_]+\b/, content)
      |> Enum.map(&hd/1)

    macro_derived =
      [
        {"ELMC_RECORD_GET_INDEX_BOOL", "elmc_as_bool"},
        {"ELMC_RECORD_GET_INDEX_FLOAT", "elmc_as_float"},
        {"ELMC_RECORD_GET_INDEX_INT", "elmc_as_int_number"}
      ]
      |> Enum.flat_map(fn {macro, fn_name} ->
        if String.contains?(content, macro), do: [fn_name], else: []
      end)

    Enum.uniq(direct ++ macro_derived)
  end

  @spec parse_function_defs(Types.runtime_source()) :: {:ok, [Types.function_def()]}
  defp parse_function_defs(source) do
    line_starts = line_start_offsets(source)
    lines = String.split(source, "\n", trim: false)

    defs =
      lines
      |> Enum.with_index()
      |> Enum.reduce([], fn {line, idx}, acc ->
        case Regex.run(
               ~r/^\s*(?:static\s+)?[A-Za-z_][A-Za-z0-9_\s\*]*\**\s*(elmc_[A-Za-z0-9_]+)\s*\(/,
               line
             ) do
          [_, name] ->
            case Enum.at(line_starts, idx) do
              line_start when is_integer(line_start) ->
                case find_function_body_start(source, line_start, name) do
                  {:ok, brace_idx} ->
                    case find_matching_brace(source, brace_idx) do
                      {:ok, end_idx} ->
                        body = binary_part(source, line_start, end_idx - line_start + 1)

                        [%{name: name, start_idx: line_start, end_idx: end_idx, body: body} | acc]

                      _ ->
                        acc
                    end

                  _ ->
                    acc
                end

              _ ->
                acc
            end

          _ ->
            acc
        end
      end)
      |> Enum.reverse()

    {:ok, defs}
  end

  @spec line_start_offsets(Types.runtime_source()) :: Types.line_offsets()
  defp line_start_offsets(source) do
    {_offset, starts} =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce({0, []}, fn line, {offset, acc} ->
        next = offset + byte_size(line) + 1
        {next, [offset | acc]}
      end)

    Enum.reverse(starts)
  end

  @spec find_function_body_start(Types.runtime_source(), non_neg_integer(), String.t()) ::
          {:ok, non_neg_integer()} | :error
  defp find_function_body_start(source, line_start, name) when is_integer(line_start) do
    marker = name <> "("
    suffix = binary_part(source, line_start, byte_size(source) - line_start)

    case :binary.match(suffix, marker) do
      {rel_idx, _} ->
        paren_open_idx = line_start + rel_idx
        param_start = paren_open_idx + byte_size(marker)

        with {:ok, close_idx} <- find_closing_paren(source, param_start, byte_size(source), 1),
             {:ok, brace_idx} <- skip_to_open_brace(source, close_idx + 1, byte_size(source)) do
          {:ok, brace_idx}
        else
          _ -> :error
        end

      :nomatch ->
        :error
    end
  end

  @spec find_closing_paren(Types.runtime_source(), non_neg_integer(), non_neg_integer(), pos_integer()) ::
          {:ok, non_neg_integer()} | :error
  defp find_closing_paren(_source, idx, limit, _depth) when idx >= limit, do: :error

  defp find_closing_paren(source, idx, limit, depth) do
    ch = :binary.at(source, idx)

    cond do
      ch == ?( ->
        find_closing_paren(source, idx + 1, limit, depth + 1)

      ch == ?) and depth == 1 ->
        {:ok, idx}

      ch == ?) ->
        find_closing_paren(source, idx + 1, limit, depth - 1)

      true ->
        find_closing_paren(source, idx + 1, limit, depth)
    end
  end

  @spec skip_to_open_brace(Types.runtime_source(), non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | :error
  defp skip_to_open_brace(_source, idx, limit) when idx >= limit, do: :error

  defp skip_to_open_brace(source, idx, limit) do
    ch = :binary.at(source, idx)

    cond do
      ch in [?\s, ?\t, ?\n, ?\r] ->
        skip_to_open_brace(source, idx + 1, limit)

      ch == ?{ ->
        {:ok, idx}

      true ->
        :error
    end
  end

  @spec find_matching_brace(Types.runtime_source(), non_neg_integer()) :: Types.brace_result()
  defp find_matching_brace(source, open_idx) do
    do_find_matching_brace(source, open_idx, byte_size(source), 0)
  end

  @spec do_find_matching_brace(
          Types.runtime_source(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          Types.brace_result()
  defp do_find_matching_brace(_source, idx, source_size, _depth) when idx >= source_size,
    do: {:error, :unbalanced_braces}

  defp do_find_matching_brace(source, idx, source_size, depth) do
    ch = :binary.at(source, idx)

    cond do
      ch == ?{ ->
        do_find_matching_brace(source, idx + 1, source_size, depth + 1)

      ch == ?} and depth == 1 ->
        {:ok, idx}

      ch == ?} and depth > 0 ->
        do_find_matching_brace(source, idx + 1, source_size, depth - 1)

      true ->
        do_find_matching_brace(source, idx + 1, source_size, depth)
    end
  end

  @spec transitive_keep_set([Types.function_def()], Types.runtime_ref_map()) :: Types.keep_set()
  defp transitive_keep_set(defs, refs) do
    def_map = Map.new(defs, &{&1.name, &1.body})
    def_names = Map.keys(def_map) |> MapSet.new()

    seed =
      refs
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.intersection(def_names)

    walk_keep(seed, MapSet.to_list(seed), def_map)
  end

  @spec walk_keep(Types.keep_set(), [String.t()], Types.def_map()) :: Types.keep_set()
  defp walk_keep(seen, [], _def_map), do: seen

  defp walk_keep(seen, frontier, def_map) do
    next =
      frontier
      |> Enum.flat_map(fn name ->
        case Map.get(def_map, name) do
          nil ->
            []

          body ->
            called_functions(body, def_map)
        end
      end)
      |> Enum.reduce(MapSet.new(), fn name, acc ->
        if MapSet.member?(seen, name), do: acc, else: MapSet.put(acc, name)
      end)

    walk_keep(MapSet.union(seen, next), MapSet.to_list(next), def_map)
  end

  @spec called_functions(Types.runtime_source(), Types.def_map()) :: [String.t()]
  defp called_functions(body, def_map) when is_binary(body) do
    Regex.scan(~r/\b([A-Za-z_][A-Za-z0-9_]*)\s*\(/, body)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.flat_map(&runtime_call_dependencies/1)
    |> Enum.filter(&Map.has_key?(def_map, &1))
    |> Enum.uniq()
  end

  defp called_functions(_, _), do: []

  defp runtime_call_dependencies("elmc_alloc"),
    do: ["elmc_alloc", "elmc_alloc_impl", "elmc_malloc_impl", "elmc_log_alloc_failed"]

  defp runtime_call_dependencies("elmc_malloc"),
    do: ["elmc_malloc", "elmc_malloc_impl", "elmc_log_alloc_failed"]

  defp runtime_call_dependencies("elmc_calloc"),
    do: ["elmc_calloc", "elmc_calloc_impl", "elmc_log_alloc_failed"]

  defp runtime_call_dependencies("elmc_realloc"),
    do: ["elmc_realloc", "elmc_realloc_impl", "elmc_log_alloc_failed"]

  defp runtime_call_dependencies("elmc_closure_new"),
    do: ["elmc_closure_new", "elmc_closure_cell_init", "elmc_malloc", "elmc_retain"]

  defp runtime_call_dependencies("elmc_closure_new_rc"),
    do: ["elmc_closure_new_rc", "elmc_closure_cell_init", "elmc_malloc", "elmc_retain"]

  defp runtime_call_dependencies(name) do
    [name | runtime_take_dependency(name)]
  end

  defp trim_suffix(string, suffix) when is_binary(string) and is_binary(suffix) do
    suffix_size = byte_size(suffix)

    if byte_size(string) >= suffix_size and binary_part(string, byte_size(string) - suffix_size, suffix_size) == suffix do
      binary_part(string, 0, byte_size(string) - suffix_size)
    else
      string
    end
  end

  defp runtime_take_dependency(name) do
    cond do
      String.ends_with?(name, "_take_value") ->
        stem = trim_suffix(name, "_take_value")
        [stem <> "_take", stem]

      String.ends_with?(name, "_take") ->
        [trim_suffix(name, "_take")]

      true ->
        []
    end
  end

  @spec prune_source(Types.runtime_source(), [Types.function_def()], Types.keep_set()) ::
          Types.runtime_source()
  defp prune_source(source, defs, kept_names) do
    kept_names =
      MapSet.reject(kept_names, fn name ->
        String.starts_with?(name, "elmc_rc_track_")
      end)

    first_start =
      case defs do
        [%{start_idx: idx} | _] -> idx
        _ -> byte_size(source)
      end

    preamble =
      source
      |> binary_part(0, first_start)
      |> maybe_drop_process_globals(kept_names)
      |> maybe_drop_unit_global(kept_names)
      |> maybe_drop_unused_forward_decls(kept_names, defs)

    kept_bodies =
      defs
      |> Enum.filter(&MapSet.member?(kept_names, &1.name))
      |> Enum.map(fn %{start_idx: s, end_idx: e} ->
        binary_part(source, s, e - s + 1)
      end)
      |> Enum.join("\n\n")

    preamble <> kept_bodies <> "\n"
  end

  @spec maybe_drop_unused_forward_decls(Types.runtime_source(), Types.keep_set(), [
          Types.function_def()
        ]) :: Types.runtime_source()
  defp maybe_drop_unused_forward_decls(preamble, kept_names, defs) do
    pruned_names =
      defs
      |> Enum.map(& &1.name)
      |> MapSet.new()
      |> MapSet.difference(kept_names)

    Enum.reduce(pruned_names, preamble, fn name, acc ->
      Regex.replace(
        ~r/^\s*static\s+.*\b#{Regex.escape(name)}\b\s*\([^;]*\)\s*;\s*$/m,
        acc,
        ""
      )
    end)
  end

  @spec maybe_drop_process_globals(Types.runtime_source(), Types.keep_set()) ::
          Types.runtime_source()
  defp maybe_drop_process_globals(preamble, kept_names) do
    process_api =
      MapSet.new([
        "elmc_process_spawn",
        "elmc_process_sleep",
        "elmc_process_kill"
      ])

    if MapSet.disjoint?(kept_names, process_api) do
      preamble
      |> then(&Regex.replace(~r/^static int64_t ELMC_NEXT_PROCESS_ID = 1;\s*$/m, &1, ""))
      |> then(
        &Regex.replace(
          ~r/^static ElmcProcessSlot ELMC_PROCESS_SLOTS\[ELMC_PROCESS_MAX_SLOTS\];\s*$/m,
          &1,
          ""
        )
      )
    else
      preamble
    end
  end

  @spec maybe_drop_unit_global(Types.runtime_source(), Types.keep_set()) :: Types.runtime_source()
  defp maybe_drop_unit_global(preamble, kept_names) do
    if MapSet.member?(kept_names, "elmc_unit") do
      preamble
    else
      Regex.replace(
        ~r/^static ElmcValue ELMC_UNIT = \{ ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, ELMC_UNIT_SCALAR \};\s*$/m,
        preamble,
        ""
      )
    end
  end

  @spec runtime_header(write_opts()) :: String.t()
  defp runtime_header(opts) do
    {small_min, small_max} = small_int_bounds(opts)

    int32_define =
      if Keyword.get(opts, :pebble_int32, false), do: "#define ELMC_PEBBLE_INT32 1\n", else: ""

    """
    #ifndef ELMC_RUNTIME_H
    #define ELMC_RUNTIME_H

    #include <stdint.h>
    #include <stddef.h>
    #include <stdbool.h>
    #include <stdlib.h>
    #{int32_define}

    #if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
    #ifndef ELMC_PEBBLE_PLATFORM
    #define ELMC_PEBBLE_PLATFORM 1
    #endif
    #include <pebble.h>
    #endif

    #if defined(ELMC_PEBBLE_INT32) || defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
    typedef int32_t elmc_int_t;
    #else
    typedef int64_t elmc_int_t;
    #endif

    typedef enum {
      ELMC_TAG_INT = 1,
      ELMC_TAG_BOOL = 2,
      ELMC_TAG_STRING = 3,
      ELMC_TAG_LIST = 4,
      ELMC_TAG_RESULT = 5,
      ELMC_TAG_MAYBE = 6,
      ELMC_TAG_TUPLE2 = 7,
      ELMC_TAG_CHAR = 8,
      ELMC_TAG_PORT_PAYLOAD = 9,
      ELMC_TAG_FLOAT = 10,
      ELMC_TAG_RECORD = 11,
      ELMC_TAG_CLOSURE = 12,
      ELMC_TAG_FORWARD_REF = 13,
      ELMC_TAG_CMD = 14,
      ELMC_TAG_SUB = 15,
      ELMC_TAG_ORDER = 16,
      ELMC_TAG_INT_LIST = 17,
      ELMC_TAG_INT_SPINE = 18,
      ELMC_TAG_RECORD_SEQ = 19,
      ELMC_TAG_FLOAT_LIST = 20
    } ElmcTag;

    typedef struct ElmcValue {
      uint16_t rc;
      uint8_t tag;
      void *payload;
      elmc_int_t scalar;
    } ElmcValue;

    typedef struct ElmcCons {
      ElmcValue *head;
      ElmcValue *tail;
    } ElmcCons;

    #{Elmc.Runtime.IntList.header_types()}
    #{Elmc.Runtime.FloatList.header_types()}

    #ifndef ELMC_RC_IMMORTAL
    #define ELMC_RC_IMMORTAL UINT16_MAX
    #endif
    #ifndef ELMC_LIST_CELL_SCALAR
    #define ELMC_LIST_CELL_SCALAR ((elmc_int_t)0x1EC011)
    #endif
    #ifndef ELMC_DICT_SCALAR
    #define ELMC_DICT_SCALAR ((elmc_int_t)0x1EC012)
    #endif

    #define ELMC_SMALL_INT_MIN (#{small_min})
    #define ELMC_SMALL_INT_MAX #{small_max}
    extern const ElmcValue ELMC_SMALL_INTS[ELMC_SMALL_INT_MAX - ELMC_SMALL_INT_MIN + 1];
    extern ElmcValue ELMC_LIST_NIL;
    #define ELMC_STATIC_INT(n) ((ElmcValue *)&ELMC_SMALL_INTS[(n) - ELMC_SMALL_INT_MIN])
    #define ELMC_STATIC_LIST_NIL (&ELMC_LIST_NIL)

    typedef struct ElmcTuple2 {
      ElmcValue *first;
      ElmcValue *second;
    } ElmcTuple2;

    typedef struct ElmcCmdPayload {
      uint8_t arity;
      elmc_int_t kind;
      elmc_int_t p0;
      elmc_int_t p1;
      elmc_int_t p2;
      elmc_int_t p3;
      elmc_int_t p4;
      elmc_int_t p5;
      ElmcValue *text;
    } ElmcCmdPayload;

    typedef struct ElmcSubPayload {
      uint8_t arity;
      elmc_int_t mask;
      elmc_int_t p0;
      elmc_int_t p1;
      elmc_int_t p2;
      elmc_int_t p3;
      elmc_int_t p4;
      elmc_int_t p5;
    } ElmcSubPayload;

    typedef struct ElmcResult {
      int is_ok;
      ElmcValue *value;
    } ElmcResult;

    typedef struct ElmcMaybe {
      int is_just;
      ElmcValue *value;
    } ElmcMaybe;

    typedef struct ElmcRecord {
      int field_count;
      uint32_t mutation_gen;
      ElmcValue **field_values;
    } ElmcRecord;

    #define ELMC_RECORD_GET_INDEX(record, index) \\
      (((record) && (record)->tag == ELMC_TAG_RECORD && (record)->payload && \\
        (index) >= 0 && (index) < ((ElmcRecord *)(record)->payload)->field_count) ? \\
       ((ElmcRecord *)(record)->payload)->field_values[(index)] : elmc_int_zero())

    #define ELMC_RECORD_GET_INDEX_INT(record, index) \\
      (((record) && (record)->tag == ELMC_TAG_RECORD && (record)->payload && \\
        (index) >= 0 && (index) < ((ElmcRecord *)(record)->payload)->field_count) ? \\
       elmc_as_int_number(((ElmcRecord *)(record)->payload)->field_values[(index)]) : 0)

    #define ELMC_RECORD_GET_INDEX_FLOAT(record, index) \\
      (((record) && (record)->tag == ELMC_TAG_RECORD && (record)->payload && \\
        (index) >= 0 && (index) < ((ElmcRecord *)(record)->payload)->field_count) ? \\
       elmc_as_float(((ElmcRecord *)(record)->payload)->field_values[(index)]) : 0.0)

    #define ELMC_RECORD_GET_INDEX_BOOL(record, index) \\
      (((record) && (record)->tag == ELMC_TAG_RECORD && (record)->payload && \\
        (index) >= 0 && (index) < ((ElmcRecord *)(record)->payload)->field_count) ? \\
       elmc_as_bool(((ElmcRecord *)(record)->payload)->field_values[(index)]) : 0)

    typedef void (*ElmcPortCallback)(ElmcValue *value, void *context);

    #{RcMacros.header_declarations()}

    typedef struct ElmcClosure {
      ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count);
      RC (*rc_fn)(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count);
      int arity;
      int capture_count;
      int is_rc;
      ElmcValue **captures;
    } ElmcClosure;

    RC elmc_new_int(ElmcValue **out, elmc_int_t value);
    RC elmc_new_bool(ElmcValue **out, int value);
    ElmcValue *elmc_new_char(elmc_int_t value);
    ElmcValue *elmc_char_from_code(ElmcValue *code);
    ElmcValue *elmc_char_from_code_int(elmc_int_t code);
    RC elmc_new_order(ElmcValue **out, elmc_int_t value);
    RC elmc_new_string(ElmcValue **out, const char *value);
    RC elmc_new_string_len(ElmcValue **out, const char *value, size_t len);
    ElmcValue *elmc_int_zero(void);
    ElmcValue *elmc_unit(void);
    ElmcValue *elmc_list_nil(void);
    RC elmc_list_cons(ElmcValue **out, ElmcValue *head, ElmcValue *tail);
    ElmcValue *elmc_list_cons_take(ElmcValue *head, ElmcValue *tail);
    RC elmc_list_from_values(ElmcValue **out, ElmcValue **items, int count);
    RC elmc_list_from_values_take(ElmcValue **out, ElmcValue **items, int count);
    int elmc_int_list_is_empty(ElmcValue *list);
    RC elmc_int_list_head_boxed(ElmcValue **out, ElmcValue *list);
    RC elmc_int_list_tail(ElmcValue **out, ElmcValue *list);
    int elmc_float_list_is_empty(ElmcValue *list);
    RC elmc_float_list_head_boxed(ElmcValue **out, ElmcValue *list);
    RC elmc_float_list_tail(ElmcValue **out, ElmcValue *list);
    int elmc_record_seq_is_empty(ElmcValue *list);
    int elmc_record_seq_length(ElmcValue *list);
    ElmcValue *elmc_record_seq_get(ElmcValue *list, elmc_int_t index);
    RC elmc_record_seq_head_boxed(ElmcValue **out, ElmcValue *list);
    RC elmc_record_seq_tail(ElmcValue **out, ElmcValue *list);
    int elmc_int_spine_is_empty(ElmcValue *list);
    RC elmc_int_spine_head_boxed(ElmcValue **out, ElmcValue *list);
    RC elmc_int_spine_tail(ElmcValue **out, ElmcValue *list);
    RC elmc_list_from_int_array(ElmcValue **out, const elmc_int_t *items, int count);
    RC elmc_list_from_int_array_reuse(ElmcValue **out, ElmcValue *existing, const elmc_int_t *items, int count);
    RC elmc_int_list_to_cons(ElmcValue **out, ElmcValue *list);
    RC elmc_int_list_to_spine(ElmcValue **out, ElmcValue *list);
    RC elmc_list_from_float_array(ElmcValue **out, const double *items, int count);
    RC elmc_list_from_record_array(ElmcValue **out, ElmcValue **items, int count);
    RC elmc_record_seq_to_cons(ElmcValue **out, ElmcValue *list);
    RC elmc_list_from_tuple2_int_array(ElmcValue **out, const elmc_int_t items[][2], int count);
    RC elmc_render_cmd6_take(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4, elmc_int_t p5);
    RC elmc_render_text_cmd_take(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4, elmc_int_t p5, ElmcValue *text);
    ElmcValue *elmc_list_replace_nth_int(ElmcValue *list, elmc_int_t index, elmc_int_t value);
    ElmcValue *elmc_maybe_nothing(void);
    RC elmc_maybe_just(ElmcValue **out, ElmcValue *value);
    RC elmc_maybe_just_own(ElmcValue **out, ElmcValue *value);
    ElmcValue *elmc_maybe_or_tuple_just_payload(ElmcValue *maybe);
    ElmcValue *elmc_maybe_or_tuple_just_payload_borrow(ElmcValue *maybe);
    RC elmc_result_ok(ElmcValue **out, ElmcValue *value);
    RC elmc_result_err(ElmcValue **out, ElmcValue *value);
    RC elmc_result_ok_own(ElmcValue **out, ElmcValue *value);
    RC elmc_result_err_own(ElmcValue **out, ElmcValue *value);
    RC elmc_tuple2(ElmcValue **out, ElmcValue *first, ElmcValue *second);
    RC elmc_tuple2_take(ElmcValue **out, ElmcValue *first, ElmcValue *second);
    ElmcValue *elmc_build_constructor_payload(ElmcValue **values, int count);
    RC elmc_tuple2_ints(ElmcValue **out, elmc_int_t first, elmc_int_t second);
    RC elmc_cmd0(ElmcValue **out, elmc_int_t kind);
    ElmcValue *elmc_cmd_batch(ElmcValue *commands);
    ElmcValue *elmc_cmd_map(ElmcValue *f, ElmcValue *cmd);
    ElmcValue *elmc_sub_batch(ElmcValue *subs);
    ElmcValue *elmc_sub_map(ElmcValue *f, ElmcValue *sub);
    ElmcValue *elmc_port_outgoing(ElmcValue *port_name, ElmcValue *payload);
    ElmcValue *elmc_port_incoming_sub(ElmcValue *port_name, ElmcValue *callback);
    RC elmc_cmd1(ElmcValue **out, elmc_int_t kind, elmc_int_t p0);
    RC elmc_cmd1_string(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, const char *text);
    RC elmc_cmd2(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1);
    RC elmc_cmd3(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2);
    RC elmc_cmd4(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3);
    RC elmc_cmd5(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4);
    RC elmc_sub0(ElmcValue **out, elmc_int_t mask);
    RC elmc_sub1(ElmcValue **out, elmc_int_t mask, elmc_int_t p0);
    RC elmc_sub2(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1);
    RC elmc_sub3(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2);
    RC elmc_sub4(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3);
    RC elmc_sub5(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4);

    elmc_int_t elmc_as_int(ElmcValue *value);
    elmc_int_t elmc_as_int_number(ElmcValue *value);
    int elmc_value_is_unit(ElmcValue *value);
    elmc_int_t elmc_int_idiv(elmc_int_t numerator, elmc_int_t denominator);
    static inline elmc_int_t elmc_angle_from_minute(elmc_int_t minute) {
      elmc_int_t angle = elmc_int_idiv(((minute - (elmc_int_t)720) * (elmc_int_t)65536), (elmc_int_t)1440) % (elmc_int_t)65536;
      return angle < 0 ? angle + (elmc_int_t)65536 : angle;
    }
    elmc_int_t elmc_polar_point_x(elmc_int_t cx, elmc_int_t cy, elmc_int_t radius, elmc_int_t angle);
    elmc_int_t elmc_polar_point_y(elmc_int_t cx, elmc_int_t cy, elmc_int_t radius, elmc_int_t angle);
    elmc_int_t elmc_as_bool(ElmcValue *value);
    int elmc_value_equal(ElmcValue *left, ElmcValue *right);
    int elmc_list_equal_int(ElmcValue *left, ElmcValue *right);
    int elmc_string_length(ElmcValue *value);
    ElmcValue *elmc_list_head(ElmcValue *list);
    ElmcValue *elmc_list_nth_maybe(ElmcValue *list, ElmcValue *index);
    elmc_int_t elmc_list_nth_int_default(ElmcValue *list, elmc_int_t index, elmc_int_t default_value);
    ElmcValue *elmc_list_nth_int_default_boxed(ElmcValue *list, ElmcValue *index, ElmcValue *default_value);
    elmc_int_t elmc_list_head_with_default_int(elmc_int_t default_val, ElmcValue *list);
    ElmcValue *elmc_tuple_first(ElmcValue *tuple);
    ElmcValue *elmc_tuple_second(ElmcValue *tuple);
    ElmcValue *elmc_tuple_first_borrow(ElmcValue *tuple);
    ElmcValue *elmc_tuple_second_borrow(ElmcValue *tuple);
    ElmcValue *elmc_result_inc_or_zero(ElmcValue *result);
    ElmcValue *elmc_basics_max(ElmcValue *left, ElmcValue *right);
    ElmcValue *elmc_basics_min(ElmcValue *left, ElmcValue *right);
    ElmcValue *elmc_basics_clamp(ElmcValue *low, ElmcValue *high, ElmcValue *value);
    ElmcValue *elmc_basics_mod_by(ElmcValue *base, ElmcValue *value);
    ElmcValue *elmc_bitwise_and(ElmcValue *left, ElmcValue *right);
    ElmcValue *elmc_bitwise_or(ElmcValue *left, ElmcValue *right);
    ElmcValue *elmc_bitwise_xor(ElmcValue *left, ElmcValue *right);
    ElmcValue *elmc_bitwise_complement(ElmcValue *value);
    ElmcValue *elmc_bitwise_shift_left_by(ElmcValue *bits, ElmcValue *value);
    ElmcValue *elmc_bitwise_shift_right_by(ElmcValue *bits, ElmcValue *value);
    ElmcValue *elmc_bitwise_shift_right_zf_by(ElmcValue *bits, ElmcValue *value);
    ElmcValue *elmc_char_to_code(ElmcValue *value);
    ElmcValue *elmc_debug_log(ElmcValue *label, ElmcValue *value);
    ElmcValue *elmc_debug_todo(ElmcValue *label);
    ElmcValue *elmc_debug_to_string(ElmcValue *value);
    ElmcValue *elmc_debug_set_to_string(ElmcValue *set);
    ElmcValue *elmc_append(ElmcValue *left, ElmcValue *right);
    RC elmc_string_append(ElmcValue **out, ElmcValue *left, ElmcValue *right);
    RC elmc_string_append_native(ElmcValue **out, const char *left, const char *right);
    ElmcValue *elmc_string_is_empty(ElmcValue *value);
    RC elmc_dict_from_list(ElmcValue **out, ElmcValue *items);
    RC elmc_dict_insert(ElmcValue **out, ElmcValue *key, ElmcValue *value, ElmcValue *dict);
    RC elmc_dict_get(ElmcValue **out, ElmcValue *key, ElmcValue *dict);
    elmc_int_t elmc_dict_get_with_default_int(elmc_int_t default_val, elmc_int_t key, ElmcValue *dict);
    elmc_int_t elmc_dict_get_with_default_int_value(elmc_int_t default_val, ElmcValue *key, ElmcValue *dict);
    ElmcValue *elmc_dict_member(ElmcValue *key, ElmcValue *dict);
    ElmcValue *elmc_dict_size(ElmcValue *dict);
    RC elmc_set_from_list(ElmcValue **out, ElmcValue *items);
    RC elmc_set_insert(ElmcValue **out, ElmcValue *value, ElmcValue *set);
    ElmcValue *elmc_set_member(ElmcValue *value, ElmcValue *set);
    ElmcValue *elmc_set_size(ElmcValue *set);
    ElmcValue *elmc_array_empty(void);
    ElmcValue *elmc_array_from_list(ElmcValue *items);
    ElmcValue *elmc_array_length(ElmcValue *array);
    ElmcValue *elmc_array_get(ElmcValue *index, ElmcValue *array);
    elmc_int_t elmc_array_get_with_default_int(elmc_int_t default_val, elmc_int_t index, ElmcValue *array);
    ElmcValue *elmc_array_set(ElmcValue *index, ElmcValue *value, ElmcValue *array);
    ElmcValue *elmc_array_push(ElmcValue *value, ElmcValue *array);
    ElmcValue *elmc_task_succeed(ElmcValue *value);
    ElmcValue *elmc_task_fail(ElmcValue *value);
    ElmcValue *elmc_task_map(ElmcValue *f, ElmcValue *task);
    ElmcValue *elmc_task_map2(ElmcValue *f, ElmcValue *a, ElmcValue *b);
    ElmcValue *elmc_task_and_then(ElmcValue *f, ElmcValue *task);
    ElmcValue *elmc_task_perform(ElmcValue *to_msg, ElmcValue *task);
    ElmcValue *elmc_task_force(ElmcValue *task);
    ElmcValue *elmc_process_spawn(ElmcValue *task);
    void elmc_process_release_all_slots(void);
    ElmcValue *elmc_process_sleep(ElmcValue *milliseconds);
    ElmcValue *elmc_process_kill(ElmcValue *pid);
    ElmcValue *elmc_time_now_millis(void);
    ElmcValue *elmc_time_zone_offset_minutes(void);
    ElmcValue *elmc_cmd_backlight_from_maybe(ElmcValue *maybe_mode);

    /* --- List operations --- */
    ElmcValue *elmc_list_tail(ElmcValue *list);
    ElmcValue *elmc_list_is_empty(ElmcValue *list);
    ElmcValue *elmc_list_length(ElmcValue *list);
    RC elmc_list_reverse(ElmcValue **out, ElmcValue *list);
    RC elmc_list_copy(ElmcValue **out, ElmcValue *list);
    ElmcValue *elmc_list_member(ElmcValue *value, ElmcValue *list);
    RC elmc_list_map(ElmcValue **out, ElmcValue *f, ElmcValue *list);
    RC elmc_list_filter(ElmcValue **out, ElmcValue *f, ElmcValue *list);
    RC elmc_list_filter_record_field(ElmcValue **out, ElmcValue *list, elmc_int_t field_index);
    RC elmc_list_filter_record_and(ElmcValue **out, ElmcValue *list, elmc_int_t field_a, elmc_int_t field_b);
    RC elmc_list_map_record_field(ElmcValue **out, ElmcValue *list, elmc_int_t field_index);
    RC elmc_list_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *list);
    RC elmc_list_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *list);
    RC elmc_list_append(ElmcValue **out, ElmcValue *a, ElmcValue *b);
    RC elmc_list_concat(ElmcValue **out, ElmcValue *lists);
    RC elmc_list_concat_array(ElmcValue **out, ElmcValue * const *lists, int count);
    RC elmc_list_concat_map(ElmcValue **out, ElmcValue *f, ElmcValue *list);
    RC elmc_list_indexed_map(ElmcValue **out, ElmcValue *f, ElmcValue *list);
    RC elmc_list_filter_map(ElmcValue **out, ElmcValue *f, ElmcValue *list);
    RC elmc_list_sum(ElmcValue **out, ElmcValue *list);
    RC elmc_list_product(ElmcValue **out, ElmcValue *list);
    RC elmc_list_maximum(ElmcValue **out, ElmcValue *list);
    RC elmc_list_minimum(ElmcValue **out, ElmcValue *list);
    RC elmc_list_any(ElmcValue **out, ElmcValue *f, ElmcValue *list);
    RC elmc_list_all(ElmcValue **out, ElmcValue *f, ElmcValue *list);
    RC elmc_list_sort(ElmcValue **out, ElmcValue *list);
    RC elmc_list_sort_by(ElmcValue **out, ElmcValue *f, ElmcValue *list);
    RC elmc_list_sort_with(ElmcValue **out, ElmcValue *f, ElmcValue *list);
    RC elmc_list_singleton(ElmcValue **out, ElmcValue *value);
    RC elmc_list_range(ElmcValue **out, ElmcValue *lo, ElmcValue *hi);
    RC elmc_list_repeat(ElmcValue **out, ElmcValue *n, ElmcValue *value);
    RC elmc_list_repeat_count(ElmcValue **out, elmc_int_t count, ElmcValue *value);
    RC elmc_list_take(ElmcValue **out, ElmcValue *n, ElmcValue *list);
    RC elmc_list_take_int(ElmcValue **out, elmc_int_t count, ElmcValue *list);
    RC elmc_list_drop(ElmcValue **out, ElmcValue *n, ElmcValue *list);
    RC elmc_list_drop_int(ElmcValue **out, elmc_int_t count, ElmcValue *list);
    RC elmc_list_slice_int(ElmcValue **out, elmc_int_t drop, elmc_int_t take, ElmcValue *list);
    RC elmc_list_partition(ElmcValue **out, ElmcValue *f, ElmcValue *list);
    RC elmc_list_unzip(ElmcValue **out, ElmcValue *list);
    RC elmc_list_intersperse(ElmcValue **out, ElmcValue *sep, ElmcValue *list);
    RC elmc_list_map2(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b);
    RC elmc_list_map3(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c);
    RC elmc_list_map4(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d);
    RC elmc_list_map5(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d, ElmcValue *e);

    /* --- Maybe operations --- */
    ElmcValue *elmc_maybe_with_default(ElmcValue *default_val, ElmcValue *maybe);
    elmc_int_t elmc_maybe_with_default_int(elmc_int_t default_val, ElmcValue *maybe);
    RC elmc_maybe_map(ElmcValue **out, ElmcValue *f, ElmcValue *maybe);
    RC elmc_maybe_map2(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b);
    RC elmc_maybe_and_then(ElmcValue **out, ElmcValue *f, ElmcValue *maybe);

    /* --- Result operations --- */
    RC elmc_result_map(ElmcValue **out, ElmcValue *f, ElmcValue *result);
    RC elmc_result_map_error(ElmcValue **out, ElmcValue *f, ElmcValue *result);
    RC elmc_result_and_then(ElmcValue **out, ElmcValue *f, ElmcValue *result);
    ElmcValue *elmc_result_with_default(ElmcValue *default_val, ElmcValue *result);
    ElmcValue *elmc_result_to_maybe(ElmcValue *result);
    ElmcValue *elmc_result_from_maybe(ElmcValue *err, ElmcValue *maybe);

    /* --- String operations (extended) --- */
    ElmcValue *elmc_string_length_val(ElmcValue *s);
    RC elmc_string_reverse(ElmcValue **out, ElmcValue *s);
    RC elmc_string_repeat(ElmcValue **out, ElmcValue *n, ElmcValue *s);
    RC elmc_string_replace(ElmcValue **out, ElmcValue *old_s, ElmcValue *new_s, ElmcValue *s);
    ElmcValue *elmc_string_from_int(ElmcValue *n);
    RC elmc_string_from_native_int(ElmcValue **out, elmc_int_t n);
    ElmcValue *elmc_string_to_int(ElmcValue *s);
    RC elmc_string_from_float(ElmcValue **out, ElmcValue *f);
    ElmcValue *elmc_string_to_float(ElmcValue *s);
    RC elmc_string_to_upper(ElmcValue **out, ElmcValue *s);
    RC elmc_string_to_lower(ElmcValue **out, ElmcValue *s);
    RC elmc_string_trim(ElmcValue **out, ElmcValue *s);
    RC elmc_string_trim_left(ElmcValue **out, ElmcValue *s);
    RC elmc_string_trim_right(ElmcValue **out, ElmcValue *s);
    ElmcValue *elmc_string_contains(ElmcValue *sub, ElmcValue *s);
    int elmc_string_equals_cstr(ElmcValue *value, const char *literal);
    ElmcValue *elmc_string_starts_with(ElmcValue *prefix, ElmcValue *s);
    ElmcValue *elmc_string_ends_with(ElmcValue *suffix, ElmcValue *s);
    RC elmc_string_split(ElmcValue **out, ElmcValue *sep, ElmcValue *s);
    RC elmc_string_join(ElmcValue **out, ElmcValue *sep, ElmcValue *list);
    ElmcValue *elmc_string_words(ElmcValue *s);
    ElmcValue *elmc_string_lines(ElmcValue *s);
    RC elmc_string_slice(ElmcValue **out, ElmcValue *start, ElmcValue *end_idx, ElmcValue *s);
    ElmcValue *elmc_string_left(ElmcValue *n, ElmcValue *s);
    ElmcValue *elmc_string_right(ElmcValue *n, ElmcValue *s);
    ElmcValue *elmc_string_drop_left(ElmcValue *n, ElmcValue *s);
    ElmcValue *elmc_string_drop_right(ElmcValue *n, ElmcValue *s);
    ElmcValue *elmc_string_cons(ElmcValue *ch, ElmcValue *s);
    RC elmc_string_uncons(ElmcValue **out, ElmcValue *s);
    RC elmc_string_to_list(ElmcValue **out, ElmcValue *s);
    RC elmc_string_from_list(ElmcValue **out, ElmcValue *list);
    RC elmc_string_from_char(ElmcValue **out, ElmcValue *ch);
    ElmcValue *elmc_string_pad(ElmcValue *n, ElmcValue *ch, ElmcValue *s);
    RC elmc_string_pad_left(ElmcValue **out, ElmcValue *n, ElmcValue *ch, ElmcValue *s);
    RC elmc_string_pad_right(ElmcValue **out, ElmcValue *n, ElmcValue *ch, ElmcValue *s);
    RC elmc_string_map(ElmcValue **out, ElmcValue *f, ElmcValue *s);
    RC elmc_string_filter(ElmcValue **out, ElmcValue *f, ElmcValue *s);
    RC elmc_string_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *s);
    RC elmc_string_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *s);
    RC elmc_string_any(ElmcValue **out, ElmcValue *f, ElmcValue *s);
    RC elmc_string_all(ElmcValue **out, ElmcValue *f, ElmcValue *s);
    RC elmc_string_indexes(ElmcValue **out, ElmcValue *sub, ElmcValue *s);

    /* --- Tuple operations (extended) --- */
    RC elmc_tuple_map_first(ElmcValue **out, ElmcValue *f, ElmcValue *t);
    RC elmc_tuple_map_second(ElmcValue **out, ElmcValue *f, ElmcValue *t);
    RC elmc_tuple_map_both(ElmcValue **out, ElmcValue *f, ElmcValue *g, ElmcValue *t);

    /* --- Basics (extended) --- */
    ElmcValue *elmc_basics_not(ElmcValue *x);
    ElmcValue *elmc_basics_negate(ElmcValue *x);
    ElmcValue *elmc_basics_abs(ElmcValue *x);
    ElmcValue *elmc_basics_to_float(ElmcValue *x);
    ElmcValue *elmc_basics_sqrt(ElmcValue *x);
    ElmcValue *elmc_basics_log_base(ElmcValue *base, ElmcValue *x);
    ElmcValue *elmc_basics_sin(ElmcValue *x);
    ElmcValue *elmc_basics_cos(ElmcValue *x);
    ElmcValue *elmc_basics_tan(ElmcValue *x);
    ElmcValue *elmc_basics_acos(ElmcValue *x);
    ElmcValue *elmc_basics_asin(ElmcValue *x);
    ElmcValue *elmc_basics_atan(ElmcValue *x);
    ElmcValue *elmc_basics_atan2(ElmcValue *y, ElmcValue *x);
    ElmcValue *elmc_basics_degrees(ElmcValue *x);
    ElmcValue *elmc_basics_radians(ElmcValue *x);
    ElmcValue *elmc_basics_turns(ElmcValue *x);
    ElmcValue *elmc_basics_from_polar(ElmcValue *polar);
    ElmcValue *elmc_basics_to_polar(ElmcValue *point);
    ElmcValue *elmc_basics_is_nan(ElmcValue *x);
    ElmcValue *elmc_basics_is_infinite(ElmcValue *x);
    ElmcValue *elmc_basics_round(ElmcValue *x);
    ElmcValue *elmc_basics_floor(ElmcValue *x);
    ElmcValue *elmc_basics_ceiling(ElmcValue *x);
    ElmcValue *elmc_basics_truncate(ElmcValue *x);
    ElmcValue *elmc_basics_remainder_by(ElmcValue *base, ElmcValue *value);
    ElmcValue *elmc_basics_pow(ElmcValue *base, ElmcValue *exponent);
    ElmcValue *elmc_basics_xor(ElmcValue *a, ElmcValue *b);
    RC elmc_basics_compare(ElmcValue **out, ElmcValue *a, ElmcValue *b);

    /* --- Char (extended) --- */
    ElmcValue *elmc_char_is_upper(ElmcValue *ch);
    ElmcValue *elmc_char_is_lower(ElmcValue *ch);
    ElmcValue *elmc_char_is_alpha(ElmcValue *ch);
    ElmcValue *elmc_char_is_alpha_num(ElmcValue *ch);
    ElmcValue *elmc_char_is_digit(ElmcValue *ch);
    ElmcValue *elmc_char_is_oct_digit(ElmcValue *ch);
    ElmcValue *elmc_char_is_hex_digit(ElmcValue *ch);
    ElmcValue *elmc_char_to_upper(ElmcValue *ch);
    ElmcValue *elmc_char_to_lower(ElmcValue *ch);

    /* --- Dict (extended) --- */
    RC elmc_dict_remove(ElmcValue **out, ElmcValue *key, ElmcValue *dict);
    ElmcValue *elmc_dict_is_empty(ElmcValue *dict);
    RC elmc_dict_keys(ElmcValue **out, ElmcValue *dict);
    RC elmc_dict_values(ElmcValue **out, ElmcValue *dict);
    ElmcValue *elmc_dict_to_list(ElmcValue *dict);
    RC elmc_dict_map(ElmcValue **out, ElmcValue *f, ElmcValue *dict);
    RC elmc_dict_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *dict);
    RC elmc_dict_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *dict);
    RC elmc_dict_filter(ElmcValue **out, ElmcValue *f, ElmcValue *dict);
    RC elmc_dict_partition(ElmcValue **out, ElmcValue *f, ElmcValue *dict);
    RC elmc_dict_union(ElmcValue **out, ElmcValue *a, ElmcValue *b);
    RC elmc_dict_intersect(ElmcValue **out, ElmcValue *a, ElmcValue *b);
    RC elmc_dict_diff(ElmcValue **out, ElmcValue *a, ElmcValue *b);
    RC elmc_dict_merge(ElmcValue **out, ElmcValue *lf, ElmcValue *bf, ElmcValue *rf, ElmcValue *a, ElmcValue *b, ElmcValue *result);
    RC elmc_dict_update(ElmcValue **out, ElmcValue *key, ElmcValue *f, ElmcValue *dict);
    ElmcValue *elmc_dict_singleton(ElmcValue *key, ElmcValue *value);

    /* --- Set (extended) --- */
    ElmcValue *elmc_set_singleton(ElmcValue *value);
    RC elmc_set_remove(ElmcValue **out, ElmcValue *value, ElmcValue *set);
    ElmcValue *elmc_set_is_empty(ElmcValue *set);
    ElmcValue *elmc_set_to_list(ElmcValue *set);
    RC elmc_set_union(ElmcValue **out, ElmcValue *a, ElmcValue *b);
    RC elmc_set_intersect(ElmcValue **out, ElmcValue *a, ElmcValue *b);
    RC elmc_set_diff(ElmcValue **out, ElmcValue *a, ElmcValue *b);
    RC elmc_set_map(ElmcValue **out, ElmcValue *f, ElmcValue *set);
    RC elmc_set_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *set);
    RC elmc_set_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *set);
    RC elmc_set_filter(ElmcValue **out, ElmcValue *f, ElmcValue *set);
    RC elmc_set_partition(ElmcValue **out, ElmcValue *f, ElmcValue *set);

    /* --- Array (extended) --- */
    ElmcValue *elmc_array_initialize(ElmcValue *n, ElmcValue *f);
    ElmcValue *elmc_array_repeat(ElmcValue *n, ElmcValue *value);
    ElmcValue *elmc_array_is_empty(ElmcValue *array);
    ElmcValue *elmc_array_to_list(ElmcValue *array);
    ElmcValue *elmc_array_to_indexed_list(ElmcValue *array);
    ElmcValue *elmc_array_map(ElmcValue *f, ElmcValue *array);
    ElmcValue *elmc_array_indexed_map(ElmcValue *f, ElmcValue *array);
    ElmcValue *elmc_array_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *array);
    ElmcValue *elmc_array_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *array);
    ElmcValue *elmc_array_filter(ElmcValue *f, ElmcValue *array);
    ElmcValue *elmc_array_append(ElmcValue *a, ElmcValue *b);
    ElmcValue *elmc_array_slice(ElmcValue *start, ElmcValue *end_idx, ElmcValue *array);

    #{JsonSections.runtime_header_declarations()}

    RC elmc_new_float(ElmcValue **out, double value);
    double elmc_as_float(ElmcValue *value);
    double elmc_basics_sqrt_double(double x);
    double elmc_basics_sin_double(double x);
    double elmc_basics_cos_double(double x);
    double elmc_basics_tan_double(double x);

    RC elmc_record_new(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values);
    RC elmc_record_new_take(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values);
    RC elmc_record_new_ints(ElmcValue **out, int field_count, const char **field_names, const elmc_int_t *field_values);
    RC elmc_record_new_static(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values);
    RC elmc_record_new_static_take(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values);
    RC elmc_record_new_static_ints(ElmcValue **out, int field_count, const char * const *field_names, const elmc_int_t *field_values);
    RC elmc_record_new_values(ElmcValue **out, int field_count, ElmcValue **field_values);
    RC elmc_record_new_values_take(ElmcValue **out, int field_count, ElmcValue **field_values);
    RC elmc_record_new_values_ints(ElmcValue **out, int field_count, const elmc_int_t *field_values);

    #{RcMacros.take_wrapper_declarations()}

    #{RcMacros.maybe_pattern_helpers()}

    ElmcValue *elmc_record_get(ElmcValue *record, const char *field_name);
    ElmcValue *elmc_record_get_at(ElmcValue *record, int index, const char *field_name);
    ElmcValue *elmc_record_get_index(ElmcValue *record, int index);
    elmc_int_t elmc_record_get_int(ElmcValue *record, const char *field_name);
    elmc_int_t elmc_record_get_at_int(ElmcValue *record, int index, const char *field_name);
    elmc_int_t elmc_record_get_index_int(ElmcValue *record, int index);
    elmc_int_t elmc_record_get_maybe_int(ElmcValue *record, const char *field_name, elmc_int_t default_val);
    elmc_int_t elmc_record_get_at_maybe_int(ElmcValue *record, int index, const char *field_name, elmc_int_t default_val);
    elmc_int_t elmc_record_get_index_maybe_int(ElmcValue *record, int index, elmc_int_t default_val);
    elmc_int_t elmc_record_get_bool(ElmcValue *record, const char *field_name);
    elmc_int_t elmc_record_get_at_bool(ElmcValue *record, int index, const char *field_name);
    elmc_int_t elmc_record_get_index_bool(ElmcValue *record, int index);
    uint32_t elmc_record_mutation_gen(ElmcValue *record);
    ElmcValue *elmc_record_update(ElmcValue *record, const char *field_name, ElmcValue *new_value);
    ElmcValue *elmc_record_update_index(ElmcValue *record, int index, ElmcValue *new_value);
    ElmcValue *elmc_record_update_index_cow(ElmcValue *record, int index, ElmcValue *new_value);
    ElmcValue *elmc_record_update_index_cow_drop(ElmcValue *record, int index, ElmcValue *new_value);
    ElmcValue *elmc_record_update_index_int_cow(ElmcValue *record, int index, elmc_int_t new_value);
    ElmcValue *elmc_record_update_index_int_cow_drop(ElmcValue *record, int index, elmc_int_t new_value);
    ElmcValue *elmc_record_update_index_bool_cow(ElmcValue *record, int index, bool new_value);
    ElmcValue *elmc_record_update_index_bool_cow_drop(ElmcValue *record, int index, bool new_value);
    ElmcValue *elmc_record_update_index_float_cow(ElmcValue *record, int index, double new_value);
    ElmcValue *elmc_record_update_index_float_cow_drop(ElmcValue *record, int index, double new_value);

    RC elmc_closure_new(ElmcValue **out, ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count), int arity, int capture_count, ElmcValue **captures);
    RC elmc_closure_new_rc(ElmcValue **out, RC (*rc_fn)(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count), int arity, int capture_count, ElmcValue **captures);
    #{RcMacros.closure_new_take_wrapper()}
    ElmcValue *elmc_closure_call(ElmcValue *closure, ElmcValue **args, int argc);
    RC elmc_closure_call_rc(ElmcValue **out, ElmcValue *closure, ElmcValue **args, int argc);
    ElmcValue *elmc_apply_extra(ElmcValue *value, ElmcValue **args, int argc);

    typedef struct ElmcForwardRef {
      ElmcValue *value;
    } ElmcForwardRef;

    ElmcForwardRef *elmc_forward_ref_new(void);
    void elmc_forward_ref_set(ElmcForwardRef *ref, ElmcValue *value);
    ElmcValue *elmc_forward_ref_get(ElmcForwardRef *ref);
    void elmc_forward_ref_free(ElmcForwardRef *ref);
    ElmcValue *elmc_forward_ref_capture(ElmcForwardRef *ref);

    uint64_t elmc_rc_allocated_count(void);
    uint64_t elmc_rc_released_count(void);

    #{RcTrack.header_declarations()}

    #{RcMacros.release_array_lifo_declaration()}

    #{AllocTrack.header_declarations()}

    #{AllocProbe.header_declarations()}

    #endif
    """
  end

  @small_int_min -1
  @default_small_int_max 64
  # Pebble watch RAM: cache only common UI/game scalars (-1..3).
  @pebble_small_int_max 3
  @default_process_max_slots 16
  @pebble_process_max_slots 2

  defp small_int_bounds(opts) do
    max =
      if Keyword.get(opts, :pebble_int32, false),
        do: @pebble_small_int_max,
        else: @default_small_int_max

    {@small_int_min, max}
  end

  defp process_max_slots(opts) do
    if Keyword.get(opts, :pebble_int32, false),
      do: @pebble_process_max_slots,
      else: @default_process_max_slots
  end

  defp small_int_table_entries(min, max) do
    Enum.map_join(min..max, ",\n", fn value ->
      "      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, #{value} }"
    end)
  end

  @spec runtime_source(write_opts()) :: String.t()
  defp runtime_source(opts) do
    {small_min, small_max} = small_int_bounds(opts)
    process_max_slots = process_max_slots(opts)
    """
    #include "elmc_runtime.h"
    #include <stdlib.h>
    #include <string.h>
    #include <stdio.h>
    #include <time.h>
    #include <math.h>
    #{JsonSections.runtime_source_includes()}
    #if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
    #define ELMC_PEBBLE_PLATFORM 1
    #endif
    #ifdef ELMC_PEBBLE_PLATFORM
    #include <pebble.h>
    #endif
    #if defined(__GNUC__)
    #define ELMC_UNUSED __attribute__((unused))
    #else
    #define ELMC_UNUSED
    #endif

    #ifdef ELMC_PEBBLE_PLATFORM
    static uint32_t ELMC_ALLOCATED = 0;
    static uint32_t ELMC_RELEASED = 0;
    #else
    static uint64_t ELMC_ALLOCATED = 0;
    static uint64_t ELMC_RELEASED = 0;
    #endif
    static int64_t ELMC_NEXT_PROCESS_ID = 1;
    #define ELMC_PROCESS_MAX_SLOTS #{process_max_slots}
    #define ELMC_RC_IMMORTAL UINT16_MAX
    static ElmcValue ELMC_BOOL_FALSE = { ELMC_RC_IMMORTAL, ELMC_TAG_BOOL, NULL, 0 };
    static ElmcValue ELMC_BOOL_TRUE = { ELMC_RC_IMMORTAL, ELMC_TAG_BOOL, NULL, 1 };
    #define ELMC_UNIT_SCALAR ((elmc_int_t)0x1EC01A)
    #define ELMC_TASK_SUCCEED_SCALAR ((elmc_int_t)0x1EC01B)
    #define ELMC_TASK_FAIL_SCALAR ((elmc_int_t)0x1EC01C)
    #define ELMC_TASK_AND_THEN_SCALAR ((elmc_int_t)0x1EC01D)
    #define ELMC_TASK_MAP_SCALAR ((elmc_int_t)0x1EC01E)
    #define ELMC_TASK_SPAWN_SCALAR ((elmc_int_t)0x1EC01F)
    #define ELMC_SMALL_INT_MIN (#{small_min})
    #define ELMC_SMALL_INT_MAX #{small_max}
    const ElmcValue ELMC_SMALL_INTS[ELMC_SMALL_INT_MAX - ELMC_SMALL_INT_MIN + 1] = {
    #{small_int_table_entries(small_min, small_max)}
    };
    static ElmcMaybe ELMC_MAYBE_NOTHING_PAYLOAD = { 0, NULL };
    static ElmcValue ELMC_MAYBE_NOTHING ELMC_UNUSED = { ELMC_RC_IMMORTAL, ELMC_TAG_MAYBE, &ELMC_MAYBE_NOTHING_PAYLOAD, 0 };
    static char ELMC_EMPTY_STRING_PAYLOAD[] = "";
    static ElmcValue ELMC_EMPTY_STRING = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, ELMC_EMPTY_STRING_PAYLOAD, 0 };
    static ElmcIntListPayload ELMC_EMPTY_INT_LIST_PAYLOAD = { NULL, 0, 0 };
    static ElmcValue ELMC_EMPTY_INT_LIST = {
      ELMC_RC_IMMORTAL,
      ELMC_TAG_INT_LIST,
      (void *)&ELMC_EMPTY_INT_LIST_PAYLOAD,
      ELMC_INT_LIST_CELL_SCALAR
    };
    ElmcValue ELMC_LIST_NIL = { ELMC_RC_IMMORTAL, ELMC_TAG_LIST, NULL, 0 };
    static ElmcValue ELMC_UNIT = { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, ELMC_UNIT_SCALAR };

    typedef struct {
      ElmcValue value;
      ElmcCons cons;
    } ElmcListCell;

    #define ELMC_LIST_CELL_SCALAR ((elmc_int_t)0x1EC011)
    #define ELMC_DICT_SCALAR ((elmc_int_t)0x1EC012)

    typedef struct {
      ElmcValue value;
      ElmcMaybe maybe;
    } ElmcMaybeCell;

    typedef struct {
      ElmcValue value;
      ElmcResult result;
    } ElmcResultCell;

    typedef struct {
      ElmcValue value;
      ElmcTuple2 tuple;
    } ElmcTuple2Cell;

    typedef struct {
      ElmcValue value;
      ElmcCmdPayload cmd;
    } ElmcCmdCell;

    typedef struct {
      ElmcValue value;
      ElmcSubPayload sub;
    } ElmcSubCell;

    typedef struct {
      ElmcValue value;
      ElmcRecord record;
    } ElmcRecordCell;

    typedef struct {
      ElmcValue value;
      ElmcRecord record;
      const char **field_names;
    } ElmcNamedRecordCell;

    typedef struct {
      ElmcValue value;
      ElmcClosure closure;
    } ElmcClosureCell;

    #define ELMC_MAYBE_CELL_SCALAR ((elmc_int_t)0x1EC012)
    #define ELMC_RESULT_CELL_SCALAR ((elmc_int_t)0x1EC013)
    #define ELMC_TUPLE2_CELL_SCALAR ((elmc_int_t)0x1EC014)
    #define ELMC_CMD_CELL_SCALAR ((elmc_int_t)0x1EC017)
    #define ELMC_SUB_CELL_SCALAR ((elmc_int_t)0x1EC018)
    #define ELMC_RECORD_CELL_SCALAR ((elmc_int_t)0x1EC015)
    #define ELMC_NAMED_RECORD_CELL_SCALAR ((elmc_int_t)0x1EC019)
    #define ELMC_CLOSURE_CELL_SCALAR ((elmc_int_t)0x1EC016)

    typedef struct {
      int active;
      int64_t pid;
      ElmcValue *task;
    #ifdef ELMC_PEBBLE_PLATFORM
      AppTimer *timer;
    #else
      void *timer;
    #endif
    } ElmcProcessSlot;

    static ElmcProcessSlot ELMC_PROCESS_SLOTS[ELMC_PROCESS_MAX_SLOTS];

    void *elmc_malloc_impl(size_t size, const char *context, const char *file, int line);
    void *elmc_calloc_impl(size_t nmemb, size_t size, const char *context, const char *file, int line);
    static ElmcValue *elmc_alloc_impl(ElmcTag tag, void *payload, const char *file, int line);
    static ElmcValue *elmc_small_int(elmc_int_t value);
    static RC elmc_list_cell_alloc(ElmcValue **out, ElmcValue *head, ElmcValue *tail, int take);
    static RC elmc_alloc_scalar(ElmcValue **out, ElmcTag tag, elmc_int_t scalar);
    static int elmc_list_cell_release(ElmcValue *value);
    static int elmc_int_list_cell_release(ElmcValue *value);
    static int elmc_maybe_cell_release(ElmcValue *value);
    static int elmc_result_cell_release(ElmcValue *value);
    static int elmc_tuple2_cell_release(ElmcValue *value);
    static int elmc_record_cell_release(ElmcValue *value);
    static int elmc_closure_cell_release(ElmcValue *value);
    static RC elmc_record_cell_alloc(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values, int take);
    static RC elmc_record_cell_alloc_static(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values, int take);
    static RC elmc_record_cell_alloc_values(ElmcValue **out, int field_count, ElmcValue **field_values, int take);
    static const char **elmc_record_field_names(ElmcValue *record);

    #{AllocTrack.register_hook()}

    #if ELMC_ALLOC_TRACE
    #define elmc_malloc(size, context) elmc_malloc_impl((size), (context), __FILE__, __LINE__)
    #define elmc_calloc(nmemb, size, context) elmc_calloc_impl((nmemb), (size), (context), __FILE__, __LINE__)
    #define elmc_alloc(tag, payload) elmc_alloc_impl((tag), (payload), __FILE__, __LINE__)
    #else
    #define elmc_malloc(size, context) elmc_malloc_impl((size), (context), NULL, 0)
    #define elmc_calloc(nmemb, size, context) elmc_calloc_impl((nmemb), (size), (context), NULL, 0)
    #define elmc_alloc(tag, payload) elmc_alloc_impl((tag), (payload), NULL, 0)
    #endif
    #define elmc_realloc(ptr, size, context) elmc_realloc_impl((ptr), (size), (context))

    #{RcTrack.register_macro()}

    static ElmcProcessSlot *elmc_process_alloc_slot(void) {
      for (int i = 0; i < ELMC_PROCESS_MAX_SLOTS; i++) {
        if (!ELMC_PROCESS_SLOTS[i].active) {
          ELMC_PROCESS_SLOTS[i].active = 1;
          ELMC_PROCESS_SLOTS[i].pid = ELMC_NEXT_PROCESS_ID++;
          ELMC_PROCESS_SLOTS[i].task = NULL;
          ELMC_PROCESS_SLOTS[i].timer = NULL;
          return &ELMC_PROCESS_SLOTS[i];
        }
      }
      return NULL;
    }

    static ElmcProcessSlot *elmc_process_find_slot(int64_t pid) {
      for (int i = 0; i < ELMC_PROCESS_MAX_SLOTS; i++) {
        if (ELMC_PROCESS_SLOTS[i].active && ELMC_PROCESS_SLOTS[i].pid == pid) {
          return &ELMC_PROCESS_SLOTS[i];
        }
      }
      return NULL;
    }

    static void elmc_process_release_slot(ElmcProcessSlot *slot) {
      if (!slot || !slot->active) return;
      if (slot->task) {
        elmc_release(slot->task);
        slot->task = NULL;
      }
    #ifdef ELMC_PEBBLE_PLATFORM
      if (slot->timer) {
        app_timer_cancel(slot->timer);
        slot->timer = NULL;
      }
    #endif
      slot->active = 0;
      slot->pid = 0;
    }

    void elmc_process_release_all_slots(void) {
    #ifndef ELMC_PEBBLE_PLATFORM
      for (int i = 0; i < ELMC_PROCESS_MAX_SLOTS; i++) {
        elmc_process_release_slot(&ELMC_PROCESS_SLOTS[i]);
      }
    #endif
    }

    #ifdef ELMC_PEBBLE_PLATFORM
    static void elmc_process_spawn_timer_cb(void *data) {
      ElmcProcessSlot *slot = (ElmcProcessSlot *)data;
      if (!slot || !slot->active) return;
      slot->timer = NULL;
      elmc_process_release_slot(slot);
    }

    static void elmc_process_sleep_timer_cb(void *data) {
      ElmcProcessSlot *slot = (ElmcProcessSlot *)data;
      if (!slot || !slot->active) return;
      slot->timer = NULL;
      elmc_process_release_slot(slot);
    }
    #endif

    static void elmc_log_alloc_failed(const char *context, size_t size, const char *file, int line) {
    #ifdef ELMC_PEBBLE_PLATFORM
      if (file && line > 0) {
        APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC malloc failed %s %s:%d %lu",
                context ? context : "?", file, line, (unsigned long)size);
      } else {
        APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC malloc failed %s %lu",
                context ? context : "?", (unsigned long)size);
      }
    #else
      if (file && line > 0) {
        fprintf(stderr, "ELMC malloc failed %s %s:%d %lu\\n",
                context ? context : "?", file, line, (unsigned long)size);
      } else {
        fprintf(stderr, "ELMC malloc failed %s %lu\\n",
                context ? context : "?", (unsigned long)size);
      }
    #endif
    }

    void *elmc_malloc_impl(size_t size, const char *context, const char *file, int line) {
      void *ptr = malloc(size);
      if (!ptr) {
        elmc_log_alloc_failed(context, size, file, line);
      }
    #if ELMC_ALLOC_TRACK
      else {
        elmc_alloc_track_register(ptr, size, context, file, line);
      }
    #endif
      return ptr;
    }

    void *elmc_calloc_impl(size_t nmemb, size_t size, const char *context, const char *file, int line) {
      void *ptr = calloc(nmemb, size);
      if (!ptr) {
        elmc_log_alloc_failed(context, nmemb * size, file, line);
      }
    #if ELMC_ALLOC_TRACK
      else if (nmemb > 0 && size > 0) {
        elmc_alloc_track_register(ptr, nmemb * size, context, file, line);
      }
    #endif
      return ptr;
    }

    static void *elmc_realloc_impl(void *ptr, size_t size, const char *context) {
      void *next = realloc(ptr, size);
      if (!next && size > 0) elmc_log_alloc_failed(context, size, NULL, 0);
      return next;
    }

    static ElmcValue *elmc_alloc_impl(ElmcTag tag, void *payload, const char *file, int line) {
      ElmcValue *value = (ElmcValue *)elmc_malloc_impl(sizeof(ElmcValue), __func__, file, line);
      if (!value) return NULL;
      value->rc = 1;
      value->tag = tag;
      value->payload = payload;
      value->scalar = 0;
      ELMC_ALLOCATED += 1;
      ELMC_RC_TRACK_REGISTER(value, __func__);
      return value;
    }

    static RC elmc_alloc_scalar(ElmcValue **out, ElmcTag tag, elmc_int_t scalar) {
      ElmcValue *value = elmc_alloc(tag, NULL);
      if (!value) return RC_ERR_OUT_OF_MEMORY;
      value->scalar = scalar;
      *out = value;
      return RC_SUCCESS;
    }

    static ElmcValue *elmc_small_int(elmc_int_t value) {
      if (value < ELMC_SMALL_INT_MIN || value > ELMC_SMALL_INT_MAX) return NULL;
      return (ElmcValue *)&ELMC_SMALL_INTS[value - ELMC_SMALL_INT_MIN];
    }

    ElmcValue *elmc_int_zero(void) {
      return elmc_small_int(0);
    }

    ElmcValue *elmc_unit(void) {
      return &ELMC_UNIT;
    }

    static RC elmc_list_cell_alloc(ElmcValue **out, ElmcValue *head, ElmcValue *tail, int take) {
      ElmcListCell *cell = (ElmcListCell *)elmc_malloc(sizeof(ElmcListCell), __func__);
      if (!cell) {
        if (take) {
          elmc_release(head);
          elmc_release(tail);
        }
        return RC_ERR_OUT_OF_MEMORY;
      }
      cell->cons.head = take ? head : elmc_retain(head);
      cell->cons.tail = take ? tail : elmc_retain(tail);
      cell->value.rc = 1;
      cell->value.tag = ELMC_TAG_LIST;
      cell->value.payload = &cell->cons;
      cell->value.scalar = ELMC_LIST_CELL_SCALAR;
      ELMC_ALLOCATED += 1;
      ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
      *out = &cell->value;
      return RC_SUCCESS;
    }

    static int elmc_list_cell_release(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_LIST) return 0;
      if (value->scalar != ELMC_LIST_CELL_SCALAR && value->scalar != ELMC_DICT_SCALAR) return 0;
      ElmcListCell *cell = (ElmcListCell *)value;
      if (value->payload != &cell->cons) return 0;
      elmc_free(cell);
      return 1;
    }

    static void elmc_dict_mark_spine(ElmcValue *dict) {
      ElmcValue *cursor = dict;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        cursor->scalar = ELMC_DICT_SCALAR;
        cursor = ((ElmcCons *)cursor->payload)->tail;
      }
    }

    static int elmc_maybe_cell_release(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_MAYBE || value->scalar != ELMC_MAYBE_CELL_SCALAR) return 0;
      ElmcMaybeCell *cell = (ElmcMaybeCell *)value;
      if (value->payload != &cell->maybe) return 0;
      elmc_free(cell);
      return 1;
    }

    static int elmc_result_cell_release(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_RESULT) return 0;
      elmc_int_t scalar = value->scalar;
      if (scalar != ELMC_RESULT_CELL_SCALAR &&
          (scalar < ELMC_TASK_SUCCEED_SCALAR || scalar > ELMC_TASK_SPAWN_SCALAR)) {
        return 0;
      }
      ElmcResultCell *cell = (ElmcResultCell *)value;
      if (value->payload != &cell->result) return 0;
      elmc_free(cell);
      return 1;
    }

    static int elmc_tuple2_cell_release(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_TUPLE2 || value->scalar != ELMC_TUPLE2_CELL_SCALAR) return 0;
      ElmcTuple2Cell *cell = (ElmcTuple2Cell *)value;
      if (value->payload != &cell->tuple) return 0;
      elmc_free(cell);
      return 1;
    }

    static int elmc_cmd_cell_release(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_CMD || value->scalar != ELMC_CMD_CELL_SCALAR) return 0;
      ElmcCmdCell *cell = (ElmcCmdCell *)value;
      if (value->payload != &cell->cmd) return 0;
      elmc_release(cell->cmd.text);
      elmc_free(cell);
      return 1;
    }

    static int elmc_sub_cell_release(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_SUB || value->scalar != ELMC_SUB_CELL_SCALAR) return 0;
      ElmcSubCell *cell = (ElmcSubCell *)value;
      if (value->payload != &cell->sub) return 0;
      elmc_free(cell);
      return 1;
    }

    static int elmc_record_cell_release(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_RECORD) return 0;
      if (value->scalar == ELMC_RECORD_CELL_SCALAR) {
        ElmcRecordCell *cell = (ElmcRecordCell *)value;
        if (value->payload != &cell->record) return 0;
        elmc_free(cell);
        return 1;
      }
      if (value->scalar == ELMC_NAMED_RECORD_CELL_SCALAR) {
        ElmcNamedRecordCell *cell = (ElmcNamedRecordCell *)value;
        if (value->payload != &cell->record) return 0;
        elmc_free(cell);
        return 1;
      }
      return 0;
    }

    static int elmc_closure_cell_release(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_CLOSURE || value->scalar != ELMC_CLOSURE_CELL_SCALAR) return 0;
      ElmcClosureCell *cell = (ElmcClosureCell *)value;
      if (value->payload != &cell->closure) return 0;
      elmc_free(cell);
      return 1;
    }

    static RC elmc_record_cell_alloc(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values, int take) {
      if (field_count < 0) return RC_ERR_INVALID_ARG;
      size_t names_size = sizeof(const char *) * (size_t)field_count;
      size_t values_size = sizeof(ElmcValue *) * (size_t)field_count;
      ElmcNamedRecordCell *cell = (ElmcNamedRecordCell *)elmc_malloc(sizeof(ElmcNamedRecordCell) + names_size + values_size, __func__);
      if (!cell) {
        if (take) {
          for (int i = 0; i < field_count; i++) {
            elmc_release(field_values[i]);
          }
        }
        return RC_ERR_OUT_OF_MEMORY;
      }

      char *cursor = (char *)(cell + 1);
      cell->record.field_count = field_count;
      cell->record.mutation_gen = 0;
      cell->field_names = (const char **)cursor;
      cursor += names_size;
      cell->record.field_values = (ElmcValue **)cursor;

      for (int i = 0; i < field_count; i++) {
        cell->field_names[i] = field_names[i];
        cell->record.field_values[i] = take ? field_values[i] : elmc_retain(field_values[i]);
      }

      cell->value.rc = 1;
      cell->value.tag = ELMC_TAG_RECORD;
      cell->value.payload = &cell->record;
      cell->value.scalar = ELMC_NAMED_RECORD_CELL_SCALAR;
      ELMC_ALLOCATED += 1;
      ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
      *out = &cell->value;
      return RC_SUCCESS;
    }

    static RC elmc_record_cell_alloc_static(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values, int take) {
      return elmc_record_cell_alloc(out, field_count, (const char **)field_names, field_values, take);
    }

    static RC elmc_record_cell_alloc_values(ElmcValue **out, int field_count, ElmcValue **field_values, int take) {
      if (field_count < 0) return RC_ERR_INVALID_ARG;
      size_t values_size = sizeof(ElmcValue *) * (size_t)field_count;
      ElmcRecordCell *cell = (ElmcRecordCell *)elmc_malloc(sizeof(ElmcRecordCell) + values_size, __func__);
      if (!cell) {
        if (take) {
          for (int i = 0; i < field_count; i++) {
            elmc_release(field_values[i]);
          }
        }
        return RC_ERR_OUT_OF_MEMORY;
      }

      cell->record.field_count = field_count;
      cell->record.mutation_gen = 0;
      cell->record.field_values = (ElmcValue **)(cell + 1);

      for (int i = 0; i < field_count; i++) {
        cell->record.field_values[i] = take ? field_values[i] : elmc_retain(field_values[i]);
      }

      cell->value.rc = 1;
      cell->value.tag = ELMC_TAG_RECORD;
      cell->value.payload = &cell->record;
      cell->value.scalar = ELMC_RECORD_CELL_SCALAR;
      ELMC_ALLOCATED += 1;
      ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
      *out = &cell->value;
      return RC_SUCCESS;
    }

    static const char **elmc_record_field_names(ElmcValue *record) {
      if (!record || record->tag != ELMC_TAG_RECORD || record->scalar != ELMC_NAMED_RECORD_CELL_SCALAR) return NULL;
      ElmcNamedRecordCell *cell = (ElmcNamedRecordCell *)record;
      if (record->payload != &cell->record) return NULL;
      return cell->field_names;
    }

    #{Elmc.Runtime.IntList.implementation()}
    #{Elmc.Runtime.FloatList.implementation()}
    #{Elmc.Runtime.RecordSeq.implementation()}

    static RC elmc_list_materialize_cons(ElmcValue **out, ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        return elmc_int_list_to_cons(out, list);
      }
      if (list && list->tag == ELMC_TAG_RECORD_SEQ) {
        return elmc_record_seq_to_cons(out, list);
      }
      *out = elmc_retain(list);
      return RC_SUCCESS;
    }

    static RC elmc_list_reverse_into(ElmcValue **out, ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        return elmc_int_list_reverse_into(out, list);
      }
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          next = NULL;
          rc = elmc_list_cons(&next, node->head, rev);
          CHECK_RC(rc);
          elmc_release(rev);
          rev = next;
          next = NULL;
          cursor = node->tail;
        }
        if (rc == RC_SUCCESS) {
          *out = rev;
          rev = NULL;
        }
      CATCH_END;
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    static RC elmc_list_reverse_transfer(ElmcValue **out, ElmcValue **src) {
      ElmcValue *list = src ? *src : NULL;
      RC rc = elmc_list_reverse_into(out, list);
      if (rc == RC_SUCCESS && src && *src) {
        elmc_release(*src);
        *src = NULL;
      }
      return rc;
    }

    static ElmcValue *elmc_list_reverse_copy(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_reverse_into(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
    }

    RC elmc_new_int(ElmcValue **out, elmc_int_t value) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        ElmcValue *small = elmc_small_int(value);
        if (small) {
          *out = small;
        } else {
          rc = elmc_alloc_scalar(out, ELMC_TAG_INT, value);
          CHECK_RC(rc);
        }
      CATCH_END;
      return rc;
    }

    RC elmc_new_bool(ElmcValue **out, int value) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        *out = value ? &ELMC_BOOL_TRUE : &ELMC_BOOL_FALSE;
      CATCH_END;
      return rc;
    }

    ElmcValue *elmc_new_char(elmc_int_t value) {
      ElmcValue *out = NULL;
      if (elmc_alloc_scalar(&out, ELMC_TAG_CHAR, value) != RC_SUCCESS) return elmc_int_zero();
      return out;
    }

    static elmc_int_t elmc_char_normalize_code(elmc_int_t code) {
      if (code < 0 || code > 0x10FFFF) return 0xFFFD;
      if (code >= 0xD800 && code <= 0xDFFF) return 0xFFFD;
      return code;
    }

    ElmcValue *elmc_char_from_code_int(elmc_int_t code) {
      return elmc_new_char(elmc_char_normalize_code(code));
    }

    ElmcValue *elmc_char_from_code(ElmcValue *code) {
      return elmc_char_from_code_int(code ? elmc_as_int(code) : 0);
    }

    RC elmc_new_order(ElmcValue **out, elmc_int_t value) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        rc = elmc_alloc_scalar(out, ELMC_TAG_ORDER, value);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    RC elmc_new_string(ElmcValue **out, const char *value) {
      RC rc = RC_SUCCESS;
      char *ptr = NULL;
      CATCH_BEGIN
        if (!value) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          size_t len = strlen(value);
          ptr = (char *)elmc_malloc(len + 1, __func__);
          if (!ptr) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          if (len > 0) memcpy(ptr, value, len);
          ptr[len] = '\\0';
          ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, ptr);
          ptr = NULL;
          if (!allocated) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          allocated->scalar = (elmc_int_t)len;
          *out = allocated;
        }
      CATCH_END;
      if (ptr) elmc_free(ptr);
      return rc;
    }

    static size_t elmc_string_byte_len(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_STRING || !value->payload) return 0;
      if (value->scalar > 0) return (size_t)value->scalar;
      return strlen((const char *)value->payload);
    }

    static const void *elmc_memmem(const void *haystack, size_t hay_len, const void *needle, size_t needle_len) {
      const unsigned char *h = (const unsigned char *)haystack;
      const unsigned char *n = (const unsigned char *)needle;
      if (!h || !n) return NULL;
      if (needle_len == 0) return h;
      if (needle_len > hay_len) return NULL;
      for (size_t i = 0; i + needle_len <= hay_len; i++) {
        if (memcmp(h + i, n, needle_len) == 0) return h + i;
      }
      return NULL;
    }

    RC elmc_new_string_len(ElmcValue **out, const char *value, size_t len) {
      RC rc = RC_SUCCESS;
      char *ptr = NULL;
      CATCH_BEGIN
        if (!value || len == 0) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          ptr = (char *)elmc_malloc(len + 1, __func__);
          if (!ptr) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          memcpy(ptr, value, len);
          ptr[len] = '\\0';
          ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, ptr);
          ptr = NULL;
          if (!allocated) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          allocated->scalar = (elmc_int_t)len;
          *out = allocated;
        }
      CATCH_END;
      if (ptr) elmc_free(ptr);
      return rc;
    }

    ElmcValue *elmc_list_nil(void) {
      return &ELMC_LIST_NIL;
    }

    RC elmc_list_cons(ElmcValue **out, ElmcValue *head, ElmcValue *tail) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        rc = elmc_list_cell_alloc(out, head, tail, 0);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    ElmcValue *elmc_list_cons_take(ElmcValue *head, ElmcValue *tail) {
      ElmcValue *out = NULL;
      if (elmc_list_cell_alloc(&out, head, tail, 1) != RC_SUCCESS) {
        return elmc_int_zero();
      }
      return out;
    }

    RC elmc_list_from_values(ElmcValue **out, ElmcValue **items, int count) {
      RC rc = RC_SUCCESS;
      ElmcValue *list = elmc_list_nil();
      ElmcValue *next = NULL;
      CATCH_BEGIN
        if (!items || count <= 0) {
          *out = list;
          list = NULL;
        } else {
          for (int i = count - 1; i >= 0; i--) {
            next = NULL;
            rc = elmc_list_cons(&next, items[i], list);
            CHECK_RC(rc);
            elmc_release(list);
            list = next;
            next = NULL;
          }
          *out = list;
          list = NULL;
        }
      CATCH_END;
      elmc_release(next);
      elmc_release(list);
      return rc;
    }

    RC elmc_list_from_values_take(ElmcValue **out, ElmcValue **items, int count) {
      RC rc = RC_SUCCESS;
      ElmcValue *list = elmc_list_nil();
      ElmcValue *next = NULL;
      CATCH_BEGIN
        if (!items || count <= 0) {
          *out = list;
          list = NULL;
        } else {
          for (int i = count - 1; i >= 0; i--) {
            next = NULL;
            rc = elmc_list_cell_alloc(&next, items[i], list, 1);
            CHECK_RC(rc);
            list = next;
            next = NULL;
          }
          *out = list;
          list = NULL;
        }
      CATCH_END;
      elmc_release(next);
      elmc_release(list);
      return rc;
    }

    RC elmc_list_from_int_array(ElmcValue **out, const elmc_int_t *items, int count) {
      return elmc_int_list_alloc_copy(out, items, count);
    }

    RC elmc_list_from_int_array_reuse(ElmcValue **out, ElmcValue *existing, const elmc_int_t *items, int count) {
      return elmc_int_list_reuse_or_copy(out, existing, items, count);
    }

    RC elmc_render_cmd6_take(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4, elmc_int_t p5) {
      RC rc = RC_SUCCESS;
      const elmc_int_t ps[6] = { p0, p1, p2, p3, p4, p5 };
      CATCH_BEGIN
        ElmcValue *tail = elmc_int_zero();
        for (int i = 5; i >= 0; i--) {
          ElmcValue *pv = elmc_new_int_take(ps[i]);
          if (!pv) { rc = RC_ERR_OUT_OF_MEMORY; CHECK_RC(rc); }
          ElmcValue *pair = NULL;
          rc = elmc_tuple2_take(&pair, pv, tail);
          CHECK_RC(rc);
          tail = pair;
        }
        ElmcValue *kind_v = elmc_new_int_take(kind);
        if (!kind_v) { rc = RC_ERR_OUT_OF_MEMORY; CHECK_RC(rc); }
        rc = elmc_tuple2_take(out, kind_v, tail);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    RC elmc_render_text_cmd_take(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4, elmc_int_t p5, ElmcValue *text) {
      RC rc = RC_SUCCESS;
      const elmc_int_t ps[6] = { p0, p1, p2, p3, p4, p5 };
      CATCH_BEGIN
        ElmcValue *tail = text ? elmc_retain(text) : elmc_int_zero();
        if (!tail) { rc = RC_ERR_OUT_OF_MEMORY; CHECK_RC(rc); }
        for (int i = 5; i >= 0; i--) {
          ElmcValue *pv = elmc_new_int_take(ps[i]);
          if (!pv) { rc = RC_ERR_OUT_OF_MEMORY; CHECK_RC(rc); }
          ElmcValue *pair = NULL;
          rc = elmc_tuple2_take(&pair, pv, tail);
          CHECK_RC(rc);
          tail = pair;
        }
        ElmcValue *kind_v = elmc_new_int_take(kind);
        if (!kind_v) { rc = RC_ERR_OUT_OF_MEMORY; CHECK_RC(rc); }
        rc = elmc_tuple2_take(out, kind_v, tail);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    RC elmc_list_from_tuple2_int_array(ElmcValue **out, const elmc_int_t items[][2], int count) {
      RC rc = RC_SUCCESS;
      ElmcValue *list = elmc_list_nil();
      ElmcValue *item = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        if (!items || count <= 0) {
          *out = list;
          list = NULL;
        } else {
          for (int i = count - 1; i >= 0; i--) {
            item = NULL;
            rc = elmc_tuple2_ints(&item, items[i][0], items[i][1]);
            CHECK_RC(rc);
            next = NULL;
            rc = elmc_list_cons(&next, item, list);
            CHECK_RC(rc);
            elmc_release(item);
            item = NULL;
            elmc_release(list);
            list = next;
            next = NULL;
          }
          *out = list;
          list = NULL;
        }
      CATCH_END;
      elmc_release(item);
      elmc_release(next);
      elmc_release(list);
      return rc;
    }

    ElmcValue *elmc_list_replace_nth_int(ElmcValue *list, elmc_int_t index, elmc_int_t value) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        return elmc_int_list_replace_nth_int(list, index, value);
      }
      ElmcValue *cursor = list;
      ElmcValue *out = NULL;
      ElmcValue **tail_slot = NULL;
      elmc_int_t i = 0;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *head = NULL;
        if (i == index) {
          if (elmc_new_int(&head, value) != RC_SUCCESS) head = NULL;
          if (!head) {
            elmc_release(out);
            return elmc_retain(list);
          }
        } else {
          head = node->head;
        }
        ElmcValue *empty = elmc_list_nil();
        ElmcValue *cell = NULL;
        if (elmc_list_cons(&cell, head, empty) != RC_SUCCESS) cell = NULL;
        elmc_release(empty);
        if (i == index) {
          elmc_release(head);
        }
        if (!cell) {
          elmc_release(out);
          return elmc_retain(list);
        }
        if (tail_slot) {
          elmc_release(*tail_slot);
          *tail_slot = cell;
        } else {
          out = cell;
        }
        tail_slot = &((ElmcCons *)cell->payload)->tail;
        cursor = node->tail;
        i++;
      }
      return out ? out : elmc_list_nil();
    }

    ElmcValue *elmc_maybe_nothing(void) {
      return &ELMC_MAYBE_NOTHING;
    }

    RC elmc_maybe_just(ElmcValue **out, ElmcValue *value) {
      RC rc = RC_SUCCESS;
      ElmcMaybeCell *cell = NULL;
      CATCH_BEGIN
        cell = (ElmcMaybeCell *)elmc_malloc(sizeof(ElmcMaybeCell), __func__);
        if (!cell) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        cell->maybe.is_just = 1;
        cell->maybe.value = elmc_retain(value);
        cell->value.rc = 1;
        cell->value.tag = ELMC_TAG_MAYBE;
        cell->value.payload = &cell->maybe;
        cell->value.scalar = ELMC_MAYBE_CELL_SCALAR;
        ELMC_ALLOCATED += 1;
        ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
        *out = &cell->value;
        cell = NULL;
      CATCH_END;
      if (cell) elmc_release(&cell->value);
      return rc;
    }

    RC elmc_maybe_just_own(ElmcValue **out, ElmcValue *value) {
      RC rc = RC_SUCCESS;
      ElmcMaybeCell *cell = NULL;
      CATCH_BEGIN
        cell = (ElmcMaybeCell *)elmc_malloc(sizeof(ElmcMaybeCell), __func__);
        if (!cell) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        cell->maybe.is_just = 1;
        cell->maybe.value = value;
        cell->value.rc = 1;
        cell->value.tag = ELMC_TAG_MAYBE;
        cell->value.payload = &cell->maybe;
        cell->value.scalar = ELMC_MAYBE_CELL_SCALAR;
        ELMC_ALLOCATED += 1;
        ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
        *out = &cell->value;
        cell = NULL;
      CATCH_END;
      if (cell) {
        elmc_release(value);
        elmc_release(&cell->value);
      }
      return rc;
    }

    ElmcValue *elmc_maybe_or_tuple_just_payload_borrow(ElmcValue *maybe) {
      if (!maybe || !maybe->payload) return elmc_int_zero();
      if (maybe->tag == ELMC_TAG_MAYBE) {
        ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
        return m->is_just && m->value ? m->value : elmc_int_zero();
      }
      if (maybe->tag == ELMC_TAG_TUPLE2) {
        ElmcTuple2 *t = (ElmcTuple2 *)maybe->payload;
        if (elmc_as_int(t->first) != 1) return elmc_int_zero();
        return t->second ? t->second : elmc_int_zero();
      }
      return elmc_int_zero();
    }

    ElmcValue *elmc_maybe_or_tuple_just_payload(ElmcValue *maybe) {
      ElmcValue *borrowed = elmc_maybe_or_tuple_just_payload_borrow(maybe);
      if (!borrowed) return elmc_int_zero();
      return elmc_retain(borrowed);
    }

    RC elmc_result_ok(ElmcValue **out, ElmcValue *value) {
      RC rc = RC_SUCCESS;
      ElmcResultCell *cell = NULL;
      CATCH_BEGIN
        cell = (ElmcResultCell *)elmc_malloc(sizeof(ElmcResultCell), __func__);
        if (!cell) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        cell->result.is_ok = 1;
        cell->result.value = elmc_retain(value);
        cell->value.rc = 1;
        cell->value.tag = ELMC_TAG_RESULT;
        cell->value.payload = &cell->result;
        cell->value.scalar = ELMC_RESULT_CELL_SCALAR;
        ELMC_ALLOCATED += 1;
        ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
        *out = &cell->value;
        cell = NULL;
      CATCH_END;
      if (cell) elmc_release(&cell->value);
      return rc;
    }

    RC elmc_result_err(ElmcValue **out, ElmcValue *value) {
      RC rc = RC_SUCCESS;
      ElmcResultCell *cell = NULL;
      CATCH_BEGIN
        cell = (ElmcResultCell *)elmc_malloc(sizeof(ElmcResultCell), __func__);
        if (!cell) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        cell->result.is_ok = 0;
        cell->result.value = elmc_retain(value);
        cell->value.rc = 1;
        cell->value.tag = ELMC_TAG_RESULT;
        cell->value.payload = &cell->result;
        cell->value.scalar = ELMC_RESULT_CELL_SCALAR;
        ELMC_ALLOCATED += 1;
        ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
        *out = &cell->value;
        cell = NULL;
      CATCH_END;
      if (cell) elmc_release(&cell->value);
      return rc;
    }

    RC elmc_result_ok_own(ElmcValue **out, ElmcValue *value) {
      RC rc = RC_SUCCESS;
      ElmcResultCell *cell = NULL;
      CATCH_BEGIN
        cell = (ElmcResultCell *)elmc_malloc(sizeof(ElmcResultCell), __func__);
        if (!cell) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        cell->result.is_ok = 1;
        cell->result.value = value;
        cell->value.rc = 1;
        cell->value.tag = ELMC_TAG_RESULT;
        cell->value.payload = &cell->result;
        cell->value.scalar = ELMC_RESULT_CELL_SCALAR;
        ELMC_ALLOCATED += 1;
        ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
        *out = &cell->value;
        cell = NULL;
      CATCH_END;
      if (cell) {
        elmc_release(value);
        elmc_release(&cell->value);
      }
      return rc;
    }

    RC elmc_result_err_own(ElmcValue **out, ElmcValue *value) {
      RC rc = RC_SUCCESS;
      ElmcResultCell *cell = NULL;
      CATCH_BEGIN
        cell = (ElmcResultCell *)elmc_malloc(sizeof(ElmcResultCell), __func__);
        if (!cell) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        cell->result.is_ok = 0;
        cell->result.value = value;
        cell->value.rc = 1;
        cell->value.tag = ELMC_TAG_RESULT;
        cell->value.payload = &cell->result;
        cell->value.scalar = ELMC_RESULT_CELL_SCALAR;
        ELMC_ALLOCATED += 1;
        ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
        *out = &cell->value;
        cell = NULL;
      CATCH_END;
      if (cell) {
        elmc_release(value);
        elmc_release(&cell->value);
      }
      return rc;
    }

    RC elmc_tuple2(ElmcValue **out, ElmcValue *first, ElmcValue *second) {
      RC rc = RC_SUCCESS;
      ElmcTuple2Cell *cell = NULL;
      CATCH_BEGIN
        cell = (ElmcTuple2Cell *)elmc_malloc(sizeof(ElmcTuple2Cell), __func__);
        if (!cell) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        cell->tuple.first = elmc_retain(first);
        cell->tuple.second = elmc_retain(second);
        cell->value.rc = 1;
        cell->value.tag = ELMC_TAG_TUPLE2;
        cell->value.payload = &cell->tuple;
        cell->value.scalar = ELMC_TUPLE2_CELL_SCALAR;
        ELMC_ALLOCATED += 1;
        ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
        *out = &cell->value;
        cell = NULL;
      CATCH_END;
      if (cell) elmc_release(&cell->value);
      return rc;
    }

    RC elmc_tuple2_take(ElmcValue **out, ElmcValue *first, ElmcValue *second) {
      RC rc = RC_SUCCESS;
      ElmcTuple2Cell *cell = NULL;
      CATCH_BEGIN
        if (out && *out && *out != first && *out != second) {
          elmc_release(*out);
        }
        cell = (ElmcTuple2Cell *)elmc_malloc(sizeof(ElmcTuple2Cell), __func__);
        if (!cell) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        cell->tuple.first = first;
        cell->tuple.second = second;
        cell->value.rc = 1;
        cell->value.tag = ELMC_TAG_TUPLE2;
        cell->value.payload = &cell->tuple;
        cell->value.scalar = ELMC_TUPLE2_CELL_SCALAR;
        ELMC_ALLOCATED += 1;
        ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
        *out = &cell->value;
        cell = NULL;
      CATCH_END;
      if (cell) {
        elmc_release(&cell->value);
      } else if (rc != RC_SUCCESS) {
        elmc_release(first);
        elmc_release(second);
      }
      return rc;
    }

    ElmcValue *elmc_build_constructor_payload(ElmcValue **values, int count) {
      if (!values || count <= 0) return elmc_int_zero();
      if (count == 1) return values[0] ? elmc_retain(values[0]) : elmc_int_zero();
      ElmcValue *tail = elmc_build_constructor_payload(values + 1, count - 1);
      if (!tail) return elmc_int_zero();
      ElmcValue *left = values[0] ? elmc_retain(values[0]) : elmc_int_zero();
      ElmcValue *out = elmc_tuple2_take_value(left, tail);
      return out ? out : elmc_int_zero();
    }

    RC elmc_tuple2_ints(ElmcValue **out, elmc_int_t first, elmc_int_t second) {
      ElmcValue *f = NULL;
      ElmcValue *s = NULL;
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        rc = elmc_new_int(&f, first);
        CHECK_RC(rc);
        rc = elmc_new_int(&s, second);
        CHECK_RC(rc);
        rc = elmc_tuple2_take(out, f, s);
        CHECK_RC(rc);
        f = NULL;
        s = NULL;
      CATCH_END;
      elmc_release(f);
      elmc_release(s);
      return rc;
    }

    static RC elmc_cmd_alloc(ElmcValue **out, uint8_t arity, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4, elmc_int_t p5) {
      RC rc = RC_SUCCESS;
      ElmcCmdCell *cell = NULL;
      CATCH_BEGIN
        cell = (ElmcCmdCell *)elmc_malloc(sizeof(ElmcCmdCell), __func__);
        if (!cell) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        cell->cmd.arity = arity;
        cell->cmd.kind = kind;
        cell->cmd.p0 = p0;
        cell->cmd.p1 = p1;
        cell->cmd.p2 = p2;
        cell->cmd.p3 = p3;
        cell->cmd.p4 = p4;
        cell->cmd.p5 = p5;
        cell->cmd.text = NULL;
        cell->value.rc = 1;
        cell->value.tag = ELMC_TAG_CMD;
        cell->value.payload = &cell->cmd;
        cell->value.scalar = ELMC_CMD_CELL_SCALAR;
        ELMC_ALLOCATED += 1;
        ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
        *out = &cell->value;
        cell = NULL;
      CATCH_END
      if (cell) elmc_free(cell);
      return rc;
    }

    RC elmc_cmd0(ElmcValue **out, elmc_int_t kind) {
      return elmc_cmd_alloc(out, 0, kind, 0, 0, 0, 0, 0, 0);
    }

    static ElmcValue *elmc_platform_manager_tag(elmc_int_t tag_num) {
      ElmcValue *tag = elmc_small_int(tag_num);
      if (tag) return tag;
      ElmcValue *out = NULL;
      if (elmc_alloc_scalar(&out, ELMC_TAG_INT, tag_num) != RC_SUCCESS) return elmc_int_zero();
      return out;
    }

    static ElmcValue *elmc_platform_manager_port(ElmcValue *key, ElmcValue *leaf) {
      static const char *names[] = {"$", "k", "l"};
      ElmcValue *empty_key = NULL;
      if (!key && elmc_new_string(&empty_key, "") != RC_SUCCESS) empty_key = NULL;
      ElmcValue *values[3] = {
        elmc_platform_manager_tag(1),
        key ? elmc_retain(key) : (empty_key ? empty_key : elmc_int_zero()),
        leaf ? elmc_retain(leaf) : elmc_int_zero()
      };
      return elmc_record_new_static_take_value(3, names, values);
    }

    static ElmcValue *elmc_platform_manager_batch(elmc_int_t tag_num, ElmcValue *items) {
      static const char *names[] = {"$", "m"};
      ElmcValue *list = items ? elmc_retain(items) : elmc_list_nil();
      ElmcValue *values[2] = {elmc_platform_manager_tag(tag_num), list};
      return elmc_record_new_static_take_value(2, names, values);
    }

    static ElmcValue *elmc_platform_manager_map(elmc_int_t tag_num, ElmcValue *fn, ElmcValue *inner) {
      static const char *names[] = {"$", "n", "o"};
      ElmcValue *values[3] = {
        elmc_platform_manager_tag(tag_num),
        fn ? elmc_retain(fn) : elmc_int_zero(),
        inner ? elmc_retain(inner) : elmc_int_zero()
      };
      return elmc_record_new_static_take_value(3, names, values);
    }

    static int elmc_list_all_tag(ElmcValue *list, elmc_int_t tag) {
      ElmcValue *cursor = list;
      int saw_any = 0;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (!node->head) return saw_any;
        if (node->head->tag != tag) return 0;
        saw_any = 1;
        cursor = node->tail;
      }
      return saw_any;
    }

    static int elmc_cmd_cell_is_none(ElmcValue *value) {
      return !value || ((value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) && elmc_as_int(value) == 0);
    }

    static ElmcValue *elmc_cmd_batch_push_back(ElmcValue *flat, ElmcValue *entry) {
      if (!entry) return flat;
      if (elmc_cmd_cell_is_none(entry)) return flat;
      ElmcValue *cell = NULL;
      if (elmc_list_cons(&cell, entry, elmc_list_nil()) != RC_SUCCESS) return flat;
      if (!flat || (flat->tag == ELMC_TAG_LIST && flat->payload == NULL)) {
        elmc_release(flat);
        return cell;
      }
      if (flat->tag != ELMC_TAG_LIST) {
        elmc_release(cell);
        return flat;
      }
      ElmcValue **tail = &flat;
      ElmcValue *cursor = flat;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        tail = &node->tail;
        cursor = node->tail;
      }
      *tail = cell;
      return flat;
    }

    static ElmcValue *elmc_cmd_batch_append_entry(ElmcValue *flat, ElmcValue *entry) {
      if (!entry) return flat;
      if (elmc_cmd_cell_is_none(entry)) return flat;
      if (entry->tag == ELMC_TAG_CMD) {
        return elmc_cmd_batch_push_back(flat, entry);
      }
      if (entry->tag == ELMC_TAG_LIST) {
        ElmcValue *cursor = entry;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          flat = elmc_cmd_batch_append_entry(flat, node->head);
          cursor = node->tail;
        }
        return flat;
      }
      return elmc_cmd_batch_push_back(flat, entry);
    }

    ElmcValue *elmc_cmd_batch(ElmcValue *commands) {
      if (!commands) return elmc_list_nil();
      if (commands->tag == ELMC_TAG_CMD) {
        ElmcValue *next = NULL;
        if (elmc_list_cons(&next, commands, elmc_list_nil()) != RC_SUCCESS) return elmc_list_nil();
        return next;
      }
      if (commands->tag != ELMC_TAG_LIST) {
        ElmcValue *flat = elmc_cmd_batch_append_entry(NULL, commands);
        if (flat) return flat;
        return elmc_platform_manager_batch(2, commands);
      }
      if (elmc_list_all_tag(commands, ELMC_TAG_CMD)) {
        return elmc_platform_manager_batch(2, commands);
      }

      ElmcValue *flat = elmc_cmd_batch_append_entry(NULL, commands);
      if (flat) {
        return elmc_platform_manager_batch(2, flat);
      }
      return elmc_platform_manager_batch(2, commands);
    }

    ElmcValue *elmc_cmd_map(ElmcValue *f, ElmcValue *cmd) {
      if (cmd && cmd->tag == ELMC_TAG_CMD) {
        return cmd ? elmc_retain(cmd) : elmc_int_zero();
      }
      return elmc_platform_manager_map(3, f, cmd);
    }

    ElmcValue *elmc_sub_batch(ElmcValue *subs) {
      if (elmc_list_all_tag(subs, ELMC_TAG_SUB)) {
        return subs ? elmc_retain(subs) : elmc_list_nil();
      }
      return elmc_platform_manager_batch(2, subs);
    }

    ElmcValue *elmc_sub_map(ElmcValue *f, ElmcValue *sub) {
      if (sub && sub->tag == ELMC_TAG_SUB) {
        return sub ? elmc_retain(sub) : elmc_int_zero();
      }
      return elmc_platform_manager_map(3, f, sub);
    }

    ElmcValue *elmc_port_outgoing(ElmcValue *port_name, ElmcValue *payload) {
      return elmc_platform_manager_port(port_name, payload);
    }

    ElmcValue *elmc_port_incoming_sub(ElmcValue *port_name, ElmcValue *callback) {
      return elmc_platform_manager_port(port_name, callback);
    }

    RC elmc_cmd1(ElmcValue **out, elmc_int_t kind, elmc_int_t p0) {
      return elmc_cmd_alloc(out, 1, kind, p0, 0, 0, 0, 0, 0);
    }

    RC elmc_cmd1_string(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, const char *text) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        rc = elmc_cmd_alloc(out, 1, kind, p0, 0, 0, 0, 0, 0);
        CHECK_RC(rc);
        if (!*out || (*out)->tag != ELMC_TAG_CMD || !(*out)->payload) {
          rc = RC_ERR_INVALID_ARG;
          CHECK_RC(rc);
        }
        ElmcCmdPayload *cmd = (ElmcCmdPayload *)(*out)->payload;
        rc = elmc_new_string(&cmd->text, text ? text : "");
        CHECK_RC(rc);
      CATCH_END
      if (rc != RC_SUCCESS && out && *out) {
        elmc_release(*out);
        *out = NULL;
      }
      return rc;
    }

    RC elmc_cmd2(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1) {
      return elmc_cmd_alloc(out, 2, kind, p0, p1, 0, 0, 0, 0);
    }

    RC elmc_cmd3(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2) {
      return elmc_cmd_alloc(out, 3, kind, p0, p1, p2, 0, 0, 0);
    }

    RC elmc_cmd4(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3) {
      return elmc_cmd_alloc(out, 4, kind, p0, p1, p2, p3, 0, 0);
    }

    RC elmc_cmd5(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4) {
      return elmc_cmd_alloc(out, 5, kind, p0, p1, p2, p3, p4, 0);
    }

    static RC elmc_sub_alloc(ElmcValue **out, uint8_t arity, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4, elmc_int_t p5) {
      RC rc = RC_SUCCESS;
      ElmcSubCell *cell = NULL;
      CATCH_BEGIN
        cell = (ElmcSubCell *)elmc_malloc(sizeof(ElmcSubCell), __func__);
        if (!cell) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        cell->sub.arity = arity;
        cell->sub.mask = mask;
        cell->sub.p0 = p0;
        cell->sub.p1 = p1;
        cell->sub.p2 = p2;
        cell->sub.p3 = p3;
        cell->sub.p4 = p4;
        cell->sub.p5 = p5;
        cell->value.rc = 1;
        cell->value.tag = ELMC_TAG_SUB;
        cell->value.payload = &cell->sub;
        cell->value.scalar = ELMC_SUB_CELL_SCALAR;
        ELMC_ALLOCATED += 1;
        ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
        *out = &cell->value;
        cell = NULL;
      CATCH_END
      if (cell) elmc_free(cell);
      return rc;
    }

    RC elmc_sub0(ElmcValue **out, elmc_int_t mask) {
      return elmc_sub_alloc(out, 0, mask, 0, 0, 0, 0, 0, 0);
    }

    RC elmc_sub1(ElmcValue **out, elmc_int_t mask, elmc_int_t p0) {
      return elmc_sub_alloc(out, 1, mask, p0, 0, 0, 0, 0, 0);
    }

    RC elmc_sub2(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1) {
      return elmc_sub_alloc(out, 2, mask, p0, p1, 0, 0, 0, 0);
    }

    RC elmc_sub3(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2) {
      return elmc_sub_alloc(out, 3, mask, p0, p1, p2, 0, 0, 0);
    }

    RC elmc_sub4(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3) {
      return elmc_sub_alloc(out, 4, mask, p0, p1, p2, p3, 0, 0);
    }

    RC elmc_sub5(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4) {
      return elmc_sub_alloc(out, 5, mask, p0, p1, p2, p3, p4, 0);
    }

    elmc_int_t elmc_as_int(ElmcValue *value) {
      if (!value || (value->tag != ELMC_TAG_INT && value->tag != ELMC_TAG_BOOL && value->tag != ELMC_TAG_CHAR && value->tag != ELMC_TAG_ORDER)) return 0;
      if (value->tag == ELMC_TAG_INT && value->scalar == ELMC_UNIT_SCALAR) return 0;
      return value->scalar;
    }

    elmc_int_t elmc_as_int_number(ElmcValue *value) {
      if (!value) return 0;
      if (value->tag == ELMC_TAG_FLOAT) return (elmc_int_t)elmc_as_float(value);
      return elmc_as_int(value);
    }

    int elmc_value_is_unit(ElmcValue *value) {
      return value && value->tag == ELMC_TAG_INT && value->scalar == ELMC_UNIT_SCALAR;
    }

    elmc_int_t elmc_int_idiv(elmc_int_t numerator, elmc_int_t denominator) {
      if (denominator == 0) return 0;
      elmc_int_t quotient = numerator / denominator;
      elmc_int_t remainder = numerator % denominator;
      if (remainder != 0 && ((numerator < 0) != (denominator < 0))) {
        return quotient - 1;
      }
      return quotient;
    }

    elmc_int_t elmc_polar_point_x(elmc_int_t cx, elmc_int_t cy, elmc_int_t radius, elmc_int_t angle) {
      double theta = (double)angle * 2.0 * 3.14159265358979323846 / 65536.0;
      (void)cy;
      return cx + (elmc_int_t)lround(sin(theta) * (double)radius);
    }

    elmc_int_t elmc_polar_point_y(elmc_int_t cx, elmc_int_t cy, elmc_int_t radius, elmc_int_t angle) {
      double theta = (double)angle * 2.0 * 3.14159265358979323846 / 65536.0;
      (void)cx;
      return cy - (elmc_int_t)lround(cos(theta) * (double)radius);
    }

    elmc_int_t elmc_as_bool(ElmcValue *value) {
      return elmc_as_int(value) != 0;
    }

    int elmc_list_equal_int(ElmcValue *left, ElmcValue *right) {
      if (left == right) return 1;
      if (left && left->tag == ELMC_TAG_INT_LIST && right && right->tag == ELMC_TAG_INT_LIST) {
        ElmcIntListPayload *a = elmc_int_list_payload(left);
        ElmcIntListPayload *b = elmc_int_list_payload(right);
        if (!a || !b) return a == b;
        if (a->length != b->length) return 0;
        for (int i = 0; i < a->length; i++) {
          if (a->values[i] != b->values[i]) return 0;
        }
        return 1;
      }
      ElmcValue *a = left;
      ElmcValue *b = right;
      while (a && b && a->tag == ELMC_TAG_LIST && b->tag == ELMC_TAG_LIST) {
        if (!a->payload || !b->payload) return a->payload == b->payload;
        ElmcCons *ca = (ElmcCons *)a->payload;
        ElmcCons *cb = (ElmcCons *)b->payload;
        if (elmc_as_int(ca->head) != elmc_as_int(cb->head)) return 0;
        a = ca->tail;
        b = cb->tail;
      }
      return 0;
    }

    int elmc_value_equal(ElmcValue *left, ElmcValue *right) {
      if (left == right) return 1;
      if (!left || !right) return 0;
      if (left->tag != right->tag) {
        if ((left->tag == ELMC_TAG_INT || left->tag == ELMC_TAG_BOOL ||
             left->tag == ELMC_TAG_CHAR || left->tag == ELMC_TAG_ORDER) &&
            (right->tag == ELMC_TAG_INT || right->tag == ELMC_TAG_BOOL ||
             right->tag == ELMC_TAG_CHAR || right->tag == ELMC_TAG_ORDER)) {
          return elmc_as_int(left) == elmc_as_int(right);
        }
        if (left->tag == ELMC_TAG_MAYBE && left->payload && right->tag == ELMC_TAG_INT) {
          ElmcMaybe *maybe = (ElmcMaybe *)left->payload;
          return !maybe->is_just && elmc_as_int(right) == 0;
        }
        if (right->tag == ELMC_TAG_MAYBE && right->payload && left->tag == ELMC_TAG_INT) {
          ElmcMaybe *maybe = (ElmcMaybe *)right->payload;
          return !maybe->is_just && elmc_as_int(left) == 0;
        }
        if (left->tag == ELMC_TAG_MAYBE && left->payload && right->tag == ELMC_TAG_TUPLE2 && right->payload) {
          ElmcMaybe *maybe = (ElmcMaybe *)left->payload;
          ElmcTuple2 *tuple = (ElmcTuple2 *)right->payload;
          int tag = (int)elmc_as_int(tuple->first);
          return maybe->is_just ? (tag == 1 && elmc_value_equal(maybe->value, tuple->second)) : tag == 0;
        }
        if (right->tag == ELMC_TAG_MAYBE && right->payload && left->tag == ELMC_TAG_TUPLE2 && left->payload) {
          return elmc_value_equal(right, left);
        }
        return 0;
      }

      switch (left->tag) {
        case ELMC_TAG_INT:
        case ELMC_TAG_BOOL:
        case ELMC_TAG_CHAR:
        case ELMC_TAG_ORDER:
          return elmc_as_int(left) == elmc_as_int(right);

        case ELMC_TAG_FLOAT:
          return elmc_as_float(left) == elmc_as_float(right);

        case ELMC_TAG_STRING:
          if (!left->payload || !right->payload) return left->payload == right->payload;
          {
            size_t left_len = elmc_string_byte_len(left);
            size_t right_len = elmc_string_byte_len(right);
            if (left_len != right_len) return 0;
            return memcmp(left->payload, right->payload, left_len) == 0;
          }

        case ELMC_TAG_LIST: {
          ElmcValue *a = left;
          ElmcValue *b = right;
          while (a && b && a->tag == ELMC_TAG_LIST && b->tag == ELMC_TAG_LIST) {
            if (!a->payload || !b->payload) return a->payload == b->payload;
            ElmcCons *ca = (ElmcCons *)a->payload;
            ElmcCons *cb = (ElmcCons *)b->payload;
            if (!elmc_value_equal(ca->head, cb->head)) return 0;
            a = ca->tail;
            b = cb->tail;
          }
          return 0;
        }

        case ELMC_TAG_INT_LIST: {
          if (left->tag != ELMC_TAG_INT_LIST || right->tag != ELMC_TAG_INT_LIST) return 0;
          ElmcIntListPayload *a = elmc_int_list_payload(left);
          ElmcIntListPayload *b = elmc_int_list_payload(right);
          if (!a || !b) return a == b;
          if (a->length != b->length) return 0;
          for (int i = 0; i < a->length; i++) {
            if (a->values[i] != b->values[i]) return 0;
          }
          return 1;
        }

        case ELMC_TAG_TUPLE2: {
          if (!left->payload || !right->payload) return left->payload == right->payload;
          ElmcTuple2 *a = (ElmcTuple2 *)left->payload;
          ElmcTuple2 *b = (ElmcTuple2 *)right->payload;
          return elmc_value_equal(a->first, b->first) && elmc_value_equal(a->second, b->second);
        }

        case ELMC_TAG_CMD: {
          if (!left->payload || !right->payload) return left->payload == right->payload;
          ElmcCmdPayload *a = (ElmcCmdPayload *)left->payload;
          ElmcCmdPayload *b = (ElmcCmdPayload *)right->payload;
          if (a->arity != b->arity || a->kind != b->kind) return 0;
          if (a->arity > 0 && a->p0 != b->p0) return 0;
          if (a->arity > 1 && a->p1 != b->p1) return 0;
          if (a->arity > 2 && a->p2 != b->p2) return 0;
          if (a->arity > 3 && a->p3 != b->p3) return 0;
          if (a->arity > 4 && a->p4 != b->p4) return 0;
          if (a->arity > 5 && a->p5 != b->p5) return 0;
          if (!elmc_value_equal(a->text, b->text)) return 0;
          return 1;
        }

        case ELMC_TAG_SUB: {
          if (!left->payload || !right->payload) return left->payload == right->payload;
          ElmcSubPayload *a = (ElmcSubPayload *)left->payload;
          ElmcSubPayload *b = (ElmcSubPayload *)right->payload;
          if (a->arity != b->arity || a->mask != b->mask) return 0;
          if (a->arity > 0 && a->p0 != b->p0) return 0;
          if (a->arity > 1 && a->p1 != b->p1) return 0;
          if (a->arity > 2 && a->p2 != b->p2) return 0;
          if (a->arity > 3 && a->p3 != b->p3) return 0;
          if (a->arity > 4 && a->p4 != b->p4) return 0;
          if (a->arity > 5 && a->p5 != b->p5) return 0;
          return 1;
        }

        case ELMC_TAG_MAYBE: {
          if (!left->payload || !right->payload) return left->payload == right->payload;
          ElmcMaybe *a = (ElmcMaybe *)left->payload;
          ElmcMaybe *b = (ElmcMaybe *)right->payload;
          if (a->is_just != b->is_just) return 0;
          return !a->is_just || elmc_value_equal(a->value, b->value);
        }

        case ELMC_TAG_RESULT: {
          if (!left->payload || !right->payload) return left->payload == right->payload;
          ElmcResult *a = (ElmcResult *)left->payload;
          ElmcResult *b = (ElmcResult *)right->payload;
          return a->is_ok == b->is_ok && elmc_value_equal(a->value, b->value);
        }

        case ELMC_TAG_RECORD: {
          if (!left->payload || !right->payload) return left->payload == right->payload;
          ElmcRecord *a = (ElmcRecord *)left->payload;
          ElmcRecord *b = (ElmcRecord *)right->payload;
          if (a->field_count != b->field_count) return 0;
          const char **a_names = elmc_record_field_names(left);
          const char **b_names = elmc_record_field_names(right);
          if ((a_names != NULL) != (b_names != NULL)) {
            for (int i = 0; i < a->field_count; i++) {
              if (!elmc_value_equal(a->field_values[i], b->field_values[i])) return 0;
            }
            return 1;
          }
          if (!a_names) {
            for (int i = 0; i < a->field_count; i++) {
              if (!elmc_value_equal(a->field_values[i], b->field_values[i])) return 0;
            }
            return 1;
          }
          for (int i = 0; i < a->field_count; i++) {
            int found = 0;
            for (int j = 0; j < b->field_count; j++) {
              if (strcmp(a_names[i], b_names[j]) == 0) {
                if (!elmc_value_equal(a->field_values[i], b->field_values[j])) return 0;
                found = 1;
                break;
              }
            }
            if (!found) return 0;
          }
          return 1;
        }

        default:
          return left->payload == right->payload;
      }
    }

    int elmc_string_length(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_STRING) return 0;
      return (int)elmc_string_byte_len(value);
    }

    ElmcValue *elmc_list_head(ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        ElmcIntListPayload *payload = elmc_int_list_payload(list);
        if (!payload || payload->length <= 0) return elmc_maybe_nothing();
        {
          ElmcValue *boxed = elmc_new_int_take(payload->values[0]);
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_maybe_just(&_elmc_rc_out, boxed) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
        }
      }
      if (list && list->tag == ELMC_TAG_RECORD_SEQ) {
        if (elmc_record_seq_is_empty(list)) return elmc_maybe_nothing();
        {
          ElmcValue *head = elmc_record_seq_get(list, 0);
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_maybe_just(&_elmc_rc_out, head) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
        }
      }
      if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) return elmc_maybe_nothing();
      ElmcCons *node = (ElmcCons *)list->payload;
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_maybe_just(&_elmc_rc_out, node->head) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_list_nth_maybe(ElmcValue *list, ElmcValue *index) {
      elmc_int_t idx = elmc_as_int(index);
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        ElmcIntListPayload *payload = elmc_int_list_payload(list);
        if (!payload || idx < 0 || idx >= payload->length) return elmc_maybe_nothing();
        {
          ElmcValue *boxed = elmc_new_int_take(payload->values[idx]);
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_maybe_just(&_elmc_rc_out, boxed) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
        }
      }
      if (idx < 0 || !list || list->tag != ELMC_TAG_LIST) return elmc_maybe_nothing();
      ElmcValue *cursor = list;
      while (idx > 0) {
        if (!cursor || cursor->tag != ELMC_TAG_LIST || cursor->payload == NULL) return elmc_maybe_nothing();
        cursor = ((ElmcCons *)cursor->payload)->tail;
        idx--;
      }
      if (!cursor || cursor->tag != ELMC_TAG_LIST || cursor->payload == NULL) return elmc_maybe_nothing();
      ElmcCons *node = (ElmcCons *)cursor->payload;
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_maybe_just(&_elmc_rc_out, node->head) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    elmc_int_t elmc_list_nth_int_default(ElmcValue *list, elmc_int_t index, elmc_int_t default_value) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        ElmcIntListPayload *payload = elmc_int_list_payload(list);
        if (!payload || index < 0 || index >= payload->length) return default_value;
        return payload->values[index];
      }
      if (index < 0 || !list || list->tag != ELMC_TAG_LIST) return default_value;
      ElmcValue *cursor = list;
      while (index > 0) {
        if (!cursor || cursor->tag != ELMC_TAG_LIST || cursor->payload == NULL) return default_value;
        cursor = ((ElmcCons *)cursor->payload)->tail;
        index--;
      }
      if (!cursor || cursor->tag != ELMC_TAG_LIST || cursor->payload == NULL) return default_value;
      ElmcCons *node = (ElmcCons *)cursor->payload;
      return node->head ? elmc_as_int(node->head) : default_value;
    }

    ElmcValue *elmc_list_nth_int_default_boxed(ElmcValue *list, ElmcValue *index, ElmcValue *default_value) {
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, elmc_list_nth_int_default(list, elmc_as_int(index), elmc_as_int(default_value))) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    elmc_int_t elmc_list_head_with_default_int(elmc_int_t default_val, ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        ElmcIntListPayload *payload = elmc_int_list_payload(list);
        if (!payload || payload->length <= 0) return default_val;
        return payload->values[0];
      }
      if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) return default_val;
      ElmcCons *node = (ElmcCons *)list->payload;
      return elmc_as_int(node->head);
    }

    ElmcValue *elmc_tuple_second(ElmcValue *tuple) {
      if (!tuple || tuple->tag != ELMC_TAG_TUPLE2 || tuple->payload == NULL) return elmc_int_zero();
      ElmcTuple2 *data = (ElmcTuple2 *)tuple->payload;
      return elmc_retain(data->second);
    }

    ElmcValue *elmc_tuple_first(ElmcValue *tuple) {
      if (!tuple || tuple->tag != ELMC_TAG_TUPLE2 || tuple->payload == NULL) return elmc_int_zero();
      ElmcTuple2 *data = (ElmcTuple2 *)tuple->payload;
      return elmc_retain(data->first);
    }

    ElmcValue *elmc_tuple_second_borrow(ElmcValue *tuple) {
      if (!tuple || tuple->tag != ELMC_TAG_TUPLE2 || tuple->payload == NULL) return elmc_int_zero();
      ElmcTuple2 *data = (ElmcTuple2 *)tuple->payload;
      return data->second ? data->second : elmc_int_zero();
    }

    ElmcValue *elmc_tuple_first_borrow(ElmcValue *tuple) {
      if (!tuple || tuple->tag != ELMC_TAG_TUPLE2 || tuple->payload == NULL) return elmc_int_zero();
      ElmcTuple2 *data = (ElmcTuple2 *)tuple->payload;
      return data->first ? data->first : elmc_int_zero();
    }

    ElmcValue *elmc_result_inc_or_zero(ElmcValue *result) {
      if (!result || result->tag != ELMC_TAG_RESULT || result->payload == NULL) return elmc_int_zero();
      ElmcResult *data = (ElmcResult *)result->payload;
      if (!data->is_ok || !data->value) return elmc_int_zero();
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, elmc_as_int(data->value) + 1) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_basics_max(ElmcValue *left, ElmcValue *right) {
      ElmcValue *cmp = elmc_basics_compare_take(left, right);
      int take_left = elmc_as_int(cmp) >= 0;
      elmc_release(cmp);
      return take_left ? elmc_retain(left) : elmc_retain(right);
    }

    ElmcValue *elmc_basics_min(ElmcValue *left, ElmcValue *right) {
      ElmcValue *cmp = elmc_basics_compare_take(left, right);
      int take_left = elmc_as_int(cmp) <= 0;
      elmc_release(cmp);
      return take_left ? elmc_retain(left) : elmc_retain(right);
    }

    ElmcValue *elmc_basics_clamp(ElmcValue *low, ElmcValue *high, ElmcValue *value) {
      ElmcValue *below = elmc_basics_compare_take(value, low);
      if (elmc_as_int(below) < 0) {
        elmc_release(below);
        return elmc_retain(low);
      }
      elmc_release(below);

      ElmcValue *above = elmc_basics_compare_take(value, high);
      if (elmc_as_int(above) > 0) {
        elmc_release(above);
        return elmc_retain(high);
      }
      elmc_release(above);
      return elmc_retain(value);
    }

    ElmcValue *elmc_basics_mod_by(ElmcValue *base, ElmcValue *value) {
      elmc_int_t b = elmc_as_int(base);
      elmc_int_t v = elmc_as_int(value);
      if (b == 0) return elmc_int_zero();
      elmc_int_t result = v % b;
      if (result < 0) result += (b < 0 ? -b : b);
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, result) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_bitwise_and(ElmcValue *left, ElmcValue *right) {
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, elmc_as_int(left) & elmc_as_int(right)) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_bitwise_or(ElmcValue *left, ElmcValue *right) {
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, elmc_as_int(left) | elmc_as_int(right)) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_bitwise_xor(ElmcValue *left, ElmcValue *right) {
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, elmc_as_int(left) ^ elmc_as_int(right)) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_bitwise_complement(ElmcValue *value) {
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, ~elmc_as_int(value)) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_bitwise_shift_left_by(ElmcValue *bits, ElmcValue *value) {
      int64_t b = elmc_as_int(bits);
      if (b < 0) b = 0;
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, elmc_as_int(value) << b) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_bitwise_shift_right_by(ElmcValue *bits, ElmcValue *value) {
      int64_t b = elmc_as_int(bits);
      if (b < 0) b = 0;
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, elmc_as_int(value) >> b) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_bitwise_shift_right_zf_by(ElmcValue *bits, ElmcValue *value) {
      int64_t b = elmc_as_int(bits);
      if (b < 0) b = 0;
      uint32_t raw = (uint32_t)(int32_t)elmc_as_int(value);
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, (int64_t)(raw >> b)) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_char_to_code(ElmcValue *value) {
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, elmc_as_int(value)) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_debug_log(ElmcValue *label, ElmcValue *value) {
      ElmcValue *label_text = elmc_debug_to_string(label);
      ElmcValue *value_text = elmc_debug_to_string(value);
      const char *label_cstr = (label_text && label_text->tag == ELMC_TAG_STRING && label_text->payload)
          ? (const char *)label_text->payload
          : "<label>";
      const char *value_cstr = (value_text && value_text->tag == ELMC_TAG_STRING && value_text->payload)
          ? (const char *)value_text->payload
          : "<value>";
    #ifdef ELMC_PEBBLE_PLATFORM
      APP_LOG(APP_LOG_LEVEL_INFO, "%s: %s", label_cstr, value_cstr);
    #else
      (void)label_cstr;
      (void)value_cstr;
    #endif
      if (label_text) elmc_release(label_text);
      if (value_text) elmc_release(value_text);
      return elmc_retain(value);
    }

    ElmcValue *elmc_debug_todo(ElmcValue *label) {
      (void)label;
      return elmc_int_zero();
    }

    static RC elmc_debug_append_cstr(ElmcValue **out, const char *piece);
    static char *elmc_debug_escape_string(const char *str);
    static int elmc_utf8_encode_codepoint(uint32_t cp, char *out, size_t cap);
    static int elmc_utf8_decode_codepoint(const unsigned char **p, const unsigned char *end, uint32_t *cp_out);
    static size_t elmc_utf8_codepoint_count(const char *src);
    static const char *elmc_utf8_byte_offset_at_codepoint(const char *src, int64_t index);
    static RC elmc_rc_assign_new_char(ElmcValue **out, elmc_int_t code);
    static RC elmc_debug_append_char(ElmcValue **out, elmc_int_t code);
    static RC elmc_debug_format_into(ElmcValue **out, ElmcValue *value);
    const char *elmc_debug_union_ctor_name(elmc_int_t tag);
    static RC elmc_debug_format_union_payload(ElmcValue **out, const char *ctor_name, ElmcValue *payload);
    static int elmc_is_task_result(ElmcValue *value);
    static const char *elmc_task_debug_ctor_name(ElmcValue *value);
    static ElmcValue *elmc_task_wrap(ElmcValue *value, elmc_int_t task_scalar);
    static ElmcValue *elmc_task_wrap_pair(ElmcValue *f, ElmcValue *task, elmc_int_t task_scalar);

    static RC elmc_debug_append_cstr(ElmcValue **out, const char *piece) {
      if (!piece) piece = "";
      if (!*out) return elmc_new_string(out, piece);
      const char *existing =
        ((*out)->tag == ELMC_TAG_STRING && (*out)->payload) ? (const char *)(*out)->payload : "";
      ElmcValue *next = NULL;
      RC rc = elmc_string_append_native(&next, existing, piece);
      if (rc == RC_SUCCESS) {
        elmc_release(*out);
        *out = next;
      }
      return rc;
    }

    static RC elmc_debug_append_float(ElmcValue **out, double value) {
      char buffer[64];
      if (value != value) {
        return elmc_debug_append_cstr(out, "nan");
      }
      if (value > 1e308 || value < -1e308) {
        return elmc_debug_append_cstr(out, value < 0.0 ? "-Infinity" : "Infinity");
      }
      snprintf(buffer, sizeof(buffer), "%.6g", value);
      return elmc_debug_append_cstr(out, buffer);
    }

    static char *elmc_debug_escape_string(const char *str) {
      if (!str) str = "";
      size_t len = strlen(str);
      char *buf = (char *)elmc_malloc(len * 2 + 4, __func__);
      if (!buf) return NULL;
      char *out = buf;
      *out++ = '"';
      for (const char *p = str; *p; p++) {
        switch (*p) {
          case '\\\\': *out++ = '\\\\'; *out++ = '\\\\'; break;
          case '"': *out++ = '\\\\'; *out++ = '"'; break;
          case '\\n': *out++ = '\\\\'; *out++ = 'n'; break;
          case '\\r': *out++ = '\\\\'; *out++ = 'r'; break;
          case '\\t': *out++ = '\\\\'; *out++ = 't'; break;
          case '\\v': *out++ = '\\\\'; *out++ = 'v'; break;
          case '\\0': *out++ = '\\\\'; *out++ = '0'; break;
          default: *out++ = *p; break;
        }
      }
      *out++ = '"';
      *out = '\\0';
      return buf;
    }

    static int elmc_utf8_encode_codepoint(uint32_t cp, char *out, size_t cap) {
      if (!out || cap == 0) return 0;
      if (cp <= 0x7F) {
        if (cap < 2) return 0;
        out[0] = (char)cp;
        out[1] = '\\0';
        return 1;
      }
      if (cp <= 0x7FF) {
        if (cap < 3) return 0;
        out[0] = (char)(0xC0 | (cp >> 6));
        out[1] = (char)(0x80 | (cp & 0x3F));
        out[2] = '\\0';
        return 2;
      }
      if (cp <= 0xFFFF) {
        if (cap < 4) return 0;
        out[0] = (char)(0xE0 | (cp >> 12));
        out[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[2] = (char)(0x80 | (cp & 0x3F));
        out[3] = '\\0';
        return 3;
      }
      if (cap < 5) return 0;
      out[0] = (char)(0xF0 | (cp >> 18));
      out[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
      out[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
      out[3] = (char)(0x80 | (cp & 0x3F));
      out[4] = '\\0';
      return 4;
    }

    static int elmc_utf8_decode_codepoint(const unsigned char **p, const unsigned char *end, uint32_t *cp_out) {
      if (!p || !*p || !cp_out || *p >= end) return 0;
      const unsigned char *s = *p;
      unsigned char c0 = s[0];
      if (c0 < 0x80) {
        *cp_out = (uint32_t)c0;
        *p = s + 1;
        return 1;
      }
      if ((c0 & 0xE0) == 0xC0 && s + 1 < end) {
        *cp_out = ((uint32_t)(c0 & 0x1F) << 6) | (uint32_t)(s[1] & 0x3F);
        *p = s + 2;
        return 1;
      }
      if ((c0 & 0xF0) == 0xE0 && s + 2 < end) {
        *cp_out = ((uint32_t)(c0 & 0x0F) << 12) | ((uint32_t)(s[1] & 0x3F) << 6) | (uint32_t)(s[2] & 0x3F);
        *p = s + 3;
        return 1;
      }
      if ((c0 & 0xF8) == 0xF0 && s + 3 < end) {
        *cp_out = ((uint32_t)(c0 & 0x07) << 18) | ((uint32_t)(s[1] & 0x3F) << 12) |
                  ((uint32_t)(s[2] & 0x3F) << 6) | (uint32_t)(s[3] & 0x3F);
        *p = s + 4;
        return 1;
      }
      *cp_out = 0xFFFD;
      *p = s + 1;
      return 1;
    }

    static size_t elmc_utf8_codepoint_count(const char *src) {
      if (!src) return 0;
      const unsigned char *p = (const unsigned char *)src;
      const unsigned char *end = p + strlen(src);
      size_t count = 0;
      while (p < end) {
        uint32_t cp;
        if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
        count++;
      }
      return count;
    }

    static const char *elmc_utf8_byte_offset_at_codepoint(const char *src, int64_t index) {
      if (!src || index <= 0) return src ? src : "";
      const unsigned char *p = (const unsigned char *)src;
      const unsigned char *end = p + strlen(src);
      int64_t i = 0;
      while (p < end && i < index) {
        uint32_t cp;
        if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
        i++;
      }
      return (const char *)p;
    }

    static RC elmc_rc_assign_new_char(ElmcValue **out, elmc_int_t code) {
      ElmcValue *ch = elmc_new_char(code);
      if (!ch) return RC_ERR_OUT_OF_MEMORY;
      *out = ch;
      return RC_SUCCESS;
    }

    static RC elmc_debug_append_char(ElmcValue **out, elmc_int_t code) {
      char buf[16];
      const char *piece = buf;
      if (code == 0) piece = "'\\\\0'";
      else if (code == '\\\\') piece = "'\\\\'";
      else if (code == '\\'') piece = "'\\''";
      else if (code == '\\n') piece = "'\\n'";
      else if (code == '\\r') piece = "'\\r'";
      else if (code == '\\t') piece = "'\\t'";
      else {
        char utf8[8];
        int n = elmc_utf8_encode_codepoint((uint32_t)code, utf8, sizeof(utf8));
        if (n <= 0) return RC_ERR_INVALID_ARG;
        buf[0] = '\\'';
        memcpy(buf + 1, utf8, (size_t)n);
        buf[1 + n] = '\\'';
        buf[2 + n] = '\\0';
      }
      return elmc_debug_append_cstr(out, piece);
    }

    static int elmc_is_task_result(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_RESULT) return 0;
      elmc_int_t scalar = value->scalar;
      return scalar >= ELMC_TASK_SUCCEED_SCALAR && scalar <= ELMC_TASK_SPAWN_SCALAR;
    }

    static const char *elmc_task_debug_ctor_name(ElmcValue *value) {
      if (!elmc_is_task_result(value)) return NULL;
      switch (value->scalar) {
        case ELMC_TASK_SUCCEED_SCALAR: return "<Task:succeed>";
        case ELMC_TASK_FAIL_SCALAR: return "<Task:fail>";
        case ELMC_TASK_AND_THEN_SCALAR: return "<Task:andThen>";
        case ELMC_TASK_SPAWN_SCALAR: return "<Task:spawn>";
        case ELMC_TASK_MAP_SCALAR: {
          if (!value->payload) return "<Task:map>";
          ElmcResult *result = (ElmcResult *)value->payload;
          ElmcValue *payload = result->value;
          if (payload && payload->tag == ELMC_TAG_TUPLE2 && payload->payload) {
            ElmcTuple2 *pair = (ElmcTuple2 *)payload->payload;
            const char *inner = elmc_task_debug_ctor_name(pair->second);
            if (inner) return inner;
          }
          return "<Task:map>";
        }
        default: return NULL;
      }
    }

    static ElmcValue *elmc_task_wrap(ElmcValue *value, elmc_int_t task_scalar) {
      ElmcValue *out = NULL;
      if (elmc_result_ok(&out, value) != RC_SUCCESS) return NULL;
      out->scalar = task_scalar;
      return out;
    }

    static ElmcValue *elmc_task_wrap_pair(ElmcValue *f, ElmcValue *task, elmc_int_t task_scalar) {
      ElmcValue *pair = NULL;
      if (elmc_tuple2(&pair, f, task) != RC_SUCCESS) return NULL;
      ElmcValue *out = elmc_task_wrap(pair, task_scalar);
      elmc_release(pair);
      return out;
    }

    static RC elmc_debug_format_union_payload(ElmcValue **out, const char *ctor_name, ElmcValue *payload) {
      RC rc = RC_SUCCESS;
      ElmcValue *part = NULL;
      CATCH_BEGIN
        if (!payload) {
        } else if (payload->tag == ELMC_TAG_INT && elmc_as_int(payload) == 0) {
        } else if (ctor_name && strcmp(ctor_name, "Char") == 0 &&
                   (payload->tag == ELMC_TAG_INT || payload->tag == ELMC_TAG_CHAR)) {
          rc = elmc_debug_append_cstr(out, " ");
          CHECK_RC(rc);
          rc = elmc_debug_append_char(out, elmc_as_int(payload));
          CHECK_RC(rc);
        } else if (payload->tag == ELMC_TAG_TUPLE2 && payload->payload != NULL) {
          ElmcValue *cursor = payload;
          int first = 1;
          while (cursor && cursor->tag == ELMC_TAG_TUPLE2 && cursor->payload != NULL) {
            ElmcTuple2 *node = (ElmcTuple2 *)cursor->payload;
            if (!first) {
              rc = elmc_debug_append_cstr(out, " ");
              CHECK_RC(rc);
            }
            part = NULL;
            rc = elmc_debug_format_into(&part, node->first);
            CHECK_RC(rc);
            const char *piece =
              (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
            rc = elmc_debug_append_cstr(out, piece);
            CHECK_RC(rc);
            elmc_release(part);
            part = NULL;
            first = 0;
            cursor = node->second;
            if (cursor && cursor->tag != ELMC_TAG_TUPLE2) {
              rc = elmc_debug_append_cstr(out, " ");
              CHECK_RC(rc);
              part = NULL;
              rc = elmc_debug_format_into(&part, cursor);
              CHECK_RC(rc);
              piece =
                (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
              rc = elmc_debug_append_cstr(out, piece);
              CHECK_RC(rc);
              elmc_release(part);
              part = NULL;
              cursor = NULL;
            }
          }
        } else {
          rc = elmc_debug_append_cstr(out, " ");
          CHECK_RC(rc);
          part = NULL;
          rc = elmc_debug_format_into(&part, payload);
          CHECK_RC(rc);
          const char *piece =
            (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
          int parenless =
            piece[0] == '{' || piece[0] == '(' || piece[0] == '[' || piece[0] == '<' || piece[0] == '"' ||
            (piece[0] >= 'A' && piece[0] <= 'Z');
          if (!parenless) {
            rc = elmc_debug_append_cstr(out, "(");
            CHECK_RC(rc);
          }
          rc = elmc_debug_append_cstr(out, piece);
          CHECK_RC(rc);
          if (!parenless) {
            rc = elmc_debug_append_cstr(out, ")");
            CHECK_RC(rc);
          }
          elmc_release(part);
          part = NULL;
        }
      CATCH_END;
      elmc_release(part);
      return rc;
    }

    static RC elmc_debug_format_into(ElmcValue **out, ElmcValue *value) {
      RC rc = RC_SUCCESS;
      char *escaped = NULL;
      char buffer[64];
      ElmcValue *part = NULL;
      CATCH_BEGIN
        if (!value) {
          rc = elmc_debug_append_cstr(out, "<null>");
          CHECK_RC(rc);
          return rc;
        }

        switch (value->tag) {
          case ELMC_TAG_STRING: {
            const char *text = value->payload ? (const char *)value->payload : "";
            escaped = elmc_debug_escape_string(text);
            if (!escaped) { rc = RC_ERR_OUT_OF_MEMORY; CHECK_RC(rc); }
            rc = elmc_debug_append_cstr(out, escaped);
            CHECK_RC(rc);
            break;
          }

          case ELMC_TAG_BOOL:
            rc = elmc_debug_append_cstr(out, elmc_as_int(value) ? "True" : "False");
            CHECK_RC(rc);
            break;

          case ELMC_TAG_FLOAT:
            rc = elmc_debug_append_float(out, elmc_as_float(value));
            CHECK_RC(rc);
            break;

          case ELMC_TAG_INT:
            if (value->scalar == ELMC_UNIT_SCALAR) {
              rc = elmc_debug_append_cstr(out, "()");
              CHECK_RC(rc);
            } else {
              snprintf(buffer, sizeof(buffer), "%lld", (long long)elmc_as_int(value));
              rc = elmc_debug_append_cstr(out, buffer);
              CHECK_RC(rc);
            }
            break;

          case ELMC_TAG_CHAR:
            rc = elmc_debug_append_char(out, elmc_as_int(value));
            CHECK_RC(rc);
            break;

          case ELMC_TAG_ORDER: {
            elmc_int_t order = elmc_as_int(value);
            const char *name = order < 0 ? "LT" : (order > 0 ? "GT" : "EQ");
            rc = elmc_debug_append_cstr(out, name);
            CHECK_RC(rc);
            break;
          }

          case ELMC_TAG_INT_LIST: {
            ElmcIntListPayload *payload = elmc_int_list_payload(value);
            rc = elmc_debug_append_cstr(out, "[");
            CHECK_RC(rc);
            if (payload) {
              for (int i = 0; i < payload->length; i++) {
                if (i > 0) {
                  rc = elmc_debug_append_cstr(out, ",");
                  CHECK_RC(rc);
                }
                snprintf(buffer, sizeof(buffer), "%lld", (long long)payload->values[i]);
                rc = elmc_debug_append_cstr(out, buffer);
                CHECK_RC(rc);
              }
            }
            rc = elmc_debug_append_cstr(out, "]");
            CHECK_RC(rc);
            break;
          }

          case ELMC_TAG_LIST: {
            if (value->scalar == ELMC_DICT_SCALAR) {
              rc = elmc_debug_append_cstr(out, "HashMap.fromList ");
              CHECK_RC(rc);
            }
            rc = elmc_debug_append_cstr(out, "[");
            CHECK_RC(rc);
            ElmcValue *cursor = value;
            int first = 1;
            while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
              ElmcCons *node = (ElmcCons *)cursor->payload;
              if (!first) {
                rc = elmc_debug_append_cstr(out, ",");
                CHECK_RC(rc);
              }
              part = NULL;
              rc = elmc_debug_format_into(&part, node->head);
              CHECK_RC(rc);
              const char *piece =
                (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
              rc = elmc_debug_append_cstr(out, piece);
              CHECK_RC(rc);
              elmc_release(part);
              part = NULL;
              first = 0;
              cursor = node->tail;
            }
            rc = elmc_debug_append_cstr(out, "]");
            CHECK_RC(rc);
            break;
          }

          case ELMC_TAG_RECORD: {
            if (!value->payload) {
              rc = elmc_debug_append_cstr(out, "{}");
              CHECK_RC(rc);
              break;
            }
            ElmcRecord *record = (ElmcRecord *)value->payload;
            const char **field_names = elmc_record_field_names(value);
            int field_count = record->field_count;
            int indices[32];
            if (field_count > 32) field_count = 32;
            if (field_count == 0) {
              rc = elmc_debug_append_cstr(out, "{}");
              CHECK_RC(rc);
              break;
            }
            for (int i = 0; i < field_count; i++) indices[i] = i;
            if (field_names) {
              for (int i = 0; i < field_count - 1; i++) {
                for (int j = i + 1; j < field_count; j++) {
                  const char *a = field_names[indices[i]] ? field_names[indices[i]] : "";
                  const char *b = field_names[indices[j]] ? field_names[indices[j]] : "";
                  if (strcmp(a, b) > 0) {
                    int tmp = indices[i];
                    indices[i] = indices[j];
                    indices[j] = tmp;
                  }
                }
              }
            }
            rc = elmc_debug_append_cstr(out, "{ ");
            CHECK_RC(rc);
            for (int i = 0; i < field_count; i++) {
              int idx = indices[i];
              if (i > 0) {
                rc = elmc_debug_append_cstr(out, ", ");
                CHECK_RC(rc);
              }
              if (field_names && field_names[idx]) {
                rc = elmc_debug_append_cstr(out, field_names[idx]);
                CHECK_RC(rc);
                rc = elmc_debug_append_cstr(out, " = ");
                CHECK_RC(rc);
              }
              part = NULL;
              rc = elmc_debug_format_into(&part, record->field_values[idx]);
              CHECK_RC(rc);
              const char *piece =
                (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
              rc = elmc_debug_append_cstr(out, piece);
              CHECK_RC(rc);
              elmc_release(part);
              part = NULL;
            }
            rc = elmc_debug_append_cstr(out, " }");
            CHECK_RC(rc);
            break;
          }

          case ELMC_TAG_MAYBE: {
            if (!value->payload) {
              rc = elmc_debug_append_cstr(out, "Nothing");
              CHECK_RC(rc);
              break;
            }
            ElmcMaybe *maybe = (ElmcMaybe *)value->payload;
            if (!maybe->is_just) {
              rc = elmc_debug_append_cstr(out, "Nothing");
              CHECK_RC(rc);
            } else {
              rc = elmc_debug_append_cstr(out, "Just ");
              CHECK_RC(rc);
              part = NULL;
              rc = elmc_debug_format_into(&part, maybe->value);
              CHECK_RC(rc);
              const char *piece =
                (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
              int parenless =
                piece[0] != '\\0' &&
                (piece[0] == '{' || piece[0] == '(' || piece[0] == '[' || piece[0] == '<' || piece[0] == '"' ||
                strchr(piece, ' ') == NULL);
              if (!parenless) {
                rc = elmc_debug_append_cstr(out, "(");
                CHECK_RC(rc);
              }
              rc = elmc_debug_append_cstr(out, piece);
              CHECK_RC(rc);
              if (!parenless) {
                rc = elmc_debug_append_cstr(out, ")");
                CHECK_RC(rc);
              }
              elmc_release(part);
              part = NULL;
            }
            break;
          }

          case ELMC_TAG_RESULT: {
            if (!value->payload) {
              rc = elmc_debug_append_cstr(out, "<internals>");
              CHECK_RC(rc);
              break;
            }
            const char *task_ctor = elmc_task_debug_ctor_name(value);
            if (task_ctor) {
              rc = elmc_debug_append_cstr(out, task_ctor);
              CHECK_RC(rc);
              break;
            }
            ElmcResult *result = (ElmcResult *)value->payload;
            rc = elmc_debug_append_cstr(out, result->is_ok ? "Ok " : "Err ");
            CHECK_RC(rc);
            part = NULL;
            rc = elmc_debug_format_into(&part, result->value);
            CHECK_RC(rc);
            const char *piece =
              (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
            int parenless =
              piece[0] == '{' || piece[0] == '(' || piece[0] == '[' || piece[0] == '<' || piece[0] == '"' ||
              strchr(piece, ' ') == NULL;
            if (!parenless) {
              rc = elmc_debug_append_cstr(out, "(");
              CHECK_RC(rc);
            }
            rc = elmc_debug_append_cstr(out, piece);
            CHECK_RC(rc);
            if (!parenless) {
              rc = elmc_debug_append_cstr(out, ")");
              CHECK_RC(rc);
            }
            elmc_release(part);
            part = NULL;
            break;
          }

          case ELMC_TAG_TUPLE2: {
            if (!value->payload) {
              rc = elmc_debug_append_cstr(out, "<internals>");
              CHECK_RC(rc);
              break;
            }
            ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
            if (tuple->first && tuple->first->tag == ELMC_TAG_INT) {
              const char *ctor_name = elmc_debug_union_ctor_name(elmc_as_int(tuple->first));
              if (ctor_name) {
                rc = elmc_debug_append_cstr(out, ctor_name);
                CHECK_RC(rc);
                rc = elmc_debug_format_union_payload(out, ctor_name, tuple->second);
                CHECK_RC(rc);
                break;
              }
            }
            rc = elmc_debug_append_cstr(out, "(");
            CHECK_RC(rc);
            part = NULL;
            rc = elmc_debug_format_into(&part, tuple->first);
            CHECK_RC(rc);
            const char *first_piece =
              (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
            rc = elmc_debug_append_cstr(out, first_piece);
            CHECK_RC(rc);
            elmc_release(part);
            part = NULL;
            ElmcValue *rest = tuple->second;
            while (rest && rest->tag == ELMC_TAG_TUPLE2 && rest->payload != NULL) {
              ElmcTuple2 *rest_tuple = (ElmcTuple2 *)rest->payload;
              if (rest_tuple->first && rest_tuple->first->tag != ELMC_TAG_TUPLE2 &&
                  rest_tuple->second && rest_tuple->second->tag == ELMC_TAG_TUPLE2) {
                break;
              }
              rc = elmc_debug_append_cstr(out, ",");
              CHECK_RC(rc);
              part = NULL;
              rc = elmc_debug_format_into(&part, rest_tuple->first);
              CHECK_RC(rc);
              const char *mid_piece =
                (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
              rc = elmc_debug_append_cstr(out, mid_piece);
              CHECK_RC(rc);
              elmc_release(part);
              part = NULL;
              rest = rest_tuple->second;
            }
            rc = elmc_debug_append_cstr(out, ",");
            CHECK_RC(rc);
            part = NULL;
            rc = elmc_debug_format_into(&part, rest);
            CHECK_RC(rc);
            const char *last_piece =
              (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
            rc = elmc_debug_append_cstr(out, last_piece);
            CHECK_RC(rc);
            elmc_release(part);
            part = NULL;
            rc = elmc_debug_append_cstr(out, ")");
            CHECK_RC(rc);
            break;
          }

          case ELMC_TAG_CLOSURE:
            rc = elmc_debug_append_cstr(out, "<function>");
            CHECK_RC(rc);
            break;

          default:
            rc = elmc_debug_append_cstr(out, "<internals>");
            CHECK_RC(rc);
            break;
        }
      CATCH_END;
      if (escaped) elmc_free(escaped);
      elmc_release(part);
      return rc;
    }

    ElmcValue *elmc_debug_to_string(ElmcValue *value) {
      ElmcValue *out = NULL;
      if (elmc_debug_format_into(&out, value) != RC_SUCCESS) {
        elmc_release(out);
        return NULL;
      }
      return out;
    }

    ElmcValue *elmc_debug_set_to_string(ElmcValue *set) {
      ElmcValue *out = NULL;
      ElmcValue *list_part = NULL;
      if (elmc_debug_append_cstr(&out, "Set.fromList ") != RC_SUCCESS) {
        elmc_release(out);
        return NULL;
      }
      if (elmc_debug_format_into(&list_part, set ? set : elmc_list_nil()) != RC_SUCCESS) {
        elmc_release(out);
        elmc_release(list_part);
        return NULL;
      }
      const char *piece =
        (list_part && list_part->tag == ELMC_TAG_STRING && list_part->payload) ? (const char *)list_part->payload : "[]";
      if (elmc_debug_append_cstr(&out, piece) != RC_SUCCESS) {
        elmc_release(out);
        elmc_release(list_part);
        return NULL;
      }
      elmc_release(list_part);
      return out;
    }

    RC elmc_string_append_native(ElmcValue **out, const char *left, const char *right) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      CATCH_BEGIN
        const char *a = left ? left : "";
        const char *b = right ? right : "";
        size_t len_a = strlen(a);
        size_t len_b = strlen(b);
        buf = (char *)elmc_malloc(len_a + len_b + 1, __func__);
        if (!buf) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        if (len_a > 0) memcpy(buf, a, len_a);
        if (len_b > 0) memcpy(buf + len_a, b, len_b);
        buf[len_a + len_b] = '\\0';
        ElmcValue *result = elmc_alloc(ELMC_TAG_STRING, buf);
        buf = NULL;
        if (!result) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        result->scalar = (elmc_int_t)(len_a + len_b);
        *out = result;
      CATCH_END;
      if (buf) elmc_free(buf);
      return rc;
    }

    RC elmc_string_append(ElmcValue **out, ElmcValue *left, ElmcValue *right) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      CATCH_BEGIN
        size_t len_a = left ? elmc_string_byte_len(left) : 0;
        size_t len_b = right ? elmc_string_byte_len(right) : 0;
        const char *a = (left && left->tag == ELMC_TAG_STRING && left->payload) ? (const char *)left->payload : "";
        const char *b = (right && right->tag == ELMC_TAG_STRING && right->payload) ? (const char *)right->payload : "";
        buf = (char *)elmc_malloc(len_a + len_b + 1, __func__);
        if (!buf) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        if (len_a > 0) memcpy(buf, a, len_a);
        if (len_b > 0) memcpy(buf + len_a, b, len_b);
        buf[len_a + len_b] = '\\0';
        ElmcValue *result = elmc_alloc(ELMC_TAG_STRING, buf);
        buf = NULL;
        if (!result) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        result->scalar = (elmc_int_t)(len_a + len_b);
        *out = result;
      CATCH_END;
      if (buf) elmc_free(buf);
      return rc;
    }

    ElmcValue *elmc_append(ElmcValue *left, ElmcValue *right) {
      if ((left && left->tag == ELMC_TAG_STRING) || (right && right->tag == ELMC_TAG_STRING)) {
        return elmc_string_append_take(left, right);
      }
      return elmc_list_append_take(left, right);
    }

    ElmcValue *elmc_string_is_empty(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_STRING || value->payload == NULL) {
        ElmcValue *_elmc_rc_out = NULL;
        (void)elmc_new_bool(&_elmc_rc_out, 1);
        return _elmc_rc_out;
      }
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, elmc_string_byte_len(value) == 0);
          return _elmc_rc_out;
      }
    }

    RC elmc_dict_from_list(ElmcValue **out, ElmcValue *items) {
      RC rc = RC_SUCCESS;
      ElmcValue *acc = elmc_list_nil();
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = items;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *entry = node->head;
          if (entry && entry->tag == ELMC_TAG_TUPLE2 && entry->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)entry->payload;
            next = NULL;
            rc = elmc_dict_insert(&next, pair->first, pair->second, acc);
            CHECK_RC(rc);
            elmc_release(acc);
            acc = next;
            next = NULL;
          }
          cursor = node->tail;
        }
        *out = acc;
        acc = NULL;
      CATCH_END;
      elmc_release(next);
      elmc_release(acc);
      return rc;
    }

    static int elmc_dict_keys_equal(ElmcValue *left, ElmcValue *right) {
      return left && right && elmc_value_equal(left, right);
    }

    RC elmc_dict_insert(ElmcValue **out, ElmcValue *key, ElmcValue *value, ElmcValue *dict) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *new_head = NULL;
      ElmcValue *pair = NULL;
      ElmcValue *next_rev = NULL;
      ElmcValue *order = NULL;
      int inserted = 0;
      CATCH_BEGIN
        ElmcValue *cursor = dict;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *cell_head = node->head;
          int skip = 0;
          if (cell_head && cell_head->tag == ELMC_TAG_TUPLE2 && cell_head->payload != NULL) {
            ElmcTuple2 *tp = (ElmcTuple2 *)cell_head->payload;
            if (tp->first && elmc_dict_keys_equal(tp->first, key)) {
              if (!inserted) {
                new_head = NULL;
                rc = elmc_tuple2(&new_head, key, value);
                CHECK_RC(rc);
                cell_head = new_head;
                inserted = 1;
              } else {
                skip = 1;
              }
            } else if (!inserted && tp->first) {
              order = elmc_basics_compare_take(key, tp->first);
              if (!order) {
                rc = RC_ERR_INVALID_ARG;
                CHECK_RC(rc);
              }
              elmc_int_t cmp = elmc_as_int(order);
              elmc_release(order);
              order = NULL;
              if (cmp < 0) {
                pair = NULL;
                rc = elmc_tuple2(&pair, key, value);
                CHECK_RC(rc);
                next_rev = NULL;
                rc = elmc_list_cons(&next_rev, pair, rev);
                CHECK_RC(rc);
                elmc_release(pair);
                pair = NULL;
                elmc_release(rev);
                rev = next_rev;
                next_rev = NULL;
                inserted = 1;
              }
            }
          }
          if (!skip) {
            next_rev = NULL;
            rc = elmc_list_cons(&next_rev, cell_head, rev);
            CHECK_RC(rc);
            elmc_release(new_head);
            new_head = NULL;
            elmc_release(rev);
            rev = next_rev;
            next_rev = NULL;
          }
          cursor = node->tail;
        }
        if (!inserted) {
          pair = NULL;
          rc = elmc_tuple2(&pair, key, value);
          CHECK_RC(rc);
          next_rev = NULL;
          rc = elmc_list_cons(&next_rev, pair, rev);
          CHECK_RC(rc);
          elmc_release(pair);
          pair = NULL;
          elmc_release(rev);
          rev = next_rev;
          next_rev = NULL;
        }
        rc = elmc_list_reverse_transfer(out, &rev);
        CHECK_RC(rc);
        if (*out) elmc_dict_mark_spine(*out);
      CATCH_END;
      elmc_release(new_head);
      elmc_release(pair);
      elmc_release(next_rev);
      elmc_release(order);
      elmc_release(rev);
      return rc;
    }

    RC elmc_dict_get(ElmcValue **out, ElmcValue *key, ElmcValue *dict) {
      RC rc = RC_SUCCESS;
      int found = 0;
      CATCH_BEGIN
        ElmcValue *cursor = dict;
        while (!found && cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
            if (pair->first && elmc_dict_keys_equal(pair->first, key)) {
              rc = elmc_maybe_just(out, pair->second);
              CHECK_RC(rc);
              found = 1;
            }
          }
          if (!found) cursor = node->tail;
        }
        if (!found) {
          *out = elmc_maybe_nothing();
        }
      CATCH_END;
      return rc;
    }

    elmc_int_t elmc_dict_get_with_default_int(elmc_int_t default_val, elmc_int_t key, ElmcValue *dict) {
      ElmcValue *cursor = dict;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
          if (pair->first && elmc_as_int(pair->first) == key) {
            return pair->second ? elmc_as_int(pair->second) : default_val;
          }
        }
        cursor = node->tail;
      }
      return default_val;
    }

    elmc_int_t elmc_dict_get_with_default_int_value(elmc_int_t default_val, ElmcValue *key, ElmcValue *dict) {
      if (!key) return default_val;
      ElmcValue *found = elmc_dict_get_take(key, dict);
      elmc_int_t out = default_val;
      if (found && found->tag == ELMC_TAG_MAYBE && found->payload != NULL) {
        ElmcMaybe *maybe = (ElmcMaybe *)found->payload;
        if (maybe->is_just && maybe->value) out = elmc_as_int(maybe->value);
      }
      elmc_release(found);
      return out;
    }

    ElmcValue *elmc_dict_member(ElmcValue *key, ElmcValue *dict) {
      ElmcValue *found = elmc_dict_get_take(key, dict);
      int present = 0;
      if (found && found->tag == ELMC_TAG_MAYBE && found->payload != NULL) {
        present = ((ElmcMaybe *)found->payload)->is_just;
      }
      elmc_release(found);
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, present);
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_dict_size(ElmcValue *dict) {
      int64_t size = 0;
      ElmcValue *cursor = dict;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        size += 1;
        cursor = ((ElmcCons *)cursor->payload)->tail;
      }
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, size) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    RC elmc_set_from_list(ElmcValue **out, ElmcValue *items) {
      RC rc = RC_SUCCESS;
      ElmcValue *acc = elmc_list_nil();
      ElmcValue *next = NULL;
      ElmcValue *owned = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = items;
        if (items && (items->tag == ELMC_TAG_INT_LIST || items->tag == ELMC_TAG_RECORD_SEQ)) {
          rc = elmc_list_materialize_cons(&cursor, items);
          CHECK_RC(rc);
          owned = cursor;
        }
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          next = NULL;
          rc = elmc_set_insert(&next, node->head, acc);
          CHECK_RC(rc);
          elmc_release(acc);
          acc = next;
          next = NULL;
          cursor = node->tail;
        }
        *out = acc;
        acc = NULL;
      CATCH_END;
      elmc_release(owned);
      elmc_release(next);
      elmc_release(acc);
      return rc;
    }

    ElmcValue *elmc_set_member(ElmcValue *value, ElmcValue *set) {
      ElmcValue *cursor = set;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (elmc_value_equal(node->head, value)) {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, 1);
          return _elmc_rc_out;
        }
        cursor = node->tail;
      }
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, 0);
          return _elmc_rc_out;
      }
    }

    RC elmc_set_insert(ElmcValue **out, ElmcValue *value, ElmcValue *set) {
      RC rc = RC_SUCCESS;
      ElmcValue *exists = NULL;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *next = NULL;
      ElmcValue *order = NULL;
      int inserted = 0;
      CATCH_BEGIN
        exists = elmc_set_member(value, set);
        int present = exists && elmc_as_int(exists) != 0;
        if (present) {
          *out = elmc_retain(set);
        } else {
          ElmcValue *cursor = set ? set : elmc_list_nil();
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            if (!inserted) {
              order = elmc_basics_compare_take(value, node->head);
              if (!order) {
                rc = RC_ERR_INVALID_ARG;
                CHECK_RC(rc);
              }
              elmc_int_t cmp = elmc_as_int(order);
              elmc_release(order);
              order = NULL;
              if (cmp < 0) {
                next = NULL;
                rc = elmc_list_cons(&next, value, rev);
                CHECK_RC(rc);
                elmc_release(rev);
                rev = next;
                next = NULL;
                inserted = 1;
              }
            }
            next = NULL;
            rc = elmc_list_cons(&next, node->head, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = next;
            next = NULL;
            cursor = node->tail;
          }
          if (!inserted) {
            next = NULL;
            rc = elmc_list_cons(&next, value, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = next;
            next = NULL;
          }
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(exists);
      elmc_release(order);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    ElmcValue *elmc_set_size(ElmcValue *set) {
      int64_t size = 0;
      ElmcValue *cursor = set;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        size += 1;
        cursor = ((ElmcCons *)cursor->payload)->tail;
      }
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, size) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_array_empty(void) {
      return elmc_list_nil();
    }

    ElmcValue *elmc_array_from_list(ElmcValue *items) {
      return elmc_retain(items);
    }

    ElmcValue *elmc_array_length(ElmcValue *array) {
      int64_t size = 0;

      if (array && array->tag == ELMC_TAG_INT_LIST) {
        size = elmc_int_list_length_native(array);
      } else if (array && array->tag == ELMC_TAG_INT_SPINE) {
        ElmcValue *cursor = array;
        while (cursor && cursor->tag == ELMC_TAG_INT_SPINE && cursor->payload != NULL) {
          size += 1;
          cursor = ((ElmcIntSpine *)cursor->payload)->tail;
        }
      } else {
        ElmcValue *cursor = array;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          size += 1;
          cursor = ((ElmcCons *)cursor->payload)->tail;
        }
      }

      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, size) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_array_get(ElmcValue *index, ElmcValue *array) {
      int64_t wanted = elmc_as_int(index);
      if (wanted < 0) return elmc_maybe_nothing();

      if (array && array->tag == ELMC_TAG_INT_LIST) {
        ElmcIntListPayload *payload = elmc_int_list_payload(array);
        if (payload && wanted < payload->length) {
          ElmcValue *boxed = NULL;
          if (elmc_new_int(&boxed, payload->values[wanted]) != RC_SUCCESS) return NULL;
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_maybe_just(&_elmc_rc_out, boxed) != RC_SUCCESS) {
            elmc_release(boxed);
            return NULL;
          }
          elmc_release(boxed);
          return _elmc_rc_out;
        }
        return elmc_maybe_nothing();
      }

      if (array && array->tag == ELMC_TAG_INT_SPINE) {
        int64_t i = 0;
        ElmcValue *cursor = array;
        while (cursor && cursor->tag == ELMC_TAG_INT_SPINE && cursor->payload != NULL) {
          if (i == wanted) {
            ElmcValue *boxed = NULL;
            if (elmc_new_int(&boxed, ((ElmcIntSpine *)cursor->payload)->head) != RC_SUCCESS) return NULL;
            ElmcValue *_elmc_rc_out = NULL;
            if (elmc_maybe_just(&_elmc_rc_out, boxed) != RC_SUCCESS) {
              elmc_release(boxed);
              return NULL;
            }
            elmc_release(boxed);
            return _elmc_rc_out;
          }
          i += 1;
          cursor = ((ElmcIntSpine *)cursor->payload)->tail;
        }
        return elmc_maybe_nothing();
      }

      int64_t i = 0;
      ElmcValue *cursor = array;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (i == wanted) {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_maybe_just(&_elmc_rc_out, node->head) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
        }
        i += 1;
        cursor = node->tail;
      }
      return elmc_maybe_nothing();
    }

    elmc_int_t elmc_array_get_with_default_int(elmc_int_t default_val, elmc_int_t index, ElmcValue *array) {
      if (index < 0) return default_val;

      if (array && array->tag == ELMC_TAG_INT_LIST) {
        ElmcIntListPayload *payload = elmc_int_list_payload(array);
        if (payload && index < payload->length) return payload->values[index];
        return default_val;
      }

      if (array && array->tag == ELMC_TAG_INT_SPINE) {
        elmc_int_t i = 0;
        ElmcValue *cursor = array;
        while (cursor && cursor->tag == ELMC_TAG_INT_SPINE && cursor->payload != NULL) {
          if (i == index) return ((ElmcIntSpine *)cursor->payload)->head;
          i += 1;
          cursor = ((ElmcIntSpine *)cursor->payload)->tail;
        }
        return default_val;
      }

      elmc_int_t i = 0;
      ElmcValue *cursor = array;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (i == index) return elmc_as_int(node->head);
        i += 1;
        cursor = node->tail;
      }
      return default_val;
    }

    ElmcValue *elmc_array_set(ElmcValue *index, ElmcValue *value, ElmcValue *array) {
      int64_t wanted = elmc_as_int(index);
      if (wanted < 0) return elmc_retain(array);

      if (array && array->tag == ELMC_TAG_INT_LIST) {
        return elmc_list_replace_nth_int(array, wanted, elmc_as_int(value));
      }

      int64_t i = 0;
      int replaced = 0;
      ElmcValue *cursor = array;
      ElmcValue *rev = elmc_list_nil();

      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *item = (i == wanted) ? value : node->head;
        if (i == wanted) replaced = 1;
        ElmcValue *next_rev = NULL;
        if (elmc_list_cons(&next_rev, item, rev) != RC_SUCCESS) next_rev = NULL;
        elmc_release(rev);
        rev = next_rev;
        i += 1;
        cursor = node->tail;
      }

      if (!replaced) {
        elmc_release(rev);
        return elmc_retain(array);
      }

      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_array_push(ElmcValue *value, ElmcValue *array) {
      ElmcValue *rev = elmc_list_reverse_copy(array);
      ElmcValue *with_tail = NULL;
      if (elmc_list_cons(&with_tail, value, rev) != RC_SUCCESS) with_tail = NULL;
      elmc_release(rev);
      ElmcValue *out = elmc_list_reverse_copy(with_tail);
      elmc_release(with_tail);
      return out;
    }

    ElmcValue *elmc_task_succeed(ElmcValue *value) {
      return elmc_task_wrap(value, ELMC_TASK_SUCCEED_SCALAR);
    }

    ElmcValue *elmc_task_fail(ElmcValue *value) {
      ElmcValue *out = NULL;
      if (elmc_result_err(&out, value) != RC_SUCCESS) return NULL;
      out->scalar = ELMC_TASK_FAIL_SCALAR;
      return out;
    }

    ElmcValue *elmc_task_map(ElmcValue *f, ElmcValue *task) {
      return elmc_task_wrap_pair(f, task, ELMC_TASK_MAP_SCALAR);
    }

    ElmcValue *elmc_task_map2(ElmcValue *f, ElmcValue *a, ElmcValue *b) {
      if (!a || a->tag != ELMC_TAG_RESULT || !a->payload) {
        ElmcValue *_elmc_rc_msg = NULL;
        if (elmc_new_string(&_elmc_rc_msg, "invalid") != RC_SUCCESS) return NULL;
        ElmcValue *_elmc_rc_out = NULL;
        if (elmc_result_err(&_elmc_rc_out, _elmc_rc_msg) != RC_SUCCESS) {
          elmc_release(_elmc_rc_msg);
          return NULL;
        }
        elmc_release(_elmc_rc_msg);
        return _elmc_rc_out;
      }
      if (!b || b->tag != ELMC_TAG_RESULT || !b->payload) {
        ElmcValue *_elmc_rc_msg = NULL;
        if (elmc_new_string(&_elmc_rc_msg, "invalid") != RC_SUCCESS) return NULL;
        ElmcValue *_elmc_rc_out = NULL;
        if (elmc_result_err(&_elmc_rc_out, _elmc_rc_msg) != RC_SUCCESS) {
          elmc_release(_elmc_rc_msg);
          return NULL;
        }
        elmc_release(_elmc_rc_msg);
        return _elmc_rc_out;
      }
      ElmcResult *ra = (ElmcResult *)a->payload;
      ElmcResult *rb = (ElmcResult *)b->payload;
      if (!ra->is_ok) return elmc_retain(a);
      if (!rb->is_ok) return elmc_retain(b);
      ElmcValue *args[2] = { ra->value, rb->value };
      ElmcValue *mapped = NULL;
      if (elmc_closure_call_rc(&mapped, f, args, 2) != RC_SUCCESS) {
        elmc_release(mapped);
        return elmc_int_zero();
      }
      ElmcValue *out = NULL;
      if (elmc_result_ok(&out, mapped) != RC_SUCCESS) out = NULL;
      elmc_release(mapped);
      return out;
    }

    ElmcValue *elmc_task_and_then(ElmcValue *f, ElmcValue *task) {
      return elmc_task_wrap_pair(f, task, ELMC_TASK_AND_THEN_SCALAR);
    }

    ElmcValue *elmc_task_force(ElmcValue *task);

    static ElmcValue *elmc_task_force_pair_step(ElmcValue *pair_value, elmc_int_t kind) {
      if (!pair_value || pair_value->tag != ELMC_TAG_TUPLE2 || !pair_value->payload) return NULL;
      ElmcTuple2 *pair = (ElmcTuple2 *)pair_value->payload;
      ElmcValue *forced = elmc_task_force(pair->second);
      if (!forced) return NULL;
      if (forced->tag != ELMC_TAG_RESULT || !forced->payload) {
        elmc_release(forced);
        return NULL;
      }
      ElmcResult *inner = (ElmcResult *)forced->payload;
      if (!inner->is_ok) {
        ElmcValue *err = elmc_retain(forced);
        elmc_release(forced);
        return err;
      }
      ElmcValue *args[1] = { inner->value };
      ElmcValue *step = NULL;
      RC rc = elmc_closure_call_rc(&step, pair->first, args, 1);
      elmc_release(forced);
      if (rc != RC_SUCCESS) {
        elmc_release(step);
        return NULL;
      }
      if (kind == ELMC_TASK_AND_THEN_SCALAR) {
        ElmcValue *out = elmc_task_force(step);
        elmc_release(step);
        return out;
      }
      ElmcValue *out = NULL;
      if (elmc_result_ok(&out, step) != RC_SUCCESS) {
        elmc_release(step);
        return NULL;
      }
      elmc_release(step);
      return out;
    }

    ElmcValue *elmc_task_force(ElmcValue *task) {
      if (!task) return NULL;
      if (!elmc_is_task_result(task)) return elmc_retain(task);
      if (!task->payload) return NULL;
      ElmcResult *result = (ElmcResult *)task->payload;

      switch (task->scalar) {
        case ELMC_TASK_SUCCEED_SCALAR: {
          ElmcValue *out = NULL;
          ElmcValue *value = result->value ? elmc_retain(result->value) : elmc_int_zero();
          if (elmc_result_ok(&out, value) != RC_SUCCESS) out = NULL;
          elmc_release(value);
          return out;
        }
        case ELMC_TASK_FAIL_SCALAR: {
          ElmcValue *out = NULL;
          ElmcValue *value = result->value ? elmc_retain(result->value) : elmc_int_zero();
          if (elmc_result_err(&out, value) != RC_SUCCESS) out = NULL;
          elmc_release(value);
          return out;
        }
        case ELMC_TASK_MAP_SCALAR:
          return elmc_task_force_pair_step(result->value, ELMC_TASK_MAP_SCALAR);
        case ELMC_TASK_AND_THEN_SCALAR:
          return elmc_task_force_pair_step(result->value, ELMC_TASK_AND_THEN_SCALAR);
        case ELMC_TASK_SPAWN_SCALAR: {
          ElmcProcessSlot *slot = elmc_process_alloc_slot();
          if (!slot) {
            ElmcValue *out = NULL;
            ElmcValue *zero = elmc_int_zero();
            if (elmc_result_ok(&out, zero) != RC_SUCCESS) out = NULL;
            elmc_release(zero);
            return out;
          }
          if (result->value) slot->task = elmc_retain(result->value);
          ElmcValue *pid = elmc_new_int_take(slot->pid);
          ElmcValue *out = NULL;
          if (elmc_result_ok(&out, pid) != RC_SUCCESS) out = NULL;
          elmc_release(pid);
          return out;
        }
        default:
          return elmc_retain(task);
      }
    }

    ElmcValue *elmc_task_perform(ElmcValue *to_msg, ElmcValue *task) {
      (void)to_msg;
      (void)task;
      return elmc_int_zero();
    }

    ElmcValue *elmc_process_spawn(ElmcValue *task) {
    #ifndef ELMC_PEBBLE_PLATFORM
      ElmcProcessSlot *slot = elmc_process_alloc_slot();
      if (!slot) {
        ElmcValue *out = NULL;
        ElmcValue *zero = elmc_int_zero();
        if (elmc_result_ok(&out, zero) != RC_SUCCESS) out = NULL;
        elmc_release(zero);
        return out;
      }
      slot->task = task ? elmc_retain(task) : NULL;
      ElmcValue *pid = elmc_new_int_take(slot->pid);
      ElmcValue *out = NULL;
      if (elmc_result_ok(&out, pid) != RC_SUCCESS) out = NULL;
      elmc_release(pid);
      if (out) out->scalar = ELMC_TASK_SPAWN_SCALAR;
      return out;
    #else
      return elmc_task_wrap(task, ELMC_TASK_SPAWN_SCALAR);
    #endif
    }

    ElmcValue *elmc_process_sleep(ElmcValue *milliseconds) {
      int64_t timeout = elmc_as_int(milliseconds);
      if (timeout < 0) timeout = 0;
      ElmcProcessSlot *slot = elmc_process_alloc_slot();
      if (slot) {
      #ifdef ELMC_PEBBLE_PLATFORM
        uint32_t ms = (uint32_t)(timeout > 2147483647 ? 2147483647 : timeout);
        slot->timer = app_timer_register(ms, elmc_process_sleep_timer_cb, slot);
      #else
        elmc_process_release_slot(slot);
      #endif
      }
      ElmcValue *unit = elmc_int_zero();
      ElmcValue *out = NULL;
      if (elmc_result_ok(&out, unit) != RC_SUCCESS) out = NULL;
      elmc_release(unit);
      return out;
    }

    ElmcValue *elmc_process_kill(ElmcValue *pid) {
      int64_t pid_raw = elmc_as_int(pid);
      ElmcProcessSlot *slot = elmc_process_find_slot(pid_raw);
      if (slot) {
        elmc_process_release_slot(slot);
      }
      ElmcValue *unit = elmc_int_zero();
      ElmcValue *out = NULL;
      if (elmc_result_ok(&out, unit) != RC_SUCCESS) out = NULL;
      elmc_release(unit);
      return out;
    }

    ElmcValue *elmc_time_now_millis(void) {
      int64_t millis = (int64_t)time(NULL) * 1000;
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, millis) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_time_zone_offset_minutes(void) {
      time_t now = time(NULL);
      struct tm local_tm = {0};
      struct tm utc_tm = {0};

    #ifdef _WIN32
      localtime_s(&local_tm, &now);
      gmtime_s(&utc_tm, &now);
    #else
      struct tm *local_ptr = localtime(&now);
      struct tm *utc_ptr = gmtime(&now);
      if (local_ptr) local_tm = *local_ptr;
      if (utc_ptr) utc_tm = *utc_ptr;
    #endif

      int local_minutes = local_tm.tm_hour * 60 + local_tm.tm_min;
      int utc_minutes = utc_tm.tm_hour * 60 + utc_tm.tm_min;
      int day_delta = local_tm.tm_yday - utc_tm.tm_yday;

      if (day_delta > 1) day_delta = -1;
      if (day_delta < -1) day_delta = 1;

      int offset = (day_delta * 24 * 60) + (local_minutes - utc_minutes);
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, (int64_t)offset) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_cmd_backlight_from_maybe(ElmcValue *maybe_mode) {
      int64_t mode = 0; /* 0 = interaction, 1 = disable, 2 = enable */

      if (maybe_mode && maybe_mode->tag == ELMC_TAG_MAYBE && maybe_mode->payload != NULL) {
        ElmcMaybe *maybe = (ElmcMaybe *)maybe_mode->payload;
        if (maybe->is_just && maybe->value) {
          mode = elmc_as_int(maybe->value) != 0 ? 2 : 1;
        }
      }

      ElmcValue *kind = NULL;
      if (elmc_new_int(&kind, 6) != RC_SUCCESS) kind = NULL;
      ElmcValue *p0 = NULL;
      if (elmc_new_int(&p0, mode) != RC_SUCCESS) p0 = NULL;
      ElmcValue *p1 = elmc_int_zero();
      ElmcValue *p2 = elmc_int_zero();
      ElmcValue *p3 = elmc_int_zero();
      ElmcValue *p4 = elmc_int_zero();
      ElmcValue *p5 = elmc_int_zero();
      ElmcValue *tail0 = NULL;
      if (elmc_tuple2(&tail0, p4, p5) != RC_SUCCESS) tail0 = NULL;
      ElmcValue *tail1 = NULL;
      if (elmc_tuple2(&tail1, p3, tail0) != RC_SUCCESS) tail1 = NULL;
      ElmcValue *tail2 = NULL;
      if (elmc_tuple2(&tail2, p2, tail1) != RC_SUCCESS) tail2 = NULL;
      ElmcValue *tail3 = NULL;
      if (elmc_tuple2(&tail3, p1, tail2) != RC_SUCCESS) tail3 = NULL;
      ElmcValue *tail4 = NULL;
      if (elmc_tuple2(&tail4, p0, tail3) != RC_SUCCESS) tail4 = NULL;
      ElmcValue *command = NULL;
      if (elmc_tuple2(&command, kind, tail4) != RC_SUCCESS) command = NULL;

      elmc_release(kind);
      elmc_release(p0);
      elmc_release(p1);
      elmc_release(p2);
      elmc_release(p3);
      elmc_release(p4);
      elmc_release(p5);
      elmc_release(tail0);
      elmc_release(tail1);
      elmc_release(tail2);
      elmc_release(tail3);
      elmc_release(tail4);
      return command;
    }

    RC elmc_new_float(ElmcValue **out, double value) {
      RC rc = RC_SUCCESS;
      double *ptr = NULL;
      CATCH_BEGIN
        ptr = (double *)elmc_malloc(sizeof(double), __func__);
        if (!ptr) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        *ptr = value;
        ElmcValue *allocated = elmc_alloc(ELMC_TAG_FLOAT, ptr);
        ptr = NULL;
        if (!allocated) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        *out = allocated;
      CATCH_END;
      if (ptr) elmc_free(ptr);
      return rc;
    }

    double elmc_as_float(ElmcValue *value) {
      if (!value) return 0.0;
      if (value->tag == ELMC_TAG_FLOAT) return *((double *)value->payload);
      if (value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) return (double)elmc_as_int(value);
      return 0.0;
    }

    RC elmc_record_new(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        rc = elmc_record_cell_alloc(out, field_count, field_names, field_values, 0);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    RC elmc_record_new_take(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        rc = elmc_record_cell_alloc(out, field_count, field_names, field_values, 1);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    RC elmc_record_new_ints(ElmcValue **out, int field_count, const char **field_names, const elmc_int_t *field_values) {
      ElmcValue *values[field_count];
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        for (int i = 0; i < field_count; i++) {
          rc = elmc_new_int(&values[i], field_values[i]);
          CHECK_RC(rc);
        }
        rc = elmc_record_new_take(out, field_count, field_names, values);
        CHECK_RC(rc);
      CATCH_END;
      if (rc != RC_SUCCESS) {
        for (int i = 0; i < field_count; i++) {
          elmc_release(values[i]);
        }
      }
      return rc;
    }

    RC elmc_record_new_static(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        rc = elmc_record_cell_alloc_static(out, field_count, field_names, field_values, 0);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    RC elmc_record_new_static_take(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        rc = elmc_record_cell_alloc_static(out, field_count, field_names, field_values, 1);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    RC elmc_record_new_static_ints(ElmcValue **out, int field_count, const char * const *field_names, const elmc_int_t *field_values) {
      ElmcValue *values[field_count];
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        for (int i = 0; i < field_count; i++) {
          rc = elmc_new_int(&values[i], field_values[i]);
          CHECK_RC(rc);
        }
        rc = elmc_record_new_static_take(out, field_count, field_names, values);
        CHECK_RC(rc);
      CATCH_END;
      if (rc != RC_SUCCESS) {
        for (int i = 0; i < field_count; i++) {
          elmc_release(values[i]);
        }
      }
      return rc;
    }

    RC elmc_record_new_values(ElmcValue **out, int field_count, ElmcValue **field_values) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        rc = elmc_record_cell_alloc_values(out, field_count, field_values, 0);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    RC elmc_record_new_values_take(ElmcValue **out, int field_count, ElmcValue **field_values) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        rc = elmc_record_cell_alloc_values(out, field_count, field_values, 1);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    RC elmc_record_new_values_ints(ElmcValue **out, int field_count, const elmc_int_t *field_values) {
      ElmcValue *values[field_count];
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        for (int i = 0; i < field_count; i++) {
          rc = elmc_new_int(&values[i], field_values[i]);
          CHECK_RC(rc);
        }
        rc = elmc_record_new_values_take(out, field_count, values);
        CHECK_RC(rc);
      CATCH_END;
      if (rc != RC_SUCCESS) {
        for (int i = 0; i < field_count; i++) {
          elmc_release(values[i]);
        }
      }
      return rc;
    }

    ElmcValue *elmc_record_get(ElmcValue *record, const char *field_name) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_int_zero();
      ElmcRecord *rec = (ElmcRecord *)record->payload;
      const char **field_names = elmc_record_field_names(record);
      if (!field_names) return elmc_int_zero();
      for (int i = 0; i < rec->field_count; i++) {
        if (field_names[i] && strcmp(field_names[i], field_name) == 0) {
          return elmc_retain(rec->field_values[i]);
        }
      }
      return elmc_int_zero();
    }

    ElmcValue *elmc_record_get_at(ElmcValue *record, int index, const char *field_name) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_int_zero();
      ElmcRecord *rec = (ElmcRecord *)record->payload;
      const char **field_names = elmc_record_field_names(record);
      if (!field_names) return elmc_int_zero();
      if (index >= 0 && index < rec->field_count && field_names[index] &&
          strcmp(field_names[index], field_name) == 0) {
        return elmc_retain(rec->field_values[index]);
      }
      return elmc_record_get(record, field_name);
    }

    ElmcValue *elmc_record_get_index(ElmcValue *record, int index) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_int_zero();
      ElmcRecord *rec = (ElmcRecord *)record->payload;
      if (index >= 0 && index < rec->field_count) return elmc_retain(rec->field_values[index]);
      return elmc_int_zero();
    }

    elmc_int_t elmc_record_get_int(ElmcValue *record, const char *field_name) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return 0;
      ElmcRecord *rec = (ElmcRecord *)record->payload;
      const char **field_names = elmc_record_field_names(record);
      if (!field_names) return 0;
      for (int i = 0; i < rec->field_count; i++) {
        if (field_names[i] && strcmp(field_names[i], field_name) == 0) {
          return elmc_as_int(rec->field_values[i]);
        }
      }
      return 0;
    }

    elmc_int_t elmc_record_get_at_int(ElmcValue *record, int index, const char *field_name) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return 0;
      ElmcRecord *rec = (ElmcRecord *)record->payload;
      const char **field_names = elmc_record_field_names(record);
      if (!field_names) return 0;
      if (index >= 0 && index < rec->field_count && field_names[index] &&
          strcmp(field_names[index], field_name) == 0) {
        return elmc_as_int(rec->field_values[index]);
      }
      return elmc_record_get_int(record, field_name);
    }

    elmc_int_t elmc_record_get_index_int(ElmcValue *record, int index) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return 0;
      ElmcRecord *rec = (ElmcRecord *)record->payload;
      if (index >= 0 && index < rec->field_count) return elmc_as_int(rec->field_values[index]);
      return 0;
    }

    elmc_int_t elmc_record_get_maybe_int(ElmcValue *record, const char *field_name, elmc_int_t default_val) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return default_val;
      ElmcRecord *rec = (ElmcRecord *)record->payload;
      const char **field_names = elmc_record_field_names(record);
      if (!field_names) return default_val;
      for (int i = 0; i < rec->field_count; i++) {
        if (field_names[i] && strcmp(field_names[i], field_name) == 0) {
          return elmc_maybe_with_default_int(default_val, rec->field_values[i]);
        }
      }
      return default_val;
    }

    elmc_int_t elmc_record_get_at_maybe_int(ElmcValue *record, int index, const char *field_name, elmc_int_t default_val) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return default_val;
      ElmcRecord *rec = (ElmcRecord *)record->payload;
      const char **field_names = elmc_record_field_names(record);
      if (!field_names) return default_val;
      if (index >= 0 && index < rec->field_count && field_names[index] &&
          strcmp(field_names[index], field_name) == 0) {
        return elmc_maybe_with_default_int(default_val, rec->field_values[index]);
      }
      return elmc_record_get_maybe_int(record, field_name, default_val);
    }

    elmc_int_t elmc_record_get_index_maybe_int(ElmcValue *record, int index, elmc_int_t default_val) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return default_val;
      ElmcRecord *rec = (ElmcRecord *)record->payload;
      if (index >= 0 && index < rec->field_count) return elmc_maybe_with_default_int(default_val, rec->field_values[index]);
      return default_val;
    }

    elmc_int_t elmc_record_get_bool(ElmcValue *record, const char *field_name) {
      return elmc_record_get_int(record, field_name) != 0;
    }

    elmc_int_t elmc_record_get_at_bool(ElmcValue *record, int index, const char *field_name) {
      return elmc_record_get_at_int(record, index, field_name) != 0;
    }

    elmc_int_t elmc_record_get_index_bool(ElmcValue *record, int index) {
      return elmc_record_get_index_int(record, index) != 0;
    }

    uint32_t elmc_record_mutation_gen(ElmcValue *record) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return 0;
      return ((ElmcRecord *)record->payload)->mutation_gen;
    }

    ElmcValue *elmc_record_update(ElmcValue *record, const char *field_name, ElmcValue *new_value) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_retain(record);
      ElmcRecord *old = (ElmcRecord *)record->payload;
      const char **field_names = elmc_record_field_names(record);
      if (!field_names) return elmc_retain(record);
      for (int i = 0; i < old->field_count; i++) {
        if (field_names[i] && strcmp(field_names[i], field_name) == 0) {
          return elmc_record_update_index(record, i, new_value);
        }
      }
      return elmc_retain(record);
    }

    ElmcValue *elmc_record_update_index(ElmcValue *record, int index, ElmcValue *new_value) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_retain(record);
      ElmcRecord *old = (ElmcRecord *)record->payload;
      if (index < 0 || index >= old->field_count) return elmc_retain(record);
      ElmcValue **values = (ElmcValue **)elmc_malloc(sizeof(ElmcValue *) * old->field_count, __func__);
      if (!values) return elmc_retain(record);
      for (int i = 0; i < old->field_count; i++) {
        if (i == index) {
          values[i] = new_value ? elmc_retain(new_value) : NULL;
        } else {
          values[i] = old->field_values[i] ? elmc_retain(old->field_values[i]) : NULL;
        }
      }
      const char **field_names = elmc_record_field_names(record);
      ElmcValue *result = NULL;
      if (field_names) {
        if (elmc_record_new_take(&result, old->field_count, field_names, values) != RC_SUCCESS) result = NULL;
      } else if (elmc_record_new_values_take(&result, old->field_count, values) != RC_SUCCESS) {
        result = NULL;
      }
      elmc_free(values);
      return result;
    }

    ElmcValue *elmc_record_update_index_cow(ElmcValue *record, int index, ElmcValue *new_value) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_retain(record);
      ElmcRecord *rec = (ElmcRecord *)record->payload;
      if (index < 0 || index >= rec->field_count) return elmc_retain(record);
      if (record->rc == 1) {
        ElmcValue *old_value = rec->field_values[index];
        rec->field_values[index] = new_value ? elmc_retain(new_value) : NULL;
        elmc_release(old_value);
        rec->mutation_gen += 1;
        return record;
      }
      return elmc_record_update_index(record, index, new_value);
    }

    ElmcValue *elmc_record_update_index_cow_drop(ElmcValue *record, int index, ElmcValue *new_value) {
      ElmcValue *next = elmc_record_update_index_cow(record, index, new_value);
      if (next != record) elmc_release(record);
      return next;
    }

    ElmcValue *elmc_record_update_index_int_cow(ElmcValue *record, int index, elmc_int_t new_value) {
      ElmcValue *boxed = elmc_small_int(new_value);
      if (boxed) {
        return elmc_record_update_index_cow(record, index, boxed);
      }
      boxed = NULL;
      if (elmc_new_int(&boxed, new_value) != RC_SUCCESS || !boxed) return elmc_retain(record);
      ElmcValue *next = elmc_record_update_index_cow(record, index, boxed);
      elmc_release(boxed);
      return next;
    }

    ElmcValue *elmc_record_update_index_int_cow_drop(ElmcValue *record, int index, elmc_int_t new_value) {
      ElmcValue *next = elmc_record_update_index_int_cow(record, index, new_value);
      if (next != record) elmc_release(record);
      return next;
    }

    ElmcValue *elmc_record_update_index_bool_cow(ElmcValue *record, int index, bool new_value) {
      ElmcValue *boxed = NULL;
      if (elmc_new_bool(&boxed, new_value ? 1 : 0) != RC_SUCCESS || !boxed) return elmc_retain(record);
      ElmcValue *next = elmc_record_update_index_cow(record, index, boxed);
      elmc_release(boxed);
      return next;
    }

    ElmcValue *elmc_record_update_index_bool_cow_drop(ElmcValue *record, int index, bool new_value) {
      ElmcValue *next = elmc_record_update_index_bool_cow(record, index, new_value);
      if (next != record) elmc_release(record);
      return next;
    }

    ElmcValue *elmc_record_update_index_float_cow(ElmcValue *record, int index, double new_value) {
      ElmcValue *boxed = NULL;
      if (elmc_new_float(&boxed, new_value) != RC_SUCCESS || !boxed) return elmc_retain(record);
      ElmcValue *next = elmc_record_update_index_cow(record, index, boxed);
      elmc_release(boxed);
      return next;
    }

    ElmcValue *elmc_record_update_index_float_cow_drop(ElmcValue *record, int index, double new_value) {
      ElmcValue *next = elmc_record_update_index_float_cow(record, index, new_value);
      if (next != record) elmc_release(record);
      return next;
    }

    static RC elmc_closure_cell_init(
        ElmcClosureCell *cell,
        int arity,
        int capture_count,
        ElmcValue **captures) {
      ElmcClosure *clo = &cell->closure;
      clo->fn = NULL;
      clo->rc_fn = NULL;
      clo->arity = arity;
      clo->capture_count = capture_count;
      clo->is_rc = 0;
      clo->captures = NULL;
      if (capture_count > 0) {
        clo->captures = (ElmcValue **)(cell + 1);
        for (int i = 0; i < capture_count; i++) {
          clo->captures[i] = elmc_retain(captures[i]);
        }
      }
      cell->value.rc = 1;
      cell->value.tag = ELMC_TAG_CLOSURE;
      cell->value.payload = clo;
      cell->value.scalar = ELMC_CLOSURE_CELL_SCALAR;
      ELMC_ALLOCATED += 1;
      ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
      return RC_SUCCESS;
    }

    RC elmc_closure_new(ElmcValue **out, ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count), int arity, int capture_count, ElmcValue **captures) {
      RC rc = RC_SUCCESS;
      ElmcClosureCell *cell = NULL;
      CATCH_BEGIN
        if (capture_count < 0) {
          rc = RC_ERR_INVALID_ARG;
          CHECK_RC(rc);
        }
        size_t captures_size = sizeof(ElmcValue *) * (size_t)capture_count;
        cell = (ElmcClosureCell *)elmc_malloc(sizeof(ElmcClosureCell) + captures_size, __func__);
        if (!cell) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        rc = elmc_closure_cell_init(cell, arity, capture_count, captures);
        CHECK_RC(rc);
        ((ElmcClosure *)cell->value.payload)->fn = fn;
        *out = &cell->value;
        cell = NULL;
      CATCH_END;
      if (cell) elmc_release(&cell->value);
      return rc;
    }

    RC elmc_closure_new_rc(ElmcValue **out, RC (*rc_fn)(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count), int arity, int capture_count, ElmcValue **captures) {
      RC rc = RC_SUCCESS;
      ElmcClosureCell *cell = NULL;
      CATCH_BEGIN
        if (capture_count < 0) {
          rc = RC_ERR_INVALID_ARG;
          CHECK_RC(rc);
        }
        size_t captures_size = sizeof(ElmcValue *) * (size_t)capture_count;
        cell = (ElmcClosureCell *)elmc_malloc(sizeof(ElmcClosureCell) + captures_size, __func__);
        if (!cell) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        rc = elmc_closure_cell_init(cell, arity, capture_count, captures);
        CHECK_RC(rc);
        ElmcClosure *clo = (ElmcClosure *)cell->value.payload;
        clo->is_rc = 1;
        clo->rc_fn = rc_fn;
        *out = &cell->value;
        cell = NULL;
      CATCH_END;
      if (cell) elmc_release(&cell->value);
      return rc;
    }

    ElmcValue *elmc_closure_call(ElmcValue *closure, ElmcValue **args, int argc) {
      if (!closure || closure->tag != ELMC_TAG_CLOSURE || !closure->payload) return elmc_int_zero();
      ElmcClosure *clo = (ElmcClosure *)closure->payload;
      int consumed = argc;
      if (clo->arity > 0 && argc > clo->arity) {
        consumed = clo->arity;
      }
      ElmcValue *result = NULL;
      if (clo->is_rc) {
        if (!clo->rc_fn || clo->rc_fn(&result, args, consumed, clo->captures, clo->capture_count) != RC_SUCCESS) {
          return elmc_int_zero();
        }
      } else {
        if (!clo->fn) return elmc_int_zero();
        result = clo->fn(args, consumed, clo->captures, clo->capture_count);
      }
      if (consumed < argc) {
        ElmcValue *next = elmc_closure_call(result, args + consumed, argc - consumed);
        elmc_release(result);
        return next;
      }
      return result;
    }

    RC elmc_closure_call_rc(ElmcValue **out, ElmcValue *closure, ElmcValue **args, int argc) {
      RC rc = RC_SUCCESS;
      ElmcValue *value = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        if (!closure || closure->tag != ELMC_TAG_CLOSURE || !closure->payload) {
          rc = RC_ERR_INVALID_ARG;
          CHECK_RC(rc);
        }
        ElmcClosure *clo = (ElmcClosure *)closure->payload;
        if (!clo->is_rc || !clo->rc_fn) {
          value = elmc_closure_call(closure, args, argc);
          *out = value;
          value = NULL;
        } else {
          int consumed = argc;
          if (clo->arity > 0 && argc > clo->arity) {
            consumed = clo->arity;
          }
          rc = clo->rc_fn(out, args, consumed, clo->captures, clo->capture_count);
          CHECK_RC(rc);
          if (consumed < argc) {
            next = NULL;
            rc = elmc_closure_call_rc(&next, *out, args + consumed, argc - consumed);
            CHECK_RC(rc);
            elmc_release(*out);
            *out = next;
            next = NULL;
          }
        }
      CATCH_END;
      elmc_release(value);
      elmc_release(next);
      return rc;
    }

    ElmcValue *elmc_apply_extra(ElmcValue *value, ElmcValue **args, int argc) {
      if (!value) return elmc_int_zero();
      if (value->tag == ELMC_TAG_CLOSURE) {
        return elmc_closure_call(value, args, argc);
      }
      if (argc == 1 && args && args[0] && args[0]->tag == ELMC_TAG_CLOSURE) {
        ElmcValue *access_args[1] = { value };
        return elmc_closure_call(args[0], access_args, 1);
      }
      return elmc_retain(value);
    }

    ElmcForwardRef *elmc_forward_ref_new(void) {
      ElmcForwardRef *ref = (ElmcForwardRef *)elmc_malloc(sizeof(ElmcForwardRef), __func__);
      if (ref) ref->value = NULL;
      return ref;
    }

    void elmc_forward_ref_set(ElmcForwardRef *ref, ElmcValue *value) {
      if (!ref) return;
      if (ref->value) elmc_release(ref->value);
      ref->value = value ? elmc_retain(value) : NULL;
    }

    ElmcValue *elmc_forward_ref_get(ElmcForwardRef *ref) {
      if (!ref || !ref->value) return elmc_int_zero();
      return elmc_retain(ref->value);
    }

    void elmc_forward_ref_free(ElmcForwardRef *ref) {
      if (!ref) return;
      if (ref->value) elmc_release(ref->value);
      elmc_free(ref);
    }

    ElmcValue *elmc_forward_ref_capture(ElmcForwardRef *ref) {
      if (!ref) return elmc_int_zero();
      ElmcForwardRef **payload = (ElmcForwardRef **)elmc_malloc(sizeof(ElmcForwardRef *), __func__);
      if (!payload) return elmc_int_zero();
      *payload = ref;
      return elmc_alloc(ELMC_TAG_FORWARD_REF, payload);
    }

    /* ================================================================
       Standard Library – List operations
       ================================================================ */

    ElmcValue *elmc_list_tail(ElmcValue *list) {
      if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) return elmc_maybe_nothing();
      ElmcCons *node = (ElmcCons *)list->payload;
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_maybe_just(&_elmc_rc_out, node->tail) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_list_is_empty(ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        ElmcIntListPayload *payload = elmc_int_list_payload(list);
        ElmcValue *_elmc_rc_out = NULL;
        (void)elmc_new_bool(&_elmc_rc_out, !payload || payload->length <= 0);
        return _elmc_rc_out;
      }
      if (!list || list->tag != ELMC_TAG_LIST) {
        ElmcValue *_elmc_rc_out = NULL;
        (void)elmc_new_bool(&_elmc_rc_out, 1);
        return _elmc_rc_out;
      }
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, list->payload == NULL);
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_list_length(ElmcValue *list) {
      int64_t count = 0;
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        count = elmc_int_list_length_native(list);
      } else {
        ElmcValue *cursor = list;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          count += 1;
          cursor = ((ElmcCons *)cursor->payload)->tail;
        }
      }
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, count) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    RC elmc_list_reverse(ElmcValue **out, ElmcValue *list) {
      return elmc_list_reverse_into(out, list);
    }

    RC elmc_list_copy(ElmcValue **out, ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        ElmcIntListPayload *payload = elmc_int_list_payload(list);
        if (!payload || payload->length <= 0) {
          return elmc_int_list_alloc_copy(out, NULL, 0);
        }
        return elmc_int_list_alloc_copy(out, payload->values, payload->length);
      }
      RC rc = RC_SUCCESS;
      ElmcValue *reversed = NULL;
      CATCH_BEGIN
        if (!list) {
          *out = elmc_int_zero();
        } else {
          rc = elmc_list_reverse_into(&reversed, list);
          CHECK_RC(rc);
          rc = elmc_list_reverse_transfer(out, &reversed);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(reversed);
      return rc;
    }

    ElmcValue *elmc_list_member(ElmcValue *value, ElmcValue *list) {
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (elmc_value_equal(node->head, value)) {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, 1);
          return _elmc_rc_out;
        }
        cursor = node->tail;
      }
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, 0);
          return _elmc_rc_out;
      }
    }

    RC elmc_list_map(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        return elmc_int_list_map(out, f, list);
      }
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *mapped = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *args[1] = { node->head };
          mapped = NULL;
          rc = elmc_closure_call_rc(&mapped, f, args, 1);
          CHECK_RC(rc);
          next = NULL;
          rc = elmc_list_cons(&next, mapped, rev);
          CHECK_RC(rc);
          elmc_release(mapped);
          mapped = NULL;
          elmc_release(rev);
          rev = next;
          next = NULL;
          cursor = node->tail;
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(mapped);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_list_filter(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        return elmc_int_list_filter(out, f, list);
      }
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *keep = NULL;
      ElmcValue *next = NULL;
      ElmcValue *owned = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        if (list && list->tag == ELMC_TAG_RECORD_SEQ) {
          rc = elmc_list_materialize_cons(&cursor, list);
          CHECK_RC(rc);
          owned = cursor;
        }
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *args[1] = { node->head };
          keep = NULL;
          rc = elmc_closure_call_rc(&keep, f, args, 1);
          CHECK_RC(rc);
          if (elmc_as_int(keep)) {
            next = NULL;
            rc = elmc_list_cons(&next, node->head, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = next;
            next = NULL;
          }
          elmc_release(keep);
          keep = NULL;
          cursor = node->tail;
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(owned);
      elmc_release(keep);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_list_filter_record_field(ElmcValue **out, ElmcValue *list, elmc_int_t field_index) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *next = NULL;
      ElmcValue *owned = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        if (list && list->tag == ELMC_TAG_RECORD_SEQ) {
          rc = elmc_list_materialize_cons(&cursor, list);
          CHECK_RC(rc);
          owned = cursor;
        }
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (elmc_record_get_index_bool(node->head, (int)field_index)) {
            next = NULL;
            rc = elmc_list_cons(&next, node->head, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = next;
            next = NULL;
          }
          cursor = node->tail;
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(owned);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_list_filter_record_and(ElmcValue **out, ElmcValue *list, elmc_int_t field_a, elmc_int_t field_b) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *next = NULL;
      ElmcValue *owned = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        if (list && list->tag == ELMC_TAG_RECORD_SEQ) {
          rc = elmc_list_materialize_cons(&cursor, list);
          CHECK_RC(rc);
          owned = cursor;
        }
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (elmc_record_get_index_bool(node->head, (int)field_a) &&
              elmc_record_get_index_bool(node->head, (int)field_b)) {
            next = NULL;
            rc = elmc_list_cons(&next, node->head, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = next;
            next = NULL;
          }
          cursor = node->tail;
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(owned);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_list_map_record_field(ElmcValue **out, ElmcValue *list, elmc_int_t field_index) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *next = NULL;
      ElmcValue *owned = NULL;
      ElmcValue *mapped = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        if (list && list->tag == ELMC_TAG_RECORD_SEQ) {
          rc = elmc_list_materialize_cons(&cursor, list);
          CHECK_RC(rc);
          owned = cursor;
        }
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          mapped = elmc_record_get_index(node->head, (int)field_index);
          next = NULL;
          rc = elmc_list_cons(&next, mapped, rev);
          CHECK_RC(rc);
          elmc_release(mapped);
          mapped = NULL;
          elmc_release(rev);
          rev = next;
          next = NULL;
          cursor = node->tail;
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(owned);
      elmc_release(mapped);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_list_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        return elmc_int_list_foldl(out, f, acc, list);
      }
      RC rc = RC_SUCCESS;
      ElmcValue *result = elmc_retain(acc);
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *args[2] = { node->head, result };
          next = NULL;
          rc = elmc_closure_call_rc(&next, f, args, 2);
          CHECK_RC(rc);
          elmc_release(result);
          result = next;
          next = NULL;
          cursor = node->tail;
        }
        if (rc == RC_SUCCESS) {
          *out = result;
          result = NULL;
        }
      CATCH_END;
      elmc_release(next);
      elmc_release(result);
      return rc;
    }

    RC elmc_list_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        return elmc_int_list_foldr(out, f, acc, list);
      }
      RC rc = RC_SUCCESS;
      ElmcValue *reversed = NULL;
      ElmcValue *result = elmc_retain(acc);
      ElmcValue *next = NULL;
      CATCH_BEGIN
        rc = elmc_list_reverse_into(&reversed, list);
        CHECK_RC(rc);
        ElmcValue *cursor = reversed;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *args[2] = { node->head, result };
          next = NULL;
          rc = elmc_closure_call_rc(&next, f, args, 2);
          CHECK_RC(rc);
          elmc_release(result);
          result = next;
          next = NULL;
          cursor = node->tail;
        }
        if (rc == RC_SUCCESS) {
          *out = result;
          result = NULL;
        }
      CATCH_END;
      elmc_release(reversed);
      elmc_release(next);
      elmc_release(result);
      return rc;
    }

    RC elmc_list_append(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
      if (a && a->tag == ELMC_TAG_INT_LIST) {
        if (b && b->tag == ELMC_TAG_INT_LIST) {
          return elmc_int_list_append(out, a, b);
        }
        if (!b || (b->tag == ELMC_TAG_LIST && b->payload == NULL) ||
            (b->tag == ELMC_TAG_INT_LIST && elmc_int_list_is_empty(b))) {
          RC rc = RC_SUCCESS;
          CATCH_BEGIN
            *out = elmc_retain(a);
          CATCH_END;
          return rc;
        }
        RC rc = RC_SUCCESS;
        ElmcValue *result = NULL;
        ElmcValue **tail_slot = NULL;
        ElmcValue *cell = NULL;
        CATCH_BEGIN
          ElmcIntListPayload *payload = elmc_int_list_payload(a);
          if (payload) {
            for (int i = 0; i < payload->length; i++) {
              ElmcValue *head = NULL;
              rc = elmc_new_int(&head, payload->values[i]);
              CHECK_RC(rc);
              cell = NULL;
              rc = elmc_list_cons(&cell, head, elmc_list_nil());
              elmc_release(head);
              CHECK_RC(rc);
              if (tail_slot) {
                elmc_release(*tail_slot);
                *tail_slot = cell;
              } else {
                result = cell;
              }
              tail_slot = &((ElmcCons *)cell->payload)->tail;
              cell = NULL;
            }
          }
          if (!result) {
            *out = elmc_retain(b);
          } else {
            elmc_release(*tail_slot);
            *tail_slot = elmc_retain(b);
            *out = result;
            result = NULL;
          }
        CATCH_END;
        elmc_release(cell);
        elmc_release(result);
        return rc;
      }
      RC rc = RC_SUCCESS;
      ElmcValue *result = NULL;
      ElmcValue **tail_slot = NULL;
      ElmcValue *cell = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = a;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          cell = NULL;
          rc = elmc_list_cons(&cell, node->head, elmc_list_nil());
          CHECK_RC(rc);
          if (tail_slot) {
            elmc_release(*tail_slot);
            *tail_slot = cell;
          } else {
            result = cell;
          }
          tail_slot = &((ElmcCons *)cell->payload)->tail;
          cell = NULL;
          cursor = node->tail;
        }
        if (!result) {
          if (b && b->tag == ELMC_TAG_INT_LIST) {
            rc = elmc_int_list_to_cons(out, b);
            CHECK_RC(rc);
          } else {
            *out = elmc_retain(b);
          }
        } else {
          elmc_release(*tail_slot);
          if (b && b->tag == ELMC_TAG_INT_LIST) {
            rc = elmc_int_list_append_to_cons_tail(tail_slot, b);
            CHECK_RC(rc);
          } else {
            *tail_slot = elmc_retain(b);
          }
          *out = result;
          result = NULL;
        }
      CATCH_END;
      elmc_release(cell);
      elmc_release(result);
      return rc;
    }

    RC elmc_list_concat(ElmcValue **out, ElmcValue *lists) {
      RC rc = RC_SUCCESS;
      ElmcValue *result = NULL;
      ElmcValue **tail_slot = NULL;
      ElmcValue *cell = NULL;
      CATCH_BEGIN
        ElmcValue *outer = lists;
        while (outer && outer->tag == ELMC_TAG_LIST && outer->payload != NULL) {
          ElmcCons *outer_node = (ElmcCons *)outer->payload;
          ElmcValue *inner = outer_node->head;
          while (inner && inner->tag == ELMC_TAG_LIST && inner->payload != NULL) {
            ElmcCons *inner_node = (ElmcCons *)inner->payload;
            cell = NULL;
            rc = elmc_list_cons(&cell, inner_node->head, elmc_list_nil());
            CHECK_RC(rc);
            if (tail_slot) {
              elmc_release(*tail_slot);
              *tail_slot = cell;
            } else {
              result = cell;
            }
            tail_slot = &((ElmcCons *)cell->payload)->tail;
            cell = NULL;
            inner = inner_node->tail;
          }
          outer = outer_node->tail;
        }
        if (!result) {
          *out = elmc_list_nil();
        } else {
          *out = result;
          if (rc == RC_SUCCESS) result = NULL;
        }
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(cell);
      elmc_release(result);
      return rc;
    }

    RC elmc_list_concat_array(ElmcValue **out, ElmcValue * const *lists, int count) {
      RC rc = RC_SUCCESS;
      ElmcValue *acc = elmc_list_nil();
      ElmcValue *merged = NULL;
      CATCH_BEGIN
        if (!lists || count <= 0) {
          *out = acc;
          acc = NULL;
        } else {
          for (int i = count - 1; i >= 0; i--) {
            merged = NULL;
            rc = elmc_list_append(&merged, lists[i], acc);
            CHECK_RC(rc);
            elmc_release(acc);
            acc = merged;
            merged = NULL;
          }
          *out = acc;
          acc = NULL;
        }
      CATCH_END;
      elmc_release(merged);
      elmc_release(acc);
      return rc;
    }

    RC elmc_list_concat_map(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      ElmcValue *mapped = NULL;
      CATCH_BEGIN
        rc = elmc_list_map(&mapped, f, list);
        CHECK_RC(rc);
        rc = elmc_list_concat(out, mapped);
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(mapped);
      return rc;
    }

    RC elmc_list_indexed_map(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        return elmc_int_list_indexed_map(out, f, list);
      }
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *index_val = NULL;
      ElmcValue *mapped = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        int64_t idx = 0;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          index_val = NULL;
          rc = elmc_new_int(&index_val, idx);
          CHECK_RC(rc);
          ElmcValue *args[2] = { index_val, node->head };
          mapped = NULL;
          rc = elmc_closure_call_rc(&mapped, f, args, 2);
          elmc_release(index_val);
          index_val = NULL;
          CHECK_RC(rc);
          next = NULL;
          rc = elmc_list_cons(&next, mapped, rev);
          CHECK_RC(rc);
          elmc_release(mapped);
          mapped = NULL;
          elmc_release(rev);
          rev = next;
          next = NULL;
          idx += 1;
          cursor = node->tail;
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(index_val);
      elmc_release(mapped);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_list_filter_map(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        return elmc_int_list_filter_map(out, f, list);
      }
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *maybe_val = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *args[1] = { node->head };
          maybe_val = NULL;
          rc = elmc_closure_call_rc(&maybe_val, f, args, 1);
          CHECK_RC(rc);
          ElmcValue *payload = NULL;
          if (maybe_val && maybe_val->tag == ELMC_TAG_MAYBE && maybe_val->payload != NULL) {
            ElmcMaybe *m = (ElmcMaybe *)maybe_val->payload;
            if (m->is_just && m->value) payload = m->value;
          } else if (maybe_val && maybe_val->tag == ELMC_TAG_TUPLE2 && maybe_val->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)maybe_val->payload;
            if (pair->first && elmc_as_int(pair->first) == 1 && pair->second) payload = pair->second;
          }
          if (payload) {
            next = NULL;
            rc = elmc_list_cons(&next, payload, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = next;
            next = NULL;
          }
          elmc_release(maybe_val);
          maybe_val = NULL;
          cursor = node->tail;
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(maybe_val);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_list_sum(ElmcValue **out, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        int64_t sum = 0;
        ElmcValue *cursor = list;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          sum += elmc_as_int(node->head);
          cursor = node->tail;
        }
        rc = elmc_new_int(out, sum);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    RC elmc_list_product(ElmcValue **out, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        int64_t prod = 1;
        ElmcValue *cursor = list;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          prod *= elmc_as_int(node->head);
          cursor = node->tail;
        }
        rc = elmc_new_int(out, prod);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    RC elmc_list_maximum(ElmcValue **out, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      ElmcValue *val = NULL;
      CATCH_BEGIN
        if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) {
          *out = elmc_maybe_nothing();
        } else {
          ElmcCons *first = (ElmcCons *)list->payload;
          int64_t best = elmc_as_int(first->head);
          ElmcValue *cursor = first->tail;
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            int64_t v = elmc_as_int(node->head);
            if (v > best) best = v;
            cursor = node->tail;
          }
          rc = elmc_new_int(&val, best);
          CHECK_RC(rc);
          rc = elmc_maybe_just(out, val);
          CHECK_RC(rc);
          val = NULL;
        }
      CATCH_END;
      elmc_release(val);
      return rc;
    }

    RC elmc_list_minimum(ElmcValue **out, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      ElmcValue *val = NULL;
      CATCH_BEGIN
        if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) {
          *out = elmc_maybe_nothing();
        } else {
          ElmcCons *first = (ElmcCons *)list->payload;
          int64_t best = elmc_as_int(first->head);
          ElmcValue *cursor = first->tail;
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            int64_t v = elmc_as_int(node->head);
            if (v < best) best = v;
            cursor = node->tail;
          }
          rc = elmc_new_int(&val, best);
          CHECK_RC(rc);
          rc = elmc_maybe_just(out, val);
          CHECK_RC(rc);
          val = NULL;
        }
      CATCH_END;
      elmc_release(val);
      return rc;
    }

    RC elmc_list_any(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      int answer = 0;
      int done = 0;
      ElmcValue *result = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        while (!done && cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *args[1] = { node->head };
          result = NULL;
          rc = elmc_closure_call_rc(&result, f, args, 1);
          CHECK_RC(rc);
          int truthy = elmc_as_int(result) != 0;
          elmc_release(result);
          result = NULL;
          if (truthy) {
            answer = 1;
            done = 1;
          } else {
            cursor = node->tail;
          }
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_new_bool(out, answer);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(result);
      return rc;
    }

    RC elmc_list_all(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      int answer = 1;
      int done = 0;
      ElmcValue *result = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        while (!done && cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *args[1] = { node->head };
          result = NULL;
          rc = elmc_closure_call_rc(&result, f, args, 1);
          CHECK_RC(rc);
          int truthy = elmc_as_int(result) != 0;
          elmc_release(result);
          result = NULL;
          if (!truthy) {
            answer = 0;
            done = 1;
          } else {
            cursor = node->tail;
          }
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_new_bool(out, answer);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(result);
      return rc;
    }

    static int elmc_order_cmp(ElmcValue *order);
    static RC elmc_list_sort_compare(int *cmp_out, ElmcValue *left, ElmcValue *right, ElmcValue *f, int sort_by);
    static RC elmc_list_insert_sorted(ElmcValue **out, ElmcValue *item, ElmcValue *sorted, ElmcValue *f, int sort_by);
    static RC elmc_list_sort_with_fn(ElmcValue **out, ElmcValue *list, ElmcValue *f, int sort_by);

    RC elmc_list_sort(ElmcValue **out, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      ElmcValue *materialized = NULL;
      CATCH_BEGIN
        rc = elmc_list_materialize_cons(&materialized, list);
        CHECK_RC(rc);
        if (!materialized || materialized->tag != ELMC_TAG_LIST) {
          *out = elmc_list_nil();
        } else {
          rc = elmc_list_sort_with_fn(out, materialized, NULL, 2);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(materialized);
      return rc;
    }

    static int elmc_order_cmp(ElmcValue *order) {
      if (!order) return 0;
      return (int)elmc_as_int(order);
    }

    static RC elmc_list_sort_compare(int *cmp_out, ElmcValue *left, ElmcValue *right, ElmcValue *f, int sort_by) {
      RC rc = RC_SUCCESS;
      ElmcValue *key_left = NULL;
      ElmcValue *key_right = NULL;
      ElmcValue *order = NULL;
      CATCH_BEGIN
        if (sort_by == 2) {
          int64_t a = elmc_as_int(left);
          int64_t b = elmc_as_int(right);
          *cmp_out = (a < b) ? -1 : (a > b) ? 1 : 0;
        } else if (sort_by) {
          ElmcValue *args_left[1] = { left };
          ElmcValue *args_right[1] = { right };
          rc = elmc_closure_call_rc(&key_left, f, args_left, 1);
          CHECK_RC(rc);
          rc = elmc_closure_call_rc(&key_right, f, args_right, 1);
          CHECK_RC(rc);
          order = elmc_basics_compare_take(key_left, key_right);
          *cmp_out = elmc_order_cmp(order);
          elmc_release(order);
          order = NULL;
        } else {
          ElmcValue *args[2] = { left, right };
          rc = elmc_closure_call_rc(&order, f, args, 2);
          CHECK_RC(rc);
          *cmp_out = elmc_order_cmp(order);
        }
      CATCH_END;
      elmc_release(key_left);
      elmc_release(key_right);
      elmc_release(order);
      return rc;
    }

    static RC elmc_list_insert_sorted(ElmcValue **out, ElmcValue *item, ElmcValue *sorted, ElmcValue *f, int sort_by) {
      RC rc = RC_SUCCESS;
      ElmcValue *item_copy = elmc_retain(item);
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *next = NULL;
      int inserted = 0;
      CATCH_BEGIN
        ElmcValue *cursor = sorted;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (!inserted) {
            int cmp = 0;
            rc = elmc_list_sort_compare(&cmp, item_copy, node->head, f, sort_by);
            CHECK_RC(rc);
            if (cmp < 0) {
              next = NULL;
              rc = elmc_list_cons(&next, item_copy, rev);
              CHECK_RC(rc);
              elmc_release(rev);
              rev = next;
              next = NULL;
              inserted = 1;
            }
          }
          next = NULL;
          rc = elmc_list_cons(&next, elmc_retain(node->head), rev);
          CHECK_RC(rc);
          elmc_release(rev);
          rev = next;
          next = NULL;
          cursor = node->tail;
        }
        if (!inserted) {
          next = NULL;
          rc = elmc_list_cons(&next, item_copy, rev);
          CHECK_RC(rc);
          elmc_release(rev);
          rev = next;
          next = NULL;
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(item_copy);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    static RC elmc_list_sort_with_fn(ElmcValue **out, ElmcValue *list, ElmcValue *f, int sort_by) {
      RC rc = RC_SUCCESS;
      ElmcValue *sorted = elmc_list_nil();
      ElmcValue *next_sorted = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          next_sorted = NULL;
          rc = elmc_list_insert_sorted(&next_sorted, node->head, sorted, f, sort_by);
          CHECK_RC(rc);
          elmc_release(sorted);
          sorted = next_sorted;
          next_sorted = NULL;
          cursor = node->tail;
        }
        if (rc == RC_SUCCESS) {
          *out = sorted;
          sorted = NULL;
        }
      CATCH_END;
      elmc_release(next_sorted);
      elmc_release(sorted);
      return rc;
    }

    RC elmc_list_sort_by(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      ElmcValue *materialized = NULL;
      CATCH_BEGIN
        rc = elmc_list_materialize_cons(&materialized, list);
        CHECK_RC(rc);
        if (!materialized || materialized->tag != ELMC_TAG_LIST) {
          *out = elmc_list_nil();
        } else {
          rc = elmc_list_sort_with_fn(out, materialized, f, 1);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(materialized);
      return rc;
    }

    RC elmc_list_sort_with(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      ElmcValue *materialized = NULL;
      CATCH_BEGIN
        rc = elmc_list_materialize_cons(&materialized, list);
        CHECK_RC(rc);
        if (!materialized || materialized->tag != ELMC_TAG_LIST) {
          *out = elmc_list_nil();
        } else {
          rc = elmc_list_sort_with_fn(out, materialized, f, 0);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(materialized);
      return rc;
    }

    RC elmc_list_singleton(ElmcValue **out, ElmcValue *value) {
      RC rc = RC_SUCCESS;
      ElmcValue *nil = elmc_list_nil();
      CATCH_BEGIN
        rc = elmc_list_cons(out, value, nil);
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(nil);
      return rc;
    }

    RC elmc_list_range(ElmcValue **out, ElmcValue *lo, ElmcValue *hi) {
      RC rc = RC_SUCCESS;
      int64_t low = elmc_as_int(lo);
      int64_t high = elmc_as_int(hi);
      ElmcValue *acc = elmc_list_nil();
      ElmcValue *val = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        for (int64_t i = high; i >= low; i--) {
          val = NULL;
          rc = elmc_new_int(&val, i);
          CHECK_RC(rc);
          next = NULL;
          rc = elmc_list_cons(&next, val, acc);
          CHECK_RC(rc);
          elmc_release(val);
          val = NULL;
          elmc_release(acc);
          acc = next;
          next = NULL;
        }
        if (rc == RC_SUCCESS) {
          *out = acc;
          acc = NULL;
        }
      CATCH_END;
      elmc_release(val);
      elmc_release(next);
      elmc_release(acc);
      return rc;
    }

    RC elmc_list_repeat_count(ElmcValue **out, elmc_int_t count, ElmcValue *value) {
      RC rc = RC_SUCCESS;
      ElmcValue *acc = elmc_list_nil();
      ElmcValue *item = value ? elmc_retain(value) : elmc_int_zero();
      ElmcValue *cons = NULL;
      CATCH_BEGIN
        for (elmc_int_t i = 0; i < count; i++) {
          cons = NULL;
          rc = elmc_list_cons(&cons, item, acc);
          CHECK_RC(rc);
          elmc_release(acc);
          acc = cons;
          cons = NULL;
        }
        if (rc == RC_SUCCESS) {
          *out = acc;
          acc = NULL;
        }
      CATCH_END;
      elmc_release(item);
      elmc_release(cons);
      elmc_release(acc);
      return rc;
    }

    RC elmc_list_repeat(ElmcValue **out, ElmcValue *n, ElmcValue *value) {
      return elmc_list_repeat_count(out, (elmc_int_t)elmc_as_int(n), value);
    }

    RC elmc_list_take(ElmcValue **out, ElmcValue *n, ElmcValue *list) {
      return elmc_list_take_int(out, elmc_as_int(n), list);
    }

    RC elmc_list_take_int(ElmcValue **out, elmc_int_t count, ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        return elmc_int_list_take_int(out, count, list);
      }
      RC rc = RC_SUCCESS;
      ElmcValue *result = NULL;
      ElmcValue **tail_slot = NULL;
      ElmcValue *cell = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        elmc_int_t i = 0;
        while (i < count && cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          cell = NULL;
          rc = elmc_list_cons(&cell, node->head, elmc_list_nil());
          CHECK_RC(rc);
          if (tail_slot) {
            elmc_release(*tail_slot);
            *tail_slot = cell;
          } else {
            result = cell;
          }
          tail_slot = &((ElmcCons *)cell->payload)->tail;
          cell = NULL;
          cursor = node->tail;
          i++;
        }
        if (!result) {
          *out = elmc_list_nil();
        } else {
          *out = result;
          if (rc == RC_SUCCESS) result = NULL;
        }
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(cell);
      elmc_release(result);
      return rc;
    }

    RC elmc_list_drop(ElmcValue **out, ElmcValue *n, ElmcValue *list) {
      return elmc_list_drop_int(out, elmc_as_int(n), list);
    }

    RC elmc_list_slice_int(ElmcValue **out, elmc_int_t drop, elmc_int_t take, ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        return elmc_int_list_slice_int(out, drop, take, list);
      }
      RC rc = RC_SUCCESS;
      ElmcValue *dropped = NULL;
      CATCH_BEGIN
        rc = elmc_list_drop_int(&dropped, drop, list);
        CHECK_RC(rc);
        rc = elmc_list_take_int(out, take, dropped);
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(dropped);
      return rc;
    }

    RC elmc_list_drop_int(ElmcValue **out, elmc_int_t count, ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        return elmc_int_list_drop_int(out, count, list);
      }
      RC rc = RC_SUCCESS;
      ElmcValue *result = NULL;
      ElmcValue **tail_slot = NULL;
      ElmcValue *cell = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        elmc_int_t i = 0;
        while (i < count && cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          cursor = ((ElmcCons *)cursor->payload)->tail;
          i++;
        }
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          cell = NULL;
          rc = elmc_list_cons(&cell, node->head, elmc_list_nil());
          CHECK_RC(rc);
          if (tail_slot) {
            elmc_release(*tail_slot);
            *tail_slot = cell;
          } else {
            result = cell;
          }
          tail_slot = &((ElmcCons *)cell->payload)->tail;
          cell = NULL;
          cursor = node->tail;
        }
        if (!result) {
          *out = elmc_list_nil();
        } else {
          *out = result;
          if (rc == RC_SUCCESS) result = NULL;
        }
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(cell);
      elmc_release(result);
      return rc;
    }

    RC elmc_list_partition(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev_yes = elmc_list_nil();
      ElmcValue *rev_no = elmc_list_nil();
      ElmcValue *keep = NULL;
      ElmcValue *next = NULL;
      ElmcValue *yes = NULL;
      ElmcValue *no = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *args[1] = { node->head };
          keep = NULL;
          rc = elmc_closure_call_rc(&keep, f, args, 1);
          CHECK_RC(rc);
          if (elmc_as_int(keep)) {
            next = NULL;
            rc = elmc_list_cons(&next, node->head, rev_yes);
            CHECK_RC(rc);
            elmc_release(rev_yes);
            rev_yes = next;
            next = NULL;
          } else {
            next = NULL;
            rc = elmc_list_cons(&next, node->head, rev_no);
            CHECK_RC(rc);
            elmc_release(rev_no);
            rev_no = next;
            next = NULL;
          }
          elmc_release(keep);
          keep = NULL;
          cursor = node->tail;
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_list_reverse_transfer(&yes, &rev_yes);
          CHECK_RC(rc);
          rc = elmc_list_reverse_transfer(&no, &rev_no);
          CHECK_RC(rc);
          rc = elmc_tuple2(out, yes, no);
          CHECK_RC(rc);
          elmc_release(yes);
          elmc_release(no);
          yes = NULL;
          no = NULL;
        }
      CATCH_END;
      elmc_release(keep);
      elmc_release(next);
      elmc_release(rev_yes);
      elmc_release(rev_no);
      elmc_release(yes);
      elmc_release(no);
      return rc;
    }

    RC elmc_list_unzip(ElmcValue **out, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev_a = elmc_list_nil();
      ElmcValue *rev_b = elmc_list_nil();
      ElmcValue *na = NULL;
      ElmcValue *nb = NULL;
      ElmcValue *a = NULL;
      ElmcValue *b = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = list;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
            na = NULL;
            rc = elmc_list_cons(&na, pair->first, rev_a);
            CHECK_RC(rc);
            elmc_release(rev_a);
            rev_a = na;
            na = NULL;
            nb = NULL;
            rc = elmc_list_cons(&nb, pair->second, rev_b);
            CHECK_RC(rc);
            elmc_release(rev_b);
            rev_b = nb;
            nb = NULL;
          }
          cursor = node->tail;
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_list_reverse_transfer(&a, &rev_a);
          CHECK_RC(rc);
          rc = elmc_list_reverse_transfer(&b, &rev_b);
          CHECK_RC(rc);
          rc = elmc_tuple2(out, a, b);
          CHECK_RC(rc);
          elmc_release(a);
          elmc_release(b);
          a = NULL;
          b = NULL;
        }
      CATCH_END;
      elmc_release(na);
      elmc_release(nb);
      elmc_release(rev_a);
      elmc_release(rev_b);
      elmc_release(a);
      elmc_release(b);
      return rc;
    }

    RC elmc_list_intersperse(ElmcValue **out, ElmcValue *sep, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *ns = NULL;
      ElmcValue *nh = NULL;
      CATCH_BEGIN
        if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) {
          *out = elmc_list_nil();
        } else {
          ElmcValue *cursor = list;
          int first = 1;
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            if (!first) {
              ns = NULL;
              rc = elmc_list_cons(&ns, sep, rev);
              CHECK_RC(rc);
              elmc_release(rev);
              rev = ns;
              ns = NULL;
            }
            nh = NULL;
            rc = elmc_list_cons(&nh, node->head, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = nh;
            nh = NULL;
            first = 0;
            cursor = node->tail;
          }
          if (rc == RC_SUCCESS) {
            rc = elmc_list_reverse_transfer(out, &rev);
            CHECK_RC(rc);
          }
        }
      CATCH_END;
      elmc_release(ns);
      elmc_release(nh);
      elmc_release(rev);
      return rc;
    }

    RC elmc_list_map2(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *mapped = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *ca = a;
        ElmcValue *cb = b;
        while (ca && ca->tag == ELMC_TAG_LIST && ca->payload != NULL &&
               cb && cb->tag == ELMC_TAG_LIST && cb->payload != NULL) {
          ElmcCons *na = (ElmcCons *)ca->payload;
          ElmcCons *nb = (ElmcCons *)cb->payload;
          ElmcValue *args[2] = { na->head, nb->head };
          mapped = NULL;
          rc = elmc_closure_call_rc(&mapped, f, args, 2);
          CHECK_RC(rc);
          next = NULL;
          rc = elmc_list_cons(&next, mapped, rev);
          CHECK_RC(rc);
          elmc_release(mapped);
          mapped = NULL;
          elmc_release(rev);
          rev = next;
          next = NULL;
          ca = na->tail;
          cb = nb->tail;
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(mapped);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_list_map3(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *mapped = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *ca = a;
        ElmcValue *cb = b;
        ElmcValue *cc = c;
        while (ca && ca->tag == ELMC_TAG_LIST && ca->payload != NULL &&
               cb && cb->tag == ELMC_TAG_LIST && cb->payload != NULL &&
               cc && cc->tag == ELMC_TAG_LIST && cc->payload != NULL) {
          ElmcCons *na = (ElmcCons *)ca->payload;
          ElmcCons *nb = (ElmcCons *)cb->payload;
          ElmcCons *nc = (ElmcCons *)cc->payload;
          ElmcValue *args[3] = { na->head, nb->head, nc->head };
          mapped = NULL;
          rc = elmc_closure_call_rc(&mapped, f, args, 3);
          CHECK_RC(rc);
          next = NULL;
          rc = elmc_list_cons(&next, mapped, rev);
          CHECK_RC(rc);
          elmc_release(mapped);
          mapped = NULL;
          elmc_release(rev);
          rev = next;
          next = NULL;
          ca = na->tail;
          cb = nb->tail;
          cc = nc->tail;
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(mapped);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_list_map4(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *mapped = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *ca = a;
        ElmcValue *cb = b;
        ElmcValue *cc = c;
        ElmcValue *cd = d;
        while (ca && ca->tag == ELMC_TAG_LIST && ca->payload != NULL &&
               cb && cb->tag == ELMC_TAG_LIST && cb->payload != NULL &&
               cc && cc->tag == ELMC_TAG_LIST && cc->payload != NULL &&
               cd && cd->tag == ELMC_TAG_LIST && cd->payload != NULL) {
          ElmcCons *na = (ElmcCons *)ca->payload;
          ElmcCons *nb = (ElmcCons *)cb->payload;
          ElmcCons *nc = (ElmcCons *)cc->payload;
          ElmcCons *nd = (ElmcCons *)cd->payload;
          ElmcValue *args[4] = { na->head, nb->head, nc->head, nd->head };
          mapped = NULL;
          rc = elmc_closure_call_rc(&mapped, f, args, 4);
          CHECK_RC(rc);
          next = NULL;
          rc = elmc_list_cons(&next, mapped, rev);
          CHECK_RC(rc);
          elmc_release(mapped);
          mapped = NULL;
          elmc_release(rev);
          rev = next;
          next = NULL;
          ca = na->tail;
          cb = nb->tail;
          cc = nc->tail;
          cd = nd->tail;
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(mapped);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_list_map5(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d, ElmcValue *e) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *mapped = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *ca = a;
        ElmcValue *cb = b;
        ElmcValue *cc = c;
        ElmcValue *cd = d;
        ElmcValue *ce = e;
        while (ca && ca->tag == ELMC_TAG_LIST && ca->payload != NULL &&
               cb && cb->tag == ELMC_TAG_LIST && cb->payload != NULL &&
               cc && cc->tag == ELMC_TAG_LIST && cc->payload != NULL &&
               cd && cd->tag == ELMC_TAG_LIST && cd->payload != NULL &&
               ce && ce->tag == ELMC_TAG_LIST && ce->payload != NULL) {
          ElmcCons *na = (ElmcCons *)ca->payload;
          ElmcCons *nb = (ElmcCons *)cb->payload;
          ElmcCons *nc = (ElmcCons *)cc->payload;
          ElmcCons *nd = (ElmcCons *)cd->payload;
          ElmcCons *ne = (ElmcCons *)ce->payload;
          ElmcValue *args[5] = { na->head, nb->head, nc->head, nd->head, ne->head };
          mapped = NULL;
          rc = elmc_closure_call_rc(&mapped, f, args, 5);
          CHECK_RC(rc);
          next = NULL;
          rc = elmc_list_cons(&next, mapped, rev);
          CHECK_RC(rc);
          elmc_release(mapped);
          mapped = NULL;
          elmc_release(rev);
          rev = next;
          next = NULL;
          ca = na->tail;
          cb = nb->tail;
          cc = nc->tail;
          cd = nd->tail;
          ce = ne->tail;
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(mapped);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    /* ================================================================
       Standard Library – Maybe operations
       ================================================================ */

    ElmcValue *elmc_maybe_with_default(ElmcValue *default_val, ElmcValue *maybe) {
      if (!maybe) return elmc_retain(default_val);
      if (maybe->tag == ELMC_TAG_MAYBE) {
        ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
        if (m && m->is_just && m->value) return elmc_retain(m->value);
        return elmc_retain(default_val);
      }
      if (maybe->tag == ELMC_TAG_TUPLE2 && maybe->payload) {
        ElmcTuple2 *pair = (ElmcTuple2 *)maybe->payload;
        if (pair->first && elmc_as_int(pair->first) == 1 && pair->second) {
          return elmc_retain(pair->second);
        }
      }
      return elmc_retain(default_val);
    }

    elmc_int_t elmc_maybe_with_default_int(elmc_int_t default_val, ElmcValue *maybe) {
      if (!maybe) return default_val;
      if (maybe->tag == ELMC_TAG_MAYBE) {
        ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
        if (m && m->is_just && m->value) return elmc_as_int(m->value);
        return default_val;
      }
      if (maybe->tag == ELMC_TAG_TUPLE2 && maybe->payload) {
        ElmcTuple2 *pair = (ElmcTuple2 *)maybe->payload;
        if (pair->first && elmc_as_int(pair->first) == 1 && pair->second) {
          return elmc_as_int(pair->second);
        }
      }
      return default_val;
    }

    RC elmc_maybe_map(ElmcValue **out, ElmcValue *f, ElmcValue *maybe) {
      RC rc = RC_SUCCESS;
      ElmcValue *mapped = NULL;
      CATCH_BEGIN
        if (!maybe || maybe->tag != ELMC_TAG_MAYBE) {
          *out = elmc_maybe_nothing();
        } else {
          ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
          if (!m->is_just || !m->value) {
            *out = elmc_maybe_nothing();
          } else {
            ElmcValue *args[1] = { m->value };
            rc = elmc_closure_call_rc(&mapped, f, args, 1);
            CHECK_RC(rc);
            rc = elmc_maybe_just(out, mapped);
            CHECK_RC(rc);
          }
        }
      CATCH_END;
      elmc_release(mapped);
      return rc;
    }

    RC elmc_maybe_map2(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b) {
      RC rc = RC_SUCCESS;
      ElmcValue *mapped = NULL;
      CATCH_BEGIN
        if (!a || a->tag != ELMC_TAG_MAYBE || !b || b->tag != ELMC_TAG_MAYBE) {
          *out = elmc_maybe_nothing();
        } else {
          ElmcMaybe *ma = (ElmcMaybe *)a->payload;
          ElmcMaybe *mb = (ElmcMaybe *)b->payload;
          if (!ma->is_just || !ma->value || !mb->is_just || !mb->value) {
            *out = elmc_maybe_nothing();
          } else {
            ElmcValue *args[2] = { ma->value, mb->value };
            rc = elmc_closure_call_rc(&mapped, f, args, 2);
            CHECK_RC(rc);
            rc = elmc_maybe_just(out, mapped);
            CHECK_RC(rc);
          }
        }
      CATCH_END;
      elmc_release(mapped);
      return rc;
    }

    RC elmc_maybe_and_then(ElmcValue **out, ElmcValue *f, ElmcValue *maybe) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        if (!maybe || maybe->tag != ELMC_TAG_MAYBE) {
          *out = elmc_maybe_nothing();
        } else {
          ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
          if (!m->is_just || !m->value) {
            *out = elmc_maybe_nothing();
          } else {
            ElmcValue *payload = elmc_retain(m->value);
            ElmcValue *args[1] = { payload };
            rc = elmc_closure_call_rc(out, f, args, 1);
            CHECK_RC(rc);
            elmc_release(maybe);
          }
        }
      CATCH_END;
      return rc;
    }

    /* ================================================================
       Standard Library – Result operations
       ================================================================ */

    RC elmc_result_map(ElmcValue **out, ElmcValue *f, ElmcValue *result) {
      RC rc = RC_SUCCESS;
      ElmcValue *msg = NULL;
      ElmcValue *mapped = NULL;
      CATCH_BEGIN
        if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) {
          rc = elmc_new_string(&msg, "invalid");
          CHECK_RC(rc);
          rc = elmc_result_err(out, msg);
          CHECK_RC(rc);
        } else {
          ElmcResult *r = (ElmcResult *)result->payload;
          if (!r->is_ok) {
            *out = result;
          } else {
            ElmcValue *args[1] = { r->value };
            rc = elmc_closure_call_rc(&mapped, f, args, 1);
            CHECK_RC(rc);
            rc = elmc_result_ok(out, mapped);
            CHECK_RC(rc);
          }
        }
      CATCH_END;
      elmc_release(msg);
      elmc_release(mapped);
      return rc;
    }

    RC elmc_result_map_error(ElmcValue **out, ElmcValue *f, ElmcValue *result) {
      RC rc = RC_SUCCESS;
      ElmcValue *mapped = NULL;
      CATCH_BEGIN
        if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) {
          *out = result;
        } else {
          ElmcResult *r = (ElmcResult *)result->payload;
          if (r->is_ok) {
            *out = result;
          } else {
            ElmcValue *args[1] = { r->value };
            rc = elmc_closure_call_rc(&mapped, f, args, 1);
            CHECK_RC(rc);
            rc = elmc_result_err(out, mapped);
            CHECK_RC(rc);
          }
        }
      CATCH_END;
      elmc_release(mapped);
      return rc;
    }

    RC elmc_result_and_then(ElmcValue **out, ElmcValue *f, ElmcValue *result) {
      RC rc = RC_SUCCESS;
      ElmcValue *msg = NULL;
      CATCH_BEGIN
        if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) {
          rc = elmc_new_string(&msg, "invalid");
          CHECK_RC(rc);
          rc = elmc_result_err(out, msg);
          CHECK_RC(rc);
          elmc_release(result);
        } else {
          ElmcResult *r = (ElmcResult *)result->payload;
          if (!r->is_ok) {
            *out = result;
          } else {
            ElmcValue *payload = elmc_retain(r->value);
            ElmcValue *args[1] = { payload };
            rc = elmc_closure_call_rc(out, f, args, 1);
            elmc_release(payload);
            CHECK_RC(rc);
            elmc_release(result);
          }
        }
      CATCH_END;
      elmc_release(msg);
      return rc;
    }

    ElmcValue *elmc_result_with_default(ElmcValue *default_val, ElmcValue *result) {
      if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) return elmc_retain(default_val);
      ElmcResult *r = (ElmcResult *)result->payload;
      if (r->is_ok && r->value) return elmc_retain(r->value);
      return elmc_retain(default_val);
    }

    ElmcValue *elmc_result_to_maybe(ElmcValue *result) {
      if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) return elmc_maybe_nothing();
      ElmcResult *r = (ElmcResult *)result->payload;
      if (r->is_ok && r->value) {
        ElmcValue *_elmc_rc_out = NULL;
        if (elmc_maybe_just(&_elmc_rc_out, r->value) != RC_SUCCESS) return NULL;
        return _elmc_rc_out;
      }
      return elmc_maybe_nothing();
    }

    ElmcValue *elmc_result_from_maybe(ElmcValue *err, ElmcValue *maybe) {
      if (!maybe || maybe->tag != ELMC_TAG_MAYBE || !maybe->payload) {
        ElmcValue *_elmc_rc_out = NULL;
        if (elmc_result_err(&_elmc_rc_out, err) != RC_SUCCESS) return NULL;
        return _elmc_rc_out;
      }
      ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
      if (m->is_just && m->value) {
        ElmcValue *_elmc_rc_out = NULL;
        if (elmc_result_ok(&_elmc_rc_out, m->value) != RC_SUCCESS) return NULL;
        return _elmc_rc_out;
      }
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_result_err(&_elmc_rc_out, err) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    /* ================================================================
       Standard Library – String operations (extended)
       ================================================================ */

    ElmcValue *elmc_string_length_val(ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_int_zero();
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, (int64_t)elmc_string_byte_len(s)) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    RC elmc_string_reverse(ElmcValue **out, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      uint32_t *cps = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          const char *src = (const char *)s->payload;
          size_t byte_len = strlen(src);
          size_t cp_count = elmc_utf8_codepoint_count(src);
          if (cp_count == 0) {
            *out = &ELMC_EMPTY_STRING;
          } else {
            cps = (uint32_t *)elmc_malloc(cp_count * sizeof(uint32_t), __func__);
            if (!cps) {
              rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(rc);
            }
            const unsigned char *p = (const unsigned char *)src;
            const unsigned char *end = p + byte_len;
            for (size_t i = 0; i < cp_count; i++) {
              if (!elmc_utf8_decode_codepoint(&p, end, &cps[i])) break;
            }
            buf = (char *)elmc_malloc(byte_len + 1, __func__);
            if (!buf) {
              rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(rc);
            }
            size_t out_len = 0;
            for (size_t i = cp_count; i > 0; i--) {
              int n = elmc_utf8_encode_codepoint(cps[i - 1], buf + out_len, byte_len + 1 - out_len);
              if (n <= 0) {
                rc = RC_ERR_INVALID_ARG;
                CHECK_RC(rc);
              }
              out_len += (size_t)n;
            }
            buf[out_len] = '\\0';
            ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
            buf = NULL;
            if (!allocated) {
              rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(rc);
            }
            *out = allocated;
          }
        }
      CATCH_END;
      if (cps) elmc_free(cps);
      if (buf) elmc_free(buf);
      return rc;
    }

    RC elmc_string_repeat(ElmcValue **out, ElmcValue *n, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      CATCH_BEGIN
        int64_t count = elmc_as_int(n);
        if (count <= 0 || !s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          const char *src = (const char *)s->payload;
          size_t slen = strlen(src);
          size_t total = slen * (size_t)count;
          buf = (char *)elmc_malloc(total + 1, __func__);
          if (!buf) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          for (int64_t i = 0; i < count; i++) {
            memcpy(buf + i * slen, src, slen);
          }
          buf[total] = '\\0';
          ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
          buf = NULL;
          if (!allocated) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          *out = allocated;
        }
      CATCH_END;
      if (buf) elmc_free(buf);
      return rc;
    }

    RC elmc_string_replace(ElmcValue **out, ElmcValue *old_s, ElmcValue *new_s, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = &ELMC_EMPTY_STRING;
        } else if (!old_s || old_s->tag != ELMC_TAG_STRING || !old_s->payload) {
          *out = elmc_retain(s);
        } else {
          if (!new_s || new_s->tag != ELMC_TAG_STRING || !new_s->payload) new_s = &ELMC_EMPTY_STRING;
          const char *haystack = (const char *)s->payload;
          const char *needle = (const char *)old_s->payload;
          const char *replacement = (const char *)new_s->payload;
          size_t needle_len = strlen(needle);
          if (needle_len == 0) {
            *out = elmc_retain(s);
          } else {
            size_t repl_len = strlen(replacement);
            size_t cap = strlen(haystack) + 1;
            buf = (char *)elmc_malloc(cap, __func__);
            if (!buf) {
              rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(rc);
            }
            size_t out_len = 0;
            const char *p = haystack;
            while (*p) {
              if (strncmp(p, needle, needle_len) == 0) {
                size_t needed = out_len + repl_len + strlen(p) + 1;
                if (needed > cap) {
                  cap = needed * 2;
                  char *grown = (char *)elmc_malloc(cap, __func__);
                  if (!grown) {
                    rc = RC_ERR_OUT_OF_MEMORY;
                    CHECK_RC(rc);
                  }
                  memcpy(grown, buf, out_len);
                  elmc_free(buf);
                  buf = grown;
                }
                memcpy(buf + out_len, replacement, repl_len);
                out_len += repl_len;
                p += needle_len;
              } else {
                size_t needed = out_len + strlen(p) + 2;
                if (needed > cap) {
                  cap = needed * 2;
                  char *grown = (char *)elmc_malloc(cap, __func__);
                  if (!grown) {
                    rc = RC_ERR_OUT_OF_MEMORY;
                    CHECK_RC(rc);
                  }
                  memcpy(grown, buf, out_len);
                  elmc_free(buf);
                  buf = grown;
                }
                buf[out_len++] = *p++;
              }
            }
            buf[out_len] = '\\0';
            ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
            buf = NULL;
            if (!allocated) {
              rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(rc);
            }
            *out = allocated;
          }
        }
      CATCH_END;
      if (buf) elmc_free(buf);
      return rc;
    }

    ElmcValue *elmc_string_from_int(ElmcValue *n) {
      return elmc_string_from_native_int_take(elmc_as_int(n));
    }

    RC elmc_string_from_native_int(ElmcValue **out, elmc_int_t n) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        char buf[32];
        snprintf(buf, sizeof(buf), "%lld", (long long)n);
        rc = elmc_new_string(out, buf);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    ElmcValue *elmc_string_to_int(ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_maybe_nothing();
      const char *str = (const char *)s->payload;
      if (!str || *str == '\\0') return elmc_maybe_nothing();
      int sign = 1;
      size_t idx = 0;
      if (str[idx] == '+' || str[idx] == '-') {
        if (str[idx] == '-') sign = -1;
        idx++;
      }
      if (str[idx] == '\\0') return elmc_maybe_nothing();

      uint64_t acc = 0;
      int saw_digit = 0;
      for (; str[idx] != '\\0'; idx++) {
        char ch = str[idx];
        if (ch < '0' || ch > '9') return elmc_maybe_nothing();
        saw_digit = 1;
        uint64_t digit = (uint64_t)(ch - '0');
        if (acc > 922337203685477580ULL || (acc == 922337203685477580ULL && digit > 7ULL + (sign < 0 ? 1ULL : 0ULL))) {
          return elmc_maybe_nothing();
        }
        acc = (acc * 10ULL) + digit;
      }
      if (!saw_digit) return elmc_maybe_nothing();

      int64_t parsed = 0;
      if (sign < 0) {
        if (acc == 9223372036854775808ULL) {
          parsed = INT64_MIN;
        } else {
          parsed = -(int64_t)acc;
        }
      } else {
        parsed = (int64_t)acc;
      }

      ElmcValue *v = NULL;
      if (elmc_new_int(&v, parsed) != RC_SUCCESS) v = NULL;
      ElmcValue *out = NULL;
      if (elmc_maybe_just(&out, v) != RC_SUCCESS) out = NULL;
      elmc_release(v);
      return out;
    }

    RC elmc_string_from_float(ElmcValue **out, ElmcValue *f) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        char buf[64];
        double val = elmc_as_float(f);
        int64_t whole = (int64_t)val;
        if (val == (double)whole) {
          snprintf(buf, sizeof(buf), "%lld", (long long)whole);
        } else {
          double abs_val = (val < 0.0) ? -val : val;
          int64_t abs_whole = (int64_t)abs_val;
          int64_t frac3 = (int64_t)((abs_val - (double)abs_whole) * 1000.0 + 0.5);
          if (frac3 >= 1000) {
            abs_whole += 1;
            frac3 = 0;
          }
          if (val < 0.0) {
            snprintf(buf, sizeof(buf), "-%lld.%03lld", (long long)abs_whole, (long long)frac3);
          } else {
            snprintf(buf, sizeof(buf), "%lld.%03lld", (long long)abs_whole, (long long)frac3);
          }
          char *dot = strchr(buf, '.');
          if (dot) {
            char *end = buf + strlen(buf) - 1;
            while (end > dot && *end == '0') {
              *end = '\\0';
              end--;
            }
            if (end == dot) *end = '\\0';
          }
        }
        rc = elmc_new_string(out, buf);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    ElmcValue *elmc_string_to_float(ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_maybe_nothing();

      const char *p = (const char *)s->payload;
      int sign = 1;
      if (*p == '+' || *p == '-') {
        if (*p == '-') sign = -1;
        p++;
      }

      int saw_digit = 0;
      double whole = 0.0;
      while (*p >= '0' && *p <= '9') {
        saw_digit = 1;
        whole = whole * 10.0 + (double)(*p - '0');
        p++;
      }

      double frac = 0.0;
      double place = 0.1;
      if (*p == '.') {
        p++;
        while (*p >= '0' && *p <= '9') {
          saw_digit = 1;
          frac += (double)(*p - '0') * place;
          place *= 0.1;
          p++;
        }
      }

      if (!saw_digit || *p != '\\0') return elmc_maybe_nothing();

      double val = (double)sign * (whole + frac);
      ElmcValue *v = elmc_new_float_take(val);
      ElmcValue *out = NULL;
      if (elmc_maybe_just(&out, v) != RC_SUCCESS) out = NULL;
      elmc_release(v);
      return out;
    }

    RC elmc_string_to_upper(ElmcValue **out, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          const char *src = (const char *)s->payload;
          size_t len = strlen(src);
          buf = (char *)elmc_malloc(len + 1, __func__);
          if (!buf) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          for (size_t i = 0; i < len; i++) {
            char c = src[i];
            buf[i] = (c >= 'a' && c <= 'z') ? (c - 32) : c;
          }
          buf[len] = '\\0';
          ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
          buf = NULL;
          if (!allocated) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          *out = allocated;
        }
      CATCH_END;
      if (buf) elmc_free(buf);
      return rc;
    }

    RC elmc_string_to_lower(ElmcValue **out, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          const char *src = (const char *)s->payload;
          size_t len = strlen(src);
          buf = (char *)elmc_malloc(len + 1, __func__);
          if (!buf) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          for (size_t i = 0; i < len; i++) {
            char c = src[i];
            buf[i] = (c >= 'A' && c <= 'Z') ? (c + 32) : c;
          }
          buf[len] = '\\0';
          ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
          buf = NULL;
          if (!allocated) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          *out = allocated;
        }
      CATCH_END;
      if (buf) elmc_free(buf);
      return rc;
    }

    RC elmc_string_trim(ElmcValue **out, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          const char *src = (const char *)s->payload;
          size_t len = strlen(src);
          size_t start = 0;
          while (start < len && (src[start] == ' ' || src[start] == '\\t' || src[start] == '\\n' || src[start] == '\\r')) start++;
          size_t end = len;
          while (end > start && (src[end-1] == ' ' || src[end-1] == '\\t' || src[end-1] == '\\n' || src[end-1] == '\\r')) end--;
          size_t new_len = end - start;
          buf = (char *)elmc_malloc(new_len + 1, __func__);
          if (!buf) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          memcpy(buf, src + start, new_len);
          buf[new_len] = '\\0';
          ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
          buf = NULL;
          if (!allocated) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          *out = allocated;
        }
      CATCH_END;
      if (buf) elmc_free(buf);
      return rc;
    }

    RC elmc_string_trim_left(ElmcValue **out, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          const char *src = (const char *)s->payload;
          size_t len = strlen(src);
          size_t start = 0;
          while (start < len && (src[start] == ' ' || src[start] == '\\t' || src[start] == '\\n' || src[start] == '\\r')) start++;
          rc = elmc_new_string(out, src + start);
          CHECK_RC(rc);
        }
      CATCH_END;
      return rc;
    }

    RC elmc_string_trim_right(ElmcValue **out, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          const char *src = (const char *)s->payload;
          size_t len = strlen(src);
          while (len > 0 && (src[len-1] == ' ' || src[len-1] == '\\t' || src[len-1] == '\\n' || src[len-1] == '\\r')) len--;
          buf = (char *)elmc_malloc(len + 1, __func__);
          if (!buf) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          memcpy(buf, src, len);
          buf[len] = '\\0';
          ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
          buf = NULL;
          if (!allocated) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          *out = allocated;
        }
      CATCH_END;
      if (buf) elmc_free(buf);
      return rc;
    }

    int elmc_string_equals_cstr(ElmcValue *value, const char *literal) {
      if (!value || value->tag != ELMC_TAG_STRING || !value->payload || !literal) return 0;
      size_t len = elmc_string_byte_len(value);
      size_t lit_len = strlen(literal);
      if (len != lit_len) return 0;
      return memcmp(value->payload, literal, len) == 0;
    }

    ElmcValue *elmc_string_contains(ElmcValue *sub, ElmcValue *s) {
      if (!sub || sub->tag != ELMC_TAG_STRING || !s || s->tag != ELMC_TAG_STRING) {
        ElmcValue *_elmc_rc_out = NULL;
        (void)elmc_new_bool(&_elmc_rc_out, 0);
        return _elmc_rc_out;
      }
      const char *haystack = (const char *)s->payload;
      const char *needle = (const char *)sub->payload;
      if (!haystack || !needle) {
        ElmcValue *_elmc_rc_out = NULL;
        (void)elmc_new_bool(&_elmc_rc_out, 0);
        return _elmc_rc_out;
      }
      size_t hay_len = elmc_string_byte_len(s);
      size_t needle_len = elmc_string_byte_len(sub);
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, elmc_memmem(haystack, hay_len, needle, needle_len) != NULL);
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_string_starts_with(ElmcValue *prefix, ElmcValue *s) {
      if (!prefix || prefix->tag != ELMC_TAG_STRING || !s || s->tag != ELMC_TAG_STRING) {
        ElmcValue *_elmc_rc_out = NULL;
        (void)elmc_new_bool(&_elmc_rc_out, 0);
        return _elmc_rc_out;
      }
      const char *str = (const char *)s->payload;
      const char *pre = (const char *)prefix->payload;
      if (!str || !pre) {
        ElmcValue *_elmc_rc_out = NULL;
        (void)elmc_new_bool(&_elmc_rc_out, 0);
        return _elmc_rc_out;
      }
      size_t plen = strlen(pre);
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, strncmp(str, pre, plen) == 0);
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_string_ends_with(ElmcValue *suffix, ElmcValue *s) {
      if (!suffix || suffix->tag != ELMC_TAG_STRING || !s || s->tag != ELMC_TAG_STRING) {
        ElmcValue *_elmc_rc_out = NULL;
        (void)elmc_new_bool(&_elmc_rc_out, 0);
        return _elmc_rc_out;
      }
      const char *str = (const char *)s->payload;
      const char *suf = (const char *)suffix->payload;
      if (!str || !suf) {
        ElmcValue *_elmc_rc_out = NULL;
        (void)elmc_new_bool(&_elmc_rc_out, 0);
        return _elmc_rc_out;
      }
      size_t slen = strlen(str);
      size_t suflen = strlen(suf);
      if (suflen > slen) {
        ElmcValue *_elmc_rc_out = NULL;
        (void)elmc_new_bool(&_elmc_rc_out, 0);
        return _elmc_rc_out;
      }
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, strcmp(str + slen - suflen, suf) == 0);
          return _elmc_rc_out;
      }
    }

    RC elmc_string_split(ElmcValue **out, ElmcValue *sep, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *ch = NULL;
      ElmcValue *part = NULL;
      ElmcValue *next = NULL;
      char *buf = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = elmc_list_nil();
        } else if (!sep || sep->tag != ELMC_TAG_STRING || !sep->payload) {
          ElmcValue *nil = elmc_list_nil();
          rc = elmc_list_cons(out, s, nil);
          elmc_release(nil);
          CHECK_RC(rc);
        } else {
          const char *str = (const char *)s->payload;
          const char *sp = (const char *)sep->payload;
          size_t splen = strlen(sp);
          if (splen == 0) {
            size_t slen = strlen(str);
            for (size_t i = 0; i < slen; i++) {
              char tmp[2] = { str[i], '\\0' };
              ch = NULL;
              rc = elmc_new_string(&ch, tmp);
              CHECK_RC(rc);
              next = NULL;
              rc = elmc_list_cons(&next, ch, rev);
              CHECK_RC(rc);
              elmc_release(ch);
              ch = NULL;
              elmc_release(rev);
              rev = next;
              next = NULL;
            }
          } else {
            const char *p = str;
            while (1) {
              const char *found = strstr(p, sp);
              if (!found) {
                part = NULL;
                rc = elmc_new_string(&part, p);
                CHECK_RC(rc);
                next = NULL;
                rc = elmc_list_cons(&next, part, rev);
                CHECK_RC(rc);
                elmc_release(part);
                part = NULL;
                elmc_release(rev);
                rev = next;
                next = NULL;
                break;
              }
              size_t chunk = (size_t)(found - p);
              buf = (char *)elmc_malloc(chunk + 1, __func__);
              if (!buf) {
                rc = RC_ERR_OUT_OF_MEMORY;
                CHECK_RC(rc);
              }
              memcpy(buf, p, chunk);
              buf[chunk] = '\\0';
              part = elmc_alloc(ELMC_TAG_STRING, buf);
              buf = NULL;
              if (!part) {
                rc = RC_ERR_OUT_OF_MEMORY;
                CHECK_RC(rc);
              }
              next = NULL;
              rc = elmc_list_cons(&next, part, rev);
              CHECK_RC(rc);
              elmc_release(part);
              part = NULL;
              elmc_release(rev);
              rev = next;
              next = NULL;
              p = found + splen;
            }
          }
          if (rc == RC_SUCCESS) {
            rc = elmc_list_reverse_transfer(out, &rev);
            CHECK_RC(rc);
          }
        }
      CATCH_END;
      if (buf) elmc_free(buf);
      elmc_release(ch);
      elmc_release(part);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_string_join(ElmcValue **out, ElmcValue *sep, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      CATCH_BEGIN
        if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          const char *sp = (sep && sep->tag == ELMC_TAG_STRING && sep->payload) ? (const char *)sep->payload : "";
          size_t splen = strlen(sp);
          size_t total = 0;
          int count = 0;
          ElmcValue *cursor = list;
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            if (node->head && node->head->tag == ELMC_TAG_STRING && node->head->payload) {
              total += strlen((const char *)node->head->payload);
            }
            count++;
            cursor = node->tail;
          }
          if (count > 1) total += splen * (size_t)(count - 1);
          buf = (char *)elmc_malloc(total + 1, __func__);
          if (!buf) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          size_t pos = 0;
          int idx = 0;
          cursor = list;
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            if (idx > 0 && splen > 0) {
              memcpy(buf + pos, sp, splen);
              pos += splen;
            }
            if (node->head && node->head->tag == ELMC_TAG_STRING && node->head->payload) {
              size_t slen = strlen((const char *)node->head->payload);
              memcpy(buf + pos, (const char *)node->head->payload, slen);
              pos += slen;
            }
            idx++;
            cursor = node->tail;
          }
          buf[pos] = '\\0';
          ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
          buf = NULL;
          if (!allocated) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          *out = allocated;
        }
      CATCH_END;
      if (buf) elmc_free(buf);
      return rc;
    }

    ElmcValue *elmc_string_words(ElmcValue *s) {
      ElmcValue *space = NULL;
      if (elmc_new_string(&space, " ") != RC_SUCCESS) space = NULL;
      ElmcValue *out = elmc_string_split_take(space, s);
      elmc_release(space);
      return out;
    }

    ElmcValue *elmc_string_lines(ElmcValue *s) {
      ElmcValue *nl = NULL;
      if (elmc_new_string(&nl, "\\n") != RC_SUCCESS) nl = NULL;
      ElmcValue *out = elmc_string_split_take(nl, s);
      elmc_release(nl);
      return out;
    }

    RC elmc_string_slice(ElmcValue **out, ElmcValue *start, ElmcValue *end_idx, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          const char *src = (const char *)s->payload;
          int64_t cp_len = (int64_t)elmc_utf8_codepoint_count(src);
          int64_t st = elmc_as_int(start);
          int64_t en = elmc_as_int(end_idx);
          if (st < 0) st = cp_len + st;
          if (en < 0) en = cp_len + en;
          if (st < 0) st = 0;
          if (en < 0) en = 0;
          if (st > cp_len) st = cp_len;
          if (en > cp_len) en = cp_len;
          if (en <= st) {
            *out = &ELMC_EMPTY_STRING;
          } else {
            const char *byte_start = elmc_utf8_byte_offset_at_codepoint(src, st);
            const char *byte_end = elmc_utf8_byte_offset_at_codepoint(src, en);
            size_t new_len = (size_t)(byte_end - byte_start);
            buf = (char *)elmc_malloc(new_len + 1, __func__);
            if (!buf) {
              rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(rc);
            }
            memcpy(buf, byte_start, new_len);
            buf[new_len] = '\\0';
            ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
            buf = NULL;
            if (!allocated) {
              rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(rc);
            }
            *out = allocated;
          }
        }
      CATCH_END;
      if (buf) elmc_free(buf);
      return rc;
    }

    ElmcValue *elmc_string_left(ElmcValue *n, ElmcValue *s) {
      ElmcValue *zero = elmc_int_zero();
      ElmcValue *out = elmc_string_slice_take(zero, n, s);
      elmc_release(zero);
      return out;
    }

    ElmcValue *elmc_string_right(ElmcValue *n, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      int64_t len = (int64_t)elmc_utf8_codepoint_count((const char *)s->payload);
      int64_t count = elmc_as_int(n);
      int64_t st = len - count;
      if (st < 0) st = 0;
      ElmcValue *start_v = NULL;
      if (elmc_new_int(&start_v, st) != RC_SUCCESS) start_v = NULL;
      ElmcValue *end_v = NULL;
      if (elmc_new_int(&end_v, len) != RC_SUCCESS) end_v = NULL;
      ElmcValue *out = elmc_string_slice_take(start_v, end_v, s);
      elmc_release(start_v);
      elmc_release(end_v);
      return out;
    }

    ElmcValue *elmc_string_drop_left(ElmcValue *n, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      int64_t len = (int64_t)elmc_utf8_codepoint_count((const char *)s->payload);
      ElmcValue *end_v = NULL;
      if (elmc_new_int(&end_v, len) != RC_SUCCESS) end_v = NULL;
      ElmcValue *out = elmc_string_slice_take(n, end_v, s);
      elmc_release(end_v);
      return out;
    }

    ElmcValue *elmc_string_drop_right(ElmcValue *n, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      int64_t len = (int64_t)elmc_utf8_codepoint_count((const char *)s->payload);
      int64_t count = elmc_as_int(n);
      int64_t en = len - count;
      if (en < 0) en = 0;
      ElmcValue *zero = elmc_int_zero();
      ElmcValue *end_v = NULL;
      if (elmc_new_int(&end_v, en) != RC_SUCCESS) end_v = NULL;
      ElmcValue *out = elmc_string_slice_take(zero, end_v, s);
      elmc_release(zero);
      elmc_release(end_v);
      return out;
    }

    ElmcValue *elmc_string_cons(ElmcValue *ch, ElmcValue *s) {
      char utf8[8];
      int n = elmc_utf8_encode_codepoint((uint32_t)elmc_as_int(ch), utf8, sizeof(utf8));
      if (n <= 0) return elmc_retain(s);
      char prefix[8];
      memcpy(prefix, utf8, (size_t)n);
      prefix[n] = '\\0';
      ElmcValue *prefix_v = NULL;
      if (elmc_new_string(&prefix_v, prefix) != RC_SUCCESS) prefix_v = NULL;
      ElmcValue *out = elmc_string_append_take(prefix_v, s);
      elmc_release(prefix_v);
      return out;
    }

    RC elmc_string_uncons(ElmcValue **out, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      ElmcValue *ch = NULL;
      ElmcValue *rest = NULL;
      ElmcValue *pair = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = elmc_maybe_nothing();
        } else {
          const char *str = (const char *)s->payload;
          if (strlen(str) == 0) {
            *out = elmc_maybe_nothing();
          } else {
            const unsigned char *p = (const unsigned char *)str;
            const unsigned char *end = p + strlen(str);
            uint32_t cp;
            if (!elmc_utf8_decode_codepoint(&p, end, &cp)) {
              *out = elmc_maybe_nothing();
            } else {
              rc = elmc_rc_assign_new_char(&ch, (elmc_int_t)cp);
              CHECK_RC(rc);
              rc = elmc_new_string(&rest, (const char *)p);
              CHECK_RC(rc);
              rc = elmc_tuple2(&pair, ch, rest);
              CHECK_RC(rc);
              rc = elmc_maybe_just(out, pair);
              CHECK_RC(rc);
            }
          }
        }
      CATCH_END;
      elmc_release(ch);
      elmc_release(rest);
      elmc_release(pair);
      return rc;
    }

    RC elmc_string_to_list(ElmcValue **out, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *ch = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = elmc_list_nil();
        } else {
          const char *str = (const char *)s->payload;
          const unsigned char *p = (const unsigned char *)str;
          const unsigned char *end = p + strlen(str);
          while (p < end) {
            uint32_t cp;
            if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
            ch = elmc_new_char((elmc_int_t)cp);
            if (!ch) {
              rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(rc);
            }
            next = NULL;
            rc = elmc_list_cons(&next, ch, rev);
            CHECK_RC(rc);
            elmc_release(ch);
            ch = NULL;
            elmc_release(rev);
            rev = next;
            next = NULL;
          }
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
          rev = NULL;
        }
      CATCH_END;
      elmc_release(ch);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_string_from_list(ElmcValue **out, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      CATCH_BEGIN
        int64_t idx = 0;
        size_t cap = 16;
        ElmcValue *cursor = list;
        buf = (char *)elmc_malloc(cap, __func__);
        if (!buf) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          char utf8[8];
          int n = elmc_utf8_encode_codepoint((uint32_t)elmc_as_int(node->head), utf8, sizeof(utf8));
          if (n <= 0) {
            rc = RC_ERR_INVALID_ARG;
            CHECK_RC(rc);
          }
          if ((size_t)idx + (size_t)n + 1 > cap) {
            cap = ((size_t)idx + (size_t)n + 1) * 2;
            char *grown = (char *)elmc_malloc(cap, __func__);
            if (!grown) {
              rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(rc);
            }
            memcpy(grown, buf, (size_t)idx);
            elmc_free(buf);
            buf = grown;
          }
          memcpy(buf + idx, utf8, (size_t)n);
          idx += (int64_t)n;
          cursor = node->tail;
        }
        buf[idx] = '\\0';
        ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
        buf = NULL;
        if (!allocated) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        *out = allocated;
      CATCH_END;
      if (buf) elmc_free(buf);
      return rc;
    }

    RC elmc_string_from_char(ElmcValue **out, ElmcValue *ch) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        char buf[1] = { (char)elmc_as_int(ch) };
        rc = elmc_new_string_len(out, buf, 1);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }

    ElmcValue *elmc_string_pad(ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
      return elmc_string_pad_left_take(n, ch, s);
    }

    RC elmc_string_pad_left(ElmcValue **out, ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          const char *src = (const char *)s->payload;
          int64_t target = elmc_as_int(n);
          int64_t cur_len = (int64_t)strlen(src);
          if (cur_len >= target) {
            *out = elmc_retain(s);
          } else {
            int64_t pad_count = target - cur_len;
            char pad_char = (char)elmc_as_int(ch);
            buf = (char *)elmc_malloc((size_t)target + 1, __func__);
            if (!buf) {
              rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(rc);
            }
            for (int64_t i = 0; i < pad_count; i++) buf[i] = pad_char;
            memcpy(buf + pad_count, src, (size_t)cur_len);
            buf[target] = '\\0';
            ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
            buf = NULL;
            if (!allocated) {
              rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(rc);
            }
            *out = allocated;
          }
        }
      CATCH_END;
      if (buf) elmc_free(buf);
      return rc;
    }

    RC elmc_string_pad_right(ElmcValue **out, ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          const char *src = (const char *)s->payload;
          int64_t target = elmc_as_int(n);
          int64_t cur_len = (int64_t)strlen(src);
          if (cur_len >= target) {
            *out = elmc_retain(s);
          } else {
            int64_t pad_count = target - cur_len;
            char pad_char = (char)elmc_as_int(ch);
            buf = (char *)elmc_malloc((size_t)target + 1, __func__);
            if (!buf) {
              rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(rc);
            }
            memcpy(buf, src, (size_t)cur_len);
            for (int64_t i = 0; i < pad_count; i++) buf[cur_len + i] = pad_char;
            buf[target] = '\\0';
            ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
            buf = NULL;
            if (!allocated) {
              rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(rc);
            }
            *out = allocated;
          }
        }
      CATCH_END;
      if (buf) elmc_free(buf);
      return rc;
    }

    RC elmc_string_map(ElmcValue **out, ElmcValue *f, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      ElmcValue *ch = NULL;
      ElmcValue *mapped = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          const char *src = (const char *)s->payload;
          size_t byte_len = strlen(src);
          size_t cap = byte_len + 1;
          buf = (char *)elmc_malloc(cap, __func__);
          if (!buf) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          size_t out_len = 0;
          const unsigned char *p = (const unsigned char *)src;
          const unsigned char *end = p + byte_len;
          while (p < end) {
            uint32_t cp;
            if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
            ch = NULL;
            rc = elmc_rc_assign_new_char(&ch, (elmc_int_t)cp);
            CHECK_RC(rc);
            ElmcValue *args[1] = { ch };
            mapped = NULL;
            rc = elmc_closure_call_rc(&mapped, f, args, 1);
            CHECK_RC(rc);
            char utf8[8];
            int n = elmc_utf8_encode_codepoint((uint32_t)elmc_as_int(mapped), utf8, sizeof(utf8));
            if (n <= 0) {
              rc = RC_ERR_INVALID_ARG;
              CHECK_RC(rc);
            }
            if (out_len + (size_t)n + 1 > cap) {
              cap = (out_len + (size_t)n + 1) * 2;
              char *grown = (char *)elmc_malloc(cap, __func__);
              if (!grown) {
                rc = RC_ERR_OUT_OF_MEMORY;
                CHECK_RC(rc);
              }
              memcpy(grown, buf, out_len);
              elmc_free(buf);
              buf = grown;
            }
            memcpy(buf + out_len, utf8, (size_t)n);
            out_len += (size_t)n;
            elmc_release(ch);
            ch = NULL;
            elmc_release(mapped);
            mapped = NULL;
          }
          buf[out_len] = '\\0';
          ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
          buf = NULL;
          if (!allocated) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          *out = allocated;
        }
      CATCH_END;
      elmc_release(ch);
      elmc_release(mapped);
      if (buf) elmc_free(buf);
      return rc;
    }

    RC elmc_string_filter(ElmcValue **out, ElmcValue *f, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      char *buf = NULL;
      ElmcValue *ch = NULL;
      ElmcValue *keep = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = &ELMC_EMPTY_STRING;
        } else {
          const char *src = (const char *)s->payload;
          size_t byte_len = strlen(src);
          buf = (char *)elmc_malloc(byte_len + 1, __func__);
          if (!buf) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          size_t out_len = 0;
          const unsigned char *p = (const unsigned char *)src;
          const unsigned char *end = p + byte_len;
          while (p < end) {
            const unsigned char *cp_start = p;
            uint32_t cp;
            if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
            ch = NULL;
            rc = elmc_rc_assign_new_char(&ch, (elmc_int_t)cp);
            CHECK_RC(rc);
            ElmcValue *args[1] = { ch };
            keep = NULL;
            rc = elmc_closure_call_rc(&keep, f, args, 1);
            CHECK_RC(rc);
            if (elmc_as_int(keep)) {
              size_t cp_bytes = (size_t)(p - cp_start);
              memcpy(buf + out_len, cp_start, cp_bytes);
              out_len += cp_bytes;
            }
            elmc_release(ch);
            ch = NULL;
            elmc_release(keep);
            keep = NULL;
          }
          buf[out_len] = '\\0';
          ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
          buf = NULL;
          if (!allocated) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          *out = allocated;
        }
      CATCH_END;
      elmc_release(ch);
      elmc_release(keep);
      if (buf) elmc_free(buf);
      return rc;
    }

    RC elmc_string_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      ElmcValue *result = elmc_retain(acc);
      ElmcValue *ch = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = result;
          result = NULL;
        } else {
          const char *src = (const char *)s->payload;
          const unsigned char *p = (const unsigned char *)src;
          const unsigned char *end = p + strlen(src);
          while (p < end) {
            uint32_t cp;
            if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
            ch = NULL;
            rc = elmc_rc_assign_new_char(&ch, (elmc_int_t)cp);
            CHECK_RC(rc);
            ElmcValue *args[2] = { ch, result };
            next = NULL;
            rc = elmc_closure_call_rc(&next, f, args, 2);
            CHECK_RC(rc);
            elmc_release(ch);
            ch = NULL;
            elmc_release(result);
            result = next;
            next = NULL;
          }
          *out = result;
          result = NULL;
        }
      CATCH_END;
      elmc_release(ch);
      elmc_release(next);
      elmc_release(result);
      return rc;
    }

    RC elmc_string_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      ElmcValue *result = elmc_retain(acc);
      ElmcValue *ch = NULL;
      ElmcValue *next = NULL;
      uint32_t *cps = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          *out = result;
          result = NULL;
        } else {
          const char *src = (const char *)s->payload;
          size_t cp_count = elmc_utf8_codepoint_count(src);
          if (cp_count > 0) {
            cps = (uint32_t *)elmc_malloc(cp_count * sizeof(uint32_t), __func__);
            if (!cps) {
              rc = RC_ERR_OUT_OF_MEMORY;
              CHECK_RC(rc);
            }
            const unsigned char *p = (const unsigned char *)src;
            const unsigned char *end = p + strlen(src);
            for (size_t i = 0; i < cp_count; i++) {
              if (!elmc_utf8_decode_codepoint(&p, end, &cps[i])) break;
            }
            for (size_t i = cp_count; i > 0; i--) {
              ch = NULL;
              rc = elmc_rc_assign_new_char(&ch, (elmc_int_t)cps[i - 1]);
              CHECK_RC(rc);
              ElmcValue *args[2] = { ch, result };
              next = NULL;
              rc = elmc_closure_call_rc(&next, f, args, 2);
              CHECK_RC(rc);
              elmc_release(ch);
              ch = NULL;
              elmc_release(result);
              result = next;
              next = NULL;
            }
          }
          *out = result;
          result = NULL;
        }
      CATCH_END;
      if (cps) elmc_free(cps);
      elmc_release(ch);
      elmc_release(next);
      elmc_release(result);
      return rc;
    }

    RC elmc_string_any(ElmcValue **out, ElmcValue *f, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      int answer = 0;
      int done = 0;
      ElmcValue *ch = NULL;
      ElmcValue *result = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          answer = 0;
        } else {
          const char *src = (const char *)s->payload;
          const unsigned char *p = (const unsigned char *)src;
          const unsigned char *end = p + strlen(src);
          while (!done && p < end) {
            uint32_t cp;
            if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
            ch = NULL;
            rc = elmc_rc_assign_new_char(&ch, (elmc_int_t)cp);
            CHECK_RC(rc);
            ElmcValue *args[1] = { ch };
            result = NULL;
            rc = elmc_closure_call_rc(&result, f, args, 1);
            CHECK_RC(rc);
            int truthy = elmc_as_int(result) != 0;
            elmc_release(ch);
            ch = NULL;
            elmc_release(result);
            result = NULL;
            if (truthy) {
              answer = 1;
              done = 1;
            }
          }
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_new_bool(out, answer);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(ch);
      elmc_release(result);
      return rc;
    }

    RC elmc_string_all(ElmcValue **out, ElmcValue *f, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      int answer = 1;
      int done = 0;
      ElmcValue *ch = NULL;
      ElmcValue *result = NULL;
      CATCH_BEGIN
        if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
          answer = 1;
        } else {
          const char *src = (const char *)s->payload;
          const unsigned char *p = (const unsigned char *)src;
          const unsigned char *end = p + strlen(src);
          while (!done && p < end) {
            uint32_t cp;
            if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
            ch = NULL;
            rc = elmc_rc_assign_new_char(&ch, (elmc_int_t)cp);
            CHECK_RC(rc);
            ElmcValue *args[1] = { ch };
            result = NULL;
            rc = elmc_closure_call_rc(&result, f, args, 1);
            CHECK_RC(rc);
            int truthy = elmc_as_int(result) != 0;
            elmc_release(ch);
            ch = NULL;
            elmc_release(result);
            result = NULL;
            if (!truthy) {
              answer = 0;
              done = 1;
            }
          }
        }
        if (rc == RC_SUCCESS) {
          rc = elmc_new_bool(out, answer);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(ch);
      elmc_release(result);
      return rc;
    }

    RC elmc_string_indexes(ElmcValue **out, ElmcValue *sub, ElmcValue *s) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *idx = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        if (!sub || sub->tag != ELMC_TAG_STRING || !s || s->tag != ELMC_TAG_STRING) {
          *out = elmc_list_nil();
        } else {
          const char *haystack = (const char *)s->payload;
          const char *needle = (const char *)sub->payload;
          if (!haystack || !needle) {
            *out = elmc_list_nil();
          } else {
            size_t nlen = strlen(needle);
            if (nlen == 0) {
              *out = elmc_list_nil();
            } else {
              const char *p = haystack;
              while ((p = strstr(p, needle)) != NULL) {
                idx = NULL;
                rc = elmc_new_int(&idx, (int64_t)(p - haystack));
                CHECK_RC(rc);
                next = NULL;
                rc = elmc_list_cons(&next, idx, rev);
                CHECK_RC(rc);
                elmc_release(idx);
                idx = NULL;
                elmc_release(rev);
                rev = next;
                next = NULL;
                p += 1;
              }
              rc = elmc_list_reverse_transfer(out, &rev);
              CHECK_RC(rc);
            }
          }
        }
      CATCH_END;
      elmc_release(idx);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    /* ================================================================
       Standard Library – Tuple operations (extended)
       ================================================================ */

    RC elmc_tuple_map_first(ElmcValue **out, ElmcValue *f, ElmcValue *t) {
      RC rc = RC_SUCCESS;
      ElmcValue *mapped = NULL;
      CATCH_BEGIN
        if (!t || t->tag != ELMC_TAG_TUPLE2 || !t->payload) {
          *out = elmc_retain(t);
        } else {
          ElmcTuple2 *tuple = (ElmcTuple2 *)t->payload;
          ElmcValue *args[1] = { tuple->first };
          rc = elmc_closure_call_rc(&mapped, f, args, 1);
          CHECK_RC(rc);
          rc = elmc_tuple2(out, mapped, tuple->second);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(mapped);
      return rc;
    }

    RC elmc_tuple_map_second(ElmcValue **out, ElmcValue *f, ElmcValue *t) {
      RC rc = RC_SUCCESS;
      ElmcValue *mapped = NULL;
      CATCH_BEGIN
        if (!t || t->tag != ELMC_TAG_TUPLE2 || !t->payload) {
          *out = elmc_retain(t);
        } else {
          ElmcTuple2 *tuple = (ElmcTuple2 *)t->payload;
          ElmcValue *args[1] = { tuple->second };
          rc = elmc_closure_call_rc(&mapped, f, args, 1);
          CHECK_RC(rc);
          rc = elmc_tuple2(out, tuple->first, mapped);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(mapped);
      return rc;
    }

    RC elmc_tuple_map_both(ElmcValue **out, ElmcValue *f, ElmcValue *g, ElmcValue *t) {
      RC rc = RC_SUCCESS;
      ElmcValue *mf = NULL;
      ElmcValue *mg = NULL;
      CATCH_BEGIN
        if (!t || t->tag != ELMC_TAG_TUPLE2 || !t->payload) {
          *out = elmc_retain(t);
        } else {
          ElmcTuple2 *tuple = (ElmcTuple2 *)t->payload;
          ElmcValue *args_f[1] = { tuple->first };
          ElmcValue *args_g[1] = { tuple->second };
          rc = elmc_closure_call_rc(&mf, f, args_f, 1);
          CHECK_RC(rc);
          rc = elmc_closure_call_rc(&mg, g, args_g, 1);
          CHECK_RC(rc);
          rc = elmc_tuple2(out, mf, mg);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(mf);
      elmc_release(mg);
      return rc;
    }

    /* ================================================================
       Standard Library – Basics (extended)
       ================================================================ */

    ElmcValue *elmc_basics_not(ElmcValue *x) {
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, elmc_as_int(x) == 0 ? 1 : 0);
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_basics_negate(ElmcValue *x) {
      if (x && x->tag == ELMC_TAG_FLOAT) {
        return elmc_new_float_take(-elmc_as_float(x));
      }
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, -elmc_as_int(x)) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_basics_abs(ElmcValue *x) {
      if (x && x->tag == ELMC_TAG_FLOAT) {
        double v = elmc_as_float(x);
        return elmc_new_float_take(v < 0 ? -v : v);
      }
      int64_t v = elmc_as_int(x);
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, v < 0 ? -v : v) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_basics_to_float(ElmcValue *x) {
      return elmc_new_float_take((double)elmc_as_int(x));
    }

    static double elmc_basics_nan(void) {
      volatile double zero = 0.0;
      return zero / zero;
    }

    static double elmc_basics_inf(void) {
      volatile double zero = 0.0;
      return 1.0 / zero;
    }

    ElmcValue *elmc_basics_sqrt(ElmcValue *x) {
      double v = elmc_as_float(x);
      if (v < 0.0) return elmc_new_float_take(elmc_basics_nan());
      if (v == 0.0) return elmc_new_float_take(0.0);

      double guess = v >= 1.0 ? v : 1.0;
      for (int i = 0; i < 24; i++) {
        guess = 0.5 * (guess + v / guess);
      }
      return elmc_new_float_take(guess);
    }

    double elmc_basics_sqrt_double(double x) {
      ElmcValue stack = { .rc = 1, .tag = ELMC_TAG_FLOAT, .payload = &x };
      ElmcValue *out = elmc_basics_sqrt(&stack);
      double result = elmc_as_float(out);
      elmc_release(out);
      return result;
    }

    static double elmc_basics_log_double(double x) {
      const double e = 2.71828182845904523536;
      if (x < 0.0) return elmc_basics_nan();
      if (x == 0.0) return -elmc_basics_inf();

      int k = 0;
      while (x > e) {
        x /= e;
        k++;
      }
      while (x < 1.0 / e) {
        x *= e;
        k--;
      }

      double z = (x - 1.0) / (x + 1.0);
      double z2 = z * z;
      double term = z;
      double sum = 0.0;
      for (int n = 1; n <= 35; n += 2) {
        sum += term / (double)n;
        term *= z2;
      }
      return 2.0 * sum + (double)k;
    }

    ElmcValue *elmc_basics_log_base(ElmcValue *base, ElmcValue *x) {
      double denominator = elmc_basics_log_double(elmc_as_float(base));
      return elmc_new_float_take(elmc_basics_log_double(elmc_as_float(x)) / denominator);
    }

    #ifdef ELMC_PEBBLE_PLATFORM
    static double elmc_basics_normalize_radians(double x) {
      const double pi = 3.14159265358979323846;
      const double two_pi = 6.28318530717958647692;
      while (x > pi) x -= two_pi;
      while (x < -pi) x += two_pi;
      return x;
    }
    #endif

    double elmc_basics_sin_double(double x) {
      #ifndef ELMC_PEBBLE_PLATFORM
      return sin(x);
      #else
      const double pi = 3.14159265358979323846;
      const double half_pi = 1.57079632679489661923;
      x = elmc_basics_normalize_radians(x);
      if (x > half_pi) x = pi - x;
      if (x < -half_pi) x = -pi - x;
      double x2 = x * x;
      return x * (1.0
          - x2 / 6.0
          + (x2 * x2) / 120.0
          - (x2 * x2 * x2) / 5040.0
          + (x2 * x2 * x2 * x2) / 362880.0);
      #endif
    }

    ElmcValue *elmc_basics_sin(ElmcValue *x) {
      return elmc_new_float_take(elmc_basics_sin_double(elmc_as_float(x)));
    }

    double elmc_basics_cos_double(double x) {
      #ifndef ELMC_PEBBLE_PLATFORM
      return cos(x);
      #else
      const double half_pi = 1.57079632679489661923;
      return elmc_basics_sin_double(x + half_pi);
      #endif
    }

    ElmcValue *elmc_basics_cos(ElmcValue *x) {
      return elmc_new_float_take(elmc_basics_cos_double(elmc_as_float(x)));
    }

    double elmc_basics_tan_double(double x) {
      return elmc_basics_sin_double(x) / elmc_basics_cos_double(x);
    }

    ElmcValue *elmc_basics_tan(ElmcValue *x) {
      return elmc_new_float_take(elmc_basics_tan_double(elmc_as_float(x)));
    }

    static double elmc_basics_atan_double(double x) {
      #ifndef ELMC_PEBBLE_PLATFORM
      return atan(x);
      #else
      const double half_pi = 1.57079632679489661923;
      int negative = x < 0.0;
      if (negative) x = -x;

      int invert = x > 1.0;
      if (invert) x = 1.0 / x;

      double x2 = x * x;
      double term = x;
      double sum = 0.0;
      double sign = 1.0;
      for (int n = 1; n <= 31; n += 2) {
        sum += sign * term / (double)n;
        term *= x2;
        sign = -sign;
      }

      if (invert) sum = half_pi - sum;
      return negative ? -sum : sum;
      #endif
    }

    ElmcValue *elmc_basics_atan(ElmcValue *x) {
      return elmc_new_float_take(elmc_basics_atan_double(elmc_as_float(x)));
    }

    ElmcValue *elmc_basics_atan2(ElmcValue *y, ElmcValue *x) {
      #ifndef ELMC_PEBBLE_PLATFORM
      return elmc_new_float_take(atan2(elmc_as_float(y), elmc_as_float(x)));
      #else
      const double pi = 3.14159265358979323846;
      const double half_pi = 1.57079632679489661923;
      double yy = elmc_as_float(y);
      double xx = elmc_as_float(x);

      if (xx > 0.0) return elmc_new_float_take(elmc_basics_atan_double(yy / xx));
      if (xx < 0.0 && yy >= 0.0) return elmc_new_float_take(elmc_basics_atan_double(yy / xx) + pi);
      if (xx < 0.0 && yy < 0.0) return elmc_new_float_take(elmc_basics_atan_double(yy / xx) - pi);
      if (xx == 0.0 && yy > 0.0) return elmc_new_float_take(half_pi);
      if (xx == 0.0 && yy < 0.0) return elmc_new_float_take(-half_pi);
      return elmc_new_float_take(0.0);
      #endif
    }

    ElmcValue *elmc_basics_asin(ElmcValue *x) {
      double v = elmc_as_float(x);
      if (v < -1.0 || v > 1.0) return elmc_new_float_take(elmc_basics_nan());
      double denom = elmc_basics_sqrt_double(1.0 - v * v);
      return elmc_new_float_take(elmc_basics_atan_double(v / denom));
    }

    ElmcValue *elmc_basics_acos(ElmcValue *x) {
      const double half_pi = 1.57079632679489661923;
      ElmcValue *asin_value = elmc_basics_asin(x);
      double out = half_pi - elmc_as_float(asin_value);
      elmc_release(asin_value);
      return elmc_new_float_take(out);
    }

    ElmcValue *elmc_basics_degrees(ElmcValue *x) {
      return elmc_new_float_take(elmc_as_float(x) * 0.01745329251994329577);
    }

    ElmcValue *elmc_basics_radians(ElmcValue *x) {
      return elmc_new_float_take(elmc_as_float(x));
    }

    ElmcValue *elmc_basics_turns(ElmcValue *x) {
      return elmc_new_float_take(elmc_as_float(x) * 6.28318530717958647692);
    }

    ElmcValue *elmc_basics_from_polar(ElmcValue *polar) {
      if (!polar || polar->tag != ELMC_TAG_TUPLE2 || !polar->payload) {
        ElmcValue *x0 = elmc_new_float_take(0.0);
        ElmcValue *y0 = elmc_new_float_take(0.0);
        ElmcValue *out0 = NULL;
        if (elmc_tuple2(&out0, x0, y0) != RC_SUCCESS) out0 = NULL;
        elmc_release(x0);
        elmc_release(y0);
        return out0;
      }
      ElmcTuple2 *pair = (ElmcTuple2 *)polar->payload;
      double radius = elmc_as_float(pair->first);
      double theta = elmc_as_float(pair->second);
      ElmcValue *x = elmc_new_float_take(radius * elmc_basics_sin_double(theta + 1.57079632679489661923));
      ElmcValue *y = elmc_new_float_take(radius * elmc_basics_sin_double(theta));
      ElmcValue *out = NULL;
      if (elmc_tuple2(&out, x, y) != RC_SUCCESS) out = NULL;
      elmc_release(x);
      elmc_release(y);
      return out;
    }

    ElmcValue *elmc_basics_to_polar(ElmcValue *point) {
      if (!point || point->tag != ELMC_TAG_TUPLE2 || !point->payload) {
        ElmcValue *r0 = elmc_new_float_take(0.0);
        ElmcValue *t0 = elmc_new_float_take(0.0);
        ElmcValue *out0 = NULL;
        if (elmc_tuple2(&out0, r0, t0) != RC_SUCCESS) out0 = NULL;
        elmc_release(r0);
        elmc_release(t0);
        return out0;
      }
      ElmcTuple2 *pair = (ElmcTuple2 *)point->payload;
      double x = elmc_as_float(pair->first);
      double y = elmc_as_float(pair->second);
      ElmcValue *radius = elmc_new_float_take(elmc_basics_sqrt_double(x * x + y * y));
      ElmcValue *theta = elmc_new_float_take(elmc_basics_atan_double(y / x));
      if (x < 0.0) {
        double adjusted = elmc_as_float(theta) + (y >= 0.0 ? 3.14159265358979323846 : -3.14159265358979323846);
        elmc_release(theta);
        theta = elmc_new_float_take(adjusted);
      } else if (x == 0.0) {
        elmc_release(theta);
        theta = elmc_new_float_take(y > 0.0 ? 1.57079632679489661923 : (y < 0.0 ? -1.57079632679489661923 : 0.0));
      }
      ElmcValue *out = NULL;
      if (elmc_tuple2(&out, radius, theta) != RC_SUCCESS) out = NULL;
      elmc_release(radius);
      elmc_release(theta);
      return out;
    }

    ElmcValue *elmc_basics_is_nan(ElmcValue *x) {
      double v = elmc_as_float(x);
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, v != v);
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_basics_is_infinite(ElmcValue *x) {
      double v = elmc_as_float(x);
      double delta = v - v;
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, (v == v && delta != delta) ? 1 : 0);
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_basics_round(ElmcValue *x) {
      double v = elmc_as_float(x);
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, (int64_t)(v + (v >= 0 ? 0.5 : -0.5))) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_basics_floor(ElmcValue *x) {
      double v = elmc_as_float(x);
      int64_t i = (int64_t)v;
      if ((double)i > v) i--;
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, i) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_basics_ceiling(ElmcValue *x) {
      double v = elmc_as_float(x);
      int64_t i = (int64_t)v;
      if ((double)i < v) i++;
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, i) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_basics_truncate(ElmcValue *x) {
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, (int64_t)elmc_as_float(x)) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_basics_remainder_by(ElmcValue *base, ElmcValue *value) {
      elmc_int_t b = elmc_as_int(base);
      elmc_int_t v = elmc_as_int(value);
      if (b == 0) return elmc_int_zero();
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, v % b) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_basics_pow(ElmcValue *base, ElmcValue *exponent) {
      int64_t exp = elmc_as_int(exponent);
      int negative = exp < 0;
      uint64_t count = (uint64_t)(negative ? -exp : exp);
      double result = 1.0;

      if (base && base->tag == ELMC_TAG_FLOAT) {
        double b = elmc_as_float(base);
        for (uint64_t i = 0; i < count; i++) result *= b;
        if (negative) result = (result == 0.0) ? 0.0 : (1.0 / result);
        return elmc_new_float_take(result);
      }

      int64_t b = elmc_as_int(base);
      for (uint64_t i = 0; i < count; i++) result *= (double)b;
      if (negative) {
        result = (result == 0.0) ? 0.0 : (1.0 / result);
        return elmc_new_float_take(result);
      }
      {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_int(&_elmc_rc_out, (int64_t)result) != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_basics_xor(ElmcValue *a, ElmcValue *b) {
      int ba = elmc_as_int(a) != 0;
      int bb = elmc_as_int(b) != 0;
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, ba != bb ? 1 : 0);
          return _elmc_rc_out;
      }
    }

    RC elmc_basics_compare(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        /* Returns LT (-1), EQ (0), or GT (1) as ORDER-tagged values */
        if (a && b && (a->tag == ELMC_TAG_FLOAT || b->tag == ELMC_TAG_FLOAT)) {
          double fa = elmc_as_float(a);
          double fb = elmc_as_float(b);
          if (fa < fb) {
            rc = elmc_new_order(out, -1);
            CHECK_RC(rc);
          } else if (fa > fb) {
            rc = elmc_new_order(out, 1);
            CHECK_RC(rc);
          } else {
            rc = elmc_new_order(out, 0);
            CHECK_RC(rc);
          }
        } else if (a && b && a->tag == ELMC_TAG_STRING && b->tag == ELMC_TAG_STRING) {
          const char *sa = (const char *)a->payload;
          const char *sb = (const char *)b->payload;
          int cmp = strcmp(sa ? sa : "", sb ? sb : "");
          if (cmp < 0) {
            rc = elmc_new_order(out, -1);
            CHECK_RC(rc);
          } else if (cmp > 0) {
            rc = elmc_new_order(out, 1);
            CHECK_RC(rc);
          } else {
            rc = elmc_new_order(out, 0);
            CHECK_RC(rc);
          }
        } else if (a && b && a->tag == ELMC_TAG_CHAR && b->tag == ELMC_TAG_CHAR) {
          elmc_int_t ia = elmc_as_int(a);
          elmc_int_t ib = elmc_as_int(b);
          if (ia < ib) {
            rc = elmc_new_order(out, -1);
            CHECK_RC(rc);
          } else if (ia > ib) {
            rc = elmc_new_order(out, 1);
            CHECK_RC(rc);
          } else {
            rc = elmc_new_order(out, 0);
            CHECK_RC(rc);
          }
        } else {
          elmc_int_t ia = elmc_as_int(a);
          elmc_int_t ib = elmc_as_int(b);
          if (ia < ib) {
            rc = elmc_new_order(out, -1);
            CHECK_RC(rc);
          } else if (ia > ib) {
            rc = elmc_new_order(out, 1);
            CHECK_RC(rc);
          } else {
            rc = elmc_new_order(out, 0);
            CHECK_RC(rc);
          }
        }
      CATCH_END
      return rc;
    }

    /* ================================================================
       Standard Library – Char (extended)
       ================================================================ */

    ElmcValue *elmc_char_is_upper(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, c >= 'A' && c <= 'Z');
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_char_is_lower(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, c >= 'a' && c <= 'z');
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_char_is_alpha(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'));
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_char_is_alpha_num(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'));
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_char_is_digit(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, c >= '0' && c <= '9');
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_char_is_oct_digit(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, c >= '0' && c <= '7');
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_char_is_hex_digit(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f'));
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_char_to_upper(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      if (c >= 'a' && c <= 'z') c -= 32;
      return elmc_new_char(c);
    }

    ElmcValue *elmc_char_to_lower(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      if (c >= 'A' && c <= 'Z') c += 32;
      return elmc_new_char(c);
    }

    /* ================================================================
       Standard Library – Dict (extended)
       ================================================================ */

    RC elmc_dict_remove(ElmcValue **out, ElmcValue *key, ElmcValue *dict) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = dict;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          int skip = 0;
          if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
            if (pair->first && elmc_dict_keys_equal(pair->first, key)) skip = 1;
          }
          if (!skip) {
            next = NULL;
            rc = elmc_list_cons(&next, node->head, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = next;
            next = NULL;
          }
          cursor = node->tail;
        }
        rc = elmc_list_reverse_transfer(out, &rev);
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    ElmcValue *elmc_dict_is_empty(ElmcValue *dict) {
      if (!dict || dict->tag != ELMC_TAG_LIST) {
        ElmcValue *_elmc_rc_out = NULL;
        (void)elmc_new_bool(&_elmc_rc_out, 1);
        return _elmc_rc_out;
      }
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, dict->payload == NULL);
          return _elmc_rc_out;
      }
    }

    RC elmc_dict_keys(ElmcValue **out, ElmcValue *dict) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = dict;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
            next = NULL;
            rc = elmc_list_cons(&next, pair->first, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = next;
            next = NULL;
          }
          cursor = node->tail;
        }
        rc = elmc_list_reverse_transfer(out, &rev);
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_dict_values(ElmcValue **out, ElmcValue *dict) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = dict;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
            next = NULL;
            rc = elmc_list_cons(&next, pair->second, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = next;
            next = NULL;
          }
          cursor = node->tail;
        }
        rc = elmc_list_reverse_transfer(out, &rev);
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    ElmcValue *elmc_dict_to_list(ElmcValue *dict) {
      ElmcValue *out = NULL;
      if (!dict) return elmc_list_nil();
      if (elmc_list_copy(&out, dict) != RC_SUCCESS) return elmc_list_nil();
      return out;
    }

    RC elmc_dict_map(ElmcValue **out, ElmcValue *f, ElmcValue *dict) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *mapped = NULL;
      ElmcValue *new_pair = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = dict;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
            ElmcValue *args[2] = { pair->first, pair->second };
            mapped = NULL;
            rc = elmc_closure_call_rc(&mapped, f, args, 2);
            CHECK_RC(rc);
            new_pair = NULL;
            rc = elmc_tuple2(&new_pair, pair->first, mapped);
            CHECK_RC(rc);
            elmc_release(mapped);
            mapped = NULL;
            next = NULL;
            rc = elmc_list_cons(&next, new_pair, rev);
            CHECK_RC(rc);
            elmc_release(new_pair);
            new_pair = NULL;
            elmc_release(rev);
            rev = next;
            next = NULL;
          }
          cursor = node->tail;
        }
        rc = elmc_list_reverse_transfer(out, &rev);
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(mapped);
      elmc_release(new_pair);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_dict_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *dict) {
      RC rc = RC_SUCCESS;
      ElmcValue *result = elmc_retain(acc);
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = dict;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
            ElmcValue *args[3] = { pair->first, pair->second, result };
            next = NULL;
            rc = elmc_closure_call_rc(&next, f, args, 3);
            CHECK_RC(rc);
            elmc_release(result);
            result = next;
            next = NULL;
          }
          cursor = node->tail;
        }
        *out = result;
        result = NULL;
      CATCH_END;
      elmc_release(next);
      elmc_release(result);
      return rc;
    }

    RC elmc_dict_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *dict) {
      RC rc = RC_SUCCESS;
      ElmcValue *reversed = NULL;
      ElmcValue *result = elmc_retain(acc);
      ElmcValue *next = NULL;
      CATCH_BEGIN
        rc = elmc_list_reverse_into(&reversed, dict);
        CHECK_RC(rc);
        ElmcValue *cursor = reversed;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
            ElmcValue *args[3] = { pair->first, pair->second, result };
            next = NULL;
            rc = elmc_closure_call_rc(&next, f, args, 3);
            CHECK_RC(rc);
            elmc_release(result);
            result = next;
            next = NULL;
          }
          cursor = node->tail;
        }
        *out = result;
        result = NULL;
      CATCH_END;
      elmc_release(reversed);
      elmc_release(next);
      elmc_release(result);
      return rc;
    }

    RC elmc_dict_filter(ElmcValue **out, ElmcValue *f, ElmcValue *dict) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *keep = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = dict;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
            ElmcValue *args[2] = { pair->first, pair->second };
            keep = NULL;
            rc = elmc_closure_call_rc(&keep, f, args, 2);
            CHECK_RC(rc);
            if (elmc_as_int(keep)) {
              next = NULL;
              rc = elmc_list_cons(&next, node->head, rev);
              CHECK_RC(rc);
              elmc_release(rev);
              rev = next;
              next = NULL;
            }
            elmc_release(keep);
            keep = NULL;
          }
          cursor = node->tail;
        }
        rc = elmc_list_reverse_transfer(out, &rev);
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(keep);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_dict_partition(ElmcValue **out, ElmcValue *f, ElmcValue *dict) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev_yes = elmc_list_nil();
      ElmcValue *rev_no = elmc_list_nil();
      ElmcValue *keep = NULL;
      ElmcValue *next = NULL;
      ElmcValue *yes = NULL;
      ElmcValue *no = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = dict;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
            ElmcValue *args[2] = { pair->first, pair->second };
            keep = NULL;
            rc = elmc_closure_call_rc(&keep, f, args, 2);
            CHECK_RC(rc);
            if (elmc_as_int(keep)) {
              next = NULL;
              rc = elmc_list_cons(&next, node->head, rev_yes);
              CHECK_RC(rc);
              elmc_release(rev_yes);
              rev_yes = next;
              next = NULL;
            } else {
              next = NULL;
              rc = elmc_list_cons(&next, node->head, rev_no);
              CHECK_RC(rc);
              elmc_release(rev_no);
              rev_no = next;
              next = NULL;
            }
            elmc_release(keep);
            keep = NULL;
          }
          cursor = node->tail;
        }
        rc = elmc_list_reverse_transfer(&yes, &rev_yes);
        CHECK_RC(rc);
        rc = elmc_list_reverse_transfer(&no, &rev_no);
        CHECK_RC(rc);
        rc = elmc_tuple2(out, yes, no);
        CHECK_RC(rc);
        elmc_release(yes);
        elmc_release(no);
        yes = NULL;
        no = NULL;
      CATCH_END;
      elmc_release(keep);
      elmc_release(next);
      elmc_release(rev_yes);
      elmc_release(rev_no);
      elmc_release(yes);
      elmc_release(no);
      return rc;
    }

    RC elmc_dict_union(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
      RC rc = RC_SUCCESS;
      ElmcValue *result = elmc_retain(b);
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = a;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
            next = NULL;
            rc = elmc_dict_insert(&next, pair->first, pair->second, result);
            CHECK_RC(rc);
            elmc_release(result);
            result = next;
            next = NULL;
          }
          cursor = node->tail;
        }
        *out = result;
        result = NULL;
      CATCH_END;
      elmc_release(next);
      elmc_release(result);
      return rc;
    }

    RC elmc_dict_intersect(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = a;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
            ElmcValue *found = elmc_dict_member(pair->first, b);
            if (elmc_as_int(found)) {
              next = NULL;
              rc = elmc_list_cons(&next, node->head, rev);
              CHECK_RC(rc);
              elmc_release(rev);
              rev = next;
              next = NULL;
            }
            elmc_release(found);
          }
          cursor = node->tail;
        }
        rc = elmc_list_reverse_transfer(out, &rev);
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_dict_diff(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = a;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
            ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
            ElmcValue *found = elmc_dict_member(pair->first, b);
            if (!elmc_as_int(found)) {
              next = NULL;
              rc = elmc_list_cons(&next, node->head, rev);
              CHECK_RC(rc);
              elmc_release(rev);
              rev = next;
              next = NULL;
            }
            elmc_release(found);
          }
          cursor = node->tail;
        }
        rc = elmc_list_reverse_transfer(out, &rev);
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    static ElmcValue *elmc_dict_pair_key(ElmcValue *pair) {
      if (!pair || pair->tag != ELMC_TAG_TUPLE2 || !pair->payload) return NULL;
      return ((ElmcTuple2 *)pair->payload)->first;
    }

    static ElmcValue *elmc_dict_pair_value(ElmcValue *pair) {
      if (!pair || pair->tag != ELMC_TAG_TUPLE2 || !pair->payload) return NULL;
      return ((ElmcTuple2 *)pair->payload)->second;
    }

    static int elmc_dict_key_cmp(ElmcValue *left_key, ElmcValue *right_key) {
      ElmcValue *order = elmc_basics_compare_take(left_key, right_key);
      int cmp = (int)elmc_as_int(order);
      elmc_release(order);
      return cmp;
    }

    static RC elmc_dict_sort_by_key(ElmcValue **out, ElmcValue *dict) {
      RC rc = RC_SUCCESS;
      ElmcValue *sorted = elmc_list_nil();
      ElmcValue *rev_before = elmc_list_nil();
      ElmcValue *rebuilt = NULL;
      ElmcValue *tmp = NULL;
      ElmcValue *next_rb = NULL;
      ElmcValue *new_tail = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = dict;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *key = elmc_dict_pair_key(node->head);
          rev_before = elmc_list_nil();
          ElmcValue *rest = sorted;
          int inserted = 0;
          while (rest && rest->tag == ELMC_TAG_LIST && rest->payload != NULL) {
            ElmcCons *sn = (ElmcCons *)rest->payload;
            ElmcValue *rest_key = elmc_dict_pair_key(sn->head);
            if (!inserted && key && rest_key && elmc_dict_key_cmp(key, rest_key) <= 0) {
              rebuilt = NULL;
              rc = elmc_list_cons(&rebuilt, node->head, rest);
              CHECK_RC(rc);
              ElmcValue *rb_cursor = rev_before;
              while (rb_cursor && rb_cursor->tag == ELMC_TAG_LIST && rb_cursor->payload != NULL) {
                ElmcCons *rbn = (ElmcCons *)rb_cursor->payload;
                tmp = NULL;
                rc = elmc_list_cons(&tmp, rbn->head, rebuilt);
                CHECK_RC(rc);
                elmc_release(rebuilt);
                rebuilt = tmp;
                tmp = NULL;
                rb_cursor = rbn->tail;
              }
              elmc_release(rev_before);
              rev_before = elmc_list_nil();
              elmc_release(sorted);
              sorted = rebuilt;
              rebuilt = NULL;
              inserted = 1;
              break;
            }
            next_rb = NULL;
            rc = elmc_list_cons(&next_rb, sn->head, rev_before);
            CHECK_RC(rc);
            elmc_release(rev_before);
            rev_before = next_rb;
            next_rb = NULL;
            rest = sn->tail;
          }
          if (!inserted) {
            new_tail = NULL;
            rc = elmc_list_cons(&new_tail, node->head, elmc_list_nil());
            CHECK_RC(rc);
            rebuilt = new_tail;
            new_tail = NULL;
            ElmcValue *rb_cursor = rev_before;
            while (rb_cursor && rb_cursor->tag == ELMC_TAG_LIST && rb_cursor->payload != NULL) {
              ElmcCons *rbn = (ElmcCons *)rb_cursor->payload;
              tmp = NULL;
              rc = elmc_list_cons(&tmp, rbn->head, rebuilt);
              CHECK_RC(rc);
              elmc_release(rebuilt);
              rebuilt = tmp;
              tmp = NULL;
              rb_cursor = rbn->tail;
            }
            elmc_release(rev_before);
            rev_before = elmc_list_nil();
            elmc_release(sorted);
            sorted = rebuilt;
            rebuilt = NULL;
          }
          cursor = node->tail;
        }
        *out = sorted;
        sorted = NULL;
      CATCH_END;
      elmc_release(rev_before);
      elmc_release(rebuilt);
      elmc_release(tmp);
      elmc_release(next_rb);
      elmc_release(new_tail);
      elmc_release(sorted);
      return rc;
    }

    RC elmc_dict_merge(ElmcValue **out, ElmcValue *lf, ElmcValue *bf, ElmcValue *rf, ElmcValue *a, ElmcValue *b, ElmcValue *result) {
      RC rc = RC_SUCCESS;
      ElmcValue *left = NULL;
      ElmcValue *right = NULL;
      ElmcValue *acc = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        if (!a) a = elmc_list_nil();
        if (!b) b = elmc_list_nil();
        if (!result) result = elmc_list_nil();
        rc = elmc_dict_sort_by_key(&left, a);
        CHECK_RC(rc);
        rc = elmc_dict_sort_by_key(&right, b);
        CHECK_RC(rc);
        acc = elmc_retain(result);
        ElmcValue *l_cursor = left;
        ElmcValue *r_cursor = right;
        while (l_cursor && l_cursor->tag == ELMC_TAG_LIST && l_cursor->payload != NULL &&
               r_cursor && r_cursor->tag == ELMC_TAG_LIST && r_cursor->payload != NULL) {
          ElmcCons *l_node = (ElmcCons *)l_cursor->payload;
          ElmcCons *r_node = (ElmcCons *)r_cursor->payload;
          ElmcValue *l_key = elmc_dict_pair_key(l_node->head);
          ElmcValue *r_key = elmc_dict_pair_key(r_node->head);
          int cmp = (l_key && r_key) ? elmc_dict_key_cmp(l_key, r_key) : 0;
          if (cmp < 0) {
            ElmcValue *l_val = elmc_dict_pair_value(l_node->head);
            ElmcValue *args[3] = { l_key, l_val, acc };
            next = NULL;
            rc = elmc_closure_call_rc(&next, lf, args, 3);
            CHECK_RC(rc);
            elmc_release(acc);
            acc = next;
            next = NULL;
            l_cursor = l_node->tail;
          } else if (cmp > 0) {
            ElmcValue *r_val = elmc_dict_pair_value(r_node->head);
            ElmcValue *args[3] = { r_key, r_val, acc };
            next = NULL;
            rc = elmc_closure_call_rc(&next, rf, args, 3);
            CHECK_RC(rc);
            elmc_release(acc);
            acc = next;
            next = NULL;
            r_cursor = r_node->tail;
          } else {
            ElmcValue *l_val = elmc_dict_pair_value(l_node->head);
            ElmcValue *r_val = elmc_dict_pair_value(r_node->head);
            ElmcValue *args[4] = { l_key, l_val, r_val, acc };
            next = NULL;
            rc = elmc_closure_call_rc(&next, bf, args, 4);
            CHECK_RC(rc);
            elmc_release(acc);
            acc = next;
            next = NULL;
            l_cursor = l_node->tail;
            r_cursor = r_node->tail;
          }
        }
        while (l_cursor && l_cursor->tag == ELMC_TAG_LIST && l_cursor->payload != NULL) {
          ElmcCons *l_node = (ElmcCons *)l_cursor->payload;
          ElmcValue *l_key = elmc_dict_pair_key(l_node->head);
          ElmcValue *l_val = elmc_dict_pair_value(l_node->head);
          ElmcValue *args[3] = { l_key, l_val, acc };
          next = NULL;
          rc = elmc_closure_call_rc(&next, lf, args, 3);
          CHECK_RC(rc);
          elmc_release(acc);
          acc = next;
          next = NULL;
          l_cursor = l_node->tail;
        }
        while (r_cursor && r_cursor->tag == ELMC_TAG_LIST && r_cursor->payload != NULL) {
          ElmcCons *r_node = (ElmcCons *)r_cursor->payload;
          ElmcValue *r_key = elmc_dict_pair_key(r_node->head);
          ElmcValue *r_val = elmc_dict_pair_value(r_node->head);
          ElmcValue *args[3] = { r_key, r_val, acc };
          next = NULL;
          rc = elmc_closure_call_rc(&next, rf, args, 3);
          CHECK_RC(rc);
          elmc_release(acc);
          acc = next;
          next = NULL;
          r_cursor = r_node->tail;
        }
        *out = acc;
        acc = NULL;
      CATCH_END;
      elmc_release(left);
      elmc_release(right);
      elmc_release(next);
      elmc_release(acc);
      return rc;
    }

    RC elmc_dict_update(ElmcValue **out, ElmcValue *key, ElmcValue *f, ElmcValue *dict) {
      RC rc = RC_SUCCESS;
      ElmcValue *old_val = NULL;
      ElmcValue *new_maybe = NULL;
      CATCH_BEGIN
        old_val = elmc_dict_get_take(key, dict);
        ElmcValue *args[1] = { old_val };
        rc = elmc_closure_call_rc(&new_maybe, f, args, 1);
        CHECK_RC(rc);
        if (new_maybe && new_maybe->tag == ELMC_TAG_MAYBE && new_maybe->payload != NULL) {
          ElmcMaybe *m = (ElmcMaybe *)new_maybe->payload;
          if (m->is_just && m->value) {
            rc = elmc_dict_insert(out, key, m->value, dict);
            CHECK_RC(rc);
          } else {
            rc = elmc_dict_remove(out, key, dict);
            CHECK_RC(rc);
          }
        } else {
          rc = elmc_dict_remove(out, key, dict);
          CHECK_RC(rc);
        }
      CATCH_END;
      elmc_release(old_val);
      elmc_release(new_maybe);
      return rc;
    }

    ElmcValue *elmc_dict_singleton(ElmcValue *key, ElmcValue *value) {
      ElmcValue *empty = elmc_list_nil();
      ElmcValue *out = elmc_dict_insert_take(key, value, empty);
      elmc_release(empty);
      return out;
    }

    /* ================================================================
       Standard Library – Set (extended)
       ================================================================ */

    ElmcValue *elmc_set_singleton(ElmcValue *value) {
      ElmcValue *empty = elmc_list_nil();
      ElmcValue *out = elmc_set_insert_take(value, empty);
      elmc_release(empty);
      return out;
    }

    RC elmc_set_remove(ElmcValue **out, ElmcValue *value, ElmcValue *set) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = set;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (!elmc_value_equal(node->head, value)) {
            next = NULL;
            rc = elmc_list_cons(&next, node->head, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = next;
            next = NULL;
          }
          cursor = node->tail;
        }
        rc = elmc_list_reverse_transfer(out, &rev);
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    ElmcValue *elmc_set_is_empty(ElmcValue *set) {
      if (!set || set->tag != ELMC_TAG_LIST) {
        ElmcValue *_elmc_rc_out = NULL;
        (void)elmc_new_bool(&_elmc_rc_out, 1);
        return _elmc_rc_out;
      }
      {
          ElmcValue *_elmc_rc_out = NULL;
          (void)elmc_new_bool(&_elmc_rc_out, set->payload == NULL);
          return _elmc_rc_out;
      }
    }

    ElmcValue *elmc_set_to_list(ElmcValue *set) {
      ElmcValue *out = NULL;
      if (!set) return elmc_list_nil();
      if (elmc_list_copy(&out, set) != RC_SUCCESS) return elmc_list_nil();
      return out;
    }

    RC elmc_set_union(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
      RC rc = RC_SUCCESS;
      ElmcValue *result = elmc_retain(b);
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = a;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          next = NULL;
          rc = elmc_set_insert(&next, node->head, result);
          CHECK_RC(rc);
          elmc_release(result);
          result = next;
          next = NULL;
          cursor = node->tail;
        }
        *out = result;
        result = NULL;
      CATCH_END;
      elmc_release(next);
      elmc_release(result);
      return rc;
    }

    RC elmc_set_intersect(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = a;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *found = elmc_set_member(node->head, b);
          if (elmc_as_int(found)) {
            next = NULL;
            rc = elmc_list_cons(&next, node->head, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = next;
            next = NULL;
          }
          elmc_release(found);
          cursor = node->tail;
        }
        rc = elmc_list_reverse_transfer(out, &rev);
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_set_diff(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = a;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *found = elmc_set_member(node->head, b);
          if (!elmc_as_int(found)) {
            next = NULL;
            rc = elmc_list_cons(&next, node->head, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = next;
            next = NULL;
          }
          elmc_release(found);
          cursor = node->tail;
        }
        rc = elmc_list_reverse_transfer(out, &rev);
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_set_map(ElmcValue **out, ElmcValue *f, ElmcValue *set) {
      RC rc = RC_SUCCESS;
      ElmcValue *acc = elmc_list_nil();
      ElmcValue *mapped = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = set;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *args[1] = { node->head };
          mapped = NULL;
          rc = elmc_closure_call_rc(&mapped, f, args, 1);
          CHECK_RC(rc);
          next = NULL;
          rc = elmc_set_insert(&next, mapped, acc);
          CHECK_RC(rc);
          elmc_release(mapped);
          mapped = NULL;
          elmc_release(acc);
          acc = next;
          next = NULL;
          cursor = node->tail;
        }
        *out = acc;
        acc = NULL;
      CATCH_END;
      elmc_release(mapped);
      elmc_release(next);
      elmc_release(acc);
      return rc;
    }

    RC elmc_set_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *set) {
      RC rc = RC_SUCCESS;
      ElmcValue *result = elmc_retain(acc);
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = set;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *args[2] = { node->head, result };
          next = NULL;
          rc = elmc_closure_call_rc(&next, f, args, 2);
          CHECK_RC(rc);
          elmc_release(result);
          result = next;
          next = NULL;
          cursor = node->tail;
        }
        *out = result;
        result = NULL;
      CATCH_END;
      elmc_release(next);
      elmc_release(result);
      return rc;
    }

    RC elmc_set_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *set) {
      RC rc = RC_SUCCESS;
      ElmcValue *reversed = NULL;
      ElmcValue *result = elmc_retain(acc);
      ElmcValue *next = NULL;
      CATCH_BEGIN
        rc = elmc_list_reverse_into(&reversed, set);
        CHECK_RC(rc);
        ElmcValue *cursor = reversed;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *args[2] = { node->head, result };
          next = NULL;
          rc = elmc_closure_call_rc(&next, f, args, 2);
          CHECK_RC(rc);
          elmc_release(result);
          result = next;
          next = NULL;
          cursor = node->tail;
        }
        *out = result;
        result = NULL;
      CATCH_END;
      elmc_release(reversed);
      elmc_release(next);
      elmc_release(result);
      return rc;
    }

    RC elmc_set_filter(ElmcValue **out, ElmcValue *f, ElmcValue *set) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *keep = NULL;
      ElmcValue *next = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = set;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *args[1] = { node->head };
          keep = NULL;
          rc = elmc_closure_call_rc(&keep, f, args, 1);
          CHECK_RC(rc);
          if (elmc_as_int(keep)) {
            next = NULL;
            rc = elmc_list_cons(&next, node->head, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = next;
            next = NULL;
          }
          elmc_release(keep);
          keep = NULL;
          cursor = node->tail;
        }
        rc = elmc_list_reverse_transfer(out, &rev);
        CHECK_RC(rc);
      CATCH_END;
      elmc_release(keep);
      elmc_release(next);
      elmc_release(rev);
      return rc;
    }

    RC elmc_set_partition(ElmcValue **out, ElmcValue *f, ElmcValue *set) {
      RC rc = RC_SUCCESS;
      ElmcValue *rev_yes = elmc_list_nil();
      ElmcValue *rev_no = elmc_list_nil();
      ElmcValue *keep = NULL;
      ElmcValue *next = NULL;
      ElmcValue *yes = NULL;
      ElmcValue *no = NULL;
      CATCH_BEGIN
        ElmcValue *cursor = set;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          ElmcValue *args[1] = { node->head };
          keep = NULL;
          rc = elmc_closure_call_rc(&keep, f, args, 1);
          CHECK_RC(rc);
          if (elmc_as_int(keep)) {
            next = NULL;
            rc = elmc_list_cons(&next, node->head, rev_yes);
            CHECK_RC(rc);
            elmc_release(rev_yes);
            rev_yes = next;
            next = NULL;
          } else {
            next = NULL;
            rc = elmc_list_cons(&next, node->head, rev_no);
            CHECK_RC(rc);
            elmc_release(rev_no);
            rev_no = next;
            next = NULL;
          }
          elmc_release(keep);
          keep = NULL;
          cursor = node->tail;
        }
        rc = elmc_list_reverse_transfer(&yes, &rev_yes);
        CHECK_RC(rc);
        rc = elmc_list_reverse_transfer(&no, &rev_no);
        CHECK_RC(rc);
        rc = elmc_tuple2(out, yes, no);
        CHECK_RC(rc);
        elmc_release(yes);
        elmc_release(no);
        yes = NULL;
        no = NULL;
      CATCH_END;
      elmc_release(keep);
      elmc_release(next);
      elmc_release(rev_yes);
      elmc_release(rev_no);
      elmc_release(yes);
      elmc_release(no);
      return rc;
    }

    /* ================================================================
       Standard Library – Array (extended)
       ================================================================ */

    ElmcValue *elmc_array_initialize(ElmcValue *n, ElmcValue *f) {
      int64_t count = elmc_as_int(n);
      ElmcValue *out = elmc_list_nil();
      for (int64_t i = count - 1; i >= 0; i--) {
        ElmcValue *idx = NULL;
        if (elmc_new_int(&idx, i) != RC_SUCCESS) idx = NULL;
        ElmcValue *args[1] = { idx };
        ElmcValue *val = NULL;
        if (elmc_closure_call_rc(&val, f, args, 1) != RC_SUCCESS) {
          elmc_release(val);
          elmc_release(idx);
          elmc_release(out);
          return elmc_int_zero();
        }
        ElmcValue *next = NULL;
        if (elmc_list_cons(&next, val, out) != RC_SUCCESS) next = NULL;
        elmc_release(idx);
        elmc_release(val);
        elmc_release(out);
        out = next;
      }
      return out;
    }

    ElmcValue *elmc_array_repeat(ElmcValue *n, ElmcValue *value) {
      return elmc_list_repeat_take(n, value);
    }

    ElmcValue *elmc_array_is_empty(ElmcValue *array) {
      return elmc_list_is_empty(array);
    }

    ElmcValue *elmc_array_to_list(ElmcValue *array) {
      if (!array) return elmc_list_nil();
      return elmc_retain(array);
    }

    ElmcValue *elmc_array_to_indexed_list(ElmcValue *array) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = array;
      int64_t idx = 0;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *index_val = NULL;
        if (elmc_new_int(&index_val, idx) != RC_SUCCESS) index_val = NULL;
        ElmcValue *pair = NULL;
        if (elmc_tuple2(&pair, index_val, node->head) != RC_SUCCESS) pair = NULL;
        ElmcValue *next = NULL;
        if (elmc_list_cons(&next, pair, rev) != RC_SUCCESS) next = NULL;
        elmc_release(index_val);
        elmc_release(pair);
        elmc_release(rev);
        rev = next;
        idx++;
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_array_map(ElmcValue *f, ElmcValue *array) {
      return elmc_list_map_take(f, array);
    }

    ElmcValue *elmc_array_indexed_map(ElmcValue *f, ElmcValue *array) {
      return elmc_list_indexed_map_take(f, array);
    }

    ElmcValue *elmc_array_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *array) {
      return elmc_list_foldl_take(f, acc, array);
    }

    ElmcValue *elmc_array_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *array) {
      return elmc_list_foldr_take(f, acc, array);
    }

    ElmcValue *elmc_array_filter(ElmcValue *f, ElmcValue *array) {
      return elmc_list_filter_take(f, array);
    }

    ElmcValue *elmc_array_append(ElmcValue *a, ElmcValue *b) {
      return elmc_list_append_take(a, b);
    }

    ElmcValue *elmc_array_slice(ElmcValue *start, ElmcValue *end_idx, ElmcValue *array) {
      int64_t len_val = 0;
      ElmcValue *cursor = array;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        len_val++;
        cursor = ((ElmcCons *)cursor->payload)->tail;
      }
      int64_t st = elmc_as_int(start);
      int64_t en = elmc_as_int(end_idx);
      if (st < 0) st = len_val + st;
      if (en < 0) en = len_val + en;
      if (st < 0) st = 0;
      if (en < 0) en = 0;
      if (st > len_val) st = len_val;
      if (en > len_val) en = len_val;
      if (en <= st) return elmc_list_nil();
      ElmcValue *rev = elmc_list_nil();
      cursor = array;
      int64_t idx = 0;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (idx >= st && idx < en) {
          ElmcValue *next = NULL;
          if (elmc_list_cons(&next, node->head, rev) != RC_SUCCESS) next = NULL;
          elmc_release(rev);
          rev = next;
        }
        idx++;
        if (idx >= en) break;
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    #{JsonSections.runtime_source_impl()}

    uint64_t elmc_rc_allocated_count(void) {
      return ELMC_ALLOCATED;
    }

    uint64_t elmc_rc_released_count(void) {
      return ELMC_RELEASED;
    }

    #{RcMacros.source_impl()}

    #{AllocTrack.source_impl()}

    #{AllocProbe.source_impl()}

    #{RcTrack.source_impl()}

    #{RcTrack.retain_release_impl()}

    void elmc_release_deep(ElmcValue *value) {
      /* Current runtime representation has no nested ownership for supported subset. */
      elmc_release(value);
    }
    """
  end
end
