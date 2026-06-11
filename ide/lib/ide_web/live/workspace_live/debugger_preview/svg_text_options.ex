defmodule IdeWeb.WorkspaceLive.DebuggerPreview.SvgTextOptions do
  @moduledoc false

  @type text_alignment :: String.t()
  @type text_overflow :: String.t()
  @type wire_input :: integer() | String.t() | atom() | nil

  @spec normalized_alignment(wire_input()) :: text_alignment()
  def normalized_alignment(value) when is_integer(value) do
    case value do
      0 -> "left"
      2 -> "right"
      _ -> "center"
    end
  end

  def normalized_alignment(value) do
    case to_string(value || "center") do
      "0" -> "left"
      "2" -> "right"
      "left" -> "left"
      "right" -> "right"
      _ -> "center"
    end
  end

  @spec normalized_overflow(wire_input()) :: text_overflow()
  def normalized_overflow(value) do
    case to_string(value || "word_wrap") do
      "trailing_ellipsis" -> "trailing_ellipsis"
      "fill" -> "fill"
      _ -> "word_wrap"
    end
  end

  @spec alignment_name(integer()) :: text_alignment()
  def alignment_name(0), do: "left"
  def alignment_name(2), do: "right"
  def alignment_name(_), do: "center"

  @spec overflow_name(integer()) :: text_overflow()
  def overflow_name(1), do: "trailing_ellipsis"
  def overflow_name(2), do: "fill"
  def overflow_name(_), do: "word_wrap"
end
