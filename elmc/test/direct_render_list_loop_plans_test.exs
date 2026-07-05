defmodule Elmc.DirectRenderListLoopPlansTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.DirectRender.ListLoopPlans
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Test.CCodegenExtract
  alias ElmEx.IR.PipeChain

  @fixture Path.expand("fixtures/simple_project", __DIR__)

  test "analyze accepts map of filter of range and append of two pipelines" do
    range = range_expr(1, 5)

    filter_fn = %{
      op: :lambda,
      args: ["n"],
      body: %{
        op: :call,
        name: "==",
        args: [
          %{op: :call, name: "modBy", args: [%{op: :int_literal, value: 2}, %{op: :var, name: "n"}]},
          %{op: :int_literal, value: 1}
        ]
      }
    }

    map_fn = %{
      op: :lambda,
      args: ["i"],
      body: %{
        op: :record_literal,
        fields: [
          %{name: "value", expr: %{op: :call, name: "__mul__", args: [%{op: :var, name: "i"}, %{op: :int_literal, value: 60}]}},
          %{name: "size", expr: %{op: :int_literal, value: 10}},
          %{name: "label", expr: %{op: :constructor_call, target: "Nothing", args: []}}
        ]
      }
    }

    short =
      %{
        op: :qualified_call,
        target: "List.map",
        args: [map_fn, %{op: :qualified_call, target: "List.filter", args: [filter_fn, range]}]
      }

    long =
      %{
        op: :qualified_call,
        target: "List.map",
        args: [
          map_fn,
          range_expr(0, 2)
        ]
      }

    append = %{op: :call, name: "__append__", args: [short, long]}

    var_append = %{
      op: :call,
      name: "__append__",
      args: [%{op: :var, name: "left"}, %{op: :var, name: "right"}]
    }

    frag_env = %{
      "left" => {:direct_fragment, short},
      "right" => {:direct_fragment, long}
    }

    assert ListLoopPlans.pipeline_fragment?(short, %{})
    assert ListLoopPlans.pipeline_fragment?(append, %{})
    assert {:ok, plans} = ListLoopPlans.analyze(append, %{})
    assert {:ok, var_plans} = ListLoopPlans.analyze(var_append, frag_env)
    assert length(plans) == 2
    assert length(var_plans) == 2
    assert Enum.at(plans, 0)[:filter] == {:mod_by_eq, 2, 1}
  end

  test "concatMap over composed range filter map pipelines emits loops without list runtime" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Layout =
        { cx : Int, cy : Int, radius : Int }

    type alias TickSpec =
        { value : Int, size : Int, label : Maybe String }

    type alias Model =
        {}

    type Msg
        = NoOp

    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }

    init _ =
        ( {}, Platform.Cmd.none )

    update _ model =
        ( model, Platform.Cmd.none )

    subscriptions _ =
        Platform.Sub.none

    view _ =
        Ui.toUiNode <|
            let
                shortItems =
                    List.map
                        (\\i -> { value = i * 60, size = 10, label = Nothing })
                        (List.filter (\\n -> modBy 2 n == 1) (List.range 1 5))

                longItems =
                    List.map
                        (\\i -> { value = i * 120, size = 6, label = Nothing })
                        (List.range 0 2)
            in
            List.concatMap (drawTick layout) (shortItems ++ longItems)

    layout =
        { cx = 72, cy = 84, radius = 60 }

    drawTick layout spec =
        let
            x0 =
                layout.cx + layout.radius

            y0 =
                layout.cy

            x1 =
                layout.cx + layout.radius + spec.size

            y1 =
                layout.cy + spec.value // 60
        in
        [ Ui.line { x = x1, y = y1 } { x = x0, y = y0 } Color.white ]
    """

    project_dir = Path.expand("tmp/direct_list_loop_plans_project", __DIR__)
    out_dir = Path.expand("tmp/direct_list_loop_plans_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(@fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true
             })

    decl_map = IRQueries.function_decl_map(result.ir)
    env = %{__module__: "Main", __program_decls__: decl_map}
    view = Map.fetch!(decl_map, {"Main", "view"})

    assert pipeline_lets_fragment?(view.expr, env)

    concat_list = concat_map_list_expr(view.expr)

    frag_env =
      lets(view.expr)
      |> Enum.reduce(env, fn {name, value}, acc ->
        Map.put(acc, name, {:direct_fragment, value})
      end)
    plans =
      case ListLoopPlans.analyze(concat_list, frag_env) do
        {:ok, plans} ->
          plans

        :error ->
          flunk("analyze failed for concat list with fragment env")
      end
    assert length(plans) == 2

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")
    draw_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_drawTick_commands_append")

    assert view_body =~ "direct_item_i_"
    assert draw_body =~ "ELMC_RENDER_OP_LINE"
    refute view_body =~ "elmc_list_range"
    refute view_body =~ "elmc_list_filter"
    refute view_body =~ "elmc_list_from_int_array"
    refute view_body =~ "ELMC_TAG_LIST"
    refute view_body =~ "elmc_malloc"
  end

  defp range_expr(first, last) do
    %{
      op: :qualified_call,
      target: "List.range",
      args: [%{op: :int_literal, value: first}, %{op: :int_literal, value: last}]
    }
  end

  defp view_body(expr), do: PipeChain.desugar(expr)

  defp lets(expr), do: expr |> view_body() |> collect_lets(%{})

  defp collect_lets(%{op: :let_in, name: name, value_expr: value, in_expr: inner}, acc),
    do: collect_lets(inner, Map.put(acc, name, value))

  defp collect_lets(%{op: :qualified_call, target: "Pebble.Ui.toUiNode", args: [inner]}, acc),
    do: collect_lets(inner, acc)

  defp collect_lets(_, acc), do: acc

  defp concat_map_list_expr(expr) do
    expr
    |> view_body()
    |> find_concat_map_list()
  end

  defp find_concat_map_list(%{op: :let_in, in_expr: inner}), do: find_concat_map_list(inner)

  defp find_concat_map_list(%{op: :qualified_call, target: t, args: [_fun, list]})
       when t in ["List.concatMap", "Elm.Kernel.List.concatMap"],
       do: list

  defp find_concat_map_list(%{op: :qualified_call, target: "Pebble.Ui.toUiNode", args: [inner]}),
    do: find_concat_map_list(inner)

  defp find_concat_map_list(_),
    do: flunk("could not find List.concatMap in view IR")

  defp pipeline_lets_fragment?(expr, env) do
    case view_body(expr) do
      %{op: :let_in, value_expr: v, in_expr: i} ->
        ListLoopPlans.pipeline_fragment?(v, env) and pipeline_lets_fragment?(i, env)

      %{op: :qualified_call, target: "Pebble.Ui.toUiNode", args: [inner]} ->
        pipeline_lets_fragment?(inner, env)

      _ ->
        true
    end
  end
end
