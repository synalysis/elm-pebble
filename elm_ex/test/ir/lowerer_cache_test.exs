defmodule ElmEx.IR.LowererCacheTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.Project
  alias ElmEx.IR.Lowerer
  alias ElmEx.IR.LowererCache

  @moduletag :tmp_dir

  test "second lower_project hits disk cache for unchanged modules", %{tmp_dir: tmp_dir} do
    project_dir = Path.join(tmp_dir, "proj")
    src = Path.join(project_dir, "src")
    File.mkdir_p!(src)
    main_path = Path.join(src, "Main.elm")

    File.write!(main_path, """
    module Main exposing (main)

    main : Int
    main =
        42
    """)

    project = %Project{
      project_dir: project_dir,
      elm_json: %{"source-directories" => ["src"]},
      modules: [
        %{
          name: "Main",
          path: main_path,
          imports: [],
          import_entries: [],
          declarations: [
            %{
              kind: :function_signature,
              name: "main",
              type: "Int",
              span: %{start_line: 3, end_line: 3}
            },
            %{
              kind: :function_definition,
              name: "main",
              args: [],
              expr: %{op: :int_literal, value: 42},
              span: %{start_line: 4, end_line: 6}
            }
          ]
        }
      ]
    }

    cache_dir = Path.join(project_dir, ".elmc-cache/ir")

    opts = [
      entry_module: "Main",
      reachable_only: true,
      cache: true,
      cache_dir: cache_dir,
      progress: false,
      roots: ["main"]
    ]

    assert {:ok, ir1} = Lowerer.lower_project(project, opts)
    assert File.dir?(cache_dir)
    assert File.ls!(cache_dir) != []

    assert {:ok, ir2} = Lowerer.lower_project(project, opts)
    main1 = Enum.find(ir1.modules, &(&1.name == "Main"))
    main2 = Enum.find(ir2.modules, &(&1.name == "Main"))
    assert length(main1.declarations) == length(main2.declarations)
  end

  test "reachable_only omits unused functions" do
    project = %Project{
      project_dir: "/tmp/reach-lower",
      elm_json: %{},
      modules: [
        %{
          name: "Main",
          path: "Main.elm",
          imports: [],
          import_entries: [],
          declarations: [
            %{
              kind: :function_definition,
              name: "main",
              args: [],
              expr: %{op: :int_literal, value: 1},
              span: %{start_line: 1, end_line: 1}
            },
            %{
              kind: :function_definition,
              name: "dead",
              args: [],
              expr: %{op: :int_literal, value: 2},
              span: %{start_line: 2, end_line: 2}
            }
          ]
        }
      ]
    }

    assert {:ok, ir} =
             Lowerer.lower_project(project,
               entry_module: "Main",
               reachable_only: true,
               roots: ["main"],
               progress: false
             )

    main = Enum.find(ir.modules, &(&1.name == "Main"))
    names = Enum.map(main.declarations, & &1.name)
    assert "main" in names
    refute "dead" in names
  end

  test "reachable_only retains port signatures (no body, never in walk)" do
    project = %Project{
      project_dir: "/tmp/reach-ports",
      elm_json: %{},
      modules: [
        %{
          name: "Main",
          path: "Main.elm",
          imports: [],
          import_entries: [],
          ports: ["fromJsPort", "toJsPort"],
          port_module: true,
          declarations: [
            %{
              kind: :function_signature,
              name: "fromJsPort",
              type: "(Json.Decode.Value -> msg) -> Sub msg",
              span: %{start_line: 1, end_line: 1}
            },
            %{
              kind: :function_signature,
              name: "toJsPort",
              type: "Json.Encode.Value -> Cmd msg",
              span: %{start_line: 2, end_line: 2}
            },
            %{
              kind: :function_definition,
              name: "subscriptions",
              args: ["_"],
              expr: %{
                op: :call,
                name: "fromJsPort",
                args: [%{op: :var, name: "identity"}]
              },
              span: %{start_line: 3, end_line: 5}
            },
            %{
              kind: :function_definition,
              name: "dead",
              args: [],
              expr: %{op: :int_literal, value: 0},
              span: %{start_line: 6, end_line: 6}
            }
          ]
        }
      ]
    }

    assert {:ok, ir} =
             Lowerer.lower_project(project,
               entry_module: "Main",
               reachable_only: true,
               roots: ["subscriptions"],
               progress: false
             )

    main = Enum.find(ir.modules, &(&1.name == "Main"))
    by_name = Map.new(main.declarations, &{&1.name, &1})

    assert main.ports == ["fromJsPort", "toJsPort"]
    assert %{expr: nil, type: type_in} = by_name["fromJsPort"]
    assert type_in =~ "Sub"
    assert %{expr: nil, type: type_out} = by_name["toJsPort"]
    assert type_out =~ "Cmd"
    refute Map.has_key?(by_name, "dead")
  end

  test "reachable_only closes callees only visible after import field normalize" do
    project = %Project{
      project_dir: "/tmp/reach-close",
      elm_json: %{},
      modules: [
        %{
          name: "Main",
          path: "Main.elm",
          imports: ["Theme"],
          import_entries: [
            %{"module" => "Theme", "as" => "Theme", "exposing" => nil}
          ],
          declarations: [
            %{
              kind: :function_definition,
              name: "main",
              args: [],
              expr: %{
                op: :field_access,
                arg: %{op: :var, name: "Theme"},
                field: "white"
              },
              span: %{start_line: 1, end_line: 1}
            }
          ]
        },
        %{
          name: "Theme",
          path: "Theme.elm",
          imports: [],
          import_entries: [],
          declarations: [
            %{
              kind: :function_definition,
              name: "white",
              args: [],
              expr: %{op: :string_literal, value: "#fff"},
              span: %{start_line: 1, end_line: 1}
            }
          ]
        }
      ]
    }

    assert {:ok, ir} =
             Lowerer.lower_project(project,
               entry_module: "Main",
               reachable_only: true,
               roots: ["main"],
               progress: false
             )

    theme = Enum.find(ir.modules, &(&1.name == "Theme"))
    names = Enum.map(theme.declarations, & &1.name)
    assert "white" in names
  end

  test "reachable_only synthesizes w3 helpers from non-reachable encodeForClient" do
    encode_for_client = %{
      kind: :function_definition,
      name: "encodePageDataForClient",
      args: ["pageData"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "pageData"},
        branches: [
          %{
            pattern: %{kind: :constructor, name: "DataFAQ", bind: "data"},
            expr: %{
              op: :qualified_call,
              target: "Bytes.Encode.unsignedInt8",
              args: [%{op: :int_literal, value: 4}]
            }
          }
        ]
      },
      span: %{start_line: 1, end_line: 1}
    }

    project = %Project{
      project_dir: "/tmp/reach-wire3",
      elm_json: %{},
      modules: [
        %{
          name: "Main",
          path: "Main.elm",
          imports: [],
          import_entries: [],
          declarations: [
            encode_for_client,
            %{
              kind: :function_definition,
              name: "encodeResponse",
              args: [],
              expr: %{
                op: :qualified_call,
                target: "Pages.Internal.ResponseSketch.w3_encode_ResponseSketch",
                args: [
                  %{op: :var, name: "w3_encode_PageData"},
                  %{op: :var, name: "w3_encode_ActionData"},
                  %{op: :qualified_ref, target: "Shared.w3_encode_Data"}
                ]
              },
              span: %{start_line: 2, end_line: 2}
            },
            %{
              kind: :function_definition,
              name: "main",
              args: [],
              expr: %{op: :var, name: "encodeResponse"},
              span: %{start_line: 3, end_line: 3}
            }
          ]
        }
      ]
    }

    assert {:ok, ir} =
             Lowerer.lower_project(project,
               entry_module: "Main",
               reachable_only: true,
               roots: ["main"],
               progress: false
             )

    main = Enum.find(ir.modules, &(&1.name == "Main"))
    names = Enum.map(main.declarations, & &1.name)
    assert "encodeResponse" in names
    assert "w3_encode_PageData" in names
    assert "encodePageDataForClient" in names
  end

  test "fingerprint_reachable distinguishes all vs set" do
    assert LowererCache.fingerprint_reachable(:all) == "all"
    a = LowererCache.fingerprint_reachable(MapSet.new(["A.f"]))
    b = LowererCache.fingerprint_reachable(MapSet.new(["A.f", "B.g"]))
    assert a != b
  end
end
