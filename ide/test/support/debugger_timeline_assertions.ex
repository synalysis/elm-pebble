defmodule Ide.Test.DebuggerTimelineAssertions do
  @moduledoc false

  @type timeline_row :: map()
  @type target_filter :: :any | String.t() | atom()

  @spec count_updates([timeline_row()], target_filter(), (String.t() -> boolean()) | String.t()) ::
          non_neg_integer()
  def count_updates(timeline, target \\ :any, message_match)

  def count_updates(timeline, target, message_prefix)
      when is_list(timeline) and is_binary(message_prefix) do
    count_updates(timeline, target, &String.starts_with?(&1, message_prefix))
  end

  def count_updates(timeline, target, message_match)
      when is_list(timeline) and is_function(message_match, 1) do
    timeline
    |> update_rows(target)
    |> Enum.count(fn row -> message_match.(row_message(row)) end)
  end

  @spec assert_update_count(
          [timeline_row()],
          target_filter(),
          (String.t() -> boolean()) | String.t(),
          non_neg_integer()
        ) :: :ok
  def assert_update_count(timeline, target, message_match, expected_count)
      when is_integer(expected_count) and expected_count >= 0 do
    actual = count_updates(timeline, target, message_match)

    if actual == expected_count do
      :ok
    else
      raise "expected #{expected_count} update(s), got #{actual} for #{inspect(message_match)}"
    end
  end

  @spec refute_consecutive_duplicate_updates([timeline_row()], target_filter()) :: :ok
  def refute_consecutive_duplicate_updates(timeline, target \\ :any)
      when is_list(timeline) do
    rows =
      timeline
      |> update_rows(target)
      |> Enum.map(fn row ->
        {row_target(row), row_message(row)}
      end)

    case Enum.chunk_every(rows, 2, 1, :discard) do
      [] ->
        :ok

      pairs ->
        duplicate =
          Enum.find(pairs, fn
            [{t1, m1}, {t2, m2}] -> t1 == t2 and m1 == m2 and m1 != ""
            _ -> false
          end)

        if duplicate do
          [{t, m}, _] = duplicate
          raise "consecutive duplicate timeline update: target=#{inspect(t)} message=#{inspect(m)}"
        else
          :ok
        end
    end
  end

  @spec update_rows([timeline_row()], target_filter()) :: [timeline_row()]
  defp update_rows(timeline, target) do
    timeline
    |> Enum.filter(fn row ->
      type = Map.get(row, :type) || Map.get(row, "type")
      type in ["update", :update]
    end)
    |> Enum.filter(fn row ->
      case target do
        :any -> true
        expected ->
          actual = row_target(row)
          to_string(actual) == to_string(expected)
      end
    end)
  end

  defp row_target(row) do
    Map.get(row, :target) || Map.get(row, "target")
  end

  defp row_message(row) do
    to_string(Map.get(row, :message) || Map.get(row, "message") || "")
  end
end
