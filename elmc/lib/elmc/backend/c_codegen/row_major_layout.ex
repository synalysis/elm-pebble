defmodule Elmc.Backend.CCodegen.RowMajorLayout do
  @moduledoc false

  @spec identity_perm(non_neg_integer()) :: [non_neg_integer()]
  def identity_perm(count), do: Enum.to_list(0..(count - 1))

  @spec reverse_rows_perm(pos_integer(), pos_integer()) :: [non_neg_integer()]
  def reverse_rows_perm(width, rows) do
    for out_i <- 0..(rows * width - 1) do
      r = div(out_i, width)
      c = rem(out_i, width)
      r * width + (width - 1 - c)
    end
  end

  @spec transpose_perm(pos_integer(), pos_integer()) :: [non_neg_integer()]
  def transpose_perm(width, rows) do
    for out_i <- 0..(rows * width - 1) do
      out_c = div(out_i, width)
      out_r = rem(out_i, width)
      out_r * width + out_c
    end
  end

  @spec compose_perms([non_neg_integer()], [non_neg_integer()]) :: [non_neg_integer()]
  def compose_perms(first, second) do
    for i <- 0..(length(first) - 1) do
      Enum.at(first, Enum.at(second, i))
    end
  end

  @spec forward_perm_table(pos_integer(), pos_integer()) :: [[non_neg_integer()]]
  def forward_perm_table(width, rows) do
    count = rows * width
    id = identity_perm(count)
    rr = reverse_rows_perm(width, rows)
    tr = transpose_perm(width, rows)
    fourth = compose_perms(tr, rr)
    [id, rr, tr, fourth]
  end

  @spec inverse_perm_table(pos_integer(), pos_integer()) :: [[non_neg_integer()]]
  def inverse_perm_table(width, rows) do
    count = rows * width
    id = identity_perm(count)
    rr = reverse_rows_perm(width, rows)
    tr = transpose_perm(width, rows)
    fourth = compose_perms(rr, tr)
    [id, rr, tr, fourth]
  end

  @spec perm_table_c(String.t(), [[non_neg_integer()]]) :: String.t()
  def perm_table_c(table_name, perms) do
    rows =
      perms
      |> Enum.with_index()
      |> Enum.map_join(",\n", fn {perm, index} ->
        values = Enum.join(perm, ", ")
        "  { #{values} } /* #{index} */"
      end)

    """
    static const elmc_int_t #{table_name}[#{length(perms)}][#{length(hd(perms))}] = {
    #{rows}
    };
    """
  end

  @spec emit_apply_row_major_perm(
          :forward | :inverse,
          pos_integer(),
          pos_integer(),
          String.t(),
          String.t(),
          String.t(),
          pos_integer() | nil
        ) :: String.t()
  def emit_apply_row_major_perm(mode, width, rows, src_buf, dst_buf, perm_case_var, count \\ nil) do
    total = count || rows * width
    fourth_src = fourth_branch_src_index(mode, width)

    """
    for (elmc_int_t perm_i = 0; perm_i < #{total}; perm_i++) {
      const elmc_int_t col = perm_i % #{width};
      const elmc_int_t row = perm_i / #{width};
      elmc_int_t src_i;
      switch (#{perm_case_var}) {
        case 0:
          src_i = perm_i;
          break;
        case 1:
          src_i = row * #{width} + (#{width} - 1 - col);
          break;
        case 2:
          src_i = col * #{width} + row;
          break;
        case 3:
          #{fourth_src};
          break;
        default:
          src_i = perm_i;
          break;
      }
      #{dst_buf}[perm_i] = #{src_buf}[src_i];
    }
    """
  end

  @spec emit_perm_src_index_fn(pos_integer()) :: String.t()
  def emit_perm_src_index_fn(width) do
    """
    static elmc_int_t elmc_row_major_perm_src_i(elmc_int_t perm_i, int perm_case, bool inverse_branch) {
      const elmc_int_t col = perm_i % #{width};
      const elmc_int_t row = perm_i / #{width};
      switch (perm_case) {
        case 0:
          return perm_i;
        case 1:
          return row * #{width} + (#{width} - 1 - col);
        case 2:
          return col * #{width} + row;
        case 3:
          if (!inverse_branch) {
            const elmc_int_t rr_i = row * #{width} + (#{width} - 1 - col);
            return (rr_i % #{width}) * #{width} + (rr_i / #{width});
          } else {
            const elmc_int_t tr_i = col * #{width} + row;
            return (tr_i / #{width}) * #{width} + (#{width} - 1 - (tr_i % #{width}));
          }
        default:
          return perm_i;
      }
    }
    """
  end

  @spec emit_apply_row_major_perm_via_helper(
          String.t(),
          String.t(),
          String.t(),
          boolean(),
          non_neg_integer()
        ) :: String.t()
  def emit_apply_row_major_perm_via_helper(src_buf, dst_buf, perm_case_var, inverse_branch?, count) do
    inverse = if inverse_branch?, do: "true", else: "false"

    """
    for (elmc_int_t perm_i = 0; perm_i < #{count}; perm_i++) {
      #{dst_buf}[perm_i] = #{src_buf}[elmc_row_major_perm_src_i(perm_i, #{perm_case_var}, #{inverse})];
    }
    """
  end

  @spec emit_row_major_perm_tables(pos_integer(), pos_integer()) :: String.t()
  def emit_row_major_perm_tables(width, rows) do
    count = rows * width
    fwd = forward_perm_table(width, rows)
    inv = inverse_perm_table(width, rows)

    """
    static const uint8_t elmc_row_major_fwd_perm[#{length(fwd)}][#{count}] = {
    #{compact_perm_table_rows(fwd)}
    };
    static const uint8_t elmc_row_major_inv_perm[#{length(inv)}][#{count}] = {
    #{compact_perm_table_rows(inv)}
    };
    """
    |> String.trim()
  end

  @spec emit_apply_row_major_perm_via_table(
          String.t(),
          String.t(),
          String.t(),
          boolean(),
          non_neg_integer()
        ) :: String.t()
  def emit_apply_row_major_perm_via_table(src_buf, dst_buf, perm_case_var, inverse_branch?, count) do
    table = if inverse_branch?, do: "elmc_row_major_inv_perm", else: "elmc_row_major_fwd_perm"

    """
    for (elmc_int_t perm_i = 0; perm_i < #{count}; perm_i++) {
      #{dst_buf}[perm_i] = #{src_buf}[#{table}[#{perm_case_var}][perm_i]];
    }
    """
  end

  defp compact_perm_table_rows(perms) do
    perms
    |> Enum.with_index()
    |> Enum.map_join(",\n", fn {perm, index} ->
      values = Enum.map_join(perm, ", ", &Integer.to_string/1)
      "  { #{values} } /* #{index} */"
    end)
  end

  defp fourth_branch_src_index(:forward, width) do
    """
    {
      const elmc_int_t rr_i = row * #{width} + (#{width} - 1 - col);
      src_i = (rr_i % #{width}) * #{width} + (rr_i / #{width});
    }
    """
    |> String.trim()
  end

  defp fourth_branch_src_index(:inverse, width) do
    """
    {
      const elmc_int_t tr_i = col * #{width} + row;
      src_i = (tr_i / #{width}) * #{width} + (#{width} - 1 - (tr_i % #{width}));
    }
    """
    |> String.trim()
  end

  @spec emit_apply_perm(String.t(), String.t(), String.t(), non_neg_integer()) :: String.t()
  def emit_apply_perm(src_buf, dst_buf, perm_expr, count) do
    """
    for (elmc_int_t perm_i = 0; perm_i < #{count}; perm_i++) {
      #{dst_buf}[perm_i] = #{src_buf}[#{perm_expr}];
    }
    """
  end

  @spec emit_adjacent_pair_merge_rows(pos_integer(), pos_integer(), String.t(), String.t(), String.t()) ::
          String.t()
  def emit_adjacent_pair_merge_rows(width, rows, src_buf, dst_buf, score_var) do
    """
    for (elmc_int_t row = 0; row < #{rows}; row++) {
      elmc_int_t buf[#{width}];
      elmc_int_t n = 0;
      for (elmc_int_t col = 0; col < #{width}; col++) {
        const elmc_int_t cell = #{src_buf}[(row * #{width}) + col];
        if (cell != 0) buf[n++] = cell;
      }
      elmc_int_t merged[#{width}];
      elmc_int_t m = 0;
      elmc_int_t row_score = 0;
      elmc_int_t i = 0;
      while (i < n) {
        if (i + 1 < n && buf[i] == buf[i + 1]) {
          const elmc_int_t v = buf[i] + buf[i + 1];
          merged[m++] = v;
          row_score += v;
          i += 2;
        } else {
          merged[m++] = buf[i++];
        }
      }
      while (m < #{width}) merged[m++] = 0;
      #{score_var} += row_score;
      for (elmc_int_t col = 0; col < #{width}; col++) {
        #{dst_buf}[(row * #{width}) + col] = merged[col];
      }
    }
    """
  end

  @spec union_tag_expr(String.t()) :: String.t()
  def union_tag_expr(tag_var) do
    "(#{tag_var} && (#{tag_var})->tag == ELMC_TAG_INT ? elmc_as_int(#{tag_var}) : (#{tag_var} && (#{tag_var})->tag == ELMC_TAG_TUPLE2 && (#{tag_var})->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(#{tag_var})->payload)->first) : -1))"
  end

  @spec case_tag_perm_index_expr(String.t(), [integer()]) :: String.t()
  def case_tag_perm_index_expr(tag_var, ordered_tags) when length(ordered_tags) == 4 do
    [t0, t1, t2, t3] = ordered_tags

    """
    (#{tag_var} == #{t0} ? 0 :
      #{tag_var} == #{t1} ? 1 :
      #{tag_var} == #{t2} ? 2 :
      #{tag_var} == #{t3} ? 3 : 0)
    """
    |> String.trim()
  end
end
