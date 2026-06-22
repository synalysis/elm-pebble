defmodule Elmx.PebbleUiRuntimeTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.Ui
  alias Elmx.Runtime.ViewOutput

  test "circle and fill_circle accept Pebble surface arity" do
    center = %{x: 10, y: 20}

    circle = Ui.circle(center, 30, 0xFF000000)
    assert circle.cx == 10
    assert circle.cy == 20
    assert circle.r == 30

    filled = Ui.fill_circle(center, 4, 0xFFFFFFFF)
    assert filled.r == 4
  end

  test "line stores flattened endpoints for debugger preview" do
    op = Ui.line(%{x: 72, y: 84}, %{x: 30, y: 60}, 192)

    assert op.x1 == 72
    assert op.y1 == 84
    assert op.x2 == 30
    assert op.y2 == 60
  end

  test "round_rect stores flattened geometry for debugger preview" do
    op = Ui.round_rect(%{x: 4, y: 8, w: 40, h: 24}, 6, 0)

    assert op.x == 4
    assert op.y == 8
    assert op.w == 40
    assert op.h == 24
    assert op.radius == 6
  end

  test "view_output flattens window stack draw ops" do
    tree =
      Ui.window_stack([
        Ui.window(1, [
          Ui.canvas_layer(0, [
            Ui.clear(0xFFFFFFFF),
            Ui.circle(%{x: 72, y: 84}, 60, 0xFF000000)
          ])
        ])
      ])

    rows = ViewOutput.from_view_tree(tree)
    kinds = Enum.map(rows, & &1["kind"])
    assert "clear" in kinds
    assert "circle" in kinds
  end

  test "draw_vector_sequence_at accepts animation id and resource" do
    op = Ui.draw_vector_sequence_at(7, "VectorAnimatedFoo", %{x: 0, y: 0})

    assert op.type == "drawVectorSequenceAt"
    assert op.animation_id == 7
    assert op.frame == 0
    assert op.rotation == 0
  end

  test "view_output reads text bounds and resolves vector resources" do
    tree = %{
      "type" => "windowStack",
      "children" => [
        %{
          "type" => "window",
          "children" => [
            %{
              "type" => "canvasLayer",
              "children" => [
                %{
                  "type" => "text",
                  "label" => "10:46",
                  "bounds" => %{"x" => 8, "y" => 108, "w" => 72, "h" => 22}
                },
                %{
                  "type" => "drawVectorAt",
                  "x" => 19,
                  "y" => 6,
                  "resource" => "VectorStaticTangramBird"
                }
              ]
            }
          ]
        }
      ]
    }

    rows =
      ViewOutput.from_view_tree(tree,
        vector_resource_indices: %{"VectorStaticTangramBird" => 1}
      )

    text_row = Enum.find(rows, &(&1["kind"] == "text"))
    assert text_row["text"] == "10:46"
    assert text_row["x"] == 8
    assert text_row["y"] == 108
    assert text_row["w"] == 72
    assert text_row["h"] == 22

    vector_row = Enum.find(rows, &(&1["kind"] == "vector_at"))
    assert vector_row["vector_id"] == 1
    assert vector_row["x"] == 19
    assert vector_row["y"] == 6
  end

  test "apply_resource_indices resolves vector_id from resource ctor on rows" do
    rows = [
      %{
        "kind" => "vector_at",
        "resource" => "VectorStaticTangramBird",
        "vector_id" => 0,
        "x" => 21,
        "y" => 7
      }
    ]

    [row] =
      ViewOutput.apply_resource_indices(rows,
        vector_resource_indices: %{"VectorStaticTangramBird" => 1}
      )

    assert row["vector_id"] == 1
  end
end
