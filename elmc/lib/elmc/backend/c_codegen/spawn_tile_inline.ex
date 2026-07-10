defmodule Elmc.Backend.CCodegen.SpawnTileInline do
  @moduledoc false

  @spec emit(String.t(), String.t(), pos_integer(), String.t() | nil) :: String.t()
  def emit(prefix, buf_var, count, seed_read \\ nil)
      when is_binary(prefix) and is_binary(buf_var) and is_integer(count) do
    seed_src = seed_read || prefix

    emit_cycle_body(buf_var, count, seed_src, prefix)
  end

  @spec emit_chained(pos_integer(), String.t(), pos_integer(), String.t()) :: String.t()
  def emit_chained(passes, buf_var, count, seed_read)
      when is_integer(passes) and passes >= 1 and is_binary(buf_var) and is_integer(count) and
             is_binary(seed_read) do
    """
    elmc_int_t seed_work = #{seed_read};
    for (int spawn_pass = 0; spawn_pass < #{passes}; spawn_pass++) {
      #{emit_cycle_body(buf_var, count, "seed_work", "spawn")}
      seed_work = spawn_after_tile;
    }
    """
    |> String.trim()
  end

  defp emit_cycle_body(buf_var, count, seed_src, prefix) do
    """
    const elmc_int_t #{prefix}_model = #{seed_src};
    elmc_int_t #{prefix}_after_choice = ((#{prefix}_model * 16807) + 11) % 2147483647;
    elmc_int_t #{prefix}_after_tile = ((#{prefix}_after_choice * 16807) + 11) % 2147483647;
    elmc_int_t #{prefix}_empty_count = 0;
    for (elmc_int_t spawn_scan_i = 0; spawn_scan_i < #{count}; spawn_scan_i++) {
      if (#{buf_var}[spawn_scan_i] == 0) #{prefix}_empty_count++;
    }
    if (#{prefix}_empty_count > 0) {
      const elmc_int_t spawn_pick = #{prefix}_after_choice % #{prefix}_empty_count;
      elmc_int_t spawn_seen_empty = 0;
      elmc_int_t spawn_tile_index = 0;
      for (elmc_int_t spawn_scan_i = 0; spawn_scan_i < #{count}; spawn_scan_i++) {
        if (#{buf_var}[spawn_scan_i] != 0) continue;
        if (spawn_seen_empty == spawn_pick) {
          spawn_tile_index = spawn_scan_i;
          break;
        }
        spawn_seen_empty++;
      }
      const elmc_int_t spawn_tile_roll = #{prefix}_after_tile % 10;
      #{buf_var}[spawn_tile_index] = spawn_tile_roll == 0 ? 4 : 2;
    }
    """
    |> String.trim()
  end
end
