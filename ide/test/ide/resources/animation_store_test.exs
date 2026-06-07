defmodule Ide.Resources.AnimationStoreTest do
  use Ide.DataCase, async: false

  alias Ide.Projects
  alias Ide.Resources.AnimationStore
  alias Ide.Resources.ApngProbe
  alias Ide.Resources.GifToApng
  alias Ide.Resources.ResourceStore

  setup do
    root = Path.join(System.tmp_dir!(), "animation_store_#{System.unique_integer([:positive])}")
    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "apng_probe rejects single-frame PNG" do
    path = Path.join(System.tmp_dir!(), "static_#{System.unique_integer([:positive])}.png")
    File.write!(path, minimal_png_bytes(2, 2))

    assert {:error, :not_animated} = ApngProbe.probe(path)
  end

  test "apng_probe reads animated chunk metadata" do
    bytes = minimal_apng_bytes(width: 4, height: 4, frames: 3, delay_num: 10, delay_den: 100)
    assert {:ok, info} = ApngProbe.probe_bytes(bytes)
    assert info.width == 4
    assert info.height == 4
    assert info.frame_count == 3
    assert info.duration_ms > 0
  end

  test "import_animation uses BitmapAnimated prefix for numeric filenames" do
    slug = "anim-num-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Anim Num",
               "slug" => slug,
               "template" => "watchface-digital"
             })

    gif = Path.join(__DIR__, "../../fixtures/animations/simple.gif")

    if GifToApng.gif2apng_bin() do
      assert {:ok, %{entry: entry}} = AnimationStore.import_animation(project, gif, "100.gif")
      assert Map.fetch!(entry, "ctor") == "BitmapAnimated100"
      assert Map.fetch!(entry, "base_name") == "100"
    end
  end

  test "import and delete animation updates generated Resources module" do
    slug = "anim-store-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Anim Store",
               "slug" => slug,
               "template" => "watchface-digital"
             })

    path = write_apng_fixture()

    assert {:ok, %{entry: entry}} = AnimationStore.import_animation(project, path, "sparkle.png")
    assert Map.fetch!(entry, "ctor") == "BitmapAnimatedSparkle"
    assert Map.fetch!(entry, "base_name") == "Sparkle"

    assert {:ok, [row]} = AnimationStore.list(project)
    assert Map.fetch!(row, :ctor) == "BitmapAnimatedSparkle"
    assert Map.fetch!(row, :frame_count) >= 2

    generated =
      Path.join(
        Projects.project_workspace_path(project),
        ResourceStore.generated_module_rel_path()
      )

    assert File.exists?(generated)
    source = File.read!(generated)
    assert source =~ "type AnimatedBitmap"
    assert source =~ "BitmapAnimatedSparkle"
    assert source =~ "animatedBitmapInfo"

    assert {:ok, _} = AnimationStore.delete_animation(project, "BitmapAnimatedSparkle")
    assert {:ok, []} = AnimationStore.list(project)
  end

  defp minimal_png_bytes(width, height) do
    ihdr =
      png_chunk("IHDR", <<
        width::32-big,
        height::32-big,
        8,
        2,
        0,
        0,
        0
      >>)

    <<137, 80, 78, 71, 13, 10, 26, 10, ihdr::binary, png_chunk("IEND", "")::binary>>
  end

  defp minimal_apng_bytes(opts) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)
    frames = Keyword.fetch!(opts, :frames)
    delay_num = Keyword.get(opts, :delay_num, 1)
    delay_den = Keyword.get(opts, :delay_den, 100)

    ihdr =
      png_chunk("IHDR", <<
        width::32-big,
        height::32-big,
        8,
        3,
        0,
        0,
        0
      >>)

    actl = png_chunk("acTL", <<frames::32-big, 0::32-big>>)

    fctls =
      for seq <- 0..(frames - 2) do
        png_chunk("fcTL", <<
          seq::32-big,
          width::32-big,
          height::32-big,
          0::32,
          0::32,
          delay_num::16-big,
          delay_den::16-big,
          0,
          0
        >>)
      end

    fctl_data = Enum.reduce(fctls, <<>>, fn chunk, acc -> acc <> chunk end)

    <<137, 80, 78, 71, 13, 10, 26, 10, ihdr::binary, actl::binary, fctl_data::binary,
      png_chunk("IEND", "")::binary>>
  end

  defp png_chunk(type, data) do
    crc = :erlang.crc32(type <> data)
    <<byte_size(data)::32-big, type::binary-size(4), data::binary, crc::32-big>>
  end

  defp write_apng_fixture do
    path = Path.join(System.tmp_dir!(), "fixture_#{System.unique_integer([:positive])}.png")
    File.write!(path, minimal_apng_bytes(width: 8, height: 8, frames: 2))
    path
  end
end
