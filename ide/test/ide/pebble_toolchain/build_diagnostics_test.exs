defmodule Ide.PebbleToolchain.BuildDiagnosticsTest do
  use ExUnit.Case, async: true

  alias Ide.PebbleToolchain.BuildDiagnostics

  test "package issue explains bitmap resource packaging failures" do
    output = """
    [ 9/29] Compiling basalt | reso: resources/bitmaps/BadLogo.png -> build/basalt/resources/bitmaps/BadLogo.png.BITMAP_BADLOGO.reso
    Traceback (most recent call last):
      File ".../resource_generator_bitmap.py", line 95, in generate_object
        _, _, bitdepth, _ = png2pblpng.get_palette_for_png(
      File ".../png2pblpng.py", line 158, in get_palette_for_png
        input_png.preamble()
  Build failed
    """

    assert %{
             title: "Bitmap resource packaging failed",
             message: message,
             detail: "resource=BadLogo.png"
           } = BuildDiagnostics.package_issue(output)

    assert message =~ "BadLogo.png"
    assert message =~ "valid PNG"
  end

  test "package issue still explains linker overflow" do
    output = """
    [135/136] Linking aplite | cprogram: build/src/c/elmc/c/elmc_generated.c.57.o -> build/aplite/pebble-app.elf
    ld: region `APP' overflowed by 12076 bytes
    """

    assert %{
             title: "PBW too large for Aplite",
             detail: "target=aplite overflow=12076 bytes"
           } = BuildDiagnostics.package_issue(output)
  end

  test "launch_message summarizes bitmap packaging failures" do
    output = """
    File ".../png2pblpng.py", line 158, in get_palette_for_png
    reso: resources/bitmaps/BadLogo.png ->
    """

    message = BuildDiagnostics.launch_message(output)

    assert message =~ "bitmap resource"
    assert message =~ "BadLogo.png"
  end
end
