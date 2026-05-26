defmodule Ide.Debugger.Attrs do
  @moduledoc false

  alias Ide.Debugger.Types

  @default_tick_interval_ms 1_000

  @spec parse_checkbox_bool(Types.wire_input()) :: boolean()
  def parse_checkbox_bool(value) when value in [true, "true", "on", "1", 1], do: true
  def parse_checkbox_bool(_value), do: false

  @spec parse_tick_interval_ms(Types.wire_input()) :: pos_integer()
  def parse_tick_interval_ms(value) when is_integer(value) and value >= 100,
    do: min(value, 60_000)

  def parse_tick_interval_ms(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 100 -> min(parsed, 60_000)
      _ -> @default_tick_interval_ms
    end
  end

  def parse_tick_interval_ms(_value), do: @default_tick_interval_ms

  @spec parse_step_count(Types.wire_input()) :: pos_integer()
  def parse_step_count(value) when is_integer(value) and value >= 1, do: min(value, 50)

  def parse_step_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed >= 1 -> min(parsed, 50)
      _ -> 1
    end
  end

  def parse_step_count(_value), do: 1

  @spec parse_optional_cursor_seq(Types.wire_input()) :: non_neg_integer() | nil
  def parse_optional_cursor_seq(value) when is_integer(value) and value >= 0, do: value

  def parse_optional_cursor_seq(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n >= 0 -> n
      _ -> nil
    end
  end

  def parse_optional_cursor_seq(_value), do: nil
end
