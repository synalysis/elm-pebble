defmodule Elmc.Backend.CCodegen.DirectRender.Emit.RecordGetHoistPass do
  @moduledoc false

  @record_get_pattern ~r/ELMC_RECORD_GET_INDEX_INT\((\w+), (\d+) \/\* (\w+) \*\/\)/

  @min_occurrences 3

  @spec run(String.t()) :: String.t()
  def run(code) when is_binary(code) do
    groups =
      Regex.scan(@record_get_pattern, code)
      |> Enum.group_by(fn [_, record, index, _field] -> {record, index} end)

    {hoists, replacements, _next} =
      Enum.reduce(groups, {%{}, %{}, 1}, fn
        {{_record, _index}, occurrences}, acc when length(occurrences) < @min_occurrences ->
          acc

        {{record, index}, [first | _]}, {hoists, replacements, next} ->
          [_full, _record, _index, field] = first
          ref = "direct_hoisted_rec_#{next}"
          expr = "ELMC_RECORD_GET_INDEX_INT(#{record}, #{index} /* #{field} */)"
          init = "const elmc_int_t #{ref} = #{expr};"

          hoists = Map.put(hoists, {record, index}, init)
          replacements = Map.put(replacements, {record, index}, ref)
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
        Enum.reduce(replacements, code, fn {{record, index}, ref}, acc ->
          expr = ~r/ELMC_RECORD_GET_INDEX_INT\(#{record}, #{index} \/\* \w+ \*\/\)/
          String.replace(acc, expr, ref)
        end)

      preamble <> "\n    " <> body
    end
  end
end
