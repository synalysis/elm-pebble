defmodule Elmx.Runtime.Core.Time do
  @moduledoc false

  alias Elmx.Runtime.Core.Task
  alias Elmx.Runtime.Values
  alias Elmx.Types

  @spec now() :: Types.task_native()
  def now, do: Task.succeed(corpus_now_millis())

  @spec corpus_now_millis() :: integer()
  def corpus_now_millis do
    case corpus_fixed_posix_millis() do
      millis when is_integer(millis) -> millis
      _ -> :os.system_time(:millisecond)
    end
  end

  defp corpus_fixed_posix_millis do
    Process.get(:elmx_corpus_fixed_posix_millis) ||
      Application.get_env(:elmx, :corpus_fixed_posix_millis)
  end

  @spec get_zone_name() :: Types.task_native()
  def get_zone_name do
    offset_min = div(DateTime.utc_now().utc_offset, 60)
    Task.succeed(Values.ctor("Offset", [offset_min]))
  end

  @spec zone_offset_minutes() :: integer()
  def zone_offset_minutes, do: div(DateTime.utc_now().utc_offset, 60)

  @spec custom_zone(integer(), list()) :: tuple()
  def custom_zone(offset_minutes, eras) when is_integer(offset_minutes) and is_list(eras) do
    {:Zone, offset_minutes, eras}
  end

  def custom_zone(_offset_minutes, _eras), do: {:Zone, 0, []}

  @spec posix_to_millis(integer()) :: integer()
  def posix_to_millis(millis) when is_integer(millis), do: millis
  def posix_to_millis(_), do: 0

  @spec millis_to_posix(integer()) :: integer()
  def millis_to_posix(millis) when is_integer(millis), do: millis
  def millis_to_posix(_), do: 0

  @spec to_year(term(), integer()) :: integer()
  def to_year(zone, millis), do: adjusted_datetime(zone, millis).year

  @spec to_month(term(), integer()) :: atom()
  def to_month(zone, millis) do
    ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)a
    |> Enum.at(adjusted_datetime(zone, millis).month - 1, :Dec)
  end

  @spec to_day(term(), integer()) :: integer()
  def to_day(zone, millis), do: adjusted_datetime(zone, millis).day

  @spec to_hour(term(), integer()) :: integer()
  def to_hour(zone, millis), do: adjusted_datetime(zone, millis).hour

  @spec to_minute(term(), integer()) :: integer()
  def to_minute(zone, millis), do: adjusted_datetime(zone, millis).minute

  @spec to_second(term(), integer()) :: integer()
  def to_second(_zone, millis) when is_integer(millis) do
    millis
    |> div(1000)
    |> Integer.mod(60)
  end

  def to_second(_zone, _millis), do: 0

  @spec to_millis(term(), integer()) :: integer()
  def to_millis(_zone, millis) when is_integer(millis), do: Integer.mod(millis, 1000)
  def to_millis(_zone, _millis), do: 0

  @spec adjusted_datetime(term(), integer()) :: DateTime.t()
  defp adjusted_datetime(zone, millis) when is_integer(millis) do
    offset_minutes = zone_offset(zone, div(millis, 60_000))

    millis
    |> Kernel.+(offset_minutes * 60_000)
    |> DateTime.from_unix!(:millisecond)
  end

  defp adjusted_datetime(zone, _millis), do: adjusted_datetime(zone, 0)

  defp zone_offset({:Zone, default_offset, eras}, posix_minutes)
       when is_integer(default_offset) and is_list(eras) do
    era_offset(eras, posix_minutes, default_offset)
  end

  defp zone_offset(%{"ctor" => "Zone", "args" => [default_offset, eras]}, posix_minutes)
       when is_integer(default_offset) and is_list(eras) do
    era_offset(eras, posix_minutes, default_offset)
  end

  defp zone_offset(_zone, _posix_minutes), do: 0

  defp era_offset([%{"start" => start, "offset" => offset} | _], posix_minutes, _default)
       when is_integer(start) and is_integer(offset) and start < posix_minutes,
       do: offset

  defp era_offset([%{start: start, offset: offset} | _], posix_minutes, _default)
       when is_integer(start) and is_integer(offset) and start < posix_minutes,
       do: offset

  defp era_offset([_ | rest], posix_minutes, default),
    do: era_offset(rest, posix_minutes, default)

  defp era_offset([], _posix_minutes, default), do: default
end
