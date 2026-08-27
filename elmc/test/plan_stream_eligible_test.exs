defmodule Elmc.PlanStreamEligibleTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Stream

  test "does not peel aliases or a bare toUiNode" do
    inner = %{op: :list_literal, items: []}

    refute Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "Ui.toUiNode",
             args: [inner]
           })

    refute Stream.eligible_expr?(%{op: :call, name: "toUiNode", args: [inner]})

    refute Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "Pebble.Ui.toUiNode",
             args: [inner]
           })
  end

  test "toUiNode is eligible only by following its kernel body" do
    inner = %{op: :var, name: "ops"}

    to_ui_node_body = %{
      op: :qualified_call,
      target: "Pebble.Ui.windowStack",
      args: [
        %{
          op: :list_literal,
          items: [
            %{
              op: :qualified_call,
              target: "Pebble.Ui.window",
              args: [
                %{op: :int_literal, value: 1},
                %{
                  op: :list_literal,
                  items: [
                    %{
                      op: :qualified_call,
                      target: "Pebble.Ui.canvasLayer",
                      args: [%{op: :int_literal, value: 1}, inner]
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }

    decl_map = %{
      {"Pebble.Ui", "toUiNode"} => %{name: "toUiNode", expr: to_ui_node_body}
    }

    assert Stream.eligible_expr?(
             %{
               op: :qualified_call,
               target: "Pebble.Ui.toUiNode",
               args: [inner]
             },
             decl_map,
             "Main"
           )
  end

  test "windowStack / window / canvasLayer stream their child lists" do
    ops = %{op: :list_literal, items: [%{op: :render_cmd}]}

    assert Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "Pebble.Ui.canvasLayer",
             args: [%{op: :int_literal, value: 1}, ops]
           })

    assert Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "Pebble.Ui.windowStack",
             args: [%{op: :list_literal, items: []}]
           })
  end

  test "Maybe case of render-op lists is stream-eligible" do
    expr = %{
      op: :case,
      subject: %{op: :var, name: "maybePts"},
      branches: [
        %{pattern: %{kind: :constructor, name: "Nothing"}, expr: %{op: :list_literal, items: []}},
        %{
          pattern: %{kind: :constructor, name: "Just", bind: "payload"},
          expr: %{op: :list_literal, items: [%{op: :render_cmd}]}
        }
      ]
    }

    assert Stream.eligible_expr?(expr)
  end

  test "List.map / concatMap / indexedMap over a literal or range are stream-eligible" do
    rect = %{op: :render_cmd}

    assert Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "List.map",
             args: [
               %{op: :lambda, args: ["c"], body: rect},
               %{op: :list_literal, items: [%{op: :var, name: "black"}]}
             ]
           })

    assert Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "List.concatMap",
             args: [
               %{op: :lambda, args: ["n"], body: %{op: :list_literal, items: [rect]}},
               %{
                 op: :qualified_call,
                 target: "List.range",
                 args: [%{op: :int_literal, value: 0}, %{op: :int_literal, value: 3}]
               }
             ]
           })

    assert Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "List.map",
             args: [
               %{op: :lambda, args: ["x"], body: rect},
               %{op: :var, name: "dynamicList"}
             ]
           })

    assert Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "List.indexedMap",
             args: [
               %{op: :var, name: "cellOp"},
               %{op: :field_access, arg: %{op: :var, name: "model"}, field: "cells"}
             ]
           })

    assert Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "List.concat",
             args: [
               %{
                 op: :list_literal,
                 items: [
                   %{
                     op: :qualified_call,
                     target: "List.map",
                     args: [
                       %{op: :lambda, args: ["c"], body: rect},
                       %{op: :list_literal, items: [%{op: :var, name: "black"}]}
                     ]
                   }
                 ]
               }
             ]
           })

    assert Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "List.concatMap",
             args: [
               %{op: :lambda, args: ["n"], body: %{op: :list_literal, items: [rect]}},
               %{
                 op: :call,
                 name: "__append__",
                 args: [
                   %{
                     op: :qualified_call,
                     target: "List.range",
                     args: [%{op: :int_literal, value: 0}, %{op: :int_literal, value: 2}]
                   },
                   %{
                     op: :qualified_call,
                     target: "List.range",
                     args: [%{op: :int_literal, value: 5}, %{op: :int_literal, value: 6}]
                   }
                 ]
               }
             ]
           })
  end

  test "List.cons / :: of a render op onto a stream list is eligible" do
    rect = %{op: :render_cmd}

    assert Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "List.cons",
             args: [rect, %{op: :list_literal, items: []}]
           })

    assert Stream.eligible_expr?(%{
             op: :runtime_call,
             function: "elmc_list_cons",
             args: [rect, %{op: :var, name: "rest"}]
           }) == false

    assert Stream.eligible_expr?(%{
             op: :runtime_call,
             function: "elmc_list_cons",
             args: [
               rect,
               %{
                 op: :qualified_call,
                 target: "List.indexedMap",
                 args: [
                   %{op: :var, name: "cellOp"},
                   %{op: :field_access, arg: %{op: :var, name: "model"}, field: "cells"}
                 ]
               }
             ]
           })
  end

  test "FQ Pebble.Ui.clear / text / context / group are stream-eligible" do
    clear = %{
      op: :qualified_call,
      target: "Pebble.Ui.clear",
      args: [%{op: :var, name: "white"}]
    }

    text = %{
      op: :qualified_call,
      target: "Pebble.Ui.text",
      args: [
        %{op: :var, name: "font"},
        %{op: :var, name: "options"},
        %{op: :var, name: "bounds"},
        %{op: :string_literal, value: "Hi"}
      ]
    }

    settings = %{
      op: :list_literal,
      items: [
        %{
          op: :qualified_call,
          target: "Pebble.Ui.strokeColor",
          args: [%{op: :var, name: "black"}]
        },
        %{
          op: :qualified_call,
          target: "Pebble.Ui.textColor",
          args: [%{op: :var, name: "black"}]
        }
      ]
    }

    context = %{
      op: :qualified_call,
      target: "Pebble.Ui.context",
      args: [settings, %{op: :list_literal, items: [clear, text]}]
    }

    assert Stream.eligible_expr?(clear)
    assert Stream.eligible_expr?(text)

    assert Stream.eligible_expr?(context)

    assert Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "Pebble.Ui.group",
             args: [context]
           })

    refute Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "Ui.group",
             args: [context]
           })
  end

  test "let-bound chrome ops appended onto indexedMap are stream-eligible" do
    chrome = %{
      op: :list_literal,
      items: [
        %{
          op: :qualified_call,
          target: "Pebble.Ui.text",
          args: [
            %{op: :var, name: "font"},
            %{op: :var, name: "options"},
            %{op: :var, name: "bounds"},
            %{op: :string_literal, value: "Best"}
          ]
        }
      ]
    }

    mapped = %{
      op: :qualified_call,
      target: "List.indexedMap",
      args: [
        %{op: :var, name: "drawCell"},
        %{op: :field_access, arg: %{op: :var, name: "model"}, field: "cells"}
      ]
    }

    assert Stream.eligible_expr?(%{
             op: :let_in,
             name: "chromeOps",
             value_expr: chrome,
             in_expr: %{
               op: :call,
               name: "__append__",
               args: [%{op: :var, name: "chromeOps"}, mapped]
             }
           })
  end

  test "List.append of eligible sides is stream-eligible" do
    left = %{op: :list_literal, items: [%{op: :render_cmd}]}

    right = %{
      op: :qualified_call,
      target: "List.map",
      args: [
        %{op: :var, name: "drawAt"},
        %{op: :field_access, arg: %{op: :var, name: "model"}, field: "slots"}
      ]
    }

    assert Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "List.append",
             args: [left, right]
           })
  end

  test "List.concatMap of a named helper over appended maps is stream-eligible" do
    ticks = %{
      op: :call,
      name: "__append__",
      args: [
        %{
          op: :qualified_call,
          target: "List.map",
          args: [
            %{op: :lambda, args: ["h"], body: %{op: :record_literal, fields: []}},
            %{
              op: :qualified_call,
              target: "List.range",
              args: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 3}]
            }
          ]
        },
        %{
          op: :qualified_call,
          target: "List.map",
          args: [
            %{op: :lambda, args: ["h"], body: %{op: :record_literal, fields: []}},
            %{
              op: :qualified_call,
              target: "List.range",
              args: [%{op: :int_literal, value: 0}, %{op: :int_literal, value: 2}]
            }
          ]
        }
      ]
    }

    assert Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "List.concatMap",
             args: [%{op: :call, name: "drawScaleTick", args: [%{op: :var, name: "layout"}]}, ticks]
           })
  end

  test "follows a List RenderOp helper body" do
    body = %{op: :list_literal, items: [%{op: :render_cmd}]}
    decl_map = %{{"Main", "drawOps"} => %{name: "drawOps", expr: body}}

    assert Stream.eligible_expr?(
             %{op: :call, name: "drawOps", args: [%{op: :var, name: "model"}]},
             decl_map,
             "Main"
           )
  end
end
