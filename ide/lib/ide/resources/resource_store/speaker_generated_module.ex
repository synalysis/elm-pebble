defmodule Ide.Resources.ResourceStore.SpeakerGeneratedModule do
  @moduledoc false

  alias Ide.Resources.Types

  @type generated_sample_row :: %{
          ctor: String.t(),
          name: String.t(),
          format: non_neg_integer(),
          base_midi_note: non_neg_integer(),
          loop: boolean(),
          num_bytes: non_neg_integer()
        }

  @spec source([Types.manifest_wire_row()]) :: String.t()
  def source(entries) when is_list(entries) do
    rows =
      entries
      |> Enum.map(&normalize_row/1)
      |> Enum.reject(&(&1.ctor == ""))
      |> Enum.sort_by(& &1.ctor)

    ctors =
      case rows do
        [] -> ["NoSample"]
        list -> ["NoSample" | Enum.map(list, & &1.ctor)]
      end

    type_decl =
      case ctors do
        [only] ->
          "type Sample\n    = #{only}\n"

        list ->
          "type Sample\n    = " <> Enum.join(list, "\n    | ") <> "\n"
      end

    all_decl =
      case rows do
        [] ->
          """
          allSamples : List Sample
          allSamples =
              [ NoSample ]
          """

        _ ->
          names = Enum.map_join(rows, ", ", & &1.ctor)

          """
          allSamples : List Sample
          allSamples =
              [ #{names} ]
          """
      end

    sample_id_cases =
      "        NoSample ->\n            0" <>
        if rows == [] do
          ""
        else
          "\n" <>
            (rows
             |> Enum.with_index(1)
             |> Enum.map_join("\n", fn {row, index} ->
               "        #{row.ctor} ->\n            #{index}"
             end))
        end

    info_cases =
      """
              NoSample ->
                  { sample = NoSample
                  , name = "NoSample"
                  , format = 0
                  , baseMidiNote = 60
                  , loop = False
                  , numBytes = 0
                  }
      """ <>
        if rows == [] do
          ""
        else
          "\n" <> Enum.map_join(rows, "\n", fn row ->
            """
                    #{row.ctor} ->
                        { sample = #{row.ctor}
                        , name = #{inspect(row.name)}
                        , format = #{row.format}
                        , baseMidiNote = #{row.base_midi_note}
                        , loop = #{row.loop}
                        , numBytes = #{row.num_bytes}
                        }
            """
          end)
        end

    """
    module Pebble.Speaker.Resources exposing
        ( Sample(..)
        , SampleInfo
        , allSamples
        , sampleId
        , sampleInfo
        )


    {-| PCM sample uploaded via the IDE Resources panel. -}
    #{type_decl}

    {-| Metadata for a speaker PCM resource. -}
    type alias SampleInfo =
        { sample : Sample
        , name : String
        , format : Int
        , baseMidiNote : Int
        , loop : Bool
        , numBytes : Int
        }


    #{all_decl}


    {-| Stable resource index used by the runtime (`0` = synthesized notes only). -}
    sampleId : Sample -> Int
    sampleId sample =
        case sample of
    #{sample_id_cases}


    {-| Metadata for a speaker sample constructor. -}
    sampleInfo : Sample -> SampleInfo
    sampleInfo sample =
        case sample of
    #{info_cases}
    """
  end

  defp normalize_row(row) when is_map(row) do
    %{
      ctor: to_string(Map.get(row, "ctor", "")),
      name: to_string(Map.get(row, "ctor", "")),
      format: Map.get(row, "format", 1) |> coerce_int(1),
      base_midi_note: Map.get(row, "base_midi_note", 60) |> coerce_int(60),
      loop: Map.get(row, "loop", false) == true,
      num_bytes: Map.get(row, "bytes", 0) |> coerce_int(0)
    }
  end

  defp coerce_int(value, _default) when is_integer(value), do: max(value, 0)
  defp coerce_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> max(int, 0)
      :error -> default
    end
  end

  defp coerce_int(_, default), do: default
end
