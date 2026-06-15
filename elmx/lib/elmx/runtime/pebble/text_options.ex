defmodule Elmx.Runtime.Pebble.TextOptions do
  @moduledoc false

  alias Elmx.Types

  @type alignment :: String.t()
  @type overflow :: String.t()

  @doc """
  Normalizes Elm `TextOptions` runtime values to debugger/emulator string fields.
  """
  @spec fields(Types.ui_text_options() | nil) :: {alignment(), overflow()}
  def fields(options) do
    settings = collect_settings(options)

    {
      alignment_from_settings(settings, options),
      overflow_from_settings(settings, options)
    }
  end

  @spec collect_settings(Types.ui_text_options() | nil) :: [map()]
  defp collect_settings(nil), do: []
  defp collect_settings([]), do: []

  defp collect_settings(%{} = setting) do
    if context_setting?(setting) do
      [setting | collect_settings(Map.get(setting, "value") || Map.get(setting, :value))]
    else
      []
    end
  end

  defp collect_settings(list) when is_list(list),
    do: Enum.flat_map(list, &collect_settings/1)

  defp collect_settings(_), do: []

  defp context_setting?(map) do
    type = Map.get(map, "type") || Map.get(map, :type)
    to_string(type || "") == "contextSetting"
  end

  @spec alignment_from_settings([map()], Types.ui_text_options() | nil) :: alignment()
  defp alignment_from_settings(settings, options) do
    keys = Enum.map(settings, &setting_key/1)

    cond do
      "align_right" in keys -> "right"
      "align_left" in keys -> "left"
      "align_center" in keys -> "center"
      true -> alignment_from_map(options)
    end
  end

  @spec overflow_from_settings([map()], Types.ui_text_options() | nil) :: overflow()
  defp overflow_from_settings(settings, options) do
    keys = Enum.map(settings, &setting_key/1)

    cond do
      "fill_overflow" in keys -> "fill"
      "trailing_ellipsis" in keys -> "trailing_ellipsis"
      "word_wrap" in keys -> "word_wrap"
      true -> overflow_from_map(options)
    end
  end

  defp alignment_from_map(%{"alignment" => value}), do: alignment_name(value)
  defp alignment_from_map(%{alignment: value}), do: alignment_name(value)
  defp alignment_from_map(_), do: "center"

  defp overflow_from_map(%{"overflow" => value}), do: overflow_name(value)
  defp overflow_from_map(%{overflow: value}), do: overflow_name(value)
  defp overflow_from_map(_), do: "word_wrap"

  @spec setting_key(map()) :: String.t()
  defp setting_key(setting) do
    to_string(Map.get(setting, "key") || Map.get(setting, :key) || "")
  end

  @spec alignment_name(String.t() | atom() | integer()) :: alignment()
  defp alignment_name("left"), do: "left"
  defp alignment_name("right"), do: "right"
  defp alignment_name("center"), do: "center"
  defp alignment_name("AlignLeft"), do: "left"
  defp alignment_name("AlignRight"), do: "right"
  defp alignment_name("AlignCenter"), do: "center"
  defp alignment_name(0), do: "left"
  defp alignment_name(2), do: "right"
  defp alignment_name(_), do: "center"

  @spec overflow_name(String.t() | atom() | integer()) :: overflow()
  defp overflow_name("trailing_ellipsis"), do: "trailing_ellipsis"
  defp overflow_name("fill"), do: "fill"
  defp overflow_name("word_wrap"), do: "word_wrap"
  defp overflow_name("TrailingEllipsis"), do: "trailing_ellipsis"
  defp overflow_name("Fill"), do: "fill"
  defp overflow_name("WordWrap"), do: "word_wrap"
  defp overflow_name(1), do: "trailing_ellipsis"
  defp overflow_name(2), do: "fill"
  defp overflow_name(_), do: "word_wrap"
end
