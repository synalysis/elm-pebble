defmodule Ide.Resources.ApngStaticPreviewTest do
  use ExUnit.Case, async: true

  alias Ide.Resources.{ApngProbe, ApngStaticPreview}

  @sparkle Path.expand(
             "../../../priv/project_templates/watch_demo_drawing_showcase/resources/animations/BitmapAnimatedSparkle.png",
             __DIR__
           )

  @static_icon Path.expand(
                 "../../../priv/project_templates/watch_demo_drawing_showcase/resources/bitmaps/BitmapStaticBtIcon.png",
                 __DIR__
               )

  test "static_png_bytes strips animation chunks from watch APNG" do
    bytes = File.read!(@sparkle)
    assert {:ok, %{frame_count: 21, width: 60, height: 60}} = ApngProbe.probe_bytes(bytes)

    assert {:ok, static_bytes} = ApngStaticPreview.static_png_bytes(bytes)
    assert static_bytes != bytes
    assert byte_size(static_bytes) < byte_size(bytes)
    refute static_bytes =~ "acTL"
    assert static_bytes =~ "PLTE"
  end

  test "static_png_bytes returns plain PNG unchanged" do
    bytes = File.read!(@static_icon)
    assert {:ok, ^bytes} = ApngStaticPreview.static_png_bytes(bytes)
  end
end
