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

  test "List.filter of a literal range is expandable for stream concatMap" do
    filtered = %{
      op: :qualified_call,
      target: "List.filter",
      args: [
        %{
          op: :lambda,
          args: ["h"],
          body: %{
            op: :call,
            name: "==",
            args: [
              %{op: :call, name: "modBy", args: [%{op: :int_literal, value: 2}, %{op: :var, name: "h"}]},
              %{op: :int_literal, value: 1}
            ]
          }
        },
        %{
          op: :qualified_call,
          target: "List.range",
          args: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 5}]
        }
      ]
    }

    mapped = %{
      op: :qualified_call,
      target: "List.map",
      args: [
        %{op: :lambda, args: ["h"], body: %{op: :record_literal, fields: []}},
        filtered
      ]
    }

    assert Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "List.concatMap",
             args: [%{op: :call, name: "drawTick", args: [%{op: :var, name: "layout"}]}, mapped]
           })
  end

  test "List.filter of render commands is stream-eligible" do
    cmds = %{
      op: :list_literal,
      items: [%{op: :render_cmd}, %{op: :render_cmd}]
    }

    filtered = %{
      op: :qualified_call,
      target: "List.filter",
      args: [
        %{op: :lambda, args: ["_"], body: %{op: :bool_literal, value: true}},
        cmds
      ]
    }

    assert Stream.eligible_expr?(filtered)
    assert Stream.pipeline_expr?(filtered)
  end

  test "List.filter of a model command list is stream-eligible" do
    filtered = %{
      op: :qualified_call,
      target: "List.filter",
      args: [
        %{op: :lambda, args: ["_"], body: %{op: :var, name: "show"}},
        %{op: :field_access, arg: %{op: :var, name: "model"}, field: "ops"}
      ]
    }

    assert Stream.eligible_expr?(filtered)
    assert Stream.pipeline_expr?(filtered)
  end

  test "List.filter of an int list is not a stream view" do
    filtered = %{
      op: :qualified_call,
      target: "List.filter",
      args: [
        %{op: :lambda, args: ["n"], body: %{op: :bool_literal, value: true}},
        %{
          op: :list_literal,
          items: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 2}]
        }
      ]
    }

    refute Stream.eligible_expr?(filtered)
  end

  test "List.filterMap of Maybe render commands is stream-eligible" do
    cmds = %{
      op: :list_literal,
      items: [
        %{op: :constructor_call, target: "Just", args: [%{op: :render_cmd}]},
        %{op: :constructor_call, target: "Nothing", args: []}
      ]
    }

    mapped = %{
      op: :qualified_call,
      target: "List.filterMap",
      args: [
        %{op: :lambda, args: ["x"], body: %{op: :var, name: "x"}},
        cmds
      ]
    }

    assert Stream.eligible_expr?(mapped)
    assert Stream.pipeline_expr?(mapped)
  end

  test "List.filterMap that draws from a model int list is stream-eligible" do
    mapped = %{
      op: :qualified_call,
      target: "List.filterMap",
      args: [
        %{
          op: :lambda,
          args: ["n"],
          body: %{
            op: :if,
            cond: %{
              op: :compare,
              kind: :gt,
              left: %{op: :var, name: "n"},
              right: %{op: :int_literal, value: 0}
            },
            then_expr: %{
              op: :constructor_call,
              target: "Just",
              args: [%{op: :render_cmd}]
            },
            else_expr: %{op: :constructor_call, target: "Nothing", args: []}
          }
        },
        %{op: :field_access, arg: %{op: :var, name: "model"}, field: "cells"}
      ]
    }

    assert Stream.eligible_expr?(mapped)
    assert Stream.pipeline_expr?(mapped)
  end

  test "List.filterMap of ints to Just int is not a stream view" do
    mapped = %{
      op: :qualified_call,
      target: "List.filterMap",
      args: [
        %{
          op: :lambda,
          args: ["n"],
          body: %{
            op: :constructor_call,
            target: "Just",
            args: [%{op: :var, name: "n"}]
          }
        },
        %{
          op: :list_literal,
          items: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 2}]
        }
      ]
    }

    refute Stream.eligible_expr?(mapped)
  end

  test "List.map over List.filter of a model field is stream-eligible" do
    filtered = %{
      op: :qualified_call,
      target: "List.filter",
      args: [
        %{
          op: :lambda,
          args: ["n"],
          body: %{
            op: :compare,
            kind: :gt,
            left: %{op: :var, name: "n"},
            right: %{op: :int_literal, value: 0}
          }
        },
        %{op: :field_access, arg: %{op: :var, name: "model"}, field: "cells"}
      ]
    }

    assert Stream.eligible_expr?(%{
             op: :qualified_call,
             target: "List.map",
             args: [
               %{op: :lambda, args: ["n"], body: %{op: :render_cmd}},
               filtered
             ]
           })

    assert Stream.pipeline_expr?(%{
             op: :qualified_call,
             target: "List.map",
             args: [
               %{op: :lambda, args: ["n"], body: %{op: :render_cmd}},
               filtered
             ]
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

  test "static command lists are eligible but not pipelines" do
    static = %{op: :list_literal, items: [%{op: :render_cmd}, %{op: :render_text_cmd}]}
    assert Stream.eligible_expr?(static)
    refute Stream.pipeline_expr?(static)
  end

  test "homogeneous static draw list is a stream pipeline" do
    rect = %{
      op: :qualified_call,
      target: "Pebble.Ui.rect",
      args: [
        %{
          op: :record_literal,
          fields: [
            %{name: "x", expr: %{op: :int_literal, value: 0}},
            %{name: "y", expr: %{op: :int_literal, value: 0}},
            %{name: "w", expr: %{op: :int_literal, value: 10}},
            %{name: "h", expr: %{op: :int_literal, value: 10}}
          ]
        },
        %{op: :int_literal, value: 1}
      ]
    }

    expr = %{op: :list_literal, items: [rect, rect]}
    assert Stream.eligible_expr?(expr)
    assert Stream.pipeline_expr?(expr)
  end

  test "List.indexedMap of draw cells is a stream pipeline" do
    rect = %{op: :render_cmd}

    expr = %{
      op: :qualified_call,
      target: "List.indexedMap",
      args: [
        %{op: :lambda, args: ["i", "v"], body: %{op: :list_literal, items: [rect]}},
        %{op: :var, name: "cells"}
      ]
    }

    assert Stream.pipeline_expr?(expr)
  end

  test "toUiNode wrapping List.map is a stream pipeline" do
    expr = %{
      op: :qualified_call,
      target: "Pebble.Ui.toUiNode",
      args: [
        %{
          op: :qualified_call,
          target: "List.map",
          args: [
            %{op: :lambda, args: ["n"], body: %{op: :render_cmd}},
            %{op: :field_access, arg: %{op: :var, name: "model"}, field: "slots"}
          ]
        }
      ]
    }

    assert Stream.pipeline_expr?(expr)
  end
end
