defmodule Elmc.UnsupportedSurfaceDiagnosticsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.{DirectRender.Emit.ExprDispatch, UnsupportedSurface}
  alias Elmc.Backend.Plan.Lower.SpecialValues.Dispatcher

  setup do
    Process.put(:elmc_compile_warnings, [])
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary, plan_ir_strict: true})

    on_exit(fn ->
      Process.delete(:elmc_compile_warnings)
      Process.delete(:elmc_codegen_opts)
    end)

    :ok
  end

  test "unknown cmd target records unsupported_cmd diagnostic" do
    assert is_nil(Dispatcher.special_value_from_target("Pebble.Cmd.unknownFutureCmd", [%{op: :int_literal, value: 1}]))

    [diag] = UnsupportedSurface.compile_warnings(plan_ir_mode: :primary, plan_ir_strict: true)

    assert diag["code"] == "unsupported_cmd"
    assert diag["source"] == "elmc/cmd"
    assert diag["severity"] == "error"
    assert diag["message"] =~ "Pebble.Cmd.unknownFutureCmd"
  end

  test "subscription miss records unsupported_sub diagnostic" do
    expr =
      UnsupportedSurface.unsupported_expr(%{
        kind: :sub,
        target: "Pebble.Events.onFutureTick",
        arity: 1,
        detail: "subscription lowering miss"
      })

    assert expr.op == :unsupported

    [diag] = UnsupportedSurface.compile_warnings(plan_ir_mode: :primary, plan_ir_strict: true)

    assert diag["code"] == "unsupported_sub"
    assert diag["message"] =~ "Pebble.Events.onFutureTick"
  end

  test "unsupported expr compile records unsupported_expr diagnostic" do
    {_code, _var, _counter} =
      ExprDispatch.compile(
        %{op: :unsupported, kind: :expr, detail: "test miss"},
        %{},
        0
      )

    diags = UnsupportedSurface.compile_warnings()

    assert Enum.any?(diags, fn diag ->
             diag["code"] == "unsupported_expr"
           end)

    # Stub may still emit elmc_int_zero for shape, but never silently under strict:
    # the diagnostic is an error when plan_ir_strict is on.
    assert Enum.any?(diags, &(&1["severity"] == "error"))
  end

  test "plan_stream_fallback Host emit is a visible warning, not a silent miss" do
    Process.put(:elmc_compile_warnings, [
      %{
        "severity" => "warning",
        "source" => "elmc/direct_render",
        "code" => "plan_stream_fallback",
        "message" => "Direct-render Main.view fell back to Host emit"
      }
    ])

    [diag] = UnsupportedSurface.compile_warnings()

    assert diag["code"] == "plan_stream_fallback"
    assert diag["source"] == "elmc/direct_render"
    assert diag["severity"] == "warning"
  end

  test "plan stream emit failure is tagged so fallback warnings can include detail" do
    alias Elmc.Backend.CCodegen.DirectRender.PlanStreamEmit

    decl = %{
      name: "view",
      args: [],
      expr: %{
        op: :list_literal,
        items: [
          %{
            op: :qualified_call,
            target: "List.map",
            args: [
              %{op: :var, name: "draw"},
              %{op: :list_literal, items: []}
            ]
          }
        ]
      }
    }

    assert {:error, {:stream_failed, reason}} = PlanStreamEmit.try_emit_body(decl, "Main", %{})
    assert reason != nil
  end

  test "plan unsupported reason formats with op and target" do
    assert UnsupportedSurface.format_plan_reason(%{op: :case, target: "List.map"}) =~ "op=case"
    assert UnsupportedSurface.format_plan_reason(%{op: :case, target: "List.map"}) =~ "List.map"
  end

  test "Time.every literal interval lowers to frame subscription on Pebble" do
    generated_c =
      Elmc.TestSupport.SnippetProject.generated_c!(
        """
        module Main exposing (main)

        import Pebble.Platform as Platform
        import Pebble.Ui as Ui
        import Pebble.Ui.Color as Color
        import Time

        type Msg
            = Tick Time.Posix

        init _ =
            ( 0, Platform.Cmd.none )

        update _ model =
            ( model, Platform.Cmd.none )

        subscriptions _ =
            Time.every 1000 Tick

        view _ =
            Ui.rect { x = 0, y = 0, w = 10, h = 10 } Color.black

        main =
            Platform.worker { init = init, update = update, subscriptions = subscriptions, view = view }
        """,
        name: "time_every_literal"
      )

    assert generated_c =~ "ELMC_SUBSCRIPTION_FRAME_BASE"
    assert generated_c =~ "ELMC_PEBBLE_MSG_TICK"
    refute generated_c =~ "elmc_int_zero()"
  end

  test "Time.every non-literal interval records unsupported_sub" do
    assert %{
             op: :unsupported,
             kind: :sub,
             target: "Elm.Kernel.Time.every"
           } =
             Dispatcher.special_value_from_target("Time.every", [
               %{op: :var, name: "interval"},
               %{op: :var, name: "Tick"}
             ])

    [diag] = UnsupportedSurface.compile_warnings(plan_ir_mode: :primary, plan_ir_strict: true)

    assert diag["code"] == "unsupported_sub"
    assert diag["message"] =~ "Time.every"
    assert diag["message"] =~ "interval must be int literal"
  end

  test "Frame.every non-literal interval records unsupported_sub" do
    assert %{
             op: :unsupported,
             kind: :sub,
             target: "Pebble.Frame.every"
           } =
             Dispatcher.special_value_from_target("Pebble.Frame.every", [
               %{op: :var, name: "interval"},
               %{op: :var, name: "Tick"}
             ])

    [diag] = UnsupportedSurface.compile_warnings(plan_ir_mode: :primary, plan_ir_strict: true)

    assert diag["code"] == "unsupported_sub"
    assert diag["message"] =~ "interval must be int literal"
  end

  test "unknown Pebble.Speaker cmd records unsupported_cmd diagnostic" do
    assert is_nil(Dispatcher.special_value_from_target("Pebble.Speaker.unknown", []))

    [diag] = UnsupportedSurface.compile_warnings(plan_ir_mode: :primary, plan_ir_strict: true)

    assert diag["code"] == "unsupported_cmd"
    assert diag["message"] =~ "Pebble.Speaker.unknown"
  end

  test "draw field arity miss records unsupported_cmd diagnostic" do
    expr =
      Elmc.Backend.Plan.Lower.SpecialValues.Helpers.encoded_draw_field_cmd_expr(
        5,
        [%{op: :int_literal, value: 1}],
        2
      )

    assert expr.op == :unsupported

    [diag] = UnsupportedSurface.compile_warnings(plan_ir_mode: :primary, plan_ir_strict: true)

    assert diag["code"] == "unsupported_cmd"
    assert diag["message"] =~ "encoded_draw_field_cmd"
  end

  test "constructor_ref and qualified_ref compile without unsupported_expr" do
    Process.put(:elmc_font_resource_slots, %{"DefaultFont" => 1})

    on_exit(fn ->
      Process.delete(:elmc_font_resource_slots)
    end)

    {_code, _var, _counter} =
      ExprDispatch.compile(
        %{op: :constructor_ref, target: "Pebble.Ui.Resources.DefaultFont"},
        %{},
        0
      )

    {_code, _var, _counter} =
      ExprDispatch.compile(
        %{op: :qualified_ref, target: "Pebble.Ui.Color.white"},
        %{},
        0
      )

    diags = UnsupportedSurface.compile_warnings(plan_ir_mode: :primary, plan_ir_strict: true)

    refute Enum.any?(diags, fn diag ->
             diag["code"] == "unsupported_expr" and
               (diag["message"] =~ "constructor_ref" or diag["message"] =~ "qualified_ref" or
                  diag["message"] =~ "unhandled expr")
           end)
  end

  test "unknown ExprCompile op records real op name not unknown" do
    {_code, _var, _counter} =
      ExprDispatch.compile(%{op: :future_ir_op, payload: 1}, %{}, 0)

    [diag] = UnsupportedSurface.compile_warnings(plan_ir_mode: :primary, plan_ir_strict: true)

    assert diag["code"] == "unsupported_expr"
    assert diag["message"] =~ "op=future_ir_op"
    refute diag["message"] =~ "op=unknown"
  end
end
