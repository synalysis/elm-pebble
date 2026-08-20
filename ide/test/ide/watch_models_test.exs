defmodule Ide.WatchModelsTest do
  use ExUnit.Case, async: true

  alias Ide.WatchModels

  test "profile_for returns catalog entry with screen dimensions" do
    basalt = WatchModels.profile_for("basalt")

    assert basalt["name"] == "Basalt"
    assert basalt["shape"] == "rect"
    assert basalt["color_mode"] == "Color"
    assert basalt["supports_health"] == true
    assert WatchModels.profile_screen(basalt) == %{"width" => 144, "height" => 168}
  end

  test "profile_for falls back to default for unknown id" do
    unknown = WatchModels.profile_for("not-a-platform")
    default = WatchModels.profile_for(WatchModels.default_id())

    assert unknown == default
  end

  test "profiles_map contains every ordered id" do
    map = WatchModels.profiles_map()

    for id <- WatchModels.ordered_ids() do
      assert %{"screen" => %{"width" => w, "height" => h}} = map[id]
      assert is_integer(w) and is_integer(h) and w > 0 and h > 0
    end
  end

  test "round chalk profile used by screenshot masking" do
    chalk = WatchModels.profile_for("chalk")

    assert chalk["shape"] == "round"
    assert WatchModels.profile_screen(chalk) == %{"width" => 180, "height" => 180}
  end

  test "round gabbro profile matches Pebble Round 2 hardware resolution" do
    gabbro = WatchModels.profile_for("gabbro")

    assert gabbro["shape"] == "round"
    assert WatchModels.profile_screen(gabbro) == %{"width" => 260, "height" => 260}
  end

  test "flint reports Pebble 2 Duo watch info, not Pebble Time" do
    flint = WatchModels.profile_for("flint")

    assert flint["watch_info_model"] == "CoreDevicesP2D"
    assert flint["watch_info_color"] == "CoreDevicesP2DWhite"
    assert WatchModels.watch_info_model_ctor("flint") == "CoreDevicesP2D"
    assert WatchModels.watch_info_color_ctor("flint") == "CoreDevicesP2DWhite"
  end

  test "launch context can override catalog watch color" do
    assert WatchModels.watch_info_color_ctor_from_launch_context(%{
             "watch_profile_id" => "flint",
             "watch_info_color" => "CoreDevicesP2DBlack"
           }) == "CoreDevicesP2DBlack"

    assert WatchModels.watch_info_color_ctor_from_launch_context(%{
             "watch_profile_id" => "flint"
           }) == "CoreDevicesP2DWhite"
  end
end
