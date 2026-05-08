defmodule Ide.Emulator.PebbleProtocol.CRC32 do
  @moduledoc false

  import Bitwise

  @polynomial 0x04C11DB7
  @initial 0xFFFFFFFF
  @mask 0xFFFFFFFF

  @spec stm32(binary()) :: non_neg_integer()
  def stm32(data) when is_binary(data) do
    data
    |> words()
    |> Enum.reduce(@initial, &add_word/2)
    |> band(@mask)
  end

  defp words(data) do
    full_size = div(byte_size(data), 4) * 4
    <<full::binary-size(full_size), rest::binary>> = data

    full_words =
      for <<word::little-32 <- full>> do
        word
      end

    case rest do
      <<>> ->
        full_words

      _ ->
        padding = :binary.copy(<<0>>, 4 - byte_size(rest))
        <<word::little-32>> = :binary.bin_to_list(padding <> rest) |> Enum.reverse() |> :binary.list_to_bin()
        full_words ++ [word]
    end
  end

  defp add_word(word, crc) do
    crc = bxor(crc, word)

    Enum.reduce(1..32, crc, fn _bit, value ->
      if band(value, 0x80000000) != 0 do
        value |> bsl(1) |> bxor(@polynomial) |> band(@mask)
      else
        value |> bsl(1) |> band(@mask)
      end
    end)
  end
end
