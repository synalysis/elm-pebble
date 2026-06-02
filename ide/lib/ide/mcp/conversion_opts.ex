defmodule Ide.Mcp.ConversionOpts do
  @moduledoc false

  @spec schema() :: map()
  def schema do
    %{
      "precise" => %{type: "boolean", default: false},
      "color_mode" => %{
        type: "string",
        enum: ["truncate", "nearest", "indexed"],
        default: "truncate"
      },
      "flatten_curves" => %{type: "boolean", default: false},
      "flatten_tolerance" => %{type: "number", default: 0.5},
      "frame_duration_ms" => %{type: "integer", default: 100, minimum: 1},
      "play_count" => %{type: "integer", default: 1, minimum: 1},
      "strict" => %{type: "boolean", default: false}
    }
  end

  @spec from_args(map()) :: keyword()
  def from_args(args) when is_map(args) do
    [
      precise: boolean_arg(args, "precise", false),
      color_mode: atom_color_mode(Map.get(args, "color_mode") || Map.get(args, :color_mode)),
      flatten_curves: boolean_arg(args, "flatten_curves", false),
      flatten_tolerance: float_arg(args, "flatten_tolerance", 0.5),
      frame_duration_ms: int_arg(args, "frame_duration_ms", 100),
      play_count: int_arg(args, "play_count", 1),
      strict: boolean_arg(args, "strict", false)
    ]
  end

  defp atom_color_mode("nearest"), do: :nearest
  defp atom_color_mode("indexed"), do: :indexed
  defp atom_color_mode("truncate"), do: :truncate
  defp atom_color_mode(:nearest), do: :nearest
  defp atom_color_mode(:indexed), do: :indexed
  defp atom_color_mode(_), do: :truncate

  defp boolean_arg(args, key, default) do
    case Map.get(args, key) || Map.get(args, String.to_atom(key)) do
      true -> true
      false -> false
      "true" -> true
      "false" -> false
      _ -> default
    end
  end

  defp int_arg(args, key, default) do
    case Map.get(args, key) || Map.get(args, String.to_atom(key)) do
      n when is_integer(n) ->
        n

      n when is_binary(n) ->
        case Integer.parse(n) do
          {value, _} -> value
          :error -> default
        end

      _ ->
        default
    end
  end

  @spec input_schema_properties() :: map()
  def input_schema_properties do
    schema()
    |> Enum.map(fn {key, meta} ->
      prop =
        meta
        |> Map.drop([:default])
        |> Enum.into(%{}, fn {k, v} -> {Atom.to_string(k), v} end)

      {key, prop}
    end)
    |> Map.new()
  end

  defp float_arg(args, key, default) do
    case Map.get(args, key) || Map.get(args, String.to_atom(key)) do
      n when is_number(n) ->
        n * 1.0

      n when is_binary(n) ->
        case Float.parse(n) do
          {value, _} -> value
          :error -> default
        end

      _ ->
        default
    end
  end
end
