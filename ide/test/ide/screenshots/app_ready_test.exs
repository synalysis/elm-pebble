defmodule Ide.Screenshots.AppReadyTest do
  use ExUnit.Case, async: true

  alias Ide.Screenshots.AppReady

  defp snapshot(overrides) do
    Map.merge(
      %{
        elapsed_ms: 0,
        saw_change?: false,
        stable?: false,
        dismissed_back?: false,
        opened_app?: false,
        target_type: "watchface",
        min_ms: 3_000,
        dismiss_ms: 5_000,
        open_app_ms: 8_000,
        stuck_ms: 12_000
      },
      Map.new(overrides)
    )
  end

  test "waits while the first post-install frame is unchanged" do
    assert AppReady.decision(snapshot(elapsed_ms: 1_000)) == :wait
  end

  test "does not treat a boot-to-launcher change as ready before Back" do
    assert AppReady.decision(
             snapshot(elapsed_ms: 3_500, saw_change?: true, stable?: true)
           ) == :wait
  end

  test "keeps a stable frame after Back dismissed the install overlay" do
    assert AppReady.decision(
             snapshot(
               elapsed_ms: 7_000,
               saw_change?: true,
               stable?: true,
               dismissed_back?: true
             )
           ) == :ready
  end

  test "does not accept a still-changing frame after Back" do
    assert AppReady.decision(
             snapshot(
               elapsed_ms: 7_000,
               saw_change?: true,
               stable?: false,
               dismissed_back?: true
             )
           ) == :wait
  end

  test "does not accept a changed frame before the minimum settle" do
    assert AppReady.decision(
             snapshot(
               elapsed_ms: 1_000,
               saw_change?: true,
               stable?: true,
               dismissed_back?: true
             )
           ) == :wait
  end

  test "dismisses the factory overlay even after a boot-to-launcher change" do
    assert AppReady.decision(snapshot(elapsed_ms: 5_000, saw_change?: true, stable?: true)) ==
             :dismiss_back
  end

  test "opens watchapps from the launcher after Back does not change the frame" do
    assert AppReady.decision(
             snapshot(
               elapsed_ms: 8_000,
               target_type: "app",
               dismissed_back?: true
             )
           ) == :open_app
  end

  test "does not open the launcher for watchfaces" do
    assert AppReady.decision(
             snapshot(
               elapsed_ms: 8_000,
               dismissed_back?: true,
               target_type: "watchface"
             )
           ) == :wait
  end

  test "accepts a static face after the stuck timeout" do
    assert AppReady.decision(snapshot(elapsed_ms: 12_000, dismissed_back?: true)) == :ready
  end

  test "png_digest changes when the framebuffer bytes change" do
    a = AppReady.png_digest("png-a")
    b = AppReady.png_digest("png-b")
    assert a != b
    assert a == AppReady.png_digest("png-a")
  end
end
