defmodule ElmEx.Frontend.Pretty.Literal do
  @moduledoc false
  @spec string_literal(String.t()) :: String.t()
  def string_literal(value) when is_binary(value) do
    "\"#{value |> normalize_source_escapes() |> escape_string()}\""
  end

  @spec char_literal(non_neg_integer()) :: String.t()
  def char_literal(codepoint) when is_integer(codepoint) do
    case escape_codepoint(codepoint) do
      escaped when is_binary(escaped) -> "'#{escaped}'"
    end
  end

  @spec escape_string(String.t()) :: String.t()
  def escape_string(value) when is_binary(value) do
    value
    |> normalize_source_escapes()
    |> String.to_charlist()
    |> Enum.map_join("", &escape_codepoint/1)
  end

  @spec normalize_source_escapes(String.t()) :: String.t()
  defp normalize_source_escapes(value) when is_binary(value) do
    Regex.replace(~r/\\x([0-9A-Fa-f]+)/u, value, fn _match, hex ->
      hex
      |> String.to_integer(16)
      |> codepoint_to_binary()
    end)
  end

  @spec codepoint_to_binary(non_neg_integer()) :: String.t()

  defp codepoint_to_binary(codepoint) when codepoint in 0..0x10FFFF,
    do: <<codepoint::utf8>>

  @spec escape_codepoint(non_neg_integer()) :: String.t()
  defp escape_codepoint(?\\), do: "\\\\"
  defp escape_codepoint(?"), do: "\\\""
  defp escape_codepoint(?\n), do: "\\n"
  defp escape_codepoint(?\t), do: "\\t"

  defp escape_codepoint(codepoint)
       when codepoint >= 32 and codepoint <= 126 and codepoint not in [?\\, ?", ?'] do
    <<codepoint::utf8>>
  end

  defp escape_codepoint(codepoint) when is_integer(codepoint) do
    unicode_escape(codepoint)
  end

  @doc false
  @spec unicode_escape(non_neg_integer()) :: String.t()
  def unicode_escape(codepoint) when codepoint < 0x10000 do
    hex = codepoint |> Integer.to_string(16) |> String.upcase()
    "\\u{#{String.pad_leading(hex, 4, "0")}}"
  end

  def unicode_escape(codepoint) do
    "\\u{#{codepoint |> Integer.to_string(16) |> String.upcase()}}"
  end
end
