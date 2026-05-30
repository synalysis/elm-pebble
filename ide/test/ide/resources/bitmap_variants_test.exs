defmodule Ide.Resources.BitmapVariantsTest do
  use ExUnit.Case, async: true

  alias Ide.Resources.BitmapVariants

  test "variant filenames use Pebble tilde tags" do
    assert BitmapVariants.variant_filename("Charmander", "BlackWhite", ".png") == "Charmander~bw.png"
    assert BitmapVariants.variant_filename("Charmander", "Color", ".png") == "Charmander~color.png"
  end

  test "normalize_row keeps variants and legacy filename" do
    row =
      BitmapVariants.normalize_row(%{
        "ctor" => "Charmander",
        "filename" => "Charmander.png",
        "variants" => %{
          "Color" => %{"filename" => "Charmander~color.png", "width" => 40, "height" => 44}
        }
      })

    assert row["filename"] == "Charmander.png"
    assert row["variants"]["Color"]["filename"] == "Charmander~color.png"
    assert BitmapVariants.filenames_for_row(row) == ["Charmander.png", "Charmander~color.png"]
  end

  test "platforms_label groups watch models by color mode" do
    assert BitmapVariants.platforms_label("BlackWhite") =~ "Aplite"
    assert BitmapVariants.platforms_label("Color") =~ "Basalt"
  end
end
