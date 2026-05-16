defmodule Elmc.Runtime.Generator do
  @moduledoc """
  Emits the reference-counted C runtime used by generated code.
  """

  alias Elmc.Runtime.JsonSections

  @type write_opts :: [prune_from_dir: String.t() | nil, pebble_int32: boolean()]

  @spec write_runtime(String.t(), write_opts()) :: :ok | {:error, term()}
  def write_runtime(runtime_dir, opts \\ []) do
    header = runtime_header(opts)
    source = runtime_source()

    {header, source} =
      maybe_prune_runtime(header, source, Keyword.get(opts, :prune_from_dir))

    with :ok <- File.mkdir_p(runtime_dir),
         :ok <- File.write(Path.join(runtime_dir, "elmc_runtime.h"), header),
         :ok <- File.write(Path.join(runtime_dir, "elmc_runtime.c"), source) do
      :ok
    end
  end

  @spec maybe_prune_runtime(term(), term(), term()) :: term()
  defp maybe_prune_runtime(header, source, prune_from_dir) when is_binary(prune_from_dir) do
    with refs when map_size(refs) > 0 <- collect_runtime_references(prune_from_dir),
         source <- maybe_drop_float_runtime(source, refs),
         {:ok, defs} <- parse_function_defs(source),
         true <- defs != [] do
      kept_names = transitive_keep_set(defs, refs)

      if MapSet.size(kept_names) > 0 do
        {header, prune_source(source, defs, kept_names)}
      else
        {header, source}
      end
    else
      _ -> {header, source}
    end
  rescue
    _error -> {header, source}
  end

  defp maybe_prune_runtime(header, source, _), do: {header, source}

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
            if (fa < fb) return elmc_new_int(-1);
            if (fa > fb) return elmc_new_int(1);
            return elmc_int_zero();
          }
        """,
        ""
      )
    else
      source
    end
  end

  @spec collect_runtime_references(term()) :: term()
  defp collect_runtime_references(dir) do
    files =
      Path.wildcard(Path.join(dir, "**/*.c"), match_dot: true)
      |> Enum.reject(&String.contains?(&1, "/runtime/elmc_runtime.c"))

    Enum.reduce(files, %{}, fn path, acc ->
      case File.read(path) do
        {:ok, content} ->
          Regex.scan(~r/\belmc_[A-Za-z0-9_]+\b/, content)
          |> Enum.map(&hd/1)
          |> Enum.reduce(acc, fn name, map -> Map.put(map, name, true) end)

        _ ->
          acc
      end
    end)
  end

  @spec parse_function_defs(term()) :: term()
  defp parse_function_defs(source) do
    line_starts = line_start_offsets(source)
    lines = String.split(source, "\n", trim: false)

    defs =
      lines
      |> Enum.with_index()
      |> Enum.reduce([], fn {line, idx}, acc ->
        case Regex.run(
               ~r/^\s*(?:static\s+)?[A-Za-z_][A-Za-z0-9_\s\*]*\**\s*(elmc_[A-Za-z0-9_]+)\s*\([^;]*\)\s*\{/,
               line
             ) do
          [_, name] ->
            start_idx = Enum.at(line_starts, idx)

            brace_idx =
              start_idx +
                case :binary.match(line, "{") do
                  {pos, _len} -> pos
                  :nomatch -> 0
                end

            case find_matching_brace(source, brace_idx) do
              {:ok, end_idx} ->
                body = binary_part(source, start_idx, end_idx - start_idx + 1)
                [%{name: name, start_idx: start_idx, end_idx: end_idx, body: body} | acc]

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

  @spec line_start_offsets(term()) :: term()
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

  @spec find_matching_brace(term(), term()) :: term()
  defp find_matching_brace(source, open_idx) do
    do_find_matching_brace(source, open_idx, byte_size(source), 0)
  end

  @spec do_find_matching_brace(term(), term(), term(), term()) :: term()
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

  @spec transitive_keep_set(term(), term()) :: term()
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

  @spec walk_keep(term(), term(), term()) :: term()
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

  @spec called_functions(term(), term()) :: term()
  defp called_functions(body, def_map) when is_binary(body) do
    Regex.scan(~r/\b([A-Za-z_][A-Za-z0-9_]*)\s*\(/, body)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.filter(&Map.has_key?(def_map, &1))
    |> Enum.uniq()
  end

  defp called_functions(_, _), do: []

  @spec prune_source(term(), term(), term()) :: term()
  defp prune_source(source, defs, kept_names) do
    first_start =
      case defs do
        [%{start_idx: idx} | _] -> idx
        _ -> byte_size(source)
      end

    preamble =
      source
      |> binary_part(0, first_start)
      |> maybe_drop_process_globals(kept_names)

    kept_bodies =
      defs
      |> Enum.filter(&MapSet.member?(kept_names, &1.name))
      |> Enum.map(fn %{start_idx: s, end_idx: e} ->
        binary_part(source, s, e - s + 1)
      end)
      |> Enum.join("\n\n")

    preamble <> kept_bodies <> "\n"
  end

  @spec maybe_drop_process_globals(term(), term()) :: term()
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

  @spec runtime_header(write_opts()) :: String.t()
  defp runtime_header(opts) do
    int32_define =
      if Keyword.get(opts, :pebble_int32, false), do: "#define ELMC_PEBBLE_INT32 1\n", else: ""

    """
    #ifndef ELMC_RUNTIME_H
    #define ELMC_RUNTIME_H

    #include <stdint.h>
    #include <stddef.h>
    #{int32_define}

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
      ELMC_TAG_PORT_PAYLOAD = 9,
      ELMC_TAG_FLOAT = 10,
      ELMC_TAG_RECORD = 11,
      ELMC_TAG_CLOSURE = 12
    } ElmcTag;

    typedef struct ElmcValue {
      uint32_t rc;
      ElmcTag tag;
      void *payload;
      elmc_int_t scalar;
    } ElmcValue;

    typedef struct ElmcCons {
      ElmcValue *head;
      ElmcValue *tail;
    } ElmcCons;

    typedef struct ElmcTuple2 {
      ElmcValue *first;
      ElmcValue *second;
    } ElmcTuple2;

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
      const char **field_names;
      ElmcValue **field_values;
    } ElmcRecord;

    #define ELMC_RECORD_GET_INDEX_INT(record, index) \\
      elmc_as_int(((ElmcRecord *)((record)->payload))->field_values[(index)])

    typedef struct ElmcClosure {
      ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count);
      int arity;
      int capture_count;
      ElmcValue **captures;
    } ElmcClosure;

    typedef void (*ElmcPortCallback)(ElmcValue *value, void *context);

    ElmcValue *elmc_new_int(elmc_int_t value);
    ElmcValue *elmc_new_bool(int value);
    ElmcValue *elmc_new_char(elmc_int_t value);
    ElmcValue *elmc_new_string(const char *value);
    extern ElmcValue ELMC_INT_ZERO;
    #define elmc_int_zero() (&ELMC_INT_ZERO)
    ElmcValue *elmc_list_nil(void);
    ElmcValue *elmc_list_cons(ElmcValue *head, ElmcValue *tail);
    ElmcValue *elmc_list_from_values(ElmcValue **items, int count);
    ElmcValue *elmc_list_from_values_take(ElmcValue **items, int count);
    ElmcValue *elmc_maybe_nothing(void);
    ElmcValue *elmc_maybe_just(ElmcValue *value);
    ElmcValue *elmc_result_ok(ElmcValue *value);
    ElmcValue *elmc_result_err(ElmcValue *value);
    ElmcValue *elmc_tuple2(ElmcValue *first, ElmcValue *second);
    ElmcValue *elmc_tuple2_take(ElmcValue *first, ElmcValue *second);
    ElmcValue *elmc_tuple2_ints(elmc_int_t first, elmc_int_t second);

    elmc_int_t elmc_as_int(ElmcValue *value);
    elmc_int_t elmc_as_bool(ElmcValue *value);
    int elmc_value_equal(ElmcValue *left, ElmcValue *right);
    int elmc_string_length(ElmcValue *value);
    ElmcValue *elmc_list_head(ElmcValue *list);
    ElmcValue *elmc_tuple_first(ElmcValue *tuple);
    ElmcValue *elmc_tuple_second(ElmcValue *tuple);
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
    ElmcValue *elmc_append(ElmcValue *left, ElmcValue *right);
    ElmcValue *elmc_string_append(ElmcValue *left, ElmcValue *right);
    ElmcValue *elmc_string_append_native(const char *left, const char *right);
    ElmcValue *elmc_string_is_empty(ElmcValue *value);
    ElmcValue *elmc_dict_from_list(ElmcValue *items);
    ElmcValue *elmc_dict_insert(ElmcValue *key, ElmcValue *value, ElmcValue *dict);
    ElmcValue *elmc_dict_get(ElmcValue *key, ElmcValue *dict);
    ElmcValue *elmc_dict_member(ElmcValue *key, ElmcValue *dict);
    ElmcValue *elmc_dict_size(ElmcValue *dict);
    ElmcValue *elmc_set_from_list(ElmcValue *items);
    ElmcValue *elmc_set_insert(ElmcValue *value, ElmcValue *set);
    ElmcValue *elmc_set_member(ElmcValue *value, ElmcValue *set);
    ElmcValue *elmc_set_size(ElmcValue *set);
    ElmcValue *elmc_array_empty(void);
    ElmcValue *elmc_array_from_list(ElmcValue *items);
    ElmcValue *elmc_array_length(ElmcValue *array);
    ElmcValue *elmc_array_get(ElmcValue *index, ElmcValue *array);
    ElmcValue *elmc_array_set(ElmcValue *index, ElmcValue *value, ElmcValue *array);
    ElmcValue *elmc_array_push(ElmcValue *value, ElmcValue *array);
    ElmcValue *elmc_task_succeed(ElmcValue *value);
    ElmcValue *elmc_task_fail(ElmcValue *value);
    ElmcValue *elmc_process_spawn(ElmcValue *task);
    ElmcValue *elmc_process_sleep(ElmcValue *milliseconds);
    ElmcValue *elmc_process_kill(ElmcValue *pid);
    ElmcValue *elmc_time_now_millis(void);
    ElmcValue *elmc_time_zone_offset_minutes(void);
    ElmcValue *elmc_cmd_backlight_from_maybe(ElmcValue *maybe_mode);

    /* --- List operations --- */
    ElmcValue *elmc_list_tail(ElmcValue *list);
    ElmcValue *elmc_list_is_empty(ElmcValue *list);
    ElmcValue *elmc_list_length(ElmcValue *list);
    ElmcValue *elmc_list_reverse(ElmcValue *list);
    ElmcValue *elmc_list_member(ElmcValue *value, ElmcValue *list);
    ElmcValue *elmc_list_map(ElmcValue *f, ElmcValue *list);
    ElmcValue *elmc_list_filter(ElmcValue *f, ElmcValue *list);
    ElmcValue *elmc_list_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *list);
    ElmcValue *elmc_list_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *list);
    ElmcValue *elmc_list_append(ElmcValue *a, ElmcValue *b);
    ElmcValue *elmc_list_concat(ElmcValue *lists);
    ElmcValue *elmc_list_concat_map(ElmcValue *f, ElmcValue *list);
    ElmcValue *elmc_list_indexed_map(ElmcValue *f, ElmcValue *list);
    ElmcValue *elmc_list_filter_map(ElmcValue *f, ElmcValue *list);
    ElmcValue *elmc_list_sum(ElmcValue *list);
    ElmcValue *elmc_list_product(ElmcValue *list);
    ElmcValue *elmc_list_maximum(ElmcValue *list);
    ElmcValue *elmc_list_minimum(ElmcValue *list);
    ElmcValue *elmc_list_any(ElmcValue *f, ElmcValue *list);
    ElmcValue *elmc_list_all(ElmcValue *f, ElmcValue *list);
    ElmcValue *elmc_list_sort(ElmcValue *list);
    ElmcValue *elmc_list_sort_by(ElmcValue *f, ElmcValue *list);
    ElmcValue *elmc_list_sort_with(ElmcValue *f, ElmcValue *list);
    ElmcValue *elmc_list_singleton(ElmcValue *value);
    ElmcValue *elmc_list_range(ElmcValue *lo, ElmcValue *hi);
    ElmcValue *elmc_list_repeat(ElmcValue *n, ElmcValue *value);
    ElmcValue *elmc_list_take(ElmcValue *n, ElmcValue *list);
    ElmcValue *elmc_list_drop(ElmcValue *n, ElmcValue *list);
    ElmcValue *elmc_list_partition(ElmcValue *f, ElmcValue *list);
    ElmcValue *elmc_list_unzip(ElmcValue *list);
    ElmcValue *elmc_list_intersperse(ElmcValue *sep, ElmcValue *list);
    ElmcValue *elmc_list_map2(ElmcValue *f, ElmcValue *a, ElmcValue *b);
    ElmcValue *elmc_list_map3(ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c);

    /* --- Maybe operations --- */
    ElmcValue *elmc_maybe_with_default(ElmcValue *default_val, ElmcValue *maybe);
    elmc_int_t elmc_maybe_with_default_int(elmc_int_t default_val, ElmcValue *maybe);
    ElmcValue *elmc_maybe_map(ElmcValue *f, ElmcValue *maybe);
    ElmcValue *elmc_maybe_map2(ElmcValue *f, ElmcValue *a, ElmcValue *b);
    ElmcValue *elmc_maybe_and_then(ElmcValue *f, ElmcValue *maybe);

    /* --- Result operations --- */
    ElmcValue *elmc_result_map(ElmcValue *f, ElmcValue *result);
    ElmcValue *elmc_result_map_error(ElmcValue *f, ElmcValue *result);
    ElmcValue *elmc_result_and_then(ElmcValue *f, ElmcValue *result);
    ElmcValue *elmc_result_with_default(ElmcValue *default_val, ElmcValue *result);
    ElmcValue *elmc_result_to_maybe(ElmcValue *result);
    ElmcValue *elmc_result_from_maybe(ElmcValue *err, ElmcValue *maybe);

    /* --- String operations (extended) --- */
    ElmcValue *elmc_string_length_val(ElmcValue *s);
    ElmcValue *elmc_string_reverse(ElmcValue *s);
    ElmcValue *elmc_string_repeat(ElmcValue *n, ElmcValue *s);
    ElmcValue *elmc_string_replace(ElmcValue *old_s, ElmcValue *new_s, ElmcValue *s);
    ElmcValue *elmc_string_from_int(ElmcValue *n);
    ElmcValue *elmc_string_from_native_int(elmc_int_t n);
    ElmcValue *elmc_string_to_int(ElmcValue *s);
    ElmcValue *elmc_string_from_float(ElmcValue *f);
    ElmcValue *elmc_string_to_float(ElmcValue *s);
    ElmcValue *elmc_string_to_upper(ElmcValue *s);
    ElmcValue *elmc_string_to_lower(ElmcValue *s);
    ElmcValue *elmc_string_trim(ElmcValue *s);
    ElmcValue *elmc_string_trim_left(ElmcValue *s);
    ElmcValue *elmc_string_trim_right(ElmcValue *s);
    ElmcValue *elmc_string_contains(ElmcValue *sub, ElmcValue *s);
    ElmcValue *elmc_string_starts_with(ElmcValue *prefix, ElmcValue *s);
    ElmcValue *elmc_string_ends_with(ElmcValue *suffix, ElmcValue *s);
    ElmcValue *elmc_string_split(ElmcValue *sep, ElmcValue *s);
    ElmcValue *elmc_string_join(ElmcValue *sep, ElmcValue *list);
    ElmcValue *elmc_string_words(ElmcValue *s);
    ElmcValue *elmc_string_lines(ElmcValue *s);
    ElmcValue *elmc_string_slice(ElmcValue *start, ElmcValue *end_idx, ElmcValue *s);
    ElmcValue *elmc_string_left(ElmcValue *n, ElmcValue *s);
    ElmcValue *elmc_string_right(ElmcValue *n, ElmcValue *s);
    ElmcValue *elmc_string_drop_left(ElmcValue *n, ElmcValue *s);
    ElmcValue *elmc_string_drop_right(ElmcValue *n, ElmcValue *s);
    ElmcValue *elmc_string_cons(ElmcValue *ch, ElmcValue *s);
    ElmcValue *elmc_string_uncons(ElmcValue *s);
    ElmcValue *elmc_string_to_list(ElmcValue *s);
    ElmcValue *elmc_string_from_list(ElmcValue *list);
    ElmcValue *elmc_string_from_char(ElmcValue *ch);
    ElmcValue *elmc_string_pad(ElmcValue *n, ElmcValue *ch, ElmcValue *s);
    ElmcValue *elmc_string_pad_left(ElmcValue *n, ElmcValue *ch, ElmcValue *s);
    ElmcValue *elmc_string_pad_right(ElmcValue *n, ElmcValue *ch, ElmcValue *s);
    ElmcValue *elmc_string_map(ElmcValue *f, ElmcValue *s);
    ElmcValue *elmc_string_filter(ElmcValue *f, ElmcValue *s);
    ElmcValue *elmc_string_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *s);
    ElmcValue *elmc_string_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *s);
    ElmcValue *elmc_string_any(ElmcValue *f, ElmcValue *s);
    ElmcValue *elmc_string_all(ElmcValue *f, ElmcValue *s);
    ElmcValue *elmc_string_indexes(ElmcValue *sub, ElmcValue *s);

    /* --- Tuple operations (extended) --- */
    ElmcValue *elmc_tuple_map_first(ElmcValue *f, ElmcValue *t);
    ElmcValue *elmc_tuple_map_second(ElmcValue *f, ElmcValue *t);
    ElmcValue *elmc_tuple_map_both(ElmcValue *f, ElmcValue *g, ElmcValue *t);

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
    ElmcValue *elmc_basics_compare(ElmcValue *a, ElmcValue *b);

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
    ElmcValue *elmc_dict_remove(ElmcValue *key, ElmcValue *dict);
    ElmcValue *elmc_dict_is_empty(ElmcValue *dict);
    ElmcValue *elmc_dict_keys(ElmcValue *dict);
    ElmcValue *elmc_dict_values(ElmcValue *dict);
    ElmcValue *elmc_dict_to_list(ElmcValue *dict);
    ElmcValue *elmc_dict_map(ElmcValue *f, ElmcValue *dict);
    ElmcValue *elmc_dict_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *dict);
    ElmcValue *elmc_dict_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *dict);
    ElmcValue *elmc_dict_filter(ElmcValue *f, ElmcValue *dict);
    ElmcValue *elmc_dict_partition(ElmcValue *f, ElmcValue *dict);
    ElmcValue *elmc_dict_union(ElmcValue *a, ElmcValue *b);
    ElmcValue *elmc_dict_intersect(ElmcValue *a, ElmcValue *b);
    ElmcValue *elmc_dict_diff(ElmcValue *a, ElmcValue *b);
    ElmcValue *elmc_dict_merge(ElmcValue *lf, ElmcValue *bf, ElmcValue *rf, ElmcValue *a, ElmcValue *b);
    ElmcValue *elmc_dict_update(ElmcValue *key, ElmcValue *f, ElmcValue *dict);
    ElmcValue *elmc_dict_singleton(ElmcValue *key, ElmcValue *value);

    /* --- Set (extended) --- */
    ElmcValue *elmc_set_singleton(ElmcValue *value);
    ElmcValue *elmc_set_remove(ElmcValue *value, ElmcValue *set);
    ElmcValue *elmc_set_is_empty(ElmcValue *set);
    ElmcValue *elmc_set_to_list(ElmcValue *set);
    ElmcValue *elmc_set_union(ElmcValue *a, ElmcValue *b);
    ElmcValue *elmc_set_intersect(ElmcValue *a, ElmcValue *b);
    ElmcValue *elmc_set_diff(ElmcValue *a, ElmcValue *b);
    ElmcValue *elmc_set_map(ElmcValue *f, ElmcValue *set);
    ElmcValue *elmc_set_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *set);
    ElmcValue *elmc_set_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *set);
    ElmcValue *elmc_set_filter(ElmcValue *f, ElmcValue *set);
    ElmcValue *elmc_set_partition(ElmcValue *f, ElmcValue *set);

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

    ElmcValue *elmc_new_float(double value);
    double elmc_as_float(ElmcValue *value);
    double elmc_basics_sqrt_double(double x);
    double elmc_basics_sin_double(double x);
    double elmc_basics_cos_double(double x);
    double elmc_basics_tan_double(double x);

    ElmcValue *elmc_record_new(int field_count, const char **field_names, ElmcValue **field_values);
    ElmcValue *elmc_record_new_take(int field_count, const char **field_names, ElmcValue **field_values);
    ElmcValue *elmc_record_new_ints(int field_count, const char **field_names, const elmc_int_t *field_values);
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
    ElmcValue *elmc_record_update(ElmcValue *record, const char *field_name, ElmcValue *new_value);

    ElmcValue *elmc_closure_new(ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count), int arity, int capture_count, ElmcValue **captures);
    ElmcValue *elmc_closure_call(ElmcValue *closure, ElmcValue **args, int argc);
    ElmcValue *elmc_apply_extra(ElmcValue *value, ElmcValue **args, int argc);

    uint64_t elmc_rc_allocated_count(void);
    uint64_t elmc_rc_released_count(void);

    ElmcValue *elmc_retain(ElmcValue *value);
    void elmc_release(ElmcValue *value);
    void elmc_release_deep(ElmcValue *value);

    #endif
    """
  end

  @spec runtime_source() :: String.t()
  defp runtime_source do
    """
    #include "elmc_runtime.h"
    #include <stdlib.h>
    #include <string.h>
    #include <stdio.h>
    #include <time.h>
    #{JsonSections.runtime_source_includes()}
    #if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
    #define ELMC_PEBBLE_PLATFORM 1
    #endif
    #ifdef ELMC_PEBBLE_PLATFORM
    #include <pebble.h>
    #endif

    static uint64_t ELMC_ALLOCATED = 0;
    static uint64_t ELMC_RELEASED = 0;
    static int64_t ELMC_NEXT_PROCESS_ID = 1;
    #define ELMC_PROCESS_MAX_SLOTS 16
    #define ELMC_RC_IMMORTAL UINT32_MAX
    static elmc_int_t ELMC_INT_ZERO_PAYLOAD = 0;
    ElmcValue ELMC_INT_ZERO = { ELMC_RC_IMMORTAL, ELMC_TAG_INT, &ELMC_INT_ZERO_PAYLOAD, 0 };
    static char ELMC_EMPTY_STRING_PAYLOAD[] = "";
    static ElmcValue ELMC_EMPTY_STRING = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, ELMC_EMPTY_STRING_PAYLOAD, 0 };
    static int ELMC_ALLOC_FAILURE_LOGGED = 0;

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

    static void elmc_log_alloc_failed_once(const char *context, size_t size) {
      if (ELMC_ALLOC_FAILURE_LOGGED) return;
      ELMC_ALLOC_FAILURE_LOGGED = 1;
    #ifdef ELMC_PEBBLE_PLATFORM
      APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC allocation failed in %s (%lu bytes)", context ? context : "unknown", (unsigned long)size);
    #else
      fprintf(stderr, "ELMC allocation failed in %s (%lu bytes)\\n", context ? context : "unknown", (unsigned long)size);
    #endif
    }

    static void *elmc_malloc(size_t size, const char *context) {
      void *ptr = malloc(size);
      if (!ptr) elmc_log_alloc_failed_once(context, size);
      return ptr;
    }

    static ElmcValue *elmc_alloc(ElmcTag tag, void *payload) {
      ElmcValue *value = (ElmcValue *)elmc_malloc(sizeof(ElmcValue), __func__);
      if (!value) return NULL;
      value->rc = 1;
      value->tag = tag;
      value->payload = payload;
      value->scalar = 0;
      ELMC_ALLOCATED += 1;
      return value;
    }

    static ElmcValue *elmc_alloc_scalar(ElmcTag tag, elmc_int_t scalar) {
      ElmcValue *value = elmc_alloc(tag, NULL);
      if (value) value->scalar = scalar;
      return value;
    }

    static ElmcValue *elmc_list_reverse_copy(ElmcValue *list) {
      ElmcValue *out = elmc_list_nil();
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *next = elmc_list_cons(node->head, out);
        elmc_release(out);
        out = next;
        cursor = node->tail;
      }
      return out;
    }

    ElmcValue *elmc_new_int(elmc_int_t value) {
      if (value == 0) return &ELMC_INT_ZERO;
      return elmc_alloc_scalar(ELMC_TAG_INT, value);
    }

    ElmcValue *elmc_new_bool(int value) {
      return elmc_alloc_scalar(ELMC_TAG_BOOL, value != 0);
    }

    ElmcValue *elmc_new_char(elmc_int_t value) {
      return elmc_new_int(value);
    }

    ElmcValue *elmc_new_string(const char *value) {
      if (!value || value[0] == '\\0') return &ELMC_EMPTY_STRING;
      size_t len = strlen(value);
      char *ptr = (char *)elmc_malloc(len + 1, __func__);
      if (!ptr) return &ELMC_EMPTY_STRING;
      memcpy(ptr, value, len + 1);
      ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, ptr);
      if (!out) {
        free(ptr);
        return &ELMC_EMPTY_STRING;
      }
      return out;
    }

    ElmcValue *elmc_list_nil(void) {
      return elmc_alloc(ELMC_TAG_LIST, NULL);
    }

    ElmcValue *elmc_list_cons(ElmcValue *head, ElmcValue *tail) {
      ElmcCons *node = (ElmcCons *)elmc_malloc(sizeof(ElmcCons), __func__);
      if (!node) return NULL;
      node->head = elmc_retain(head);
      node->tail = elmc_retain(tail);
      return elmc_alloc(ELMC_TAG_LIST, node);
    }

    static ElmcValue *elmc_list_cons_take(ElmcValue *head, ElmcValue *tail) {
      ElmcCons *node = (ElmcCons *)elmc_malloc(sizeof(ElmcCons), __func__);
      if (!node) {
        elmc_release(head);
        elmc_release(tail);
        return NULL;
      }
      node->head = head;
      node->tail = tail;
      return elmc_alloc(ELMC_TAG_LIST, node);
    }

    ElmcValue *elmc_list_from_values(ElmcValue **items, int count) {
      ElmcValue *out = elmc_list_nil();
      if (!items || count <= 0) return out;
      for (int i = count - 1; i >= 0; i--) {
        ElmcValue *next = elmc_list_cons(items[i], out);
        elmc_release(out);
        out = next;
      }
      return out;
    }

    ElmcValue *elmc_list_from_values_take(ElmcValue **items, int count) {
      ElmcValue *out = elmc_list_nil();
      if (!items || count <= 0) return out;
      for (int i = count - 1; i >= 0; i--) {
        out = elmc_list_cons_take(items[i], out);
      }
      return out;
    }

    ElmcValue *elmc_maybe_nothing(void) {
      ElmcMaybe *maybe = (ElmcMaybe *)elmc_malloc(sizeof(ElmcMaybe), __func__);
      if (!maybe) return NULL;
      maybe->is_just = 0;
      maybe->value = NULL;
      return elmc_alloc(ELMC_TAG_MAYBE, maybe);
    }

    ElmcValue *elmc_maybe_just(ElmcValue *value) {
      ElmcMaybe *maybe = (ElmcMaybe *)elmc_malloc(sizeof(ElmcMaybe), __func__);
      if (!maybe) return NULL;
      maybe->is_just = 1;
      maybe->value = elmc_retain(value);
      return elmc_alloc(ELMC_TAG_MAYBE, maybe);
    }

    ElmcValue *elmc_result_ok(ElmcValue *value) {
      ElmcResult *result = (ElmcResult *)elmc_malloc(sizeof(ElmcResult), __func__);
      if (!result) return NULL;
      result->is_ok = 1;
      result->value = elmc_retain(value);
      return elmc_alloc(ELMC_TAG_RESULT, result);
    }

    ElmcValue *elmc_result_err(ElmcValue *value) {
      ElmcResult *result = (ElmcResult *)elmc_malloc(sizeof(ElmcResult), __func__);
      if (!result) return NULL;
      result->is_ok = 0;
      result->value = elmc_retain(value);
      return elmc_alloc(ELMC_TAG_RESULT, result);
    }

    ElmcValue *elmc_tuple2(ElmcValue *first, ElmcValue *second) {
      ElmcTuple2 *tuple = (ElmcTuple2 *)elmc_malloc(sizeof(ElmcTuple2), __func__);
      if (!tuple) return NULL;
      tuple->first = elmc_retain(first);
      tuple->second = elmc_retain(second);
      return elmc_alloc(ELMC_TAG_TUPLE2, tuple);
    }

    ElmcValue *elmc_tuple2_take(ElmcValue *first, ElmcValue *second) {
      ElmcTuple2 *tuple = (ElmcTuple2 *)elmc_malloc(sizeof(ElmcTuple2), __func__);
      if (!tuple) {
        elmc_release(first);
        elmc_release(second);
        return NULL;
      }
      tuple->first = first;
      tuple->second = second;
      return elmc_alloc(ELMC_TAG_TUPLE2, tuple);
    }

    ElmcValue *elmc_tuple2_ints(elmc_int_t first, elmc_int_t second) {
      return elmc_tuple2_take(elmc_new_int(first), elmc_new_int(second));
    }

    elmc_int_t elmc_as_int(ElmcValue *value) {
      if (!value || (value->tag != ELMC_TAG_INT && value->tag != ELMC_TAG_BOOL)) return 0;
      return value->scalar;
    }

    elmc_int_t elmc_as_bool(ElmcValue *value) {
      return elmc_as_int(value) != 0;
    }

    int elmc_value_equal(ElmcValue *left, ElmcValue *right) {
      if (left == right) return 1;
      if (!left || !right) return 0;
      if (left->tag != right->tag) {
        if ((left->tag == ELMC_TAG_INT || left->tag == ELMC_TAG_BOOL) &&
            (right->tag == ELMC_TAG_INT || right->tag == ELMC_TAG_BOOL)) {
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
          return elmc_as_int(left) == elmc_as_int(right);

        case ELMC_TAG_FLOAT:
          return elmc_as_float(left) == elmc_as_float(right);

        case ELMC_TAG_STRING:
          if (!left->payload || !right->payload) return left->payload == right->payload;
          return strcmp((const char *)left->payload, (const char *)right->payload) == 0;

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

        case ELMC_TAG_TUPLE2: {
          if (!left->payload || !right->payload) return left->payload == right->payload;
          ElmcTuple2 *a = (ElmcTuple2 *)left->payload;
          ElmcTuple2 *b = (ElmcTuple2 *)right->payload;
          return elmc_value_equal(a->first, b->first) && elmc_value_equal(a->second, b->second);
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
          for (int i = 0; i < a->field_count; i++) {
            int found = 0;
            for (int j = 0; j < b->field_count; j++) {
              if (strcmp(a->field_names[i], b->field_names[j]) == 0) {
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
      return (int)strlen((const char *)value->payload);
    }

    ElmcValue *elmc_list_head(ElmcValue *list) {
      if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) return elmc_maybe_nothing();
      ElmcCons *node = (ElmcCons *)list->payload;
      return elmc_maybe_just(node->head);
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

    ElmcValue *elmc_result_inc_or_zero(ElmcValue *result) {
      if (!result || result->tag != ELMC_TAG_RESULT || result->payload == NULL) return elmc_int_zero();
      ElmcResult *data = (ElmcResult *)result->payload;
      if (!data->is_ok || !data->value) return elmc_int_zero();
      return elmc_new_int(elmc_as_int(data->value) + 1);
    }

    ElmcValue *elmc_basics_max(ElmcValue *left, ElmcValue *right) {
      ElmcValue *cmp = elmc_basics_compare(left, right);
      int take_left = elmc_as_int(cmp) >= 0;
      elmc_release(cmp);
      return take_left ? elmc_retain(left) : elmc_retain(right);
    }

    ElmcValue *elmc_basics_min(ElmcValue *left, ElmcValue *right) {
      ElmcValue *cmp = elmc_basics_compare(left, right);
      int take_left = elmc_as_int(cmp) <= 0;
      elmc_release(cmp);
      return take_left ? elmc_retain(left) : elmc_retain(right);
    }

    ElmcValue *elmc_basics_clamp(ElmcValue *low, ElmcValue *high, ElmcValue *value) {
      ElmcValue *below = elmc_basics_compare(value, low);
      if (elmc_as_int(below) < 0) {
        elmc_release(below);
        return elmc_retain(low);
      }
      elmc_release(below);

      ElmcValue *above = elmc_basics_compare(value, high);
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
      return elmc_new_int(result);
    }

    ElmcValue *elmc_bitwise_and(ElmcValue *left, ElmcValue *right) {
      return elmc_new_int(elmc_as_int(left) & elmc_as_int(right));
    }

    ElmcValue *elmc_bitwise_or(ElmcValue *left, ElmcValue *right) {
      return elmc_new_int(elmc_as_int(left) | elmc_as_int(right));
    }

    ElmcValue *elmc_bitwise_xor(ElmcValue *left, ElmcValue *right) {
      return elmc_new_int(elmc_as_int(left) ^ elmc_as_int(right));
    }

    ElmcValue *elmc_bitwise_complement(ElmcValue *value) {
      return elmc_new_int(~elmc_as_int(value));
    }

    ElmcValue *elmc_bitwise_shift_left_by(ElmcValue *bits, ElmcValue *value) {
      int64_t b = elmc_as_int(bits);
      if (b < 0) b = 0;
      return elmc_new_int(elmc_as_int(value) << b);
    }

    ElmcValue *elmc_bitwise_shift_right_by(ElmcValue *bits, ElmcValue *value) {
      int64_t b = elmc_as_int(bits);
      if (b < 0) b = 0;
      return elmc_new_int(elmc_as_int(value) >> b);
    }

    ElmcValue *elmc_bitwise_shift_right_zf_by(ElmcValue *bits, ElmcValue *value) {
      int64_t b = elmc_as_int(bits);
      if (b < 0) b = 0;
      uint64_t raw = (uint64_t)elmc_as_int(value);
      return elmc_new_int((int64_t)(raw >> b));
    }

    ElmcValue *elmc_char_to_code(ElmcValue *value) {
      return elmc_new_int(elmc_as_int(value));
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

    ElmcValue *elmc_debug_to_string(ElmcValue *value) {
      if (!value) return elmc_new_string("<null>");
      if (value->tag == ELMC_TAG_STRING) return elmc_retain(value);

      char buffer[64];
      if (value->tag == ELMC_TAG_BOOL) {
        return elmc_new_string(elmc_as_int(value) ? "True" : "False");
      }

      if (value->tag == ELMC_TAG_FLOAT) {
        snprintf(buffer, sizeof(buffer), "%g", elmc_as_float(value));
        return elmc_new_string(buffer);
      }

      snprintf(buffer, sizeof(buffer), "%lld", (long long)elmc_as_int(value));
      return elmc_new_string(buffer);
    }

    ElmcValue *elmc_string_append(ElmcValue *left, ElmcValue *right) {
      const char *a = (left && left->tag == ELMC_TAG_STRING && left->payload) ? (const char *)left->payload : "";
      const char *b = (right && right->tag == ELMC_TAG_STRING && right->payload) ? (const char *)right->payload : "";
      return elmc_string_append_native(a, b);
    }

    ElmcValue *elmc_string_append_native(const char *left, const char *right) {
      const char *a = left ? left : "";
      const char *b = right ? right : "";
      size_t len_a = strlen(a);
      size_t len_b = strlen(b);
      char *out = (char *)elmc_malloc(len_a + len_b + 1, __func__);
      if (!out) return &ELMC_EMPTY_STRING;
      memcpy(out, a, len_a);
      memcpy(out + len_a, b, len_b);
      out[len_a + len_b] = '\\0';
      ElmcValue *result = elmc_alloc(ELMC_TAG_STRING, out);
      if (!result) free(out);
      return result;
    }

    ElmcValue *elmc_append(ElmcValue *left, ElmcValue *right) {
      if ((left && left->tag == ELMC_TAG_STRING) || (right && right->tag == ELMC_TAG_STRING)) {
        return elmc_string_append(left, right);
      }
      return elmc_list_append(left, right);
    }

    ElmcValue *elmc_string_is_empty(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_STRING || value->payload == NULL) return elmc_new_bool(1);
      return elmc_new_bool(strlen((const char *)value->payload) == 0);
    }

    ElmcValue *elmc_dict_from_list(ElmcValue *items) {
      ElmcValue *out = elmc_list_nil();
      ElmcValue *cursor = items;

      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *entry = node->head;
        if (entry && entry->tag == ELMC_TAG_TUPLE2 && entry->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)entry->payload;
          ElmcValue *next = elmc_dict_insert(pair->first, pair->second, out);
          elmc_release(out);
          out = next;
        }
        cursor = node->tail;
      }

      return out;
    }

    ElmcValue *elmc_dict_insert(ElmcValue *key, ElmcValue *value, ElmcValue *dict) {
      int64_t wanted = elmc_as_int(key);
      ElmcValue *cursor = dict;
      ElmcValue *rev = elmc_list_nil();
      int inserted = 0;

      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *head = node->head;
        int owns_head = 0;
        int skip = 0;

        if (head && head->tag == ELMC_TAG_TUPLE2 && head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)head->payload;
          if (pair->first && elmc_as_int(pair->first) == wanted) {
            if (!inserted) {
              head = elmc_tuple2(key, value);
              owns_head = 1;
              inserted = 1;
            } else {
              skip = 1;
            }
          }
        }

        if (!skip) {
          ElmcValue *next_rev = elmc_list_cons(head, rev);
          if (owns_head) elmc_release(head);
          elmc_release(rev);
          rev = next_rev;
        } else if (owns_head) {
          elmc_release(head);
        }

        cursor = node->tail;
      }

      if (!inserted) {
        ElmcValue *pair = elmc_tuple2(key, value);
        ElmcValue *next_rev = elmc_list_cons(pair, rev);
        elmc_release(pair);
        elmc_release(rev);
        rev = next_rev;
      }

      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_dict_get(ElmcValue *key, ElmcValue *dict) {
      int64_t wanted = elmc_as_int(key);
      ElmcValue *cursor = dict;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
          if (pair->first && elmc_as_int(pair->first) == wanted) {
            return elmc_maybe_just(pair->second);
          }
        }
        cursor = node->tail;
      }
      return elmc_maybe_nothing();
    }

    ElmcValue *elmc_dict_member(ElmcValue *key, ElmcValue *dict) {
      ElmcValue *found = elmc_dict_get(key, dict);
      int present = 0;
      if (found && found->tag == ELMC_TAG_MAYBE && found->payload != NULL) {
        present = ((ElmcMaybe *)found->payload)->is_just;
      }
      elmc_release(found);
      return elmc_new_bool(present);
    }

    ElmcValue *elmc_dict_size(ElmcValue *dict) {
      int64_t size = 0;
      ElmcValue *cursor = dict;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        size += 1;
        cursor = ((ElmcCons *)cursor->payload)->tail;
      }
      return elmc_new_int(size);
    }

    ElmcValue *elmc_set_from_list(ElmcValue *items) {
      ElmcValue *out = elmc_list_nil();
      ElmcValue *cursor = items;

      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *next = elmc_set_insert(node->head, out);
        elmc_release(out);
        out = next;
        cursor = node->tail;
      }

      return out;
    }

    ElmcValue *elmc_set_member(ElmcValue *value, ElmcValue *set) {
      int64_t wanted = elmc_as_int(value);
      ElmcValue *cursor = set;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (elmc_as_int(node->head) == wanted) return elmc_new_bool(1);
        cursor = node->tail;
      }
      return elmc_new_bool(0);
    }

    ElmcValue *elmc_set_insert(ElmcValue *value, ElmcValue *set) {
      ElmcValue *exists = elmc_set_member(value, set);
      int present = elmc_as_int(exists) != 0;
      elmc_release(exists);
      if (present) return elmc_retain(set);
      ElmcValue *tail = set;
      int created_tail = 0;
      if (!tail) {
        tail = elmc_list_nil();
        created_tail = 1;
      }
      ElmcValue *out = elmc_list_cons(value, tail);
      if (created_tail) elmc_release(tail);
      return out;
    }

    ElmcValue *elmc_set_size(ElmcValue *set) {
      int64_t size = 0;
      ElmcValue *cursor = set;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        size += 1;
        cursor = ((ElmcCons *)cursor->payload)->tail;
      }
      return elmc_new_int(size);
    }

    ElmcValue *elmc_array_empty(void) {
      return elmc_list_nil();
    }

    ElmcValue *elmc_array_from_list(ElmcValue *items) {
      return elmc_retain(items);
    }

    ElmcValue *elmc_array_length(ElmcValue *array) {
      return elmc_set_size(array);
    }

    ElmcValue *elmc_array_get(ElmcValue *index, ElmcValue *array) {
      int64_t wanted = elmc_as_int(index);
      if (wanted < 0) return elmc_maybe_nothing();

      int64_t i = 0;
      ElmcValue *cursor = array;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (i == wanted) return elmc_maybe_just(node->head);
        i += 1;
        cursor = node->tail;
      }
      return elmc_maybe_nothing();
    }

    ElmcValue *elmc_array_set(ElmcValue *index, ElmcValue *value, ElmcValue *array) {
      int64_t wanted = elmc_as_int(index);
      if (wanted < 0) return elmc_retain(array);

      int64_t i = 0;
      int replaced = 0;
      ElmcValue *cursor = array;
      ElmcValue *rev = elmc_list_nil();

      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *item = (i == wanted) ? value : node->head;
        if (i == wanted) replaced = 1;
        ElmcValue *next_rev = elmc_list_cons(item, rev);
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
      ElmcValue *with_tail = elmc_list_cons(value, rev);
      elmc_release(rev);
      ElmcValue *out = elmc_list_reverse_copy(with_tail);
      elmc_release(with_tail);
      return out;
    }

    ElmcValue *elmc_task_succeed(ElmcValue *value) {
      return elmc_result_ok(value);
    }

    ElmcValue *elmc_task_fail(ElmcValue *value) {
      return elmc_result_err(value);
    }

    ElmcValue *elmc_process_spawn(ElmcValue *task) {
      ElmcProcessSlot *slot = elmc_process_alloc_slot();
      int64_t pid_raw = slot ? slot->pid : 0;
      if (slot) {
        slot->task = elmc_retain(task);
      #ifdef ELMC_PEBBLE_PLATFORM
        slot->timer = app_timer_register(1, elmc_process_spawn_timer_cb, slot);
      #else
        elmc_process_release_slot(slot);
      #endif
      }
      ElmcValue *pid = elmc_new_int(pid_raw);
      ElmcValue *out = elmc_result_ok(pid);
      elmc_release(pid);
      return out;
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
      ElmcValue *out = elmc_result_ok(unit);
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
      ElmcValue *out = elmc_result_ok(unit);
      elmc_release(unit);
      return out;
    }

    ElmcValue *elmc_time_now_millis(void) {
      int64_t millis = (int64_t)time(NULL) * 1000;
      return elmc_new_int(millis);
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
      return elmc_new_int((int64_t)offset);
    }

    ElmcValue *elmc_cmd_backlight_from_maybe(ElmcValue *maybe_mode) {
      int64_t mode = 0; /* 0 = interaction, 1 = disable, 2 = enable */

      if (maybe_mode) {
        if (maybe_mode->tag == ELMC_TAG_MAYBE && maybe_mode->payload != NULL) {
          ElmcMaybe *maybe = (ElmcMaybe *)maybe_mode->payload;
          if (maybe->is_just && maybe->value) {
            mode = elmc_as_int(maybe->value) != 0 ? 2 : 1;
          }
        } else if (maybe_mode->tag == ELMC_TAG_TUPLE2 && maybe_mode->payload != NULL) {
          ElmcTuple2 *tuple = (ElmcTuple2 *)maybe_mode->payload;
          int64_t ctor_tag = tuple->first ? elmc_as_int(tuple->first) : 0;
          if (ctor_tag == 1 && tuple->second) {
            mode = elmc_as_int(tuple->second) != 0 ? 2 : 1;
          }
        }
      }

      ElmcValue *kind = elmc_new_int(6);
      ElmcValue *p0 = elmc_new_int(mode);
      ElmcValue *p1 = elmc_int_zero();
      ElmcValue *p2 = elmc_int_zero();
      ElmcValue *p3 = elmc_int_zero();
      ElmcValue *p4 = elmc_int_zero();
      ElmcValue *p5 = elmc_int_zero();
      ElmcValue *tail0 = elmc_tuple2(p4, p5);
      ElmcValue *tail1 = elmc_tuple2(p3, tail0);
      ElmcValue *tail2 = elmc_tuple2(p2, tail1);
      ElmcValue *tail3 = elmc_tuple2(p1, tail2);
      ElmcValue *tail4 = elmc_tuple2(p0, tail3);
      ElmcValue *command = elmc_tuple2(kind, tail4);

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

    ElmcValue *elmc_new_float(double value) {
      double *ptr = (double *)elmc_malloc(sizeof(double), __func__);
      if (!ptr) return NULL;
      *ptr = value;
      return elmc_alloc(ELMC_TAG_FLOAT, ptr);
    }

    double elmc_as_float(ElmcValue *value) {
      if (!value) return 0.0;
      if (value->tag == ELMC_TAG_FLOAT) return *((double *)value->payload);
      if (value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) return (double)elmc_as_int(value);
      return 0.0;
    }

    ElmcValue *elmc_record_new(int field_count, const char **field_names, ElmcValue **field_values) {
      ElmcRecord *record = (ElmcRecord *)elmc_malloc(sizeof(ElmcRecord), __func__);
      if (!record) return NULL;
      record->field_count = field_count;
      record->field_names = (const char **)elmc_malloc(sizeof(const char *) * field_count, __func__);
      record->field_values = (ElmcValue **)elmc_malloc(sizeof(ElmcValue *) * field_count, __func__);
      if (!record->field_names || !record->field_values) {
        free(record->field_names);
        free(record->field_values);
        free(record);
        return NULL;
      }
      for (int i = 0; i < field_count; i++) {
        size_t len = strlen(field_names[i]);
        char *name_copy = (char *)elmc_malloc(len + 1, __func__);
        if (name_copy) { memcpy(name_copy, field_names[i], len + 1); }
        record->field_names[i] = name_copy;
        record->field_values[i] = elmc_retain(field_values[i]);
      }
      return elmc_alloc(ELMC_TAG_RECORD, record);
    }

    ElmcValue *elmc_record_new_take(int field_count, const char **field_names, ElmcValue **field_values) {
      ElmcRecord *record = (ElmcRecord *)elmc_malloc(sizeof(ElmcRecord), __func__);
      if (!record) return NULL;
      record->field_count = field_count;
      record->field_names = (const char **)elmc_malloc(sizeof(const char *) * field_count, __func__);
      record->field_values = (ElmcValue **)elmc_malloc(sizeof(ElmcValue *) * field_count, __func__);
      if (!record->field_names || !record->field_values) {
        free(record->field_names);
        free(record->field_values);
        free(record);
        for (int i = 0; i < field_count; i++) {
          elmc_release(field_values[i]);
        }
        return NULL;
      }
      for (int i = 0; i < field_count; i++) {
        size_t len = strlen(field_names[i]);
        char *name_copy = (char *)elmc_malloc(len + 1, __func__);
        if (name_copy) { memcpy(name_copy, field_names[i], len + 1); }
        record->field_names[i] = name_copy;
        record->field_values[i] = field_values[i];
      }
      return elmc_alloc(ELMC_TAG_RECORD, record);
    }

    ElmcValue *elmc_record_new_ints(int field_count, const char **field_names, const elmc_int_t *field_values) {
      ElmcValue *values[field_count];
      for (int i = 0; i < field_count; i++) {
        values[i] = elmc_new_int(field_values[i]);
      }
      return elmc_record_new_take(field_count, field_names, values);
    }

    ElmcValue *elmc_record_get(ElmcValue *record, const char *field_name) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_int_zero();
      ElmcRecord *rec = (ElmcRecord *)record->payload;
      for (int i = 0; i < rec->field_count; i++) {
        if (rec->field_names[i] && strcmp(rec->field_names[i], field_name) == 0) {
          return elmc_retain(rec->field_values[i]);
        }
      }
      return elmc_int_zero();
    }

    ElmcValue *elmc_record_get_at(ElmcValue *record, int index, const char *field_name) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_int_zero();
      ElmcRecord *rec = (ElmcRecord *)record->payload;
      if (index >= 0 && index < rec->field_count && rec->field_names[index] &&
          strcmp(rec->field_names[index], field_name) == 0) {
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
      for (int i = 0; i < rec->field_count; i++) {
        if (rec->field_names[i] && strcmp(rec->field_names[i], field_name) == 0) {
          return elmc_as_int(rec->field_values[i]);
        }
      }
      return 0;
    }

    elmc_int_t elmc_record_get_at_int(ElmcValue *record, int index, const char *field_name) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return 0;
      ElmcRecord *rec = (ElmcRecord *)record->payload;
      if (index >= 0 && index < rec->field_count && rec->field_names[index] &&
          strcmp(rec->field_names[index], field_name) == 0) {
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
      for (int i = 0; i < rec->field_count; i++) {
        if (rec->field_names[i] && strcmp(rec->field_names[i], field_name) == 0) {
          return elmc_maybe_with_default_int(default_val, rec->field_values[i]);
        }
      }
      return default_val;
    }

    elmc_int_t elmc_record_get_at_maybe_int(ElmcValue *record, int index, const char *field_name, elmc_int_t default_val) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return default_val;
      ElmcRecord *rec = (ElmcRecord *)record->payload;
      if (index >= 0 && index < rec->field_count && rec->field_names[index] &&
          strcmp(rec->field_names[index], field_name) == 0) {
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

    ElmcValue *elmc_record_update(ElmcValue *record, const char *field_name, ElmcValue *new_value) {
      if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_retain(record);
      ElmcRecord *old = (ElmcRecord *)record->payload;
      const char **names = (const char **)elmc_malloc(sizeof(const char *) * old->field_count, __func__);
      ElmcValue **values = (ElmcValue **)elmc_malloc(sizeof(ElmcValue *) * old->field_count, __func__);
      if (!names || !values) { free(names); free(values); return elmc_retain(record); }
      for (int i = 0; i < old->field_count; i++) {
        names[i] = old->field_names[i];
        if (old->field_names[i] && strcmp(old->field_names[i], field_name) == 0) {
          values[i] = new_value;
        } else {
          values[i] = old->field_values[i];
        }
      }
      ElmcValue *result = elmc_record_new(old->field_count, names, values);
      free(names);
      free(values);
      return result;
    }

    ElmcValue *elmc_closure_new(ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count), int arity, int capture_count, ElmcValue **captures) {
      ElmcClosure *clo = (ElmcClosure *)elmc_malloc(sizeof(ElmcClosure), __func__);
      if (!clo) return NULL;
      clo->fn = fn;
      clo->arity = arity;
      clo->capture_count = capture_count;
      clo->captures = NULL;
      if (capture_count > 0) {
        clo->captures = (ElmcValue **)elmc_malloc(sizeof(ElmcValue *) * capture_count, __func__);
        if (!clo->captures) { free(clo); return NULL; }
        for (int i = 0; i < capture_count; i++) {
          clo->captures[i] = elmc_retain(captures[i]);
        }
      }
      return elmc_alloc(ELMC_TAG_CLOSURE, clo);
    }

    ElmcValue *elmc_closure_call(ElmcValue *closure, ElmcValue **args, int argc) {
      if (!closure || closure->tag != ELMC_TAG_CLOSURE || !closure->payload) return elmc_int_zero();
      ElmcClosure *clo = (ElmcClosure *)closure->payload;
      int consumed = argc;
      if (clo->arity > 0 && argc > clo->arity) {
        consumed = clo->arity;
      }
      ElmcValue *result = clo->fn(args, consumed, clo->captures, clo->capture_count);
      if (consumed < argc) {
        ElmcValue *next = elmc_closure_call(result, args + consumed, argc - consumed);
        elmc_release(result);
        return next;
      }
      return result;
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

    /* ================================================================
       Standard Library – List operations
       ================================================================ */

    ElmcValue *elmc_list_tail(ElmcValue *list) {
      if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) return elmc_maybe_nothing();
      ElmcCons *node = (ElmcCons *)list->payload;
      return elmc_maybe_just(node->tail);
    }

    ElmcValue *elmc_list_is_empty(ElmcValue *list) {
      if (!list || list->tag != ELMC_TAG_LIST) return elmc_new_bool(1);
      return elmc_new_bool(list->payload == NULL);
    }

    ElmcValue *elmc_list_length(ElmcValue *list) {
      int64_t count = 0;
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        count += 1;
        cursor = ((ElmcCons *)cursor->payload)->tail;
      }
      return elmc_new_int(count);
    }

    ElmcValue *elmc_list_reverse(ElmcValue *list) {
      return elmc_list_reverse_copy(list);
    }

    ElmcValue *elmc_list_member(ElmcValue *value, ElmcValue *list) {
      int64_t wanted = elmc_as_int(value);
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (elmc_as_int(node->head) == wanted) return elmc_new_bool(1);
        cursor = node->tail;
      }
      return elmc_new_bool(0);
    }

    ElmcValue *elmc_list_map(ElmcValue *f, ElmcValue *list) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[1] = { node->head };
        ElmcValue *mapped = elmc_closure_call(f, args, 1);
        ElmcValue *next = elmc_list_cons(mapped, rev);
        elmc_release(mapped);
        elmc_release(rev);
        rev = next;
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_list_filter(ElmcValue *f, ElmcValue *list) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[1] = { node->head };
        ElmcValue *keep = elmc_closure_call(f, args, 1);
        if (elmc_as_int(keep)) {
          ElmcValue *next = elmc_list_cons(node->head, rev);
          elmc_release(rev);
          rev = next;
        }
        elmc_release(keep);
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_list_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *list) {
      ElmcValue *result = elmc_retain(acc);
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[2] = { node->head, result };
        ElmcValue *next = elmc_closure_call(f, args, 2);
        elmc_release(result);
        result = next;
        cursor = node->tail;
      }
      return result;
    }

    ElmcValue *elmc_list_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *list) {
      ElmcValue *reversed = elmc_list_reverse_copy(list);
      ElmcValue *result = elmc_retain(acc);
      ElmcValue *cursor = reversed;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[2] = { node->head, result };
        ElmcValue *next = elmc_closure_call(f, args, 2);
        elmc_release(result);
        result = next;
        cursor = node->tail;
      }
      elmc_release(reversed);
      return result;
    }

    ElmcValue *elmc_list_append(ElmcValue *a, ElmcValue *b) {
      ElmcValue *rev_a = elmc_list_reverse_copy(a);
      ElmcValue *out = elmc_retain(b);
      ElmcValue *cursor = rev_a;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *next = elmc_list_cons(node->head, out);
        elmc_release(out);
        out = next;
        cursor = node->tail;
      }
      elmc_release(rev_a);
      return out;
    }

    ElmcValue *elmc_list_concat(ElmcValue *lists) {
      ElmcValue *rev_lists = elmc_list_reverse_copy(lists);
      ElmcValue *out = elmc_list_nil();
      ElmcValue *cursor = rev_lists;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *merged = elmc_list_append(node->head, out);
        elmc_release(out);
        out = merged;
        cursor = node->tail;
      }
      elmc_release(rev_lists);
      return out;
    }

    ElmcValue *elmc_list_concat_map(ElmcValue *f, ElmcValue *list) {
      ElmcValue *mapped = elmc_list_map(f, list);
      ElmcValue *out = elmc_list_concat(mapped);
      elmc_release(mapped);
      return out;
    }

    ElmcValue *elmc_list_indexed_map(ElmcValue *f, ElmcValue *list) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = list;
      int64_t idx = 0;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *index_val = elmc_new_int(idx);
        ElmcValue *args[2] = { index_val, node->head };
        ElmcValue *mapped = elmc_closure_call(f, args, 2);
        elmc_release(index_val);
        ElmcValue *next = elmc_list_cons(mapped, rev);
        elmc_release(mapped);
        elmc_release(rev);
        rev = next;
        idx += 1;
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_list_filter_map(ElmcValue *f, ElmcValue *list) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[1] = { node->head };
        ElmcValue *maybe_val = elmc_closure_call(f, args, 1);
        if (maybe_val && maybe_val->tag == ELMC_TAG_MAYBE && maybe_val->payload != NULL) {
          ElmcMaybe *m = (ElmcMaybe *)maybe_val->payload;
          if (m->is_just && m->value) {
            ElmcValue *next = elmc_list_cons(m->value, rev);
            elmc_release(rev);
            rev = next;
          }
        }
        elmc_release(maybe_val);
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_list_sum(ElmcValue *list) {
      int64_t sum = 0;
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        sum += elmc_as_int(node->head);
        cursor = node->tail;
      }
      return elmc_new_int(sum);
    }

    ElmcValue *elmc_list_product(ElmcValue *list) {
      int64_t prod = 1;
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        prod *= elmc_as_int(node->head);
        cursor = node->tail;
      }
      return elmc_new_int(prod);
    }

    ElmcValue *elmc_list_maximum(ElmcValue *list) {
      if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) return elmc_maybe_nothing();
      ElmcCons *first = (ElmcCons *)list->payload;
      int64_t best = elmc_as_int(first->head);
      ElmcValue *cursor = first->tail;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        int64_t v = elmc_as_int(node->head);
        if (v > best) best = v;
        cursor = node->tail;
      }
      ElmcValue *val = elmc_new_int(best);
      ElmcValue *out = elmc_maybe_just(val);
      elmc_release(val);
      return out;
    }

    ElmcValue *elmc_list_minimum(ElmcValue *list) {
      if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) return elmc_maybe_nothing();
      ElmcCons *first = (ElmcCons *)list->payload;
      int64_t best = elmc_as_int(first->head);
      ElmcValue *cursor = first->tail;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        int64_t v = elmc_as_int(node->head);
        if (v < best) best = v;
        cursor = node->tail;
      }
      ElmcValue *val = elmc_new_int(best);
      ElmcValue *out = elmc_maybe_just(val);
      elmc_release(val);
      return out;
    }

    ElmcValue *elmc_list_any(ElmcValue *f, ElmcValue *list) {
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[1] = { node->head };
        ElmcValue *result = elmc_closure_call(f, args, 1);
        int truthy = elmc_as_int(result) != 0;
        elmc_release(result);
        if (truthy) return elmc_new_bool(1);
        cursor = node->tail;
      }
      return elmc_new_bool(0);
    }

    ElmcValue *elmc_list_all(ElmcValue *f, ElmcValue *list) {
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[1] = { node->head };
        ElmcValue *result = elmc_closure_call(f, args, 1);
        int truthy = elmc_as_int(result) != 0;
        elmc_release(result);
        if (!truthy) return elmc_new_bool(0);
        cursor = node->tail;
      }
      return elmc_new_bool(1);
    }

    ElmcValue *elmc_list_sort(ElmcValue *list) {
      /* Simple insertion sort for embedded use */
      ElmcValue *sorted = elmc_list_nil();
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        int64_t val = elmc_as_int(node->head);
        /* Insert val into sorted list in order */
        ElmcValue *rev_before = elmc_list_nil();
        ElmcValue *rest = sorted;
        int inserted = 0;
        while (rest && rest->tag == ELMC_TAG_LIST && rest->payload != NULL) {
          ElmcCons *sn = (ElmcCons *)rest->payload;
          if (!inserted && val <= elmc_as_int(sn->head)) {
            ElmcValue *new_node = elmc_list_cons(node->head, rest);
            /* rebuild from rev_before */
            ElmcValue *rebuilt = new_node;
            ElmcValue *rb_cursor = rev_before;
            while (rb_cursor && rb_cursor->tag == ELMC_TAG_LIST && rb_cursor->payload != NULL) {
              ElmcCons *rbn = (ElmcCons *)rb_cursor->payload;
              ElmcValue *tmp = elmc_list_cons(rbn->head, rebuilt);
              elmc_release(rebuilt);
              rebuilt = tmp;
              rb_cursor = rbn->tail;
            }
            elmc_release(rev_before);
            elmc_release(sorted);
            sorted = rebuilt;
            inserted = 1;
            break;
          }
          ElmcValue *next_rb = elmc_list_cons(sn->head, rev_before);
          elmc_release(rev_before);
          rev_before = next_rb;
          rest = sn->tail;
        }
        if (!inserted) {
          /* append at end */
          ElmcValue *new_tail = elmc_list_cons(node->head, elmc_list_nil());
          /* rebuild from rev_before onto new_tail */
          ElmcValue *rebuilt = new_tail;
          ElmcValue *rb_cursor = rev_before;
          while (rb_cursor && rb_cursor->tag == ELMC_TAG_LIST && rb_cursor->payload != NULL) {
            ElmcCons *rbn = (ElmcCons *)rb_cursor->payload;
            ElmcValue *tmp = elmc_list_cons(rbn->head, rebuilt);
            elmc_release(rebuilt);
            rebuilt = tmp;
            rb_cursor = rbn->tail;
          }
          elmc_release(rev_before);
          elmc_release(sorted);
          sorted = rebuilt;
        }
        cursor = node->tail;
      }
      return sorted;
    }

    ElmcValue *elmc_list_sort_by(ElmcValue *f, ElmcValue *list) {
      (void)f;
      /* Stub: return copy of list */
      return elmc_list_reverse_copy(elmc_list_reverse_copy(list));
    }

    ElmcValue *elmc_list_sort_with(ElmcValue *f, ElmcValue *list) {
      (void)f;
      /* Stub: return copy of list */
      return elmc_list_reverse_copy(elmc_list_reverse_copy(list));
    }

    ElmcValue *elmc_list_singleton(ElmcValue *value) {
      ElmcValue *nil = elmc_list_nil();
      ElmcValue *out = elmc_list_cons(value, nil);
      elmc_release(nil);
      return out;
    }

    ElmcValue *elmc_list_range(ElmcValue *lo, ElmcValue *hi) {
      int64_t low = elmc_as_int(lo);
      int64_t high = elmc_as_int(hi);
      ElmcValue *out = elmc_list_nil();
      for (int64_t i = high; i >= low; i--) {
        ElmcValue *val = elmc_new_int(i);
        ElmcValue *next = elmc_list_cons(val, out);
        elmc_release(val);
        elmc_release(out);
        out = next;
      }
      return out;
    }

    ElmcValue *elmc_list_repeat(ElmcValue *n, ElmcValue *value) {
      int64_t count = elmc_as_int(n);
      ElmcValue *out = elmc_list_nil();
      for (int64_t i = 0; i < count; i++) {
        ElmcValue *next = elmc_list_cons(value, out);
        elmc_release(out);
        out = next;
      }
      return out;
    }

    ElmcValue *elmc_list_take(ElmcValue *n, ElmcValue *list) {
      int64_t count = elmc_as_int(n);
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = list;
      int64_t i = 0;
      while (i < count && cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *next = elmc_list_cons(node->head, rev);
        elmc_release(rev);
        rev = next;
        cursor = node->tail;
        i++;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_list_drop(ElmcValue *n, ElmcValue *list) {
      int64_t count = elmc_as_int(n);
      ElmcValue *cursor = list;
      int64_t i = 0;
      while (i < count && cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        cursor = ((ElmcCons *)cursor->payload)->tail;
        i++;
      }
      /* Copy the remainder */
      ElmcValue *rev = elmc_list_nil();
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *next = elmc_list_cons(node->head, rev);
        elmc_release(rev);
        rev = next;
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_list_partition(ElmcValue *f, ElmcValue *list) {
      ElmcValue *rev_yes = elmc_list_nil();
      ElmcValue *rev_no = elmc_list_nil();
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[1] = { node->head };
        ElmcValue *keep = elmc_closure_call(f, args, 1);
        if (elmc_as_int(keep)) {
          ElmcValue *next = elmc_list_cons(node->head, rev_yes);
          elmc_release(rev_yes);
          rev_yes = next;
        } else {
          ElmcValue *next = elmc_list_cons(node->head, rev_no);
          elmc_release(rev_no);
          rev_no = next;
        }
        elmc_release(keep);
        cursor = node->tail;
      }
      ElmcValue *yes = elmc_list_reverse_copy(rev_yes);
      ElmcValue *no = elmc_list_reverse_copy(rev_no);
      elmc_release(rev_yes);
      elmc_release(rev_no);
      ElmcValue *out = elmc_tuple2(yes, no);
      elmc_release(yes);
      elmc_release(no);
      return out;
    }

    ElmcValue *elmc_list_unzip(ElmcValue *list) {
      ElmcValue *rev_a = elmc_list_nil();
      ElmcValue *rev_b = elmc_list_nil();
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
          ElmcValue *na = elmc_list_cons(pair->first, rev_a);
          elmc_release(rev_a);
          rev_a = na;
          ElmcValue *nb = elmc_list_cons(pair->second, rev_b);
          elmc_release(rev_b);
          rev_b = nb;
        }
        cursor = node->tail;
      }
      ElmcValue *a = elmc_list_reverse_copy(rev_a);
      ElmcValue *b = elmc_list_reverse_copy(rev_b);
      elmc_release(rev_a);
      elmc_release(rev_b);
      ElmcValue *out = elmc_tuple2(a, b);
      elmc_release(a);
      elmc_release(b);
      return out;
    }

    ElmcValue *elmc_list_intersperse(ElmcValue *sep, ElmcValue *list) {
      if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) return elmc_list_nil();
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = list;
      int first = 1;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (!first) {
          ElmcValue *ns = elmc_list_cons(sep, rev);
          elmc_release(rev);
          rev = ns;
        }
        ElmcValue *nh = elmc_list_cons(node->head, rev);
        elmc_release(rev);
        rev = nh;
        first = 0;
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_list_map2(ElmcValue *f, ElmcValue *a, ElmcValue *b) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *ca = a;
      ElmcValue *cb = b;
      while (ca && ca->tag == ELMC_TAG_LIST && ca->payload != NULL &&
             cb && cb->tag == ELMC_TAG_LIST && cb->payload != NULL) {
        ElmcCons *na = (ElmcCons *)ca->payload;
        ElmcCons *nb = (ElmcCons *)cb->payload;
        ElmcValue *args[2] = { na->head, nb->head };
        ElmcValue *mapped = elmc_closure_call(f, args, 2);
        ElmcValue *next = elmc_list_cons(mapped, rev);
        elmc_release(mapped);
        elmc_release(rev);
        rev = next;
        ca = na->tail;
        cb = nb->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_list_map3(ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c) {
      ElmcValue *rev = elmc_list_nil();
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
        ElmcValue *mapped = elmc_closure_call(f, args, 3);
        ElmcValue *next = elmc_list_cons(mapped, rev);
        elmc_release(mapped);
        elmc_release(rev);
        rev = next;
        ca = na->tail;
        cb = nb->tail;
        cc = nc->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
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

    ElmcValue *elmc_maybe_map(ElmcValue *f, ElmcValue *maybe) {
      if (!maybe || maybe->tag != ELMC_TAG_MAYBE) return elmc_maybe_nothing();
      ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
      if (!m->is_just || !m->value) return elmc_maybe_nothing();
      ElmcValue *args[1] = { m->value };
      ElmcValue *mapped = elmc_closure_call(f, args, 1);
      ElmcValue *out = elmc_maybe_just(mapped);
      elmc_release(mapped);
      return out;
    }

    ElmcValue *elmc_maybe_map2(ElmcValue *f, ElmcValue *a, ElmcValue *b) {
      if (!a || a->tag != ELMC_TAG_MAYBE || !b || b->tag != ELMC_TAG_MAYBE) return elmc_maybe_nothing();
      ElmcMaybe *ma = (ElmcMaybe *)a->payload;
      ElmcMaybe *mb = (ElmcMaybe *)b->payload;
      if (!ma->is_just || !ma->value || !mb->is_just || !mb->value) return elmc_maybe_nothing();
      ElmcValue *args[2] = { ma->value, mb->value };
      ElmcValue *mapped = elmc_closure_call(f, args, 2);
      ElmcValue *out = elmc_maybe_just(mapped);
      elmc_release(mapped);
      return out;
    }

    ElmcValue *elmc_maybe_and_then(ElmcValue *f, ElmcValue *maybe) {
      if (!maybe || maybe->tag != ELMC_TAG_MAYBE) return elmc_maybe_nothing();
      ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
      if (!m->is_just || !m->value) return elmc_maybe_nothing();
      ElmcValue *args[1] = { m->value };
      return elmc_closure_call(f, args, 1);
    }

    /* ================================================================
       Standard Library – Result operations
       ================================================================ */

    ElmcValue *elmc_result_map(ElmcValue *f, ElmcValue *result) {
      if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) return elmc_result_err(elmc_new_string("invalid"));
      ElmcResult *r = (ElmcResult *)result->payload;
      if (!r->is_ok) return elmc_retain(result);
      ElmcValue *args[1] = { r->value };
      ElmcValue *mapped = elmc_closure_call(f, args, 1);
      ElmcValue *out = elmc_result_ok(mapped);
      elmc_release(mapped);
      return out;
    }

    ElmcValue *elmc_result_map_error(ElmcValue *f, ElmcValue *result) {
      if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) return elmc_retain(result);
      ElmcResult *r = (ElmcResult *)result->payload;
      if (r->is_ok) return elmc_retain(result);
      ElmcValue *args[1] = { r->value };
      ElmcValue *mapped = elmc_closure_call(f, args, 1);
      ElmcValue *out = elmc_result_err(mapped);
      elmc_release(mapped);
      return out;
    }

    ElmcValue *elmc_result_and_then(ElmcValue *f, ElmcValue *result) {
      if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) return elmc_result_err(elmc_new_string("invalid"));
      ElmcResult *r = (ElmcResult *)result->payload;
      if (!r->is_ok) return elmc_retain(result);
      ElmcValue *args[1] = { r->value };
      return elmc_closure_call(f, args, 1);
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
      if (r->is_ok && r->value) return elmc_maybe_just(r->value);
      return elmc_maybe_nothing();
    }

    ElmcValue *elmc_result_from_maybe(ElmcValue *err, ElmcValue *maybe) {
      if (!maybe || maybe->tag != ELMC_TAG_MAYBE || !maybe->payload) return elmc_result_err(err);
      ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
      if (m->is_just && m->value) return elmc_result_ok(m->value);
      return elmc_result_err(err);
    }

    /* ================================================================
       Standard Library – String operations (extended)
       ================================================================ */

    ElmcValue *elmc_string_length_val(ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_int_zero();
      return elmc_new_int((int64_t)strlen((const char *)s->payload));
    }

    ElmcValue *elmc_string_reverse(ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      char *buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) return &ELMC_EMPTY_STRING;
      for (size_t i = 0; i < len; i++) {
        buf[i] = src[len - 1 - i];
      }
      buf[len] = '\\0';
      ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!out) { free(buf); return &ELMC_EMPTY_STRING; }
      return out;
    }

    ElmcValue *elmc_string_repeat(ElmcValue *n, ElmcValue *s) {
      int64_t count = elmc_as_int(n);
      if (count <= 0 || !s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      const char *src = (const char *)s->payload;
      size_t slen = strlen(src);
      size_t total = slen * (size_t)count;
      char *buf = (char *)elmc_malloc(total + 1, __func__);
      if (!buf) return &ELMC_EMPTY_STRING;
      for (int64_t i = 0; i < count; i++) {
        memcpy(buf + i * slen, src, slen);
      }
      buf[total] = '\\0';
      ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!out) { free(buf); return &ELMC_EMPTY_STRING; }
      return out;
    }

    ElmcValue *elmc_string_replace(ElmcValue *old_s, ElmcValue *new_s, ElmcValue *s) {
      (void)old_s; (void)new_s;
      if (!s || s->tag != ELMC_TAG_STRING) return &ELMC_EMPTY_STRING;
      return elmc_retain(s);
    }

    ElmcValue *elmc_string_from_int(ElmcValue *n) {
      return elmc_string_from_native_int(elmc_as_int(n));
    }

    ElmcValue *elmc_string_from_native_int(elmc_int_t n) {
      char buf[32];
      snprintf(buf, sizeof(buf), "%lld", (long long)n);
      return elmc_new_string(buf);
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

      ElmcValue *v = elmc_new_int(parsed);
      ElmcValue *out = elmc_maybe_just(v);
      elmc_release(v);
      return out;
    }

    ElmcValue *elmc_string_from_float(ElmcValue *f) {
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
      }
      return elmc_new_string(buf);
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
      ElmcValue *v = elmc_new_float(val);
      ElmcValue *out = elmc_maybe_just(v);
      elmc_release(v);
      return out;
    }

    ElmcValue *elmc_string_to_upper(ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      char *buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) return &ELMC_EMPTY_STRING;
      for (size_t i = 0; i < len; i++) {
        char c = src[i];
        buf[i] = (c >= 'a' && c <= 'z') ? (c - 32) : c;
      }
      buf[len] = '\\0';
      ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!out) { free(buf); return &ELMC_EMPTY_STRING; }
      return out;
    }

    ElmcValue *elmc_string_to_lower(ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      char *buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) return &ELMC_EMPTY_STRING;
      for (size_t i = 0; i < len; i++) {
        char c = src[i];
        buf[i] = (c >= 'A' && c <= 'Z') ? (c + 32) : c;
      }
      buf[len] = '\\0';
      ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!out) { free(buf); return &ELMC_EMPTY_STRING; }
      return out;
    }

    ElmcValue *elmc_string_trim(ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      size_t start = 0;
      while (start < len && (src[start] == ' ' || src[start] == '\\t' || src[start] == '\\n' || src[start] == '\\r')) start++;
      size_t end = len;
      while (end > start && (src[end-1] == ' ' || src[end-1] == '\\t' || src[end-1] == '\\n' || src[end-1] == '\\r')) end--;
      size_t new_len = end - start;
      char *buf = (char *)elmc_malloc(new_len + 1, __func__);
      if (!buf) return &ELMC_EMPTY_STRING;
      memcpy(buf, src + start, new_len);
      buf[new_len] = '\\0';
      ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!out) { free(buf); return &ELMC_EMPTY_STRING; }
      return out;
    }

    ElmcValue *elmc_string_trim_left(ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      size_t start = 0;
      while (start < len && (src[start] == ' ' || src[start] == '\\t' || src[start] == '\\n' || src[start] == '\\r')) start++;
      return elmc_new_string(src + start);
    }

    ElmcValue *elmc_string_trim_right(ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      while (len > 0 && (src[len-1] == ' ' || src[len-1] == '\\t' || src[len-1] == '\\n' || src[len-1] == '\\r')) len--;
      char *buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) return &ELMC_EMPTY_STRING;
      memcpy(buf, src, len);
      buf[len] = '\\0';
      ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!out) { free(buf); return &ELMC_EMPTY_STRING; }
      return out;
    }

    ElmcValue *elmc_string_contains(ElmcValue *sub, ElmcValue *s) {
      if (!sub || sub->tag != ELMC_TAG_STRING || !s || s->tag != ELMC_TAG_STRING) return elmc_new_bool(0);
      const char *haystack = (const char *)s->payload;
      const char *needle = (const char *)sub->payload;
      if (!haystack || !needle) return elmc_new_bool(0);
      return elmc_new_bool(strstr(haystack, needle) != NULL);
    }

    ElmcValue *elmc_string_starts_with(ElmcValue *prefix, ElmcValue *s) {
      if (!prefix || prefix->tag != ELMC_TAG_STRING || !s || s->tag != ELMC_TAG_STRING) return elmc_new_bool(0);
      const char *str = (const char *)s->payload;
      const char *pre = (const char *)prefix->payload;
      if (!str || !pre) return elmc_new_bool(0);
      size_t plen = strlen(pre);
      return elmc_new_bool(strncmp(str, pre, plen) == 0);
    }

    ElmcValue *elmc_string_ends_with(ElmcValue *suffix, ElmcValue *s) {
      if (!suffix || suffix->tag != ELMC_TAG_STRING || !s || s->tag != ELMC_TAG_STRING) return elmc_new_bool(0);
      const char *str = (const char *)s->payload;
      const char *suf = (const char *)suffix->payload;
      if (!str || !suf) return elmc_new_bool(0);
      size_t slen = strlen(str);
      size_t suflen = strlen(suf);
      if (suflen > slen) return elmc_new_bool(0);
      return elmc_new_bool(strcmp(str + slen - suflen, suf) == 0);
    }

    ElmcValue *elmc_string_split(ElmcValue *sep, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_list_nil();
      if (!sep || sep->tag != ELMC_TAG_STRING || !sep->payload) {
        ElmcValue *nil = elmc_list_nil();
        ElmcValue *out = elmc_list_cons(s, nil);
        elmc_release(nil);
        return out;
      }
      const char *str = (const char *)s->payload;
      const char *sp = (const char *)sep->payload;
      size_t splen = strlen(sp);
      ElmcValue *rev = elmc_list_nil();
      if (splen == 0) {
        /* split into characters */
        size_t slen = strlen(str);
        for (size_t i = 0; i < slen; i++) {
          char tmp[2] = { str[i], '\\0' };
          ElmcValue *ch = elmc_new_string(tmp);
          ElmcValue *next = elmc_list_cons(ch, rev);
          elmc_release(ch);
          elmc_release(rev);
          rev = next;
        }
      } else {
        const char *p = str;
        while (1) {
          const char *found = strstr(p, sp);
          if (!found) {
            ElmcValue *part = elmc_new_string(p);
            ElmcValue *next = elmc_list_cons(part, rev);
            elmc_release(part);
            elmc_release(rev);
            rev = next;
            break;
          }
          size_t chunk = (size_t)(found - p);
          char *buf = (char *)elmc_malloc(chunk + 1, __func__);
          if (buf) {
            memcpy(buf, p, chunk);
            buf[chunk] = '\\0';
            ElmcValue *part = elmc_alloc(ELMC_TAG_STRING, buf);
            if (part) {
              ElmcValue *next = elmc_list_cons(part, rev);
              elmc_release(part);
              elmc_release(rev);
              rev = next;
            } else {
              free(buf);
            }
          }
          p = found + splen;
        }
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_string_join(ElmcValue *sep, ElmcValue *list) {
      if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) return &ELMC_EMPTY_STRING;
      const char *sp = (sep && sep->tag == ELMC_TAG_STRING && sep->payload) ? (const char *)sep->payload : "";
      size_t splen = strlen(sp);
      /* First pass: compute total length */
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
      char *buf = (char *)elmc_malloc(total + 1, __func__);
      if (!buf) return &ELMC_EMPTY_STRING;
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
      ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!out) { free(buf); return &ELMC_EMPTY_STRING; }
      return out;
    }

    ElmcValue *elmc_string_words(ElmcValue *s) {
      ElmcValue *space = elmc_new_string(" ");
      ElmcValue *out = elmc_string_split(space, s);
      elmc_release(space);
      return out;
    }

    ElmcValue *elmc_string_lines(ElmcValue *s) {
      ElmcValue *nl = elmc_new_string("\\n");
      ElmcValue *out = elmc_string_split(nl, s);
      elmc_release(nl);
      return out;
    }

    ElmcValue *elmc_string_slice(ElmcValue *start, ElmcValue *end_idx, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      const char *src = (const char *)s->payload;
      int64_t len = (int64_t)strlen(src);
      int64_t st = elmc_as_int(start);
      int64_t en = elmc_as_int(end_idx);
      if (st < 0) st = len + st;
      if (en < 0) en = len + en;
      if (st < 0) st = 0;
      if (en < 0) en = 0;
      if (st > len) st = len;
      if (en > len) en = len;
      if (en <= st) return &ELMC_EMPTY_STRING;
      size_t new_len = (size_t)(en - st);
      char *buf = (char *)elmc_malloc(new_len + 1, __func__);
      if (!buf) return &ELMC_EMPTY_STRING;
      memcpy(buf, src + st, new_len);
      buf[new_len] = '\\0';
      ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!out) { free(buf); return &ELMC_EMPTY_STRING; }
      return out;
    }

    ElmcValue *elmc_string_left(ElmcValue *n, ElmcValue *s) {
      ElmcValue *zero = elmc_int_zero();
      ElmcValue *out = elmc_string_slice(zero, n, s);
      elmc_release(zero);
      return out;
    }

    ElmcValue *elmc_string_right(ElmcValue *n, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      int64_t len = (int64_t)strlen((const char *)s->payload);
      int64_t count = elmc_as_int(n);
      int64_t st = len - count;
      if (st < 0) st = 0;
      ElmcValue *start_v = elmc_new_int(st);
      ElmcValue *end_v = elmc_new_int(len);
      ElmcValue *out = elmc_string_slice(start_v, end_v, s);
      elmc_release(start_v);
      elmc_release(end_v);
      return out;
    }

    ElmcValue *elmc_string_drop_left(ElmcValue *n, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      int64_t len = (int64_t)strlen((const char *)s->payload);
      ElmcValue *end_v = elmc_new_int(len);
      ElmcValue *out = elmc_string_slice(n, end_v, s);
      elmc_release(end_v);
      return out;
    }

    ElmcValue *elmc_string_drop_right(ElmcValue *n, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      int64_t len = (int64_t)strlen((const char *)s->payload);
      int64_t count = elmc_as_int(n);
      int64_t en = len - count;
      if (en < 0) en = 0;
      ElmcValue *zero = elmc_int_zero();
      ElmcValue *end_v = elmc_new_int(en);
      ElmcValue *out = elmc_string_slice(zero, end_v, s);
      elmc_release(zero);
      elmc_release(end_v);
      return out;
    }

    ElmcValue *elmc_string_cons(ElmcValue *ch, ElmcValue *s) {
      char prefix[2] = { (char)elmc_as_int(ch), '\\0' };
      ElmcValue *prefix_v = elmc_new_string(prefix);
      ElmcValue *out = elmc_string_append(prefix_v, s);
      elmc_release(prefix_v);
      return out;
    }

    ElmcValue *elmc_string_uncons(ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_maybe_nothing();
      const char *str = (const char *)s->payload;
      if (strlen(str) == 0) return elmc_maybe_nothing();
      ElmcValue *ch = elmc_new_int((int64_t)(unsigned char)str[0]);
      ElmcValue *rest = elmc_new_string(str + 1);
      ElmcValue *pair = elmc_tuple2(ch, rest);
      elmc_release(ch);
      elmc_release(rest);
      return elmc_maybe_just(pair);
    }

    ElmcValue *elmc_string_to_list(ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_list_nil();
      const char *str = (const char *)s->payload;
      size_t len = strlen(str);
      ElmcValue *out = elmc_list_nil();
      for (size_t i = len; i > 0; i--) {
        ElmcValue *ch = elmc_new_int((int64_t)(unsigned char)str[i - 1]);
        ElmcValue *next = elmc_list_cons(ch, out);
        elmc_release(ch);
        elmc_release(out);
        out = next;
      }
      return out;
    }

    ElmcValue *elmc_string_from_list(ElmcValue *list) {
      /* count length */
      int64_t count = 0;
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        count++;
        cursor = ((ElmcCons *)cursor->payload)->tail;
      }
      char *buf = (char *)elmc_malloc((size_t)count + 1, __func__);
      if (!buf) return &ELMC_EMPTY_STRING;
      int64_t idx = 0;
      cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        buf[idx++] = (char)elmc_as_int(node->head);
        cursor = node->tail;
      }
      buf[count] = '\\0';
      ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!out) { free(buf); return &ELMC_EMPTY_STRING; }
      return out;
    }

    ElmcValue *elmc_string_from_char(ElmcValue *ch) {
      char buf[2] = { (char)elmc_as_int(ch), '\\0' };
      return elmc_new_string(buf);
    }

    ElmcValue *elmc_string_pad(ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
      return elmc_string_pad_left(n, ch, s);
    }

    ElmcValue *elmc_string_pad_left(ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      const char *src = (const char *)s->payload;
      int64_t target = elmc_as_int(n);
      int64_t cur_len = (int64_t)strlen(src);
      if (cur_len >= target) return elmc_retain(s);
      int64_t pad_count = target - cur_len;
      char pad_char = (char)elmc_as_int(ch);
      char *buf = (char *)elmc_malloc((size_t)target + 1, __func__);
      if (!buf) return elmc_retain(s);
      for (int64_t i = 0; i < pad_count; i++) buf[i] = pad_char;
      memcpy(buf + pad_count, src, (size_t)cur_len);
      buf[target] = '\\0';
      ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!out) { free(buf); return elmc_retain(s); }
      return out;
    }

    ElmcValue *elmc_string_pad_right(ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      const char *src = (const char *)s->payload;
      int64_t target = elmc_as_int(n);
      int64_t cur_len = (int64_t)strlen(src);
      if (cur_len >= target) return elmc_retain(s);
      int64_t pad_count = target - cur_len;
      char pad_char = (char)elmc_as_int(ch);
      char *buf = (char *)elmc_malloc((size_t)target + 1, __func__);
      if (!buf) return elmc_retain(s);
      memcpy(buf, src, (size_t)cur_len);
      for (int64_t i = 0; i < pad_count; i++) buf[cur_len + i] = pad_char;
      buf[target] = '\\0';
      ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!out) { free(buf); return elmc_retain(s); }
      return out;
    }

    ElmcValue *elmc_string_map(ElmcValue *f, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      char *buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) return &ELMC_EMPTY_STRING;
      for (size_t i = 0; i < len; i++) {
        ElmcValue *ch = elmc_new_int((int64_t)(unsigned char)src[i]);
        ElmcValue *args[1] = { ch };
        ElmcValue *mapped = elmc_closure_call(f, args, 1);
        buf[i] = (char)elmc_as_int(mapped);
        elmc_release(ch);
        elmc_release(mapped);
      }
      buf[len] = '\\0';
      ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!out) { free(buf); return &ELMC_EMPTY_STRING; }
      return out;
    }

    ElmcValue *elmc_string_filter(ElmcValue *f, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      char *buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) return &ELMC_EMPTY_STRING;
      size_t out_len = 0;
      for (size_t i = 0; i < len; i++) {
        ElmcValue *ch = elmc_new_int((int64_t)(unsigned char)src[i]);
        ElmcValue *args[1] = { ch };
        ElmcValue *keep = elmc_closure_call(f, args, 1);
        if (elmc_as_int(keep)) buf[out_len++] = src[i];
        elmc_release(ch);
        elmc_release(keep);
      }
      buf[out_len] = '\\0';
      ElmcValue *out = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!out) { free(buf); return &ELMC_EMPTY_STRING; }
      return out;
    }

    ElmcValue *elmc_string_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_retain(acc);
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      ElmcValue *result = elmc_retain(acc);
      for (size_t i = 0; i < len; i++) {
        ElmcValue *ch = elmc_new_int((int64_t)(unsigned char)src[i]);
        ElmcValue *args[2] = { ch, result };
        ElmcValue *next = elmc_closure_call(f, args, 2);
        elmc_release(ch);
        elmc_release(result);
        result = next;
      }
      return result;
    }

    ElmcValue *elmc_string_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_retain(acc);
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      ElmcValue *result = elmc_retain(acc);
      for (size_t i = len; i > 0; i--) {
        ElmcValue *ch = elmc_new_int((int64_t)(unsigned char)src[i - 1]);
        ElmcValue *args[2] = { ch, result };
        ElmcValue *next = elmc_closure_call(f, args, 2);
        elmc_release(ch);
        elmc_release(result);
        result = next;
      }
      return result;
    }

    ElmcValue *elmc_string_any(ElmcValue *f, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_new_bool(0);
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      for (size_t i = 0; i < len; i++) {
        ElmcValue *ch = elmc_new_int((int64_t)(unsigned char)src[i]);
        ElmcValue *args[1] = { ch };
        ElmcValue *result = elmc_closure_call(f, args, 1);
        int truthy = elmc_as_int(result) != 0;
        elmc_release(ch);
        elmc_release(result);
        if (truthy) return elmc_new_bool(1);
      }
      return elmc_new_bool(0);
    }

    ElmcValue *elmc_string_all(ElmcValue *f, ElmcValue *s) {
      if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_new_bool(1);
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      for (size_t i = 0; i < len; i++) {
        ElmcValue *ch = elmc_new_int((int64_t)(unsigned char)src[i]);
        ElmcValue *args[1] = { ch };
        ElmcValue *result = elmc_closure_call(f, args, 1);
        int truthy = elmc_as_int(result) != 0;
        elmc_release(ch);
        elmc_release(result);
        if (!truthy) return elmc_new_bool(0);
      }
      return elmc_new_bool(1);
    }

    ElmcValue *elmc_string_indexes(ElmcValue *sub, ElmcValue *s) {
      if (!sub || sub->tag != ELMC_TAG_STRING || !s || s->tag != ELMC_TAG_STRING) return elmc_list_nil();
      const char *haystack = (const char *)s->payload;
      const char *needle = (const char *)sub->payload;
      if (!haystack || !needle) return elmc_list_nil();
      size_t nlen = strlen(needle);
      if (nlen == 0) return elmc_list_nil();
      ElmcValue *rev = elmc_list_nil();
      const char *p = haystack;
      while ((p = strstr(p, needle)) != NULL) {
        ElmcValue *idx = elmc_new_int((int64_t)(p - haystack));
        ElmcValue *next = elmc_list_cons(idx, rev);
        elmc_release(idx);
        elmc_release(rev);
        rev = next;
        p += 1;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    /* ================================================================
       Standard Library – Tuple operations (extended)
       ================================================================ */

    ElmcValue *elmc_tuple_map_first(ElmcValue *f, ElmcValue *t) {
      if (!t || t->tag != ELMC_TAG_TUPLE2 || !t->payload) return elmc_retain(t);
      ElmcTuple2 *tuple = (ElmcTuple2 *)t->payload;
      ElmcValue *args[1] = { tuple->first };
      ElmcValue *mapped = elmc_closure_call(f, args, 1);
      ElmcValue *out = elmc_tuple2(mapped, tuple->second);
      elmc_release(mapped);
      return out;
    }

    ElmcValue *elmc_tuple_map_second(ElmcValue *f, ElmcValue *t) {
      if (!t || t->tag != ELMC_TAG_TUPLE2 || !t->payload) return elmc_retain(t);
      ElmcTuple2 *tuple = (ElmcTuple2 *)t->payload;
      ElmcValue *args[1] = { tuple->second };
      ElmcValue *mapped = elmc_closure_call(f, args, 1);
      ElmcValue *out = elmc_tuple2(tuple->first, mapped);
      elmc_release(mapped);
      return out;
    }

    ElmcValue *elmc_tuple_map_both(ElmcValue *f, ElmcValue *g, ElmcValue *t) {
      if (!t || t->tag != ELMC_TAG_TUPLE2 || !t->payload) return elmc_retain(t);
      ElmcTuple2 *tuple = (ElmcTuple2 *)t->payload;
      ElmcValue *args_f[1] = { tuple->first };
      ElmcValue *args_g[1] = { tuple->second };
      ElmcValue *mf = elmc_closure_call(f, args_f, 1);
      ElmcValue *mg = elmc_closure_call(g, args_g, 1);
      ElmcValue *out = elmc_tuple2(mf, mg);
      elmc_release(mf);
      elmc_release(mg);
      return out;
    }

    /* ================================================================
       Standard Library – Basics (extended)
       ================================================================ */

    ElmcValue *elmc_basics_not(ElmcValue *x) {
      return elmc_new_bool(elmc_as_int(x) == 0 ? 1 : 0);
    }

    ElmcValue *elmc_basics_negate(ElmcValue *x) {
      if (x && x->tag == ELMC_TAG_FLOAT) {
        return elmc_new_float(-elmc_as_float(x));
      }
      return elmc_new_int(-elmc_as_int(x));
    }

    ElmcValue *elmc_basics_abs(ElmcValue *x) {
      if (x && x->tag == ELMC_TAG_FLOAT) {
        double v = elmc_as_float(x);
        return elmc_new_float(v < 0 ? -v : v);
      }
      int64_t v = elmc_as_int(x);
      return elmc_new_int(v < 0 ? -v : v);
    }

    ElmcValue *elmc_basics_to_float(ElmcValue *x) {
      return elmc_new_float((double)elmc_as_int(x));
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
      if (v < 0.0) return elmc_new_float(elmc_basics_nan());
      if (v == 0.0) return elmc_new_float(0.0);

      double guess = v >= 1.0 ? v : 1.0;
      for (int i = 0; i < 24; i++) {
        guess = 0.5 * (guess + v / guess);
      }
      return elmc_new_float(guess);
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
      return elmc_new_float(elmc_basics_log_double(elmc_as_float(x)) / denominator);
    }

    static double elmc_basics_normalize_radians(double x) {
      const double pi = 3.14159265358979323846;
      const double two_pi = 6.28318530717958647692;
      while (x > pi) x -= two_pi;
      while (x < -pi) x += two_pi;
      return x;
    }

    double elmc_basics_sin_double(double x) {
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
    }

    ElmcValue *elmc_basics_sin(ElmcValue *x) {
      return elmc_new_float(elmc_basics_sin_double(elmc_as_float(x)));
    }

    double elmc_basics_cos_double(double x) {
      const double half_pi = 1.57079632679489661923;
      return elmc_basics_sin_double(x + half_pi);
    }

    ElmcValue *elmc_basics_cos(ElmcValue *x) {
      return elmc_new_float(elmc_basics_cos_double(elmc_as_float(x)));
    }

    double elmc_basics_tan_double(double x) {
      return elmc_basics_sin_double(x) / elmc_basics_cos_double(x);
    }

    ElmcValue *elmc_basics_tan(ElmcValue *x) {
      return elmc_new_float(elmc_basics_tan_double(elmc_as_float(x)));
    }

    static double elmc_basics_atan_double(double x) {
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
    }

    ElmcValue *elmc_basics_atan(ElmcValue *x) {
      return elmc_new_float(elmc_basics_atan_double(elmc_as_float(x)));
    }

    ElmcValue *elmc_basics_atan2(ElmcValue *y, ElmcValue *x) {
      const double pi = 3.14159265358979323846;
      const double half_pi = 1.57079632679489661923;
      double yy = elmc_as_float(y);
      double xx = elmc_as_float(x);

      if (xx > 0.0) return elmc_new_float(elmc_basics_atan_double(yy / xx));
      if (xx < 0.0 && yy >= 0.0) return elmc_new_float(elmc_basics_atan_double(yy / xx) + pi);
      if (xx < 0.0 && yy < 0.0) return elmc_new_float(elmc_basics_atan_double(yy / xx) - pi);
      if (xx == 0.0 && yy > 0.0) return elmc_new_float(half_pi);
      if (xx == 0.0 && yy < 0.0) return elmc_new_float(-half_pi);
      return elmc_new_float(0.0);
    }

    ElmcValue *elmc_basics_asin(ElmcValue *x) {
      double v = elmc_as_float(x);
      if (v < -1.0 || v > 1.0) return elmc_new_float(elmc_basics_nan());
      double denom = elmc_basics_sqrt_double(1.0 - v * v);
      return elmc_new_float(elmc_basics_atan_double(v / denom));
    }

    ElmcValue *elmc_basics_acos(ElmcValue *x) {
      const double half_pi = 1.57079632679489661923;
      ElmcValue *asin_value = elmc_basics_asin(x);
      double out = half_pi - elmc_as_float(asin_value);
      elmc_release(asin_value);
      return elmc_new_float(out);
    }

    ElmcValue *elmc_basics_degrees(ElmcValue *x) {
      return elmc_new_float(elmc_as_float(x) * 0.01745329251994329577);
    }

    ElmcValue *elmc_basics_radians(ElmcValue *x) {
      return elmc_new_float(elmc_as_float(x));
    }

    ElmcValue *elmc_basics_turns(ElmcValue *x) {
      return elmc_new_float(elmc_as_float(x) * 6.28318530717958647692);
    }

    ElmcValue *elmc_basics_from_polar(ElmcValue *polar) {
      if (!polar || polar->tag != ELMC_TAG_TUPLE2 || !polar->payload) {
        ElmcValue *x0 = elmc_new_float(0.0);
        ElmcValue *y0 = elmc_new_float(0.0);
        ElmcValue *out0 = elmc_tuple2(x0, y0);
        elmc_release(x0);
        elmc_release(y0);
        return out0;
      }
      ElmcTuple2 *pair = (ElmcTuple2 *)polar->payload;
      double radius = elmc_as_float(pair->first);
      double theta = elmc_as_float(pair->second);
      ElmcValue *x = elmc_new_float(radius * elmc_basics_sin_double(theta + 1.57079632679489661923));
      ElmcValue *y = elmc_new_float(radius * elmc_basics_sin_double(theta));
      ElmcValue *out = elmc_tuple2(x, y);
      elmc_release(x);
      elmc_release(y);
      return out;
    }

    ElmcValue *elmc_basics_to_polar(ElmcValue *point) {
      if (!point || point->tag != ELMC_TAG_TUPLE2 || !point->payload) {
        ElmcValue *r0 = elmc_new_float(0.0);
        ElmcValue *t0 = elmc_new_float(0.0);
        ElmcValue *out0 = elmc_tuple2(r0, t0);
        elmc_release(r0);
        elmc_release(t0);
        return out0;
      }
      ElmcTuple2 *pair = (ElmcTuple2 *)point->payload;
      double x = elmc_as_float(pair->first);
      double y = elmc_as_float(pair->second);
      ElmcValue *radius = elmc_new_float(elmc_basics_sqrt_double(x * x + y * y));
      ElmcValue *theta = elmc_new_float(elmc_basics_atan_double(y / x));
      if (x < 0.0) {
        double adjusted = elmc_as_float(theta) + (y >= 0.0 ? 3.14159265358979323846 : -3.14159265358979323846);
        elmc_release(theta);
        theta = elmc_new_float(adjusted);
      } else if (x == 0.0) {
        elmc_release(theta);
        theta = elmc_new_float(y > 0.0 ? 1.57079632679489661923 : (y < 0.0 ? -1.57079632679489661923 : 0.0));
      }
      ElmcValue *out = elmc_tuple2(radius, theta);
      elmc_release(radius);
      elmc_release(theta);
      return out;
    }

    ElmcValue *elmc_basics_is_nan(ElmcValue *x) {
      double v = elmc_as_float(x);
      return elmc_new_bool(v != v);
    }

    ElmcValue *elmc_basics_is_infinite(ElmcValue *x) {
      double v = elmc_as_float(x);
      double delta = v - v;
      return elmc_new_bool((v == v && delta != delta) ? 1 : 0);
    }

    ElmcValue *elmc_basics_round(ElmcValue *x) {
      double v = elmc_as_float(x);
      return elmc_new_int((int64_t)(v + (v >= 0 ? 0.5 : -0.5)));
    }

    ElmcValue *elmc_basics_floor(ElmcValue *x) {
      double v = elmc_as_float(x);
      int64_t i = (int64_t)v;
      if ((double)i > v) i--;
      return elmc_new_int(i);
    }

    ElmcValue *elmc_basics_ceiling(ElmcValue *x) {
      double v = elmc_as_float(x);
      int64_t i = (int64_t)v;
      if ((double)i < v) i++;
      return elmc_new_int(i);
    }

    ElmcValue *elmc_basics_truncate(ElmcValue *x) {
      return elmc_new_int((int64_t)elmc_as_float(x));
    }

    ElmcValue *elmc_basics_remainder_by(ElmcValue *base, ElmcValue *value) {
      elmc_int_t b = elmc_as_int(base);
      elmc_int_t v = elmc_as_int(value);
      if (b == 0) return elmc_int_zero();
      return elmc_new_int(v % b);
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
        return elmc_new_float(result);
      }

      int64_t b = elmc_as_int(base);
      for (uint64_t i = 0; i < count; i++) result *= (double)b;
      if (negative) {
        result = (result == 0.0) ? 0.0 : (1.0 / result);
        return elmc_new_float(result);
      }
      return elmc_new_int((int64_t)result);
    }

    ElmcValue *elmc_basics_xor(ElmcValue *a, ElmcValue *b) {
      int ba = elmc_as_int(a) != 0;
      int bb = elmc_as_int(b) != 0;
      return elmc_new_bool(ba != bb ? 1 : 0);
    }

    ElmcValue *elmc_basics_compare(ElmcValue *a, ElmcValue *b) {
      /* Returns -1, 0, or 1 as an int for LT, EQ, GT */
      if (a && b && (a->tag == ELMC_TAG_FLOAT || b->tag == ELMC_TAG_FLOAT)) {
        double fa = elmc_as_float(a);
        double fb = elmc_as_float(b);
        if (fa < fb) return elmc_new_int(-1);
        if (fa > fb) return elmc_new_int(1);
        return elmc_int_zero();
      }
      if (a && b && a->tag == ELMC_TAG_STRING && b->tag == ELMC_TAG_STRING) {
        const char *sa = (const char *)a->payload;
        const char *sb = (const char *)b->payload;
        int cmp = strcmp(sa ? sa : "", sb ? sb : "");
        if (cmp < 0) return elmc_new_int(-1);
        if (cmp > 0) return elmc_new_int(1);
        return elmc_int_zero();
      }
      elmc_int_t ia = elmc_as_int(a);
      elmc_int_t ib = elmc_as_int(b);
      if (ia < ib) return elmc_new_int(-1);
      if (ia > ib) return elmc_new_int(1);
      return elmc_int_zero();
    }

    /* ================================================================
       Standard Library – Char (extended)
       ================================================================ */

    ElmcValue *elmc_char_is_upper(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      return elmc_new_bool(c >= 'A' && c <= 'Z');
    }

    ElmcValue *elmc_char_is_lower(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      return elmc_new_bool(c >= 'a' && c <= 'z');
    }

    ElmcValue *elmc_char_is_alpha(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      return elmc_new_bool((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'));
    }

    ElmcValue *elmc_char_is_alpha_num(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      return elmc_new_bool((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'));
    }

    ElmcValue *elmc_char_is_digit(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      return elmc_new_bool(c >= '0' && c <= '9');
    }

    ElmcValue *elmc_char_is_oct_digit(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      return elmc_new_bool(c >= '0' && c <= '7');
    }

    ElmcValue *elmc_char_is_hex_digit(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      return elmc_new_bool((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f'));
    }

    ElmcValue *elmc_char_to_upper(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      if (c >= 'a' && c <= 'z') c -= 32;
      return elmc_new_int(c);
    }

    ElmcValue *elmc_char_to_lower(ElmcValue *ch) {
      int64_t c = elmc_as_int(ch);
      if (c >= 'A' && c <= 'Z') c += 32;
      return elmc_new_int(c);
    }

    /* ================================================================
       Standard Library – Dict (extended)
       ================================================================ */

    ElmcValue *elmc_dict_remove(ElmcValue *key, ElmcValue *dict) {
      int64_t wanted = elmc_as_int(key);
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = dict;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        int skip = 0;
        if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
          if (pair->first && elmc_as_int(pair->first) == wanted) skip = 1;
        }
        if (!skip) {
          ElmcValue *next = elmc_list_cons(node->head, rev);
          elmc_release(rev);
          rev = next;
        }
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_dict_is_empty(ElmcValue *dict) {
      if (!dict || dict->tag != ELMC_TAG_LIST) return elmc_new_bool(1);
      return elmc_new_bool(dict->payload == NULL);
    }

    ElmcValue *elmc_dict_keys(ElmcValue *dict) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = dict;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
          ElmcValue *next = elmc_list_cons(pair->first, rev);
          elmc_release(rev);
          rev = next;
        }
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_dict_values(ElmcValue *dict) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = dict;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
          ElmcValue *next = elmc_list_cons(pair->second, rev);
          elmc_release(rev);
          rev = next;
        }
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_dict_to_list(ElmcValue *dict) {
      /* Dict is already stored as a list of tuples */
      if (!dict) return elmc_list_nil();
      return elmc_retain(dict);
    }

    ElmcValue *elmc_dict_map(ElmcValue *f, ElmcValue *dict) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = dict;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
          ElmcValue *args[2] = { pair->first, pair->second };
          ElmcValue *mapped = elmc_closure_call(f, args, 2);
          ElmcValue *new_pair = elmc_tuple2(pair->first, mapped);
          elmc_release(mapped);
          ElmcValue *next = elmc_list_cons(new_pair, rev);
          elmc_release(new_pair);
          elmc_release(rev);
          rev = next;
        }
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_dict_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *dict) {
      ElmcValue *result = elmc_retain(acc);
      ElmcValue *cursor = dict;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
          ElmcValue *args[3] = { pair->first, pair->second, result };
          ElmcValue *next = elmc_closure_call(f, args, 3);
          elmc_release(result);
          result = next;
        }
        cursor = node->tail;
      }
      return result;
    }

    ElmcValue *elmc_dict_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *dict) {
      ElmcValue *reversed = elmc_list_reverse_copy(dict);
      ElmcValue *result = elmc_retain(acc);
      ElmcValue *cursor = reversed;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
          ElmcValue *args[3] = { pair->first, pair->second, result };
          ElmcValue *next = elmc_closure_call(f, args, 3);
          elmc_release(result);
          result = next;
        }
        cursor = node->tail;
      }
      elmc_release(reversed);
      return result;
    }

    ElmcValue *elmc_dict_filter(ElmcValue *f, ElmcValue *dict) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = dict;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
          ElmcValue *args[2] = { pair->first, pair->second };
          ElmcValue *keep = elmc_closure_call(f, args, 2);
          if (elmc_as_int(keep)) {
            ElmcValue *next = elmc_list_cons(node->head, rev);
            elmc_release(rev);
            rev = next;
          }
          elmc_release(keep);
        }
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_dict_partition(ElmcValue *f, ElmcValue *dict) {
      ElmcValue *rev_yes = elmc_list_nil();
      ElmcValue *rev_no = elmc_list_nil();
      ElmcValue *cursor = dict;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
          ElmcValue *args[2] = { pair->first, pair->second };
          ElmcValue *keep = elmc_closure_call(f, args, 2);
          if (elmc_as_int(keep)) {
            ElmcValue *next = elmc_list_cons(node->head, rev_yes);
            elmc_release(rev_yes);
            rev_yes = next;
          } else {
            ElmcValue *next = elmc_list_cons(node->head, rev_no);
            elmc_release(rev_no);
            rev_no = next;
          }
          elmc_release(keep);
        }
        cursor = node->tail;
      }
      ElmcValue *yes = elmc_list_reverse_copy(rev_yes);
      ElmcValue *no = elmc_list_reverse_copy(rev_no);
      elmc_release(rev_yes);
      elmc_release(rev_no);
      ElmcValue *out = elmc_tuple2(yes, no);
      elmc_release(yes);
      elmc_release(no);
      return out;
    }

    ElmcValue *elmc_dict_union(ElmcValue *a, ElmcValue *b) {
      /* Insert all of a into b (a takes precedence) */
      ElmcValue *out = elmc_retain(b);
      ElmcValue *cursor = a;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
          ElmcValue *next = elmc_dict_insert(pair->first, pair->second, out);
          elmc_release(out);
          out = next;
        }
        cursor = node->tail;
      }
      return out;
    }

    ElmcValue *elmc_dict_intersect(ElmcValue *a, ElmcValue *b) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = a;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
          ElmcValue *found = elmc_dict_member(pair->first, b);
          if (elmc_as_int(found)) {
            ElmcValue *next = elmc_list_cons(node->head, rev);
            elmc_release(rev);
            rev = next;
          }
          elmc_release(found);
        }
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_dict_diff(ElmcValue *a, ElmcValue *b) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = a;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
          ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
          ElmcValue *found = elmc_dict_member(pair->first, b);
          if (!elmc_as_int(found)) {
            ElmcValue *next = elmc_list_cons(node->head, rev);
            elmc_release(rev);
            rev = next;
          }
          elmc_release(found);
        }
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_dict_merge(ElmcValue *lf, ElmcValue *bf, ElmcValue *rf, ElmcValue *a, ElmcValue *b) {
      (void)lf; (void)bf; (void)rf;
      /* Stub: return union */
      return elmc_dict_union(a, b);
    }

    ElmcValue *elmc_dict_update(ElmcValue *key, ElmcValue *f, ElmcValue *dict) {
      ElmcValue *old_val = elmc_dict_get(key, dict);
      ElmcValue *args[1] = { old_val };
      ElmcValue *new_maybe = elmc_closure_call(f, args, 1);
      elmc_release(old_val);
      if (new_maybe && new_maybe->tag == ELMC_TAG_MAYBE && new_maybe->payload != NULL) {
        ElmcMaybe *m = (ElmcMaybe *)new_maybe->payload;
        if (m->is_just && m->value) {
          ElmcValue *out = elmc_dict_insert(key, m->value, dict);
          elmc_release(new_maybe);
          return out;
        }
      }
      elmc_release(new_maybe);
      return elmc_dict_remove(key, dict);
    }

    ElmcValue *elmc_dict_singleton(ElmcValue *key, ElmcValue *value) {
      ElmcValue *empty = elmc_list_nil();
      ElmcValue *out = elmc_dict_insert(key, value, empty);
      elmc_release(empty);
      return out;
    }

    /* ================================================================
       Standard Library – Set (extended)
       ================================================================ */

    ElmcValue *elmc_set_singleton(ElmcValue *value) {
      ElmcValue *empty = elmc_list_nil();
      ElmcValue *out = elmc_set_insert(value, empty);
      elmc_release(empty);
      return out;
    }

    ElmcValue *elmc_set_remove(ElmcValue *value, ElmcValue *set) {
      int64_t wanted = elmc_as_int(value);
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = set;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (elmc_as_int(node->head) != wanted) {
          ElmcValue *next = elmc_list_cons(node->head, rev);
          elmc_release(rev);
          rev = next;
        }
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_set_is_empty(ElmcValue *set) {
      if (!set || set->tag != ELMC_TAG_LIST) return elmc_new_bool(1);
      return elmc_new_bool(set->payload == NULL);
    }

    ElmcValue *elmc_set_to_list(ElmcValue *set) {
      if (!set) return elmc_list_nil();
      return elmc_retain(set);
    }

    ElmcValue *elmc_set_union(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = elmc_retain(b);
      ElmcValue *cursor = a;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *next = elmc_set_insert(node->head, out);
        elmc_release(out);
        out = next;
        cursor = node->tail;
      }
      return out;
    }

    ElmcValue *elmc_set_intersect(ElmcValue *a, ElmcValue *b) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = a;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *found = elmc_set_member(node->head, b);
        if (elmc_as_int(found)) {
          ElmcValue *next = elmc_list_cons(node->head, rev);
          elmc_release(rev);
          rev = next;
        }
        elmc_release(found);
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_set_diff(ElmcValue *a, ElmcValue *b) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = a;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *found = elmc_set_member(node->head, b);
        if (!elmc_as_int(found)) {
          ElmcValue *next = elmc_list_cons(node->head, rev);
          elmc_release(rev);
          rev = next;
        }
        elmc_release(found);
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_set_map(ElmcValue *f, ElmcValue *set) {
      ElmcValue *out = elmc_list_nil();
      ElmcValue *cursor = set;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[1] = { node->head };
        ElmcValue *mapped = elmc_closure_call(f, args, 1);
        ElmcValue *next = elmc_set_insert(mapped, out);
        elmc_release(mapped);
        elmc_release(out);
        out = next;
        cursor = node->tail;
      }
      return out;
    }

    ElmcValue *elmc_set_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *set) {
      ElmcValue *result = elmc_retain(acc);
      ElmcValue *cursor = set;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[2] = { node->head, result };
        ElmcValue *next = elmc_closure_call(f, args, 2);
        elmc_release(result);
        result = next;
        cursor = node->tail;
      }
      return result;
    }

    ElmcValue *elmc_set_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *set) {
      ElmcValue *reversed = elmc_list_reverse_copy(set);
      ElmcValue *result = elmc_retain(acc);
      ElmcValue *cursor = reversed;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[2] = { node->head, result };
        ElmcValue *next = elmc_closure_call(f, args, 2);
        elmc_release(result);
        result = next;
        cursor = node->tail;
      }
      elmc_release(reversed);
      return result;
    }

    ElmcValue *elmc_set_filter(ElmcValue *f, ElmcValue *set) {
      ElmcValue *rev = elmc_list_nil();
      ElmcValue *cursor = set;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[1] = { node->head };
        ElmcValue *keep = elmc_closure_call(f, args, 1);
        if (elmc_as_int(keep)) {
          ElmcValue *next = elmc_list_cons(node->head, rev);
          elmc_release(rev);
          rev = next;
        }
        elmc_release(keep);
        cursor = node->tail;
      }
      ElmcValue *out = elmc_list_reverse_copy(rev);
      elmc_release(rev);
      return out;
    }

    ElmcValue *elmc_set_partition(ElmcValue *f, ElmcValue *set) {
      ElmcValue *rev_yes = elmc_list_nil();
      ElmcValue *rev_no = elmc_list_nil();
      ElmcValue *cursor = set;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[1] = { node->head };
        ElmcValue *keep = elmc_closure_call(f, args, 1);
        if (elmc_as_int(keep)) {
          ElmcValue *next = elmc_list_cons(node->head, rev_yes);
          elmc_release(rev_yes);
          rev_yes = next;
        } else {
          ElmcValue *next = elmc_list_cons(node->head, rev_no);
          elmc_release(rev_no);
          rev_no = next;
        }
        elmc_release(keep);
        cursor = node->tail;
      }
      ElmcValue *yes = elmc_list_reverse_copy(rev_yes);
      ElmcValue *no = elmc_list_reverse_copy(rev_no);
      elmc_release(rev_yes);
      elmc_release(rev_no);
      ElmcValue *out = elmc_tuple2(yes, no);
      elmc_release(yes);
      elmc_release(no);
      return out;
    }

    /* ================================================================
       Standard Library – Array (extended)
       ================================================================ */

    ElmcValue *elmc_array_initialize(ElmcValue *n, ElmcValue *f) {
      int64_t count = elmc_as_int(n);
      ElmcValue *out = elmc_list_nil();
      for (int64_t i = count - 1; i >= 0; i--) {
        ElmcValue *idx = elmc_new_int(i);
        ElmcValue *args[1] = { idx };
        ElmcValue *val = elmc_closure_call(f, args, 1);
        ElmcValue *next = elmc_list_cons(val, out);
        elmc_release(idx);
        elmc_release(val);
        elmc_release(out);
        out = next;
      }
      return out;
    }

    ElmcValue *elmc_array_repeat(ElmcValue *n, ElmcValue *value) {
      return elmc_list_repeat(n, value);
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
        ElmcValue *index_val = elmc_new_int(idx);
        ElmcValue *pair = elmc_tuple2(index_val, node->head);
        ElmcValue *next = elmc_list_cons(pair, rev);
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
      return elmc_list_map(f, array);
    }

    ElmcValue *elmc_array_indexed_map(ElmcValue *f, ElmcValue *array) {
      return elmc_list_indexed_map(f, array);
    }

    ElmcValue *elmc_array_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *array) {
      return elmc_list_foldl(f, acc, array);
    }

    ElmcValue *elmc_array_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *array) {
      return elmc_list_foldr(f, acc, array);
    }

    ElmcValue *elmc_array_filter(ElmcValue *f, ElmcValue *array) {
      return elmc_list_filter(f, array);
    }

    ElmcValue *elmc_array_append(ElmcValue *a, ElmcValue *b) {
      return elmc_list_append(a, b);
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
          ElmcValue *next = elmc_list_cons(node->head, rev);
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

    ElmcValue *elmc_retain(ElmcValue *value) {
      if (!value) return NULL;
      if (value->rc == ELMC_RC_IMMORTAL) return value;
      value->rc += 1;
      return value;
    }

    void elmc_release(ElmcValue *value) {
      if (!value) return;
      if (value->rc == ELMC_RC_IMMORTAL) return;
      if (value->rc == 0) return;
      value->rc -= 1;
      if (value->rc > 0) return;
      if (value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) {
        /* Scalar values live inline in ElmcValue, not in heap payloads. */
      } else if (value->tag == ELMC_TAG_LIST && value->payload != NULL) {
        ElmcCons *node = (ElmcCons *)value->payload;
        elmc_release(node->head);
        elmc_release(node->tail);
      } else if (value->tag == ELMC_TAG_MAYBE && value->payload != NULL) {
        ElmcMaybe *maybe = (ElmcMaybe *)value->payload;
        if (maybe->value) elmc_release(maybe->value);
      } else if (value->tag == ELMC_TAG_RESULT && value->payload != NULL) {
        ElmcResult *result = (ElmcResult *)value->payload;
        if (result->value) elmc_release(result->value);
      } else if (value->tag == ELMC_TAG_TUPLE2 && value->payload != NULL) {
        ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
        if (tuple->first) elmc_release(tuple->first);
        if (tuple->second) elmc_release(tuple->second);
      } else if (value->tag == ELMC_TAG_RECORD && value->payload != NULL) {
        ElmcRecord *rec = (ElmcRecord *)value->payload;
        for (int i = 0; i < rec->field_count; i++) {
          if (rec->field_values[i]) elmc_release(rec->field_values[i]);
          free((void *)rec->field_names[i]);
        }
        free(rec->field_names);
        free(rec->field_values);
      } else if (value->tag == ELMC_TAG_CLOSURE && value->payload != NULL) {
        ElmcClosure *clo = (ElmcClosure *)value->payload;
        for (int i = 0; i < clo->capture_count; i++) {
          if (clo->captures[i]) elmc_release(clo->captures[i]);
        }
        free(clo->captures);
      }
      if (value->tag != ELMC_TAG_INT && value->tag != ELMC_TAG_BOOL) {
        free(value->payload);
      }
      free(value);
      ELMC_RELEASED += 1;
    }

    void elmc_release_deep(ElmcValue *value) {
      /* Current runtime representation has no nested ownership for supported subset. */
      elmc_release(value);
    }
    """
  end
end
