defmodule Elmc.Backend.CCodegen.DirectRender.Emit.RecordGetHoistPass do
  @moduledoc false

  @record_get_pattern ~r/ELMC_RECORD_GET_INDEX_INT\((\w+), ([^)]+)\)/

  @min_occurrences 3

  @spec run(String.t()) :: String.t()
  def run(code) when is_binary(code) do
    groups =
      Regex.scan(@record_get_pattern, code)
      |> Enum.group_by(fn [_, record, field] -> {record, field} end)

    {hoists, replacements, _next} =
      Enum.reduce(groups, {%{}, %{}, 1}, fn
        {{_record, _field}, occurrences}, acc when length(occurrences) < @min_occurrences ->
          acc

        {{record, field}, [_first | _]}, {hoists, replacements, next} ->
          ref = "direct_hoisted_rec_#{next}"
          expr = "ELMC_RECORD_GET_INDEX_INT(#{record}, #{field})"
          init = "const elmc_int_t #{ref} = #{expr};"

          hoists = Map.put(hoists, {record, field}, init)
          replacements = Map.put(replacements, {record, field}, ref)
          {hoists, replacements, next + 1}
      end)

    if map_size(hoists) == 0 do
      code
    else
      preamble =
        hoists
        |> Map.values()
        |> Enum.join("\n    ")

      body =
        Enum.reduce(replacements, code, fn {{record, field}, ref}, acc ->
          String.replace(acc, "ELMC_RECORD_GET_INDEX_INT(#{record}, #{field})", ref)
        end)

      preamble <> "\n    " <> body
    end
  end
end
