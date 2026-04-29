defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Time do
  @moduledoc false

  @spec eval(String.t(), term()) :: {:ok, term()} | :no_builtin
  def eval("millistoposix", [value]) when is_integer(value),
    do: {:ok, %{"ctor" => "Posix", "args" => [value]}}

  def eval("millistoposix", [value]) when is_number(value),
    do: {:ok, %{"ctor" => "Posix", "args" => [trunc(value)]}}

  def eval("posixtomillis", [value]) do
    case posix_millis(value) do
      {:ok, millis} -> {:ok, millis}
      :error -> :no_builtin
    end
  end

  def eval("toadjustedminutes", [zone, posix]) do
    with {:ok, {default_offset, eras}} <- zone_parts(zone),
         {:ok, millis} <- posix_millis(posix) do
      posix_minutes = floor(millis / 60_000)
      {:ok, adjusted_minutes(default_offset, posix_minutes, eras)}
    else
      _ -> :no_builtin
    end
  end

  def eval("pointone", []), do: {:ok, 100}
  def eval(_function_name, _values), do: :no_builtin

  @spec eval_kernel(String.t(), term()) :: {:ok, term()} | :no_builtin
  def eval_kernel("nowmillis", [_unit]), do: {:ok, System.system_time(:millisecond)}
  def eval_kernel("zoneoffsetminutes", [_unit]), do: {:ok, kernel_zone_offset_minutes()}
  def eval_kernel("every", [_interval, _tagger]), do: {:ok, 1}
  def eval_kernel(_function_name, _values), do: :no_builtin

  @spec posix_millis(term()) :: {:ok, integer()} | :error
  defp posix_millis(value) when is_integer(value), do: {:ok, value}
  defp posix_millis(value) when is_float(value), do: {:ok, trunc(value)}

  defp posix_millis(%{"ctor" => "Posix", "args" => [millis]}) when is_integer(millis),
    do: {:ok, millis}

  defp posix_millis(%{"ctor" => "Posix", "args" => [millis]}) when is_float(millis),
    do: {:ok, trunc(millis)}

  defp posix_millis(%{ctor: "Posix", args: [millis]}) when is_integer(millis),
    do: {:ok, millis}

  defp posix_millis(%{ctor: "Posix", args: [millis]}) when is_float(millis),
    do: {:ok, trunc(millis)}

  defp posix_millis(_), do: :error

  @spec zone_parts(term()) :: {:ok, {integer(), list()}} | :error
  defp zone_parts(%{"ctor" => "Zone", "args" => [default_offset, eras]})
       when is_integer(default_offset) and is_list(eras),
       do: {:ok, {default_offset, eras}}

  defp zone_parts(%{ctor: "Zone", args: [default_offset, eras]})
       when is_integer(default_offset) and is_list(eras),
       do: {:ok, {default_offset, eras}}

  defp zone_parts(_), do: :error

  @spec adjusted_minutes(integer(), integer(), list()) :: integer()
  defp adjusted_minutes(default_offset, posix_minutes, []), do: posix_minutes + default_offset

  defp adjusted_minutes(default_offset, posix_minutes, [era | older_eras]) do
    case era_parts(era) do
      {:ok, start, offset} ->
        if start < posix_minutes do
          posix_minutes + offset
        else
          adjusted_minutes(default_offset, posix_minutes, older_eras)
        end

      :error ->
        adjusted_minutes(default_offset, posix_minutes, older_eras)
    end
  end

  @spec era_parts(term()) :: {:ok, integer(), integer()} | :error
  defp era_parts(%{"start" => start, "offset" => offset})
       when is_integer(start) and is_integer(offset),
       do: {:ok, start, offset}

  defp era_parts(%{start: start, offset: offset})
       when is_integer(start) and is_integer(offset),
       do: {:ok, start, offset}

  defp era_parts(_), do: :error

  @spec kernel_zone_offset_minutes() :: integer()
  defp kernel_zone_offset_minutes do
    local_seconds =
      :calendar.local_time()
      |> :calendar.datetime_to_gregorian_seconds()

    utc_seconds =
      :calendar.universal_time()
      |> :calendar.datetime_to_gregorian_seconds()

    div(local_seconds - utc_seconds, 60)
  end
end
