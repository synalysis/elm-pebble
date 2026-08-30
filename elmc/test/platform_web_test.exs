defmodule Elmc.PlatformWebTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Function
  alias Elmc.Backend.Plan.Lower.Platform.Web

  @sandbox_element_record %{
    op: :record_literal,
    fields: [
      %{
        name: "init",
        expr: %{
          op: :lambda,
          args: ["unitArg"],
          body: %{
            op: :tuple2,
            left: %{op: :field_access, arg: "impl", field: "init"},
            right: %{op: :qualified_call, target: "Cmd.none", args: []}
          }
        }
      },
      %{name: "view", expr: %{op: :field_access, arg: "impl", field: "view"}},
      %{
        name: "update",
        expr: %{
          op: :lambda,
          args: ["msg"],
          body: %{
            op: :lambda,
            args: ["model"],
            body: %{
              op: :tuple2,
              left: %{
                op: :field_call,
                arg: "impl",
                field: "update",
                args: [%{op: :var, name: "msg"}, %{op: :var, name: "model"}]
              },
              right: %{op: :qualified_call, target: "Cmd.none", args: []}
            }
          }
        }
      },
      %{
        name: "subscriptions",
        expr: %{
          op: :lambda,
          args: ["ignoredArg"],
          body: %{op: :qualified_call, target: "Sub.none", args: []}
        }
      }
    ]
  }

  setup do
    Process.put(:elmc_codegen_opts, %{targets: [:wasm], web: true})
    on_exit(fn -> Process.delete(:elmc_codegen_opts) end)
    :ok
  end

  test "web_target? follows wasm targets opt" do
    assert Web.web_target?(%{targets: [:wasm], web: true})
    refute Web.web_target?(%{targets: [:wasm]})
    refute Web.web_target?(%{targets: [:c]})
  end

  test "rewrite_html_tag_function_decl expands VirtualDom.node partials" do
    decl = %{
      name: "code",
      expr: %{
        op: :qualified_call,
        target: "Elm.Kernel.VirtualDom.node",
        args: [%{op: :string_literal, value: "code"}]
      }
    }

    rewritten =
      Web.rewrite_html_tag_function_decl("Html", decl, %{targets: [:wasm], web: true})

    assert rewritten.args == ["attrs", "children"]
    assert %{op: :html_cmd, kind: %{value: 2}} = rewritten.expr
  end

  test "rewrite_html_lazy_function_decl expands Html.Lazy.lazy2 and lazy5" do
    lazy2 =
      Web.rewrite_html_lazy_function_decl(
        "Html.Lazy",
        %{name: "lazy2", expr: %{op: :int_literal, value: 0}},
        %{targets: [:wasm], web: true}
      )

    assert lazy2.args == ["fn", "a", "b"]
    assert %{op: :html_cmd, kind: %{value: 11}, params: params2} = lazy2.expr
    assert length(params2) == 3

    lazy5 =
      Web.rewrite_html_lazy_function_decl(
        "Html.Lazy",
        %{name: "lazy5", expr: %{op: :int_literal, value: 0}},
        %{targets: [:wasm], web: true}
      )

    assert lazy5.args == ["fn", "a", "b", "c", "d", "e"]
    assert %{op: :html_cmd, kind: %{value: 16}} = lazy5.expr
  end

  test "rewrite_html_map_function_decl expands Html.Attributes.map to html_cmd kind 21" do
    decl = %{
      name: "map",
      expr: %{
        op: :qualified_call,
        target: "VirtualDom.mapAttribute",
        args: []
      }
    }

    rewritten =
      Web.rewrite_html_map_function_decl("Html.Attributes", decl, %{targets: [:wasm], web: true})

    assert rewritten.args == ["func", "attr"]
    assert %{op: :html_cmd, kind: %{value: 21}, params: [func, attr]} = rewritten.expr
    assert func == %{op: :var, name: "func"}
    assert attr == %{op: :var, name: "attr"}
  end

  test "rewrite_html_lazy_function_decl expands Html.Lazy.lazy to html_cmd kind 6" do
    decl = %{
      name: "lazy",
      expr: %{
        op: :qualified_call,
        target: "Html.Lazy.lazy",
        args: [%{op: :var, name: "fn"}, %{op: :var, name: "arg"}]
      }
    }

    rewritten =
      Web.rewrite_html_lazy_function_decl("Html.Lazy", decl, %{targets: [:wasm], web: true})

    assert rewritten.args == ["fn", "arg"]
    assert %{op: :html_cmd, kind: %{value: 6}} = rewritten.expr
  end

  test "Browser.sandbox lowers Elm.Kernel.Browser.element to browser_cmd" do
    decl = %{
      name: "sandbox",
      args: ["impl"],
      type:
        "{init : model, view : model -> Html msg, update : msg -> model -> model} -> Program () model msg",
      expr: %{
        op: :qualified_call,
        target: "Elm.Kernel.Browser.element",
        args: [@sandbox_element_record]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Browser", %{}, targets: [:wasm], web: true)

    ops =
      plan.blocks
      |> Enum.flat_map(fn block ->
        block.instrs ++
          case block.terminator do
            {:ret, _} -> []
            term when is_map(term) -> [term]
            _ -> []
          end
      end)
      |> Enum.map(& &1.op)

    assert :browser_cmd in ops
    refute Enum.any?(ops, &(&1 == :pebble_sub))
    refute Enum.any?(ops, &(&1 == :pebble_cmd))

    view_gets =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(fn instr ->
        instr.op == :record_get and Map.get(instr.args, :field) == "view"
      end)

    assert view_gets != []
  # Sandbox impl `{init, view, update}` is stored alphabetically: init, update, view.
    assert Enum.all?(view_gets, fn instr -> String.starts_with?(instr.args[:field_index], "2") end)
  end

  test "Html.Events.onMouseEnter lowers to html_cmd event" do
    decl = %{
      name: "hover",
      args: ["msg"],
      expr: %{
        op: :qualified_call,
        target: "Html.Events.onMouseEnter",
        args: [%{op: :var, name: "msg"}]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, targets: [:wasm], web: true)

    events =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :html_cmd))

    assert events != []
    assert Enum.any?(events, fn instr ->
             kind = instr.args[:kind]
             kind == 8 or match?(%{op: :int_literal, value: 8}, kind)
           end)
  end
end
