defmodule Ide.Debugger.TextParityYesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.TextParity

  @moduletag :slow

  @fixture "yes_emery"
  # Centroid |dy|: mean alone previously hid top-of-dial min_y errors of −5..−6.
  @max_mean_abs_dy 1.0
  @max_per_label_abs_dy 1.5
  @max_mean_height_error 2.5

  test "yes dial labels match emulator ink placement within tolerance" do
    assert {:ok, report} = TextParity.compare_fixture(@fixture)

    missing =
      report.labels
      |> Enum.filter(fn row -> is_nil(row.emulator) or is_nil(row.debugger) end)
      |> Enum.map(& &1.text)

    assert missing == [],
           "missing ink bbox for labels: #{inspect(missing)}\n#{TextParity.format_report(report)}"

    assert report.mean_abs_dy <= @max_mean_abs_dy,
           "mean |dy| #{report.mean_abs_dy} > #{@max_mean_abs_dy}\n#{TextParity.format_report(report)}"

    assert report.max_abs_dy <= @max_per_label_abs_dy,
           "max |dy| #{report.max_abs_dy} > #{@max_per_label_abs_dy}\n#{TextParity.format_report(report)}"

    offenders = TextParity.labels_exceeding_abs_dy(report, @max_per_label_abs_dy)

    assert offenders == [],
           "labels exceeding |dy|≤#{@max_per_label_abs_dy}: " <>
             Enum.map_join(offenders, ", ", fn row ->
               "#{row.text}(dy=#{Float.round(row.dy * 1.0, 2)})"
             end) <>
             "\n#{TextParity.format_report(report)}"

    assert report.mean_height_error <= @max_mean_height_error,
           "mean height error #{report.mean_height_error} > #{@max_mean_height_error}\n#{TextParity.format_report(report)}"
  end
end
