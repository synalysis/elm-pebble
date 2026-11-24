defmodule Ide.Handheld.ModelsTest do
  use ExUnit.Case, async: false

  alias Ide.DeviceFamily
  alias Ide.Handheld.Models
  alias Ide.Projects.Project

  test "catalog lists MeowKit and Flipper Zero" do
    assert Models.ordered_ids() == ["meowkit", "flipper-zero"]
    refute "flipper-one" in Models.ordered_ids()
    assert Models.normalize("flipper-one") == "meowkit"
    assert Models.profile("meowkit")["screen"] == %{"width" => 320, "height" => 240}
    assert Models.profile("flipper-zero")["color_depth"] == 1
    assert Models.profile("flipper-zero")["modules"]["usb"] == false
    assert Models.profile("meowkit")["modules"]["usb"] == true
  end

  test "known devices pack to their own targets" do
    assert Models.preview_screen("meowkit") == {320, 240, false}
    assert Models.preview_screen("flipper-zero") == {128, 64, false}
    assert Models.pack_target("flipper-zero") == :flipper
    assert Models.pack_target("meowkit") == :meowkit
  end

  test "debugger launch context carries the handheld panel" do
    alias Ide.Debugger.RuntimeSurfaces

    meow = RuntimeSurfaces.launch_context_for("meowkit", "LaunchUser")
    flipper = RuntimeSurfaces.launch_context_for("flipper-zero", "LaunchUser")

    assert meow["device"] == :MeowKit
    assert meow["touch"] == true
    assert meow["screen"] == %{"width" => 320, "height" => 240, "colorDepth" => 16}
    assert flipper["device"] == :FlipperZero
    assert flipper["touch"] == false
    assert flipper["screen"]["colorDepth"] == 1
    refute Map.has_key?(meow, "watch_profile_id")
  end

  test "pebble projects keep watch ids and handheld projects keep handheld ids" do
    pebble = %Project{release_defaults: %{}}
    handheld = %Project{release_defaults: %{"device_family" => "handheld"}}

    assert DeviceFamily.family(pebble) == "pebble"
    assert DeviceFamily.normalize_id(pebble, "meowkit") != "meowkit"
    assert DeviceFamily.emulator_target_ids(pebble) |> Enum.member?("basalt")

    assert DeviceFamily.family(handheld) == "handheld"
    assert DeviceFamily.normalize_id(handheld, "basalt") == "meowkit"
    assert DeviceFamily.normalize_id(handheld, "flipper-zero") == "flipper-zero"
    assert DeviceFamily.picker_label(handheld) == "Handheld type"
    refute DeviceFamily.emulator_page?(handheld)
    assert DeviceFamily.emulator_page?(pebble)
    assert DeviceFamily.default_platforms("handheld") == Models.ordered_ids()
  end

  test "IDE_DEVICE_FAMILY switches the IDE session to handheld" do
    previous = System.get_env("IDE_DEVICE_FAMILY")
    pebble = %Project{release_defaults: %{}}

    on_exit(fn ->
      if previous,
        do: System.put_env("IDE_DEVICE_FAMILY", previous),
        else: System.delete_env("IDE_DEVICE_FAMILY")
    end)

    System.put_env("IDE_DEVICE_FAMILY", "handheld")
    assert DeviceFamily.family(pebble) == "handheld"
    refute DeviceFamily.emulator_page?(pebble)

    System.delete_env("IDE_DEVICE_FAMILY")
    assert DeviceFamily.family(pebble) == "pebble"
    assert DeviceFamily.emulator_page?(pebble)
  end
end
