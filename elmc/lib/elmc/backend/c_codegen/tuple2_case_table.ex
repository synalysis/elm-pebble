defmodule Elmc.Backend.CCodegen.Tuple2CaseTable do
  @moduledoc false

  alias Elmc.Backend.CCodegen.FusionSupport
  alias Elmc.Backend.CCodegen.Util

  @spec try_emit(String.t(), String.t(), map() | nil) ::
          {:ok, String.t(), [FusionSupport.callee_key()]} | {:ok, String.t(), [FusionSupport.callee_key()], :rc_native} | :error
  def try_emit(_module_name, _name, nil), do: :error

  def try_emit(module_name, name, expr) do
    with {:ok, outer_mod, outer_branches} <- parse_outer_case(expr),
         {:ok, rows} <- parse_rows(outer_branches),
         true <- length(rows) > 0 do
      FusionSupport.ok_rc(emit(module_name, name, outer_mod, rows), ["elmc_list_from_tuple2_int_array"])
    else
      _ -> :error
    end
  end

  @spec recognized?(String.t(), String.t(), map() | nil) :: boolean()
  def recognized?(module_name, name, expr) do
    case try_emit(module_name, name, expr) do
      {:ok, _, _, _} -> true
      _ -> false
    end
  end

  @spec table_shape(map() | nil) :: {:ok, integer(), integer()} | :error
  def table_shape(nil), do: :error

  def table_shape(expr) do
    with {:ok, outer_mod, outer_branches} <- parse_outer_case(expr),
         {:ok, rows} <- parse_rows(outer_branches),
         [{_k, inner} | _] <- rows,
         true <- length(inner) > 0 do
      {:ok, outer_mod, length(inner)}
    else
      _ -> :error
    end
  end

  defp parse_outer_case(%{
         op: :let_in,
         value_expr: value,
         in_expr: %{op: :case, branches: branches}
       }) do
    with {:ok, mod} <- mod_base(value) do
      {:ok, mod, branches}
    end
  end

  defp parse_outer_case(%{op: :case, subject: subject, branches: branches}) do
    with {:ok, mod} <- mod_base(subject) do
      {:ok, mod, branches}
    end
  end

  defp parse_outer_case(%{op: :let_in, in_expr: body}), do: parse_outer_case(body)

  defp parse_outer_case(_), do: :error

  defp mod_base(%{op: :call, name: "modBy", args: [%{op: :int_literal, value: mod}, _]}),
    do: {:ok, mod}

  defp mod_base(%{op: :qualified_call, target: target, args: [%{op: :int_literal, value: mod}, _]})
       when target in ["Basics.modBy", "modBy"],
       do: {:ok, mod}

  defp mod_base(_), do: :error

  defp parse_rows(branches) do
    rows =
      Enum.map(branches, fn branch ->
        index = int_pattern_index(branch.pattern)

        case parse_inner_cells(branch.expr) do
          {:ok, cells} -> {index, cells}
          :error -> nil
        end
      end)

    normalized = normalize_rows(rows)

    if normalized == [], do: :error, else: {:ok, normalized}
  end

  defp parse_inner_cells(expr) do
    case parse_inner_case(expr) do
      {:ok, cells} -> {:ok, cells}
      :error -> flat_rot_cells(expr)
    end
  end

  defp flat_rot_cells(expr) do
    case static_pairs(expr) do
      {:ok, pairs} -> {:ok, Enum.map(0..3, fn rot -> {rot, pairs} end)}
      :error -> :error
    end
  end

  defp normalize_rows(rows) do
    rows
    |> Enum.map(fn
      {:default, cells} -> {6, normalize_rot_cells(cells)}
      {index, cells} when is_integer(index) -> {index, normalize_rot_cells(cells)}
      _ -> nil
    end)
    |> then(fn
      normalized when length(normalized) == 7 ->
        if Enum.all?(normalized, fn row -> match?({_, _}, row) end), do: normalized, else: []

      _ ->
        []
    end)
  end

  defp normalize_rot_cells(cells) do
    cells
    |> Enum.map(fn
      {:default, pairs} -> {3, pairs}
      {rot, pairs} when is_integer(rot) -> {rot, pairs}
      _ -> nil
    end)
    |> then(fn
      normalized when length(normalized) == 4 ->
        if Enum.all?(normalized, fn cell -> match?({_, _}, cell) end),
          do: Enum.sort_by(normalized, fn {rot, _} -> rot end),
          else: nil

      _ ->
        nil
    end)
  end

  defp int_pattern_index(%{kind: :int, value: n}) when is_integer(n), do: n
  defp int_pattern_index(%{kind: :wildcard}), do: :default
  defp int_pattern_index(_), do: nil

  defp parse_inner_case(%{
         op: :let_in,
         value_expr: value,
         in_expr: %{op: :case, branches: branches}
       }) do
    with {:ok, 4} <- mod_base(value), {:ok, cells} <- parse_cells(branches), do: {:ok, cells}
  end

  defp parse_inner_case(%{op: :let_in, in_expr: body}), do: parse_inner_case(body)

  defp parse_inner_case(%{op: :case, subject: subject, branches: branches}) do
    with {:ok, 4} <- mod_base(subject),
         {:ok, cells} <- parse_cells(branches) do
      {:ok, cells}
    end
  end

  defp parse_inner_case(_), do: :error

  defp parse_cells(branches) do
    cells =
      Enum.map(branches, fn branch ->
        index = int_pattern_index(branch.pattern)

        case static_pairs(branch.expr) do
          {:ok, pairs} -> {index, pairs}
          :error -> nil
        end
      end)

    if Enum.any?(cells, &is_nil/1), do: :error, else: {:ok, cells}
  end

  defp static_pairs(%{op: :list_literal, items: items}) do
    pairs =
      Enum.map(items, fn
        %{op: :tuple2, left: %{op: :int_literal, value: a}, right: %{op: :int_literal, value: b}} ->
          {a, b}

        _ ->
          :error
      end)

    if Enum.any?(pairs, &(&1 == :error)), do: :error, else: {:ok, pairs}
  end

  defp static_pairs(_), do: :error

  defp emit(module_name, name, outer_mod, rows) do
    c_prefix = Util.module_fn_name(module_name, name)
    safe = Util.safe_c_suffix(name)
    kind_count = length(rows)

    array_defs =
      for {k, inner} <- rows,
          {r, pairs} <- inner,
          pairs != [] do
        values = Enum.map_join(pairs, ", ", fn {a, b} -> "{ #{a}, #{b} }" end)
        "static const elmc_int_t #{safe}_k#{k}_r#{r}[#{length(pairs)}][2] = { #{values} };"
      end

    table_type = "#{safe}_entry_t"

    table_rows =
      Enum.map_join(rows, ",\n", fn {k, inner} ->
        entries =
          Enum.map_join(inner, ", ", fn {r, pairs} ->
            "{ #{safe}_k#{k}_r#{r}, #{length(pairs)} }"
          end)

        "  { #{entries} }"
      end)

    """
    #{Enum.join(array_defs, "\n")}

    typedef struct { const elmc_int_t (*cells)[2]; int count; } #{table_type};

    static const #{table_type} #{safe}_table[#{kind_count}][4] = {
    #{table_rows}
    };

    static RC #{c_prefix}_native(ElmcValue **out, const elmc_int_t kind, const elmc_int_t rot) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        elmc_int_t k = kind % #{outer_mod};
        if (k < 0) k += #{outer_mod};
        elmc_int_t r = rot % 4;
        if (r < 0) r += 4;
        const #{table_type} *entry = &#{safe}_table[k][r];
        rc = elmc_list_from_tuple2_int_array(out, entry->cells, entry->count);
        CHECK_RC(rc);
      CATCH_END
      return rc;
    }
    """
  end
end
