defmodule ElmEx.IR.DeadCodeTest do
  use ExUnit.Case, async: true

  alias ElmEx.IR
  alias ElmEx.IR.DeadCode

  test "keeps helpers reachable through nested lets and list HOFs" do
    draw_tile = %{
      op: :call,
      name: "Ui.fillRect",
      args: [%{op: :var, name: "rect"}, %{op: :var, name: "color"}]
    }

    view_body = %{
      op: :let_in,
      value_expr: %{
        op: :call,
        name: "visibleTiles",
        args: [%{op: :field_access, arg: %{op: :var, name: "model"}, field: "offset"}]
      },
      in_expr: %{
        op: :call,
        name: "List.map",
        args: [
          %{
            op: :call,
            name: "drawTile",
            args: [%{op: :field_access, arg: %{op: :var, name: "model"}, field: "offset"}]
          },
          %{op: :var, name: "tiles"}
        ]
      }
    }

    visible_tiles_body = %{
      op: :qualified_call,
      target: "List.concatMap",
      args: [%{op: :var, name: "genPlatforms"}, %{op: :call, name: "visibleSlots", args: [%{op: :var, name: "offset"}]}]
    }

    step_body = %{
      op: :call,
      name: "visibleTiles",
      args: [%{op: :var, name: "nextOffset"}]
    }

    update_body = %{
      op: :case,
      subject: %{op: :var, name: "msg"},
      branches: [
        %{
          pattern: %{kind: :ctor, name: "FrameTick"},
          expr: %{op: :call, name: "step", args: [%{op: :var, name: "model"}]}
        }
      ]
    }

    ir = %IR{
      modules: [
        %{
          name: "Main",
          declarations: [
            %{kind: :function, name: "update", expr: update_body},
            %{kind: :function, name: "view", expr: view_body},
            %{kind: :function, name: "step", expr: step_body},
            %{kind: :function, name: "visibleTiles", expr: visible_tiles_body},
            %{kind: :function, name: "visibleSlots", expr: %{op: :int_literal, value: 0}},
            %{kind: :function, name: "genPlatforms", expr: %{op: :int_literal, value: 0}},
            %{kind: :function, name: "drawTile", expr: draw_tile},
            %{kind: :function, name: "orphan", expr: %{op: :int_literal, value: 0}}
          ]
        }
      ],
      diagnostics: []
    }

    stripped = DeadCode.strip(ir, "Main")

    kept =
      stripped.modules
      |> List.first()
      |> Map.fetch!(:declarations)
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(& &1.name)
      |> MapSet.new()

    assert MapSet.member?(kept, "step")
    assert MapSet.member?(kept, "visibleTiles")
    assert MapSet.member?(kept, "genPlatforms")
    assert MapSet.member?(kept, "drawTile")
    refute MapSet.member?(kept, "orphan")
  end
end
