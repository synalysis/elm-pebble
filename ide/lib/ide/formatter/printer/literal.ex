defmodule Ide.Formatter.Printer.Literal do
  @moduledoc false

  @spec normalize_escape_sequences(String.t()) :: String.t()
  def normalize_escape_sequences(source) when is_binary(source) do
    source
    |> normalize_hex_escape_sequences()
    |> normalize_nbsp_escape_sequences()
  end

  @spec normalize_hex_escape_sequences(term()) :: term()
  defp normalize_hex_escape_sequences(source) do
    Regex.replace(~r/\\x([0-9A-Fa-f]{2,6})/, source, fn _m, hex ->
      normalized =
        hex
        |> String.upcase()
        |> then(fn value ->
          if String.length(value) < 4 do
            String.pad_leading(value, 4, "0")
          else
            value
          end
        end)

      "\\u{#{normalized}}"
    end)
  end

  @spec normalize_nbsp_escape_sequences(term()) :: term()
  defp normalize_nbsp_escape_sequences(source) do
    String.replace(source, <<0xC2, 0xA0>>, "\\u{00A0}")
  end
end
