defmodule Ide.Emulator.SdkImagesTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.SdkImages

  test "images_present? requires micro flash and either raw or compressed spi flash" do
    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-sdk-images-test-#{System.unique_integer([:positive])}"
      )

    qemu_dir = Path.join([root, "basalt", "qemu"])
    File.mkdir_p!(qemu_dir)

    refute SdkImages.images_present?(root, "basalt")

    File.write!(Path.join(qemu_dir, "qemu_micro_flash.bin"), "")
    refute SdkImages.images_present?(root, "basalt")

    File.write!(Path.join(qemu_dir, "qemu_spi_flash.bin.bz2"), "")
    assert SdkImages.images_present?(root, "basalt")

    File.rm_rf!(root)
  end
end
