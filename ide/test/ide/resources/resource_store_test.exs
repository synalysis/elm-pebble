defmodule Ide.Resources.ResourceStoreTest do
  use ExUnit.Case, async: true

  alias Ide.Projects
  alias Ide.Resources.ResourceStore

  test "generated modules are read-only across editor path variants" do
    assert ResourceStore.read_only_generated_module?("watch", "src/Pebble/Ui/Resources.elm")
    assert ResourceStore.read_only_generated_module?("watch", "Pebble/Ui/Resources.elm")
    assert ResourceStore.read_only_generated_module?("watch", "Pebble/Ui/Resources")
    assert ResourceStore.read_only_generated_module?("/phone/", "/Companion/GeneratedPreferences")

    refute ResourceStore.read_only_generated_module?("watch", "src/Main.elm")
    refute ResourceStore.read_only_generated_module?("protocol", "src/Companion/Types.elm")
  end

  test "generated Resources.elm sorts constructors within each resource kind" do
    slug = "resources-sort-#{System.unique_integer([:positive])}"
    project = %Ide.Projects.Project{slug: slug}
    workspace = Projects.project_workspace_path(project)
    on_exit(fn -> File.rm_rf!(workspace) end)

    File.mkdir_p!(Path.join(workspace, "watch/resources/bitmaps"))
    File.mkdir_p!(Path.join(workspace, "watch/resources/vectors"))

    File.write!(Path.join(workspace, "watch/resources/bitmaps/BitmapStaticZulu.png"), <<137, 80, 78, 71>>)
    File.write!(Path.join(workspace, "watch/resources/bitmaps/BitmapStaticAlpha.png"), <<137, 80, 78, 71>>)
    File.write!(Path.join(workspace, "watch/resources/vectors/VectorAnimatedRain.pdc"), "pdc")
    File.write!(Path.join(workspace, "watch/resources/vectors/VectorStaticSun.pdc"), "pdc")

    bitmaps = %{
      "schema_version" => 1,
      "entries" => [
        %{
          "ctor" => "BitmapStaticZulu",
          "base_name" => "Zulu",
          "filename" => "BitmapStaticZulu.png",
          "mime" => "image/png",
          "bytes" => 4,
          "width" => 1,
          "height" => 1
        },
        %{
          "ctor" => "BitmapStaticAlpha",
          "base_name" => "Alpha",
          "filename" => "BitmapStaticAlpha.png",
          "mime" => "image/png",
          "bytes" => 4,
          "width" => 1,
          "height" => 1
        }
      ]
    }

    vectors = %{
      "schema_version" => 1,
      "entries" => [
        %{
          "ctor" => "VectorAnimatedRain",
          "base_name" => "Rain",
          "filename" => "VectorAnimatedRain.pdc",
          "mime" => "application/octet-stream",
          "bytes" => 3,
          "source" => "pdc",
          "kind" => "sequence",
          "frames" => 2,
          "frame_duration_ms" => 100
        },
        %{
          "ctor" => "VectorStaticSun",
          "base_name" => "Sun",
          "filename" => "VectorStaticSun.pdc",
          "mime" => "application/octet-stream",
          "bytes" => 3,
          "source" => "pdc",
          "kind" => "image"
        }
      ]
    }

    File.write!(Path.join(workspace, "watch/resources/bitmaps.json"), Jason.encode!(bitmaps, pretty: true))
    File.write!(Path.join(workspace, "watch/resources/vectors.json"), Jason.encode!(vectors, pretty: true))

    assert :ok = ResourceStore.ensure_generated_workspace(workspace)

    source =
      Path.join(workspace, ResourceStore.generated_module_rel_path())
      |> File.read!()

    assert type_ctor_order(source, "StaticBitmap", "BitmapStaticAlpha", "BitmapStaticZulu")
    assert type_ctor_order(source, "StaticVector", "VectorStaticSun", "VectorAnimatedRain")
    assert section_order(source, "staticBitmapInfo", "type Font")
    assert section_order(source, "animatedBitmapInfo", "type Font")
    assert section_order(source, "fontInfo", "type StaticVector")
    assert section_order(source, "staticVectorInfo", "type AnimatedVector")
  end

  defp section_order(source, earlier_marker, later_marker) do
    {earlier_pos, _} = :binary.match(source, earlier_marker)
    {later_pos, _} = :binary.match(source, later_marker)
    earlier_pos < later_pos
  end

  defp type_ctor_order(source, type_name, first_ctor, second_ctor) do
    type_marker = "type #{type_name}"
    {type_pos, _} = :binary.match(source, type_marker)
    fragment = String.slice(source, type_pos, 800)
    {first_pos, _} = :binary.match(fragment, first_ctor)
    {second_pos, _} = :binary.match(fragment, second_ctor)
    first_pos < second_pos
  end
end
