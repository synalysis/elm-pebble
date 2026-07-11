defmodule Elmc.Backend.Bytecode.FusionRunner do
  @moduledoc false

  alias Elmc.Backend.Bytecode.Runtime
  alias Elmc.Backend.CCodegen.RowMajorLayout
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @spec runnable?(FunctionPlan.t()) :: boolean()
  def runnable?(%FunctionPlan{blocks: [], fusion_kind: kind}) when not is_nil(kind), do: true
  def runnable?(_), do: false

  @spec run(FunctionPlan.t(), keyword()) :: {:ok, term()} | :unsupported
  def run(%FunctionPlan{fusion_kind: :tuple2_case_table, fusion_data: data}, opts) do
    params = Keyword.get(opts, :params, [])

    with {:ok, table} <- normalize_table(data),
         [kind, rot | _] <- params,
         pairs when is_list(pairs) <- lookup_pairs(table, kind, rot) do
      {:ok, Enum.map(pairs, fn [a, b] -> {:tuple2, a, b} end)}
    else
      _ ->
        if length(params) >= 2 do
          {:ok, []}
        else
          :unsupported
        end
    end
  end

  def run(%FunctionPlan{fusion_kind: :filter_map_row_drop, fusion_data: data}, opts) do
    [board | _] = Keyword.get(opts, :params, [])

    with rows when is_integer(rows) <- int_field(data, "rows"),
         cols when is_integer(cols) <- int_field(data, "cols") do
      board_list = normalize_board(board)
      cleared = count_full_rows(board_list, rows, cols)

      if cleared == 0 do
        {:ok, {:tuple2, board_list, 0}}
      else
        zeros = List.duplicate(0, cleared * cols)

        kept =
          for row <- 0..(rows - 1),
              not row_full?(board_list, row, cols),
              col <- 0..(cols - 1),
              do: cell_at(board_list, row, cols, col)

        {:ok, {:tuple2, zeros ++ kept, cleared}}
      end
    else
      _ -> :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :foldl_offset_patch, fusion_data: data}, opts) do
    [piece, board | _] = Keyword.get(opts, :params, [])

    with cols when is_integer(cols) <- int_field(data, "cols"),
         rows when is_integer(rows) <- int_field(data, "rows"),
         fields when is_map(fields) <- map_field(data, "piece_fields"),
         {mod, name} <- callee_field(data, "offsets"),
         kind_idx when is_integer(kind_idx) <- int_field(fields, "kind"),
         rot_idx when is_integer(rot_idx) <- int_field(fields, "rot"),
         x_idx when is_integer(x_idx) <- int_field(fields, "x"),
         y_idx when is_integer(y_idx) <- int_field(fields, "y") do
      kind = record_field(piece, kind_idx)
      rot = record_field(piece, rot_idx)
      px = record_field(piece, x_idx)
      py = record_field(piece, y_idx)
      value = kind + 1

      offsets =
        case invoke_callee(opts, {mod, name}, [kind, rot]) do
          list when is_list(list) -> list
          _ -> []
        end

      patches =
        for {:tuple2, dx, dy} <- offsets,
            x = px + as_int(dx),
            y = py + as_int(dy),
            x >= 0 and x < cols and y >= 0 and y < rows,
            do: y * cols + x

      board_list = normalize_board(board)
      total = cols * rows

      new_board =
        if length(board_list) == total do
          Enum.reduce(patches, board_list, fn patch, acc ->
            List.replace_at(acc, patch, value)
          end)
        else
          board_list
        end

      {:ok, new_board}
    else
      _ -> :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :reverse_foldl_occupied, fusion_data: data}, opts) do
    [board | _] = Keyword.get(opts, :params, [])

    with count when is_integer(count) <- int_field(data, "count") do
      board_list = normalize_board(board)

      slots =
        for index <- 0..(count - 1),
            Enum.at(board_list, index, 0) != 0,
            do: index

      {:ok, slots}
    else
      _ -> :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :list_indexed_replace, fusion_data: _data}, opts) do
    [index, value, list | _] = Keyword.get(opts, :params, [])

    idx = as_int(index)
    val = as_int(value)
    board = normalize_board(list)

    if idx >= 0 and idx < length(board) do
      {:ok, List.replace_at(board, idx, val)}
    else
      {:ok, board}
    end
  end

  def run(%FunctionPlan{fusion_kind: :list_int_search, fusion_data: data}, opts) do
    case fusion_mode(data) do
      :help ->
        [target, index, list | _] = Keyword.get(opts, :params, [])
        not_found = int_field(data, "not_found") || -1

        {:ok,
         list_int_search_walk(
           as_int(target),
           as_int(index),
           normalize_board(list),
           not_found
         )}

      :delegate ->
        [target, list | _] = Keyword.get(opts, :params, [])

        with {mod, name} <- callee_field(data, "help") do
          case invoke_callee(opts, {mod, name}, [as_int(target), 0, list]) do
            n when is_integer(n) -> {:ok, n}
            _ -> :unsupported
          end
        else
          _ -> :unsupported
        end

      _ ->
        :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :spawn_tile_chain, fusion_data: data}, opts) do
    [seed | _] = Keyword.get(opts, :params, [])

    with count when is_integer(count) <- int_field(data, "count"),
         passes when is_integer(passes) <- int_field(data, "passes") || 2 do
      buf = load_spawn_board(data, count, opts)
      {cells, seed_out} = spawn_tile_chained(buf, as_int(seed), passes)
      {:ok, {:tuple2, cells, seed_out}}
    else
      _ -> :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :union_int_lut, fusion_data: data}, opts) do
    [tag | _] = Keyword.get(opts, :params, [])

    with lut when is_map(lut) <- normalize_lut(data) do
      case Map.get(lut, as_int(tag)) do
        nil -> :unsupported
        wire -> {:ok, wire}
      end
    else
      _ -> :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :union_string_lut, fusion_data: data}, opts) do
    [tag | _] = Keyword.get(opts, :params, [])

    with lut when is_map(lut) <- normalize_string_lut(data) do
      case Map.get(lut, as_int(tag)) do
        nil -> :unsupported
        text -> {:ok, text}
      end
    else
      _ -> :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :int_string_lut, fusion_data: data}, opts) do
    [key | _] = Keyword.get(opts, :params, [])

    with lut when is_map(lut) <- normalize_string_lut(data) do
      case Map.get(lut, as_int(key)) do
        nil ->
          case string_field(data, "default") do
            text when is_binary(text) -> {:ok, text}
            _ -> :unsupported
          end

        text ->
          {:ok, text}
      end
    else
      _ -> :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :maybe_int_string, fusion_data: data}, opts) do
    [model | _] = Keyword.get(opts, :params, [])

    with idx when is_integer(idx) <- int_field(data, "field") do
      maybe_val = record_maybe_field(model, idx)

      case maybe_int_mode(data) do
        :default_append ->
          default = int_field(data, "default") || 0
          suffix = string_field(data, "suffix") || ""
          int_val = maybe_with_default_int(maybe_val, default)
          {:ok, Integer.to_string(int_val) <> suffix}

        :maybe_case ->
          nothing_text = string_field(data, "nothing") || ""

          case maybe_val do
            :nothing ->
              {:ok, nothing_text}

            {:just, n} ->
              format_maybe_int(n, map_field(data, "format"))

            _ ->
              :unsupported
          end

        _ ->
          :unsupported
      end
    else
      _ -> :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :list_concat_reversed_row_slices, fusion_data: data}, opts) do
    [cells | _] = Keyword.get(opts, :params, [])

    with width when is_integer(width) <- int_field(data, "width"),
         rows when is_integer(rows) <- int_field(data, "rows") do
      board = normalize_board(cells)

      reversed =
        for row <- 0..(rows - 1),
            col <- 0..(width - 1),
            do: cell_at(board, row, width, width - 1 - col)

      {:ok, reversed}
    else
      _ -> :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :row_slice_adjacent_merge, fusion_data: data}, opts) do
    [cells | _] = Keyword.get(opts, :params, [])

    with width when is_integer(width) <- int_field(data, "width"),
         rows when is_integer(rows) <- int_field(data, "rows") do
      board = normalize_board(cells)
      {flat, score} = collapse_adjacent_rows(board, width, rows)
      {:ok, {:record, [flat, score]}}
    else
      _ -> :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :union_int_suffix, fusion_data: data}, opts) do
    params = Keyword.get(opts, :params, [])

    case union_suffix_mode(data) do
      :direct ->
        [union_val | _] = params

        with {:union, tag, payload} <- normalize_union(union_val),
             branch when is_map(branch) <- suffix_branch_for_tag(data, tag) do
          {:ok, format_suffix_branch(branch, payload)}
        else
          _ -> :unsupported
        end

      :maybe_map_field ->
        [model | _] = params

        with outer_idx when is_integer(outer_idx) <- int_field(data, "outer_field"),
             inner_idx when is_integer(inner_idx) <- int_field(data, "inner_field") do
          case record_maybe_field(model, outer_idx) do
            :nothing ->
              {:ok, string_field(data, "nothing") || ""}

            {:just, {:record, fields}} ->
              case record_union_field({:record, fields}, inner_idx) do
                {:union, tag, payload} ->
                  case suffix_branch_for_tag(data, tag) do
                    branch when is_map(branch) -> {:ok, format_suffix_branch(branch, payload)}
                    _ -> :unsupported
                  end

                _ ->
                  :unsupported
              end

            _ ->
              :unsupported
          end
        else
          _ -> :unsupported
        end

      :maybe_field ->
        [model | _] = params

        with idx when is_integer(idx) <- int_field(data, "field") do
          case record_maybe_field(model, idx) do
            :nothing ->
              {:ok, string_field(data, "nothing") || ""}

            {:just, union_val} ->
              with {:union, tag, payload} <- normalize_union(union_val) do
                case suffix_branch_for_tag(data, tag) do
                  branch when is_map(branch) -> {:ok, format_suffix_branch(branch, payload)}
                  _ -> :unsupported
                end
              else
                _ -> :unsupported
              end

            _ ->
              :unsupported
          end
        else
          _ -> :unsupported
        end

      _ ->
        :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :union_case_four_perm, fusion_data: data}, opts) do
    [tag, cells | _] = Keyword.get(opts, :params, [])

    with width when is_integer(width) <- int_field(data, "width"),
         rows when is_integer(rows) <- int_field(data, "rows"),
         tags when is_list(tags) <- tags_field(data) do
      perm_case = tag_to_perm_case(tag, tags)

      table =
        case perm_mode(data) do
          :inverse -> RowMajorLayout.inverse_perm_table(width, rows)
          _ -> RowMajorLayout.forward_perm_table(width, rows)
        end

      perm = Enum.at(table, perm_case, hd(table))
      board = normalize_board(cells)
      count = width * rows

      {:ok,
       Enum.map(0..(count - 1), fn dest ->
         src = Enum.at(perm, dest, dest)
         Enum.at(board, src, 0)
       end)}
    else
      _ -> :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :maybe_with_default_pick_slot, fusion_data: data}, opts) do
    [model | _] = Keyword.get(opts, :params, [])

    with default when is_integer(default) <- int_field(data, "default"),
         {pick_mod, pick_name} <- callee_field(data, "pick"),
         {slots_mod, slots_name} <- callee_field(data, "slots") do
      slots =
        case invoke_callee(opts, {slots_mod, slots_name}, [model]) do
          list when is_list(list) -> list
          _ -> []
        end

      picked =
        case invoke_callee(opts, {pick_mod, pick_name}, [model, slots]) do
          nil -> default
          :nothing -> default
          {:just, v} -> as_int(v)
          v when is_integer(v) -> v
          _ -> default
        end

      {:ok, picked}
    else
      _ -> :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :list_map_static_index_at, fusion_data: data}, opts) do
    [list | _] = Keyword.get(opts, :params, [])

    with default when is_integer(default) <- int_field(data, "default"),
         indices when is_list(indices) <- indices_field(data) do
      board = normalize_board(list)

      {:ok,
       Enum.map(indices, fn idx ->
         index = as_int(idx)
         if index >= 0 and index < length(board), do: Enum.at(board, index), else: default
       end)}
    else
      _ -> :unsupported
    end
  end

  def run(%FunctionPlan{fusion_kind: :permute_merge_inverse_pipeline, fusion_data: data}, opts) do
    [direction, model | _] = Keyword.get(opts, :params, [])

    with width when is_integer(width) <- int_field(data, "width"),
         rows when is_integer(rows) <- int_field(data, "rows"),
         tags when is_list(tags) <- tags_field(data),
         fields when is_map(fields) <- map_field(data, "fields"),
         cells_idx when is_integer(cells_idx) <- int_field(fields, "cells"),
         seed_idx when is_integer(seed_idx) <- int_field(fields, "seed"),
         score_idx when is_integer(score_idx) <- int_field(fields, "score"),
         best_idx when is_integer(best_idx) <- int_field(fields, "best"),
         turn_idx when is_integer(turn_idx) <- int_field(fields, "turn"),
         storage_key when is_integer(storage_key) <- int_field(data, "storage_key") do
      src = record_field_list(model, cells_idx)
      perm_case = tag_to_perm_case(direction, tags)
      count = width * rows

      forward_perm =
        RowMajorLayout.forward_perm_table(width, rows)
        |> Enum.at(perm_case, hd(RowMajorLayout.forward_perm_table(width, rows)))

      inverse_perm =
        RowMajorLayout.inverse_perm_table(width, rows)
        |> Enum.at(perm_case, hd(RowMajorLayout.inverse_perm_table(width, rows)))

      perm_buf = apply_row_major_perm(src, forward_perm, count)
      {merge_buf, merge_score} = collapse_adjacent_rows(perm_buf, width, rows)
      out_buf = apply_row_major_perm(merge_buf, inverse_perm, count)

      if out_buf == src do
        {:ok, {:tuple2, model, 0}}
      else
        model_seed = record_field(model, seed_idx)
        model_score = record_field(model, score_idx)
        model_best = record_field(model, best_idx)
        model_turn = record_field(model, turn_idx)
        {next_cells, next_seed} = spawn_tile_once(out_buf, model_seed)
        next_score = model_score + merge_score
        next_best = max(model_best, next_score)
        next_turn = model_turn + 1

        next_model =
          model
          |> record_set_field(cells_idx, next_cells)
          |> record_set_field(seed_idx, next_seed)
          |> record_set_field(score_idx, next_score)
          |> record_set_field(best_idx, next_best)
          |> record_set_field(turn_idx, next_turn)

        cmd =
          if next_best > model_best do
            {:pebble_cmd, :cmd1_string, 26, [storage_key, Integer.to_string(next_best)]}
          else
            0
          end

        {:ok, {:tuple2, next_model, cmd}}
      end
    else
      _ -> :unsupported
    end
  end

  def run(%FunctionPlan{}, _opts), do: :unsupported

  defp list_int_search_walk(_target, _index, [], not_found), do: not_found

  defp list_int_search_walk(target, index, [head | rest], not_found) do
    if as_int(head) == 0 do
      if target == 0 do
        index
      else
        list_int_search_walk(target - 1, index + 1, rest, not_found)
      end
    else
      list_int_search_walk(target, index + 1, rest, not_found)
    end
  end

  defp collapse_adjacent_rows(board, width, rows) do
    Enum.reduce(0..(rows - 1), {[], 0}, fn row, {acc_cells, acc_score} ->
      buf =
        for col <- 0..(width - 1),
            cell = cell_at(board, row, width, col),
            cell != 0,
            do: cell

      {merged, row_score} = merge_adjacent_row(buf)
      padded = merged ++ List.duplicate(0, max(width - length(merged), 0))
      {acc_cells ++ Enum.take(padded, width), acc_score + row_score}
    end)
  end

  defp merge_adjacent_row(cells) do
    merge_adjacent_walk(cells, [], 0)
  end

  defp merge_adjacent_walk([], merged, score), do: {Enum.reverse(merged), score}

  defp merge_adjacent_walk([a, b | rest], merged, score) when a == b do
    v = a + b
    merge_adjacent_walk(rest, [v | merged], score + v)
  end

  defp merge_adjacent_walk([a | rest], merged, score) do
    merge_adjacent_walk(rest, [a | merged], score)
  end

  defp union_suffix_mode(data) do
    case map_field(data, "mode") || map_field(data, :mode) do
      "direct" -> :direct
      :direct -> :direct
      "maybe_map_field" -> :maybe_map_field
      :maybe_map_field -> :maybe_map_field
      "maybe_field" -> :maybe_field
      :maybe_field -> :maybe_field
      _ -> nil
    end
  end

  defp suffix_branch_for_tag(data, tag) do
    branches = map_field(data, "branches") || map_field(data, :branches) || []

    Enum.find(branches, fn branch ->
      branch_tag = map_field(branch, "tag") || map_field(branch, :tag)
      as_int(branch_tag) == as_int(tag)
    end)
  end

  defp format_suffix_branch(branch, payload) do
    prefix = string_field(branch, "prefix") || ""
    suffix = string_field(branch, "suffix") || ""
    int_val = eval_suffix_int(payload, map_field(branch, "expr") || map_field(branch, :expr) || %{})
    prefix <> Integer.to_string(int_val) <> suffix
  end

  defp eval_suffix_int(payload, expr) do
    n = union_int_payload(payload)

    case map_field(expr, "kind") || map_field(expr, :kind) do
      k when k in ["scaled", :scaled] ->
        offset = int_field(expr, "offset") || 0
        divisor = int_field(expr, "divisor") || 1
        div(n + offset, divisor)

      _ ->
        n
    end
  end

  defp normalize_union({:union, tag, payload}), do: {:union, as_int(tag), payload}
  defp normalize_union(other), do: {:union, as_int(other), 0}

  defp union_int_payload(payload) when is_integer(payload), do: payload
  defp union_int_payload({:just, v}), do: as_int(v)
  defp union_int_payload(v), do: as_int(v)

  defp record_union_field({:record, fields}, idx) when is_integer(idx) do
    case Enum.at(fields, idx) do
      {:union, tag, payload} -> {:union, as_int(tag), payload}
      other -> normalize_union(other)
    end
  end

  defp record_union_field(_, _), do: :error

  defp perm_mode(data) do
    case map_field(data, "mode") || map_field(data, :mode) do
      "inverse" -> :inverse
      :inverse -> :inverse
      _ -> :forward
    end
  end

  defp tags_field(data) do
    case map_field(data, "tags") || map_field(data, :tags) do
      list when is_list(list) -> list
      _ -> nil
    end
  end

  defp tag_to_perm_case(tag, tags) do
    wanted = as_int(tag)

    case Enum.find_index(tags, fn entry -> as_int(entry) == wanted end) do
      nil -> 0
      idx -> idx
    end
  end

  defp maybe_int_mode(data) do
    case map_field(data, "mode") || map_field(data, :mode) do
      "default_append" -> :default_append
      :default_append -> :default_append
      "maybe_case" -> :maybe_case
      :maybe_case -> :maybe_case
      _ -> nil
    end
  end

  defp record_maybe_field({:record, fields}, idx) when is_integer(idx) do
    case Enum.at(fields, idx) do
      {:just, v} -> {:just, v}
      nil -> :nothing
      v when is_integer(v) -> {:just, v}
      _ -> :nothing
    end
  end

  defp record_maybe_field(_, _), do: :nothing

  defp maybe_with_default_int(:nothing, default), do: default
  defp maybe_with_default_int({:just, n}, _default), do: as_int(n)

  defp format_maybe_int(n, format) when is_map(format) do
    kind = map_field(format, "kind") || map_field(format, :kind)
    suffix = string_field(format, "suffix") || ""

    case kind do
      k when k in ["threshold", :threshold] ->
        threshold = int_field(format, "threshold")
        divisor = int_field(format, "divisor") || 1

        if n >= threshold do
          {:ok, Integer.to_string(div(n, divisor)) <> suffix}
        else
          {:ok, Integer.to_string(n)}
        end

      k when k in ["plain", :plain] ->
        {:ok, Integer.to_string(n) <> suffix}

      _ ->
        {:ok, Integer.to_string(n)}
    end
  end

  defp format_maybe_int(n, _), do: {:ok, Integer.to_string(n)}

  defp fusion_mode(data) do
    case map_field(data, "mode") || map_field(data, :mode) do
      "help" -> :help
      :help -> :help
      "delegate" -> :delegate
      :delegate -> :delegate
      _ -> nil
    end
  end

  defp load_spawn_board(data, count, opts) do
    case board_source(data) do
      :zeros ->
        List.duplicate(0, count)

      {mod, name} ->
        case invoke_callee(opts, {mod, name}, []) do
          list when is_list(list) -> normalize_board(list)
          _ -> List.duplicate(0, count)
        end

      _ ->
        List.duplicate(0, count)
    end
  end

  defp board_source(data) do
    case map_field(data, "board") || map_field(data, :board) do
      "zeros" -> :zeros
      :zeros -> :zeros
      %{"module" => mod, "name" => name} -> {mod, name}
      %{module: mod, name: name} -> {mod, name}
      {mod, name} when is_binary(mod) and is_binary(name) -> {mod, name}
      _ -> :zeros
    end
  end

  defp spawn_tile_chained(buf, seed, passes) when passes >= 1 do
    Enum.reduce(1..passes, {buf, seed}, fn _pass, {cells, seed_work} ->
      spawn_tile_once(cells, seed_work)
    end)
  end

  defp spawn_tile_once(cells, seed) do
    after_choice = lcg(seed)
    after_tile = lcg(after_choice)
    empty_count = Enum.count(cells, &(&1 == 0))

    updated =
      if empty_count > 0 do
        pick = rem(after_choice, empty_count)
        index = nth_empty_index(cells, pick)

        tile = if rem(after_tile, 10) == 0, do: 4, else: 2
        List.replace_at(cells, index, tile)
      else
        cells
      end

    {updated, after_tile}
  end

  defp nth_empty_index(cells, pick) do
    cells
    |> Enum.with_index()
    |> Enum.filter(fn {cell, _} -> cell == 0 end)
    |> Enum.at(pick)
    |> case do
      {_, idx} -> idx
      nil -> 0
    end
  end

  defp lcg(seed) do
    rem(seed * 16807 + 11, 2147483647)
  end

  defp normalize_lut(data) do
    case map_field(data, "lut") || map_field(data, :lut) do
      lut when is_map(lut) ->
        Map.new(lut, fn {k, v} ->
          key =
            cond do
              is_integer(k) -> k
              is_binary(k) -> String.to_integer(k)
              true -> as_int(k)
            end

          {key, as_int(v)}
        end)

      _ ->
        nil
    end
  end

  defp normalize_string_lut(data) do
    case map_field(data, "lut") || map_field(data, :lut) do
      lut when is_map(lut) ->
        Map.new(lut, fn {k, v} ->
          key =
            cond do
              is_integer(k) -> k
              is_binary(k) -> String.to_integer(k)
              true -> as_int(k)
            end

          {key, to_string(v)}
        end)

      _ ->
        nil
    end
  end

  defp indices_field(data) do
    case map_field(data, "indices") || map_field(data, :indices) do
      list when is_list(list) -> list
      _ -> nil
    end
  end

  defp string_field(data, "default"), do: map_field(data, "default") || map_field(data, :default)
  defp string_field(data, key) when is_binary(key), do: map_field(data, key)

  defp normalize_table(%{"outer_mod" => outer_mod, "rows" => rows}) do
    {:ok, %{outer_mod: outer_mod, rows: normalize_rows(rows)}}
  end

  defp normalize_table(%{outer_mod: outer_mod, rows: rows}) do
    {:ok, %{outer_mod: outer_mod, rows: normalize_rows(rows)}}
  end

  defp normalize_table(_), do: :error

  defp normalize_rows(rows) when is_list(rows) do
    Enum.map(rows, fn row ->
      kind = Map.get(row, "kind") || Map.get(row, :kind)
      rotations = Map.get(row, "rotations") || Map.get(row, :rotations) || []

      {kind,
       Enum.map(rotations, fn rot_row ->
         rot = Map.get(rot_row, "rot") || Map.get(rot_row, :rot)
         pairs = Map.get(rot_row, "pairs") || Map.get(rot_row, :pairs) || []
         {rot, pairs}
       end)}
    end)
  end

  defp lookup_pairs(%{outer_mod: outer_mod, rows: rows}, kind, rot) do
    k = positive_mod(as_int(kind), outer_mod)
    r = positive_mod(as_int(rot), 4)

    case Enum.find(rows, fn {row_kind, _} -> row_kind == k end) do
      {_, rotations} ->
        case Enum.find(rotations, fn {row_rot, _} -> row_rot == r end) do
          {_, pairs} -> pairs
          _ -> []
        end

      _ ->
        []
    end
  end

  defp count_full_rows(board, rows, cols) do
    Enum.count(0..(rows - 1), &row_full?(board, &1, cols))
  end

  defp row_full?(board, row, cols) do
    Enum.all?(0..(cols - 1), fn col -> cell_at(board, row, cols, col) != 0 end)
  end

  defp cell_at(board, row, cols, col) do
    index = row * cols + col
    Enum.at(board, index, 0) |> as_int()
  end

  defp normalize_board(list) when is_list(list), do: Enum.map(list, &as_int/1)
  defp normalize_board(_), do: []

  defp record_field({:record, fields}, idx) when is_integer(idx),
    do: Enum.at(fields, idx, 0) |> as_int()

  defp record_field(_, _), do: 0

  defp record_field_list({:record, fields}, idx) when is_integer(idx) do
    case Enum.at(fields, idx) do
      list when is_list(list) -> normalize_board(list)
      _ -> []
    end
  end

  defp record_field_list(_, _), do: []

  defp record_set_field({:record, fields} = _model, idx, value) when is_integer(idx) do
    {:record, List.replace_at(pad_record_fields(fields, idx + 1), idx, value)}
  end

  defp record_set_field(other, idx, value) when is_integer(idx) do
    {:record, List.replace_at(List.duplicate(nil, idx + 1), idx, value)}
  end

  defp pad_record_fields(fields, size) when length(fields) >= size, do: fields
  defp pad_record_fields(fields, size), do: fields ++ List.duplicate(nil, size - length(fields))

  defp apply_row_major_perm(board, perm, count) do
    Enum.map(0..(count - 1), fn dest ->
      src = Enum.at(perm, dest, dest)
      Enum.at(board, src, 0)
    end)
  end

  defp invoke_callee(opts, {mod, name}, params) do
    plans = Keyword.get(opts, :plans, %{})

    case Map.get(plans, {mod, name}) do
      %FunctionPlan{} = plan ->
        case Runtime.run_function(plan, Keyword.merge(opts, params: params)) do
          {:ok, val} -> val
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp int_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp map_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp map_field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp callee_field(map, key) do
    case map_field(map, key) do
      %{"module" => mod, "name" => name} -> {mod, name}
      %{module: mod, name: name} -> {mod, name}
      {mod, name} when is_binary(mod) and is_binary(name) -> {mod, name}
      _ -> :error
    end
  end

  defp as_int(n) when is_integer(n), do: n
  defp as_int(n) when is_float(n), do: trunc(n)
  defp as_int({:tuple2, a, _}), do: as_int(a)
  defp as_int(_), do: 0

  defp positive_mod(value, base) when base > 0 do
    rem = rem(value, base)
    if rem < 0, do: rem + base, else: rem
  end
end
