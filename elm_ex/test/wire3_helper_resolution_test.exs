defmodule ElmEx.Wire3HelperResolutionTest do
  use ExUnit.Case, async: true

  alias ElmEx.IR.Wire3HelperResolution

  test "aliases w3_encode to encodeForClient and synthesizes tagged decode" do
    defs = [
      %{
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
                target: "Lamdera.Wire3.encodeSequenceWithoutLength",
                args: [
                  %{
                    op: :list_literal,
                    items: [
                      %{
                        op: :qualified_call,
                        target: "Bytes.Encode.unsignedInt8",
                        args: [%{op: :int_literal, value: 4}]
                      },
                      %{
                        op: :qualified_call,
                        target: "Route.FAQ.w3_encode_Data",
                        args: [%{op: :var, name: "data"}]
                      }
                    ]
                  }
                ]
              }
            },
            %{
              pattern: %{kind: :constructor, name: "Data404NotFoundPage____"},
              expr: %{
                op: :qualified_call,
                target: "Bytes.Encode.unsignedInt8",
                args: [%{op: :int_literal, value: 0}]
              }
            }
          ]
        }
      },
      %{
        kind: :function_definition,
        name: "encodeResponse",
        args: [],
        expr: %{
          op: :qualified_call,
          target: "Pages.Internal.ResponseSketch.w3_encode_ResponseSketch",
          args: [
            %{op: :var, name: "w3_encode_PageData"},
            %{op: :var, name: "w3_decode_PageData"},
            %{op: :var, name: "w3_encode_ActionData"},
            %{op: :qualified_ref, target: "Shared.w3_encode_Data"}
          ]
        }
      }
    ]

    augmented = Wire3HelperResolution.augment_function_definitions("Main", defs)

    encode = Enum.find(augmented, &(&1.name == "w3_encode_PageData"))
    decode = Enum.find(augmented, &(&1.name == "w3_decode_PageData"))

    assert encode.expr == %{
             op: :qualified_call,
             target: "Main.encodePageDataForClient",
             args: [%{op: :var, name: "pageData"}]
           }

    assert %{op: :qualified_call, target: "Bytes.Decode.andThen"} = decode.expr
    assert Enum.find(augmented, &(&1.name == "w3_decode_PageData__tagSwitch"))
  end

  test "synthesizes tagged w3 helpers from plain encode function" do
    defs = [
      %{
        kind: :function_definition,
        name: "encodeActionData",
        args: ["actionData"],
        expr: %{
          op: :case,
          subject: %{op: :var, name: "actionData"},
          branches: [
            %{
              pattern: %{
                kind: :constructor,
                name: "ActionDataFAQ",
                bind: "data"
              },
              expr: %{
                op: :qualified_call,
                target: "Route.FAQ.w3_encode_ActionData",
                args: [%{op: :var, name: "data"}]
              }
            },
            %{
              pattern: %{
                kind: :constructor,
                name: "ActionDataBlog__Slug_",
                bind: "data"
              },
              expr: %{
                op: :qualified_call,
                target: "Route.Blog.Slug_.w3_encode_ActionData",
                args: [%{op: :var, name: "data"}]
              }
            }
          ]
        }
      },
      %{
        kind: :function_definition,
        name: "encodeResponse",
        args: [],
        expr: %{
          op: :qualified_call,
          target: "Sketch.w3_encode_ResponseSketch",
          args: [
            %{op: :var, name: "w3_encode_ActionData"},
            %{op: :var, name: "w3_decode_ActionData"}
          ]
        }
      }
    ]

    augmented = Wire3HelperResolution.augment_function_definitions("Main", defs)

    encode = Enum.find(augmented, &(&1.name == "w3_encode_ActionData"))
    decode = Enum.find(augmented, &(&1.name == "w3_decode_ActionData"))

    assert %{op: :case, branches: encode_branches} = encode.expr
    assert Enum.any?(encode_branches, &match_tagged_branch?/1)

    assert %{op: :qualified_call, target: "Bytes.Decode.andThen"} = decode.expr
  end

  test "augment_cross_module_wire3 adds route helpers referenced from Main decoder" do
    main_mod = %{
      name: "Main",
      declarations: [
        %{
          kind: :function,
          name: "w3_decode_ActionData__tagSwitch",
          args: ["tag"],
          expr: %{
            op: :case,
            subject: %{op: :var, name: "tag"},
            branches: [
              %{
                pattern: %{kind: :int, value: 0},
                expr: %{
                  op: :qualified_call,
                  target: "Route.FAQ.w3_decode_ActionData",
                  args: []
                }
              }
            ]
          }
        }
      ]
    }

    route_mod = %{name: "Route.FAQ", declarations: []}

    [main_out, route_out] =
      Wire3HelperResolution.augment_cross_module_wire3([main_mod, route_mod])

    assert main_out == main_mod

    assert Enum.any?(route_out.declarations, fn decl ->
             decl.kind == :function and decl.name == "w3_decode_ActionData"
           end)
  end

  test "augment_cross_module_wire3 synthesizes empty-record w3_encode helpers" do
    main_mod = %{
      name: "Main",
      declarations: [
        %{
          kind: :function,
          name: "byteEncodePageData",
          args: ["pageData"],
          expr: %{
            op: :qualified_call,
            target: "Route.FAQ.w3_encode_Data",
            args: [%{op: :var, name: "pageData"}]
          }
        }
      ]
    }

    route_mod = %{
      name: "Route.FAQ",
      declarations: [
        %{kind: :type_alias, name: "Data", expr: nil},
        %{kind: :type_alias, name: "ActionData", expr: nil}
      ]
    }

    [_main_out, route_out] =
      Wire3HelperResolution.augment_cross_module_wire3([main_mod, route_mod])

    encode =
      Enum.find(route_out.declarations, fn decl ->
        decl.kind == :function and decl.name == "w3_encode_Data"
      end)

    assert encode.args == ["value"]

    assert encode.expr == %{
             op: :qualified_call,
             target: "Lamdera.Wire3.encodeSequenceWithoutLength",
             args: [%{op: :list_literal, items: []}]
           }
  end

  test "augment_cross_module_wire3 synthesizes empty-record w3_decode helpers" do
    main_mod = %{
      name: "Main",
      declarations: [
        %{
          kind: :function,
          name: "byteDecodeShared",
          args: ["bytes"],
          expr: %{
            op: :qualified_call,
            target: "Shared.w3_decode_Data",
            args: []
          }
        }
      ]
    }

    shared_mod = %{
      name: "Shared",
      declarations: [
        %{kind: :type_alias, name: "Data", expr: nil}
      ]
    }

    [_main_out, shared_out] =
      Wire3HelperResolution.augment_cross_module_wire3([main_mod, shared_mod])

    decode =
      Enum.find(shared_out.declarations, fn decl ->
        decl.kind == :function and decl.name == "w3_decode_Data"
      end)

    assert decode.expr == %{
             op: :qualified_call,
             target: "Bytes.Decode.succeed",
             args: [%{op: :record_literal, fields: []}]
           }
  end

  defp match_tagged_branch?(%{
         expr: %{
           op: :qualified_call,
           target: "Lamdera.Wire3.encodeSequenceWithoutLength"
         }
       }),
       do: true

  defp match_tagged_branch?(_), do: false
end
