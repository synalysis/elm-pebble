defmodule Elmx.ViewOutputTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.Ui
  alias Elmx.Runtime.ViewOutput
  alias Elmx.Runtime.ViewShape

  test "from_view_tree emits bitmap_in_rect rows with resolved bitmap_id" do
    tree =
      Ui.to_ui_node([
        Ui.draw_bitmap_in_rect("BitmapStaticPikachuBack", %{x: 24, y: 103, w: 56, h: 48})
      ])

    rows =
      ViewOutput.from_view_tree(tree,
        bitmap_resource_indices: %{"BitmapStaticPikachuBack" => 16},
        screen_w: 144,
        screen_h: 168
      )

    assert [%{"kind" => "bitmap_in_rect", "bitmap_id" => 16, "x" => 24, "y" => 103, "w" => 56, "h" => 48}] =
             rows
  end

  test "from_view_tree flattens line endpoints from lowered ctor" do
    tree =
      ViewShape.normalize([
        Ui.line(%{x: 72, y: 84}, %{x: 30, y: 60}, Ui.named_color("black"))
      ])

    assert [%{"kind" => "line", "x1" => 72, "y1" => 84, "x2" => 30, "y2" => 60}] =
             ViewOutput.from_view_tree(tree, screen_w: 144, screen_h: 168)
  end

  test "from_view_tree flattens roundRect bounds and radius" do
    tree =
      Ui.to_ui_node([
        Ui.round_rect(%{x: 11, y: 53, w: 122, h: 66}, 8, Ui.named_color("black"))
      ])

    assert [
             %{
               "kind" => "round_rect",
               "x" => 11,
               "y" => 53,
               "w" => 122,
               "h" => 66,
               "radius" => 8
             }
           ] = ViewOutput.from_view_tree(tree, screen_w: 144, screen_h: 168)
  end

  test "from_view_tree flattens path draw ops for debugger preview" do
    y0 = 30

    triangle =
      Ui.path(
        [%{x: 20, y: y0 + 40}, %{x: 60, y: y0 + 40}, %{x: 40, y: y0}],
        %{x: 0, y: 0},
        0
      )

    tree =
      Ui.to_ui_node([
        Ui.path_filled(triangle),
        Ui.path_outline(triangle),
        Ui.path_outline_open(triangle)
      ])

    assert [
             %{
               "kind" => "path_filled",
               "points" => [[20, 70], [60, 70], [40, 30]],
               "offset_x" => 0,
               "offset_y" => 0,
               "rotation" => 0
             },
             %{"kind" => "path_outline", "points" => [[20, 70], [60, 70], [40, 30]]},
             %{"kind" => "path_outline_open", "points" => [[20, 70], [60, 70], [40, 30]]}
           ] =
             ViewOutput.from_view_tree(tree, screen_w: 144, screen_h: 168)
             |> Enum.map(&Map.take(&1, ["kind", "points", "offset_x", "offset_y", "rotation"]))
  end

  test "from_view_tree clamps fill_rect to screen bounds" do
    tree =
      Ui.to_ui_node([
        Ui.fill_rect(%{x: 86, y: 138, w: 3698, h: 2}, Ui.named_color("green"))
      ])

    assert [%{"kind" => "fill_rect", "w" => 58, "h" => 2, "fill" => 0xCC}] =
             ViewOutput.from_view_tree(tree, screen_w: 144, screen_h: 168)
  end

  test "from_view_tree emits bitmap_sequence_at and rotated_bitmap rows" do
    tree =
      Ui.to_ui_node([
        Ui.draw_bitmap_sequence_at("BitmapAnimatedSparkle", %{x: 10, y: 20}),
        Ui.draw_rotated_bitmap(
          "BitmapStaticImage",
          %{x: 0, y: 0, w: 30, h: 30},
          4096,
          %{x: 72, y: 84}
        )
      ])

    rows =
      ViewOutput.from_view_tree(tree,
        bitmap_resource_indices: %{"BitmapStaticImage" => 1},
        animation_resource_indices: %{"BitmapAnimatedSparkle" => 2},
        screen_w: 144,
        screen_h: 168
      )

    assert Enum.any?(rows, fn row ->
             row["kind"] == "bitmap_sequence_at" and row["animation_id"] == 2 and row["x"] == 10 and
               row["y"] == 20
           end)

    assert Enum.any?(rows, fn row ->
             row["kind"] == "rotated_bitmap" and row["bitmap_id"] == 1 and row["src_w"] == 30 and
               row["src_h"] == 30 and row["center_x"] == 72 and row["center_y"] == 84
           end)
  end

  test "view_shape normalizes RenderOp bitmap constructors" do
    tree =
      Elmx.Runtime.ViewShape.normalize([
        {:BitmapSequenceAt, ["BitmapAnimatedSparkle", 10, 20]},
        {:RotatedBitmap, ["BitmapStaticImage", 30, 30, 4096, 72, 84]}
      ])

    rows =
      ViewOutput.from_view_tree(tree,
        bitmap_resource_indices: %{"BitmapStaticImage" => 1},
        animation_resource_indices: %{"BitmapAnimatedSparkle" => 2},
        screen_w: 144,
        screen_h: 168
      )

    assert length(rows) == 2
  end

  test "from_view_tree emits text_int and WaitingForCompanion text_label rows" do
    tree =
      Ui.to_ui_node([
        Ui.text_int(0, %{x: 4, y: 72}, 42),
        Ui.text_label(0, %{x: 4, y: 96}, :WaitingForCompanion)
      ])

    rows = ViewOutput.from_view_tree(tree, screen_w: 144, screen_h: 168)

    assert Enum.any?(rows, fn row ->
             row["kind"] == "text_int" and row["text"] == "42" and row["x"] == 4 and row["y"] == 72
           end)

    assert Enum.any?(rows, fn row ->
             row["kind"] == "text_label" and row["text"] == "Waiting for companion app"
           end)
  end
end
