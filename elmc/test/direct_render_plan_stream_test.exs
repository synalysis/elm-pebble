defmodule Elmc.DirectRenderPlanStreamTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.SnippetProject
  alias Elmc.TestSupport.TemplateCompile

  test "simple view list lowers through plan stream SSA with scene writer push" do
    {result, generated_c} =
      SnippetProject.compile_checked!(simple_view_source(),
        name: "direct_plan_stream_simple_view",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_simple_view_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "elmc_draw_cmd_init"
    assert view_body =~ "elmc_scene_writer_push_cmd"
    refute view_body =~ "elmc_render_cmd6_take"
    refute view_body =~ "ELMC_TAG_LIST"
    refute_plan_stream_fallback(result)
  end

  test "homogeneous static draw list emits a Plan table walk" do
    {result, generated_c} =
      SnippetProject.compile_checked!(static_draw_table_view_source(),
        name: "direct_plan_stream_static_draw_table",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_static_draw_table_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "direct_static_draw_table_"
    assert view_body =~ "elmc_scene_writer_push_cmd"
    refute view_body =~ "ELMC_TAG_LIST"
    refute view_body =~ "elmc_render_cmd6_take"
    refute_plan_stream_fallback(result)
  end

  test "indexedMap affine textInt helper streams as a Plan affine loop" do
    {result, generated_c} =
      SnippetProject.compile_checked!(affine_text_int_view_source(),
        name: "direct_plan_stream_affine_text_int",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_affine_text_int_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "direct_index_"
    assert view_body =~ "direct_item_i_"
    assert view_body =~ "elmc_scene_writer_push_cmd"
    refute view_body =~ "elmc_fn_Main_row_commands_append_native"
    refute_plan_stream_fallback(result)
  end

  test "indexedMap affine text fromInt with different names streams as Plan fusion" do
    {result, generated_c} =
      SnippetProject.compile_checked!(affine_text_label_view_source(),
        name: "direct_plan_stream_affine_text_label",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_affine_text_label_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "ELMC_RENDER_OP_TEXT"
    assert view_body =~ "elmc_scene_text_from_nonzero_int"
    assert view_body =~ "scene_cmd.text[0] = '.'"
    refute view_body =~ "elmc_fn_Main_paintMark_commands_append_native"
    refute_plan_stream_fallback(result)
  end

  test "Maybe case view list lowers through plan stream SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(maybe_case_view_source(),
        name: "direct_plan_stream_maybe_case",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_maybe_case_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "elmc_scene_writer_push_cmd"
    refute view_body =~ "ELMC_TAG_LIST"
    refute_plan_stream_fallback(result)
  end

  test "List.map over a literal and List.range unrolls through plan stream SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(list_map_view_source(),
        name: "direct_plan_stream_list_map",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_list_map_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "elmc_scene_writer_push_cmd"
    refute view_body =~ "elmc_list_map"
    refute_plan_stream_fallback(result)
  end

  test "List.map of a capturing lambda over a model list walks through plan stream SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(lambda_map_view_source(),
        name: "direct_plan_stream_lambda_map",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_lambda_map_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    streamed_lambda? =
      generated_c =~
        ~r/static RC elmc_fn_Main_view_closure_\d+\(ElmcValue \*\*args, int argc, ElmcValue \*\*captures, int capture_count, ElmcSceneWriter \*writer\)/

    assert streamed_lambda? or view_body =~ "elmc_scene_writer_push_cmd"
    assert view_body =~ "ELMC_TAG_INT_LIST" or view_body =~ "ELMC_TAG_LIST" or
             view_body =~ "ELMC_RENDER_OP_RECT"
    refute view_body =~ "elmc_list_map"
    refute_plan_stream_fallback(result)
  end

  test "List.map of a lambda that calls a named draw helper walks through plan stream SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(lambda_draw_at_view_source(),
        name: "direct_plan_stream_lambda_draw_at",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_lambda_draw_at_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    streamed_lambda? =
      generated_c =~
        ~r/static RC elmc_fn_Main_view_closure_\d+\(ElmcValue \*\*args, int argc, ElmcValue \*\*captures, int capture_count, ElmcSceneWriter \*writer\)/

    streamed_apply? =
      view_body =~ "elmc_fn_Main_drawAt_commands_append_native" or
        view_body =~ "elmc_fn_Main_drawAt_commands_append("

    assert streamed_lambda? or streamed_apply?
    assert view_body =~ "ELMC_TAG_INT_LIST" or view_body =~ "ELMC_TAG_LIST"
    refute view_body =~ "elmc_list_map"
    refute_plan_stream_fallback(result)
  end

  test "List.map of a named draw helper uses native commands_append ABI" do
    {result, generated_c} =
      SnippetProject.compile_checked!(lambda_draw_at_view_source(),
        name: "direct_plan_stream_nested_native_append",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_nested_native_append_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "elmc_fn_Main_drawAt_commands_append_native"
    assert view_body =~ "stream_fe_"
    refute view_body =~ ~r/elmc_fn_Main_drawAt_commands_append\(stream_fe_argv_/
    refute view_body =~ "elmc_list_map"
    refute_plan_stream_fallback(result)
  end

  test "List.filter of static render commands walks through plan stream SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(filter_static_cmds_view_source(),
        name: "direct_plan_stream_filter_static_cmds",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_filter_static_cmds_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "elmc_scene_writer_push_cmd"
    refute view_body =~ "elmc_list_filter"
    refute_plan_stream_fallback(result)
  end

  test "List.filter of a model command list walks through plan stream SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(filter_model_cmds_view_source(),
        name: "direct_plan_stream_filter_model_cmds",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_filter_model_cmds_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    streamed_lambda? =
      generated_c =~
        ~r/static RC elmc_fn_Main_view_closure_\d+\(ElmcValue \*\*args, int argc, ElmcValue \*\*captures, int capture_count, ElmcSceneWriter \*writer\)/

    assert streamed_lambda? or view_body =~ "elmc_draw_cmd_from_value"
    assert view_body =~ "elmc_scene_writer_push_cmd" or generated_c =~ "elmc_draw_cmd_from_value"
    refute view_body =~ "elmc_list_filter"
    refute_plan_stream_fallback(result)
  end

  test "List.map over List.filter of a model list walks through plan stream SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(filter_map_view_source(),
        name: "direct_plan_stream_filter_map",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_filter_map_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    streamed_lambda? =
      generated_c =~
        ~r/static RC elmc_fn_Main_view_closure_\d+\(ElmcValue \*\*args, int argc, ElmcValue \*\*captures, int capture_count, ElmcSceneWriter \*writer\)/

    assert streamed_lambda? or view_body =~ "elmc_scene_writer_push_cmd"
    assert view_body =~ "ELMC_TAG_INT_LIST" or view_body =~ "ELMC_TAG_LIST" or
             view_body =~ "ELMC_RENDER_OP_RECT"
    refute view_body =~ "elmc_list_map"
    refute_plan_stream_fallback(result)
  end

  test "List.filterMap of static Maybe render commands walks through plan stream SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(filter_map_static_maybe_cmds_view_source(),
        name: "direct_plan_stream_filter_map_static_maybe",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_filter_map_static_maybe_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "elmc_scene_writer_push_cmd"
    refute view_body =~ "elmc_list_filter_map"
    refute_plan_stream_fallback(result)
  end

  test "List.filterMap that draws from a model int list walks through plan stream SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(filter_map_draw_cells_view_source(),
        name: "direct_plan_stream_filter_map_draw_cells",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_filter_map_draw_cells_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    streamed_lambda? =
      generated_c =~
        ~r/static RC elmc_fn_Main_view_closure_\d+\(ElmcValue \*\*args, int argc, ElmcValue \*\*captures, int capture_count, ElmcSceneWriter \*writer\)/

    assert streamed_lambda? or view_body =~ "elmc_scene_writer_push_cmd"
    assert generated_c =~ "elmc_scene_writer_push_cmd"
    refute view_body =~ "elmc_list_filter_map"
    refute_plan_stream_fallback(result)
  end

  test "List.cons of a clear onto indexedMap walks through plan stream SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(cons_indexed_map_view_source(),
        name: "direct_plan_stream_cons_indexed_map",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_cons_indexed_map_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "elmc_scene_writer_push_cmd"
    assert view_body =~ "elmc_fn_Main_cellOp_commands_append" or view_body =~ "ELMC_RENDER_OP_RECT"
    assert view_body =~ "ELMC_TAG_INT_LIST" or view_body =~ "ELMC_TAG_LIST"
    refute view_body =~ "elmc_list_cons"
    refute_plan_stream_fallback(result)
  end

  test "List.indexedMap of a named helper over a model list walks through plan stream SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(indexed_map_view_source(),
        name: "direct_plan_stream_indexed_map",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_indexed_map_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "elmc_fn_Main_cellOp_commands_append" or view_body =~ "ELMC_RENDER_OP_RECT"
    assert view_body =~ "ELMC_TAG_INT_LIST" or view_body =~ "ELMC_TAG_LIST"
    refute view_body =~ "elmc_list_indexed_map"
    refute_plan_stream_fallback(result)
  end

  test "direct render keeps native Basics.min and font literals unboxed in view_commands_append" do
    out_dir =
      SnippetProject.compile_main!(native_min_view_source(),
        name: "direct_plan_stream_native_min",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_native_min_codegen", __DIR__)
      )

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    refute view_body =~ ~r/elmc_new_int\(&owned\[\d+\], 1\)/
    assert view_body =~ "scene_cmd.p0 = 1"
    assert view_body =~ "scene_cmd.text["
    refute view_body =~ ~r/elmc_as_int_number\(owned\[\d+\]\)/
    refute view_body =~ "direct_cursor_"
  end

  test "Ui.text, textInt, and string-append labels stream through plan SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(text_hud_view_source(),
        name: "direct_plan_stream_text_hud",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_text_hud_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "elmc_scene_writer_push_cmd"
    assert view_body =~ "scene_cmd.text["
    refute view_body =~ "elmc_render_text_cmd_take"
    refute view_body =~ "direct_cursor_"
    refute_plan_stream_fallback(result)
  end

  test "2048-shaped chrome if and drawCell label if stream through plan SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(chrome_draw_cell_view_source(),
        name: "direct_plan_stream_chrome_draw_cell",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_chrome_draw_cell_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")
    cell_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_drawCell_commands_append")

    assert view_body =~ "elmc_fn_Main_drawCell_commands_append"
    assert view_body =~ "elmc_scene_writer_push_cmd"
    assert cell_body =~ "ELMC_RENDER_OP_PUSH_CONTEXT"
    assert cell_body =~ "scene_cmd.text["
    refute_plan_stream_fallback(result)
  end

  test "Ui.context / Ui.group stream as push/pop around nested draw ops" do
    {result, generated_c} =
      SnippetProject.compile_checked!(context_group_view_source(),
        name: "direct_plan_stream_context_group",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_context_group_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")
    cell_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_drawCell_commands_append")

    assert view_body =~ "elmc_fn_Main_drawCell_commands_append"
    assert cell_body =~ "ELMC_RENDER_OP_PUSH_CONTEXT"
    assert cell_body =~ "ELMC_RENDER_OP_POP_CONTEXT"
    assert cell_body =~ "ELMC_RENDER_OP_STROKE_COLOR" or cell_body =~ "ELMC_RENDER_OP_TEXT_COLOR"
    assert cell_body =~ "elmc_scene_writer_push_cmd"
    refute_plan_stream_fallback(result)
  end

  test "elmtris-shaped hud helper, overlay if, and slot map stream through plan SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(elmtris_hud_slots_view_source(),
        name: "direct_plan_stream_elmtris_hud_slots",
        typecheck: false,
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_elmtris_hud_slots_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "elmc_scene_writer_push_cmd"
    assert view_body =~ "ELMC_RENDER_OP_TEXT"
    assert view_body =~ "stream_fe_" or view_body =~ "elmc_fn_Main_drawAt_commands_append" or
             view_body =~ "ELMC_RENDER_OP_RECT"
    refute_plan_stream_fallback(result)
  end

  test "yes-shaped concatMap tick records and textAt stream through plan SSA" do
    {result, generated_c} =
      SnippetProject.compile_checked!(yes_tick_scale_view_source(),
        name: "direct_plan_stream_yes_tick_scale",
        typecheck: false,
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary,
          plan_ir_strict: true
        },
        out_dir: Path.expand("tmp/direct_plan_stream_yes_tick_scale_codegen", __DIR__)
      )

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "elmc_scene_writer_push_cmd"
    assert view_body =~ "stream_fe_" or view_body =~ "elmc_fn_Main_drawScaleTick_commands_append" or
             view_body =~ "elmc_fn_Main_drawDial_commands_append" or view_body =~ "ELMC_RENDER_OP_LINE"
    refute_plan_stream_fallback(result)
  end

  @tag :slow
  test "watchface_yes face streams through plan SSA" do
    out_dir = Path.expand("tmp/direct_plan_stream_yes_face_codegen", __DIR__)

    {:ok, result} =
      TemplateCompile.compile_watch_template("watchface_yes",
        plan_ir_mode: :primary,
        plan_ir_strict: true,
        out_dir: out_dir
      )

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "elmc_scene_writer_push_cmd"
    assert view_body =~ "stream_fe_" or
             view_body =~ "elmc_fn_Yes_Render_drawScaleTick_commands_append"

    refute_list_loop_cursor(view_body)
    refute_plan_stream_fallback(result)
  end

  @tag :slow
  test "game_2048 view streams through plan SSA" do
    {result, view_body} = compile_template_view_stream("game_2048")

    assert view_body =~ "elmc_scene_writer_push_cmd"
    assert view_body =~ "stream_fe_" or view_body =~ "elmc_fn_Main_drawCell_commands_append"
    refute_list_loop_cursor(view_body)
    refute_plan_stream_fallback(result)
  end

  @tag :slow
  test "game_elmtris view streams through plan SSA" do
    {result, view_body} = compile_template_view_stream("game_elmtris")

    assert view_body =~ "elmc_scene_writer_push_cmd"
    assert view_body =~ "stream_fe_" or view_body =~ "elmc_fn_Main_drawAt_commands_append"
    refute_list_loop_cursor(view_body)
    refute_plan_stream_fallback(result)
  end

  defp compile_template_view_stream(template) when is_binary(template) do
    out_dir = Path.expand("tmp/direct_plan_stream_#{template}_codegen", __DIR__)

    {:ok, result} =
      TemplateCompile.compile_watch_template(template,
        plan_ir_mode: :primary,
        plan_ir_strict: true,
        out_dir: out_dir
      )

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")
    {result, view_body}
  end

  defp text_hud_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { score : Int
        , best : Int
        }


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
        ( { score = 12, best = 40 }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode
            [ Ui.clear Color.white
            , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 4, w = 80, h = 14 } "Elmtris"
            , Ui.textInt Resources.DefaultFont { x = 4, y = 18 } model.score
            , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 32, w = 80, h = 14 } ("Best " ++ String.fromInt model.best)
            ]
    """
  end

  defp chrome_draw_cell_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Layout =
        { cell : Int
        , gap : Int
        }


    type alias Model =
        { cells : List Int
        , best : Int
        , layout : Layout
        , round : Bool
        }


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
        ( { cells = [ 0, 2 ], best = 8, layout = { cell = 16, gap = 2 }, round = False }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    drawCell : Layout -> Int -> Int -> Ui.RenderOp
    drawCell layout i n =
        let
            x =
                i * (layout.cell + layout.gap)

            label =
                if n == 0 then
                    "."

                else
                    String.fromInt n
        in
        Ui.context
            [ Ui.strokeColor Color.black
            , Ui.textColor Color.black
            ]
            [ Ui.rect { x = x, y = 0, w = layout.cell, h = layout.cell } Color.white
            , Ui.text Resources.DefaultFont (Ui.alignCenter Ui.defaultTextOptions) { x = x, y = 0, w = layout.cell, h = 18 } label
            ]
            |> Ui.group


    view model =
        let
            textOptions =
                Ui.alignCenter Ui.defaultTextOptions

            chromeOps =
                if model.round then
                    [ Ui.text Resources.DefaultFont textOptions { x = 4, y = 4, w = 40, h = 14 } "2048"
                    , Ui.text Resources.DefaultFont textOptions { x = 4, y = 20, w = 40, h = 14 } ("Best " ++ String.fromInt model.best)
                    ]

                else
                    [ Ui.text Resources.DefaultFont textOptions { x = 4, y = 4, w = 80, h = 14 } ("2048  Best " ++ String.fromInt model.best)
                    ]
        in
        Ui.clear Color.white
            :: (chromeOps ++ List.indexedMap (drawCell model.layout) model.cells)
            |> Ui.toUiNode
    """
  end

  defp elmtris_hud_slots_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Layout =
        { x : Int
        , y : Int
        , cell : Int
        , gap : Int
        }


    type alias Model =
        { slots : List Int
        , score : Int
        , lines : Int
        , screenW : Int
        , screenH : Int
        , displayShape : Platform.DisplayShape
        , gameOver : Bool
        }


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
        ( { slots = [ 0, 1 ]
          , score = 12
          , lines = 3
          , screenW = 144
          , screenH = 168
          , displayShape = Platform.Round
          , gameOver = False
          }
        , Cmd.none
        )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    boardLayout : Model -> Layout
    boardLayout model =
        if Platform.displayShapeIsRound model.displayShape then
            { x = 8, y = 28, cell = 10, gap = 1 }

        else
            { x = 6, y = 30, cell = 8, gap = 1 }


    cellColor : Int -> Color
    cellColor kind =
        case modBy 7 kind of
            0 ->
                Color.black

            1 ->
                Color.darkGray

            _ ->
                Color.black


    drawAt : Layout -> Int -> Int -> Int -> Ui.RenderOp
    drawAt layout col row kind =
        let
            x =
                layout.x + col * (layout.cell + layout.gap)

            y =
                layout.y + row * (layout.cell + layout.gap)
        in
        Ui.fillRect { x = x, y = y, w = layout.cell, h = layout.cell }
            (if kind == 0 then
                Color.white

             else
                cellColor kind
            )


    hudOps : Model -> List Ui.RenderOp
    hudOps model =
        let
            textOptions =
                if Platform.displayShapeIsRound model.displayShape then
                    Ui.alignCenter Ui.defaultTextOptions

                else
                    Ui.defaultTextOptions

            textW =
                if Platform.displayShapeIsRound model.displayShape then
                    (min model.screenW model.screenH * 4) // 9

                else
                    model.screenW - 8

            textX =
                (model.screenW - textW) // 2

            y =
                if Platform.displayShapeIsRound model.displayShape then
                    6

                else
                    4
        in
        [ Ui.text Resources.DefaultFont textOptions { x = textX, y = y, w = textW, h = 14 } "Elmtris"
        , Ui.textInt Resources.DefaultFont { x = textX, y = y + 14 } model.score
        , Ui.textInt Resources.DefaultFont { x = textX + textW // 2, y = y + 14 } model.lines
        ]


    gameOverOps : Model -> List Ui.RenderOp
    gameOverOps model =
        let
            textOptions =
                Ui.alignCenter Ui.defaultTextOptions

            textW =
                if Platform.displayShapeIsRound model.displayShape then
                    (min model.screenW model.screenH * 4) // 9

                else
                    model.screenW - 8
        in
        [ Ui.text Resources.DefaultFont textOptions { x = 8, y = 80, w = textW, h = 14 } "Up/Back" ]


    slotOps : Layout -> Model -> List Ui.RenderOp
    slotOps layout model =
        List.map
            (\\slot ->
                drawAt layout (modBy 10 slot) (slot // 10) 1
            )
            model.slots


    view model =
        let
            layout =
                boardLayout model

            overlay =
                if model.gameOver then
                    gameOverOps model

                else
                    []
        in
        Ui.toUiNode
            ([ Ui.clear Color.white ]
                ++ hudOps model
                ++ slotOps layout model
                ++ overlay
            )
    """
  end

  defp yes_tick_scale_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Layout =
        { cx : Int
        , cy : Int
        , outerRadius : Int
        , timeTextBand : { x : Int, y : Int, w : Int, h : Int }
        }


    type alias TickSpec =
        { minute : Int
        , extra : Int
        , label : Maybe String
        }


    type SunMode
        = PolarNight
        | PolarDay
        | SunCycle


    type alias Model =
        { layout : Layout
        , timeText : String
        , showCorners : Bool
        , moonriseMin : Maybe Int
        , moonsetMin : Maybe Int
        , sunMode : SunMode
        , sun : Maybe { sunrise : Int, sunset : Int }
        }


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
        ( { layout =
                { cx = 72
                , cy = 84
                , outerRadius = 70
                , timeTextBand = { x = 40, y = 76, w = 64, h = 16 }
                }
          , timeText = "12:00"
          , showCorners = True
          , moonriseMin = Just 360
          , moonsetMin = Just 1080
          , sunMode = SunCycle
          , sun = Just { sunrise = 360, sunset = 1080 }
          }
        , Cmd.none
        )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    textAt : Color.Color -> { x : Int, y : Int, w : Int, h : Int } -> String -> Ui.RenderOp
    textAt color bounds value =
        Ui.group
            (Ui.context
                [ Ui.textColor color ]
                [ Ui.text Resources.DefaultFont Ui.defaultTextOptions bounds value ]
            )


    angleFromMinute : Int -> Int
    angleFromMinute minute =
        modBy 65536 (((minute - 720) * 65536) // 1440)


    pointAt : Int -> Int -> Int -> Int -> { x : Int, y : Int }
    pointAt cx cy radius angle =
        let
            theta =
                toFloat angle * 2 * pi / 65536
        in
        { x = cx + round (sin theta * toFloat radius)
        , y = cy - round (cos theta * toFloat radius)
        }


    coloredRadial : { x : Int, y : Int, w : Int, h : Int } -> Color.Color -> Int -> Int -> List Ui.RenderOp
    coloredRadial bounds fill start end =
        [ Ui.group
            (Ui.context
                [ Ui.fillColor fill, Ui.strokeColor fill ]
                [ Ui.fillRadial bounds start end ]
            )
        ]


    drawScaleTick : Layout -> TickSpec -> List Ui.RenderOp
    drawScaleTick layout spec =
        let
            tickAngle =
                angleFromMinute spec.minute

            inner =
                pointAt layout.cx layout.cy layout.outerRadius tickAngle

            outer =
                pointAt layout.cx layout.cy (layout.outerRadius + spec.extra) tickAngle
        in
        case spec.label of
            Nothing ->
                [ Ui.line outer inner Color.white ]

            Just value ->
                [ Ui.line outer inner Color.white
                , textAt Color.white { x = outer.x - 9, y = outer.y - 12, w = 18, h = 12 } value
                ]


    drawOuterScale : Layout -> List Ui.RenderOp
    drawOuterScale layout =
        let
            oddTicks =
                List.map
                    (\\hour -> { minute = hour * 60, extra = 10, label = Nothing })
                    (List.range 1 5 |> List.filter (\\h -> modBy 2 h == 1))

            evenTicks =
                List.map
                    (\\hour -> { minute = hour * 120, extra = 6, label = Just (String.fromInt hour) })
                    (List.range 0 2)
        in
        List.concatMap (drawScaleTick layout) (oddTicks ++ evenTicks)


    defaultSun : { sunrise : Int, sunset : Int }
    defaultSun =
        { sunrise = 360, sunset = 1080 }


    centerBox : Layout -> Int -> { x : Int, y : Int, w : Int, h : Int }
    centerBox layout r =
        { x = layout.cx - r, y = layout.cy - r, w = r * 2, h = r * 2 }


    drawSunWindow : SunMode -> { x : Int, y : Int, w : Int, h : Int } -> Maybe { sunrise : Int, sunset : Int } -> List Ui.RenderOp
    drawSunWindow mode bounds sun =
        let
            window =
                Maybe.withDefault defaultSun sun
        in
        case mode of
            PolarNight ->
                []

            PolarDay ->
                [ Ui.fillCircle { x = bounds.x, y = bounds.y } 8 Color.white ]

            SunCycle ->
                coloredRadial bounds Color.white (window.sunrise * 10) (window.sunset * 10)


    drawDial : Layout -> Model -> List Ui.RenderOp
    drawDial layout model =
        let
            moonBounds =
                centerBox layout layout.outerRadius

            sunBounds =
                centerBox layout 8

            moonArc =
                case ( model.moonriseMin, model.moonsetMin ) of
                    ( Just rise, Just set ) ->
                        coloredRadial moonBounds Color.white (angleFromMinute rise) (angleFromMinute set)

                    _ ->
                        []
        in
        moonArc
            ++ drawSunWindow model.sunMode sunBounds model.sun
            ++ drawOuterScale layout
            ++ [ textAt Color.black layout.timeTextBand model.timeText ]


    view model =
        Ui.toUiNode
            ([ Ui.clear Color.black ]
                ++ drawDial model.layout model
                ++ (if model.showCorners then
                        [ textAt Color.white { x = 4, y = 4, w = 40, h = 14 } "YES" ]

                    else
                        []
                   )
            )
    """
  end

  defp context_group_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Layout =
        { cell : Int
        }


    type alias Model =
        { cells : List Int
        , layout : Layout
        }


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
        ( { cells = [ 0, 2, 4 ], layout = { cell = 16 } }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    drawCell : Layout -> Int -> Int -> Ui.RenderOp
    drawCell layout i n =
        let
            x =
                i * layout.cell

            label =
                String.fromInt n
        in
        Ui.context
            [ Ui.strokeColor Color.black
            , Ui.textColor Color.black
            ]
            [ Ui.rect { x = x, y = 0, w = layout.cell, h = layout.cell } Color.white
            , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = x, y = 0, w = layout.cell, h = 18 } label
            ]
            |> Ui.group


    view model =
        Ui.clear Color.white
            :: List.indexedMap (drawCell model.layout) model.cells
            |> Ui.toUiNode
    """
  end

  defp native_min_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { screenW : Int
        , screenH : Int
        }


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
        ( { screenW = 144, screenH = 168 }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        let
            minDim =
                Basics.min model.screenW model.screenH

            bounds =
                { x = 0, y = 0, w = minDim, h = 18 }
        in
        Ui.toUiNode
            [ Ui.text Resources.DefaultFont Ui.defaultTextOptions bounds "Hi"
            ]
    """
  end

  defp simple_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


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
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode
            [ Ui.clear Color.black
            , Ui.fillCircle { x = 20, y = 30 } 12 Color.white
            ]
    """
  end

  defp static_draw_table_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


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
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode
            [ Ui.fillRect { x = 0, y = 0, w = 20, h = 10 } Color.black
            , Ui.fillRect { x = 8, y = 4, w = 16, h = 8 } Color.white
            , Ui.fillRect { x = 24, y = 12, w = 6, h = 6 } Color.red
            ]
    """
  end

  defp affine_text_int_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Resources as Resources


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
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode (List.indexedMap row (List.range 0 3))


    row : Int -> Int -> Ui.RenderOp
    row i n =
        Ui.textInt Resources.DefaultFont { x = i * 10, y = n } n
    """
  end

  defp affine_text_label_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { slots : List Int }


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
        ( { slots = [ 0, 2, 4 ] }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        model.slots
            |> List.indexedMap paintMark
            |> Ui.toUiNode


    paintMark : Int -> Int -> Ui.RenderOp
    paintMark origin slot =
        let
            x =
                origin * 8

            caption =
                if slot == 0 then
                    "."
                else
                    String.fromInt slot
        in
        Ui.text Resources.DefaultFont
            Ui.defaultTextOptions
            { x = x, y = 0, w = 10, h = 10 }
            caption
    """
  end

  defp list_map_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


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
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    tick : Int -> List Ui.RenderOp
    tick n =
        [ Ui.rect { x = n, y = 0, w = 2, h = 2 } Color.black ]


    view _ =
        Ui.toUiNode
            (List.concat
                [ List.map (\\c -> Ui.rect { x = 0, y = 0, w = 4, h = 4 } c) [ Color.black, Color.white ]
                , List.concatMap tick (List.range 0 2)
                ]
            )
    """
  end

  defp lambda_map_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        { cells : List Int
        , size : Int
        }


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
        ( { cells = [ 0, 1, 2 ], size = 4 }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode
            (List.map
                (\\n -> Ui.rect { x = n, y = 0, w = model.size, h = model.size } Color.black)
                model.cells
            )
    """
  end

  defp filter_static_cmds_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        { showSecond : Bool }


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
        ( { showSecond = True }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode
            (List.filter
                (\\_ -> model.showSecond)
                [ Ui.rect { x = 0, y = 0, w = 4, h = 4 } Color.black
                , Ui.fillRect { x = 8, y = 0, w = 4, h = 4 } Color.white
                ]
            )
    """
  end

  defp filter_model_cmds_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        { ops : List Ui.RenderOp
        , showSecond : Bool
        }


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
        ( { ops =
                [ Ui.rect { x = 0, y = 0, w = 4, h = 4 } Color.black
                , Ui.fillRect { x = 8, y = 0, w = 4, h = 4 } Color.white
                ]
          , showSecond = True
          }
        , Cmd.none
        )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode (List.filter (\\_ -> model.showSecond) model.ops)
    """
  end

  defp filter_map_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        { cells : List Int
        , size : Int
        }


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
        ( { cells = [ 0, 1, 2 ], size = 4 }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode
            (List.map
                (\\n -> Ui.rect { x = n, y = 0, w = model.size, h = model.size } Color.black)
                (List.filter (\\n -> n > 0) model.cells)
            )
    """
  end

  defp filter_map_static_maybe_cmds_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        { showSecond : Bool }


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
        ( { showSecond = True }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode
            (List.filterMap identity
                [ Just (Ui.rect { x = 0, y = 0, w = 4, h = 4 } Color.black)
                , if model.showSecond then
                    Just (Ui.fillRect { x = 8, y = 0, w = 4, h = 4 } Color.white)

                  else
                    Nothing
                ]
            )
    """
  end

  defp filter_map_draw_cells_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        { cells : List Int
        , size : Int
        }


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
        ( { cells = [ 0, 1, 2 ], size = 4 }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode
            (List.filterMap
                (\\n ->
                    if n > 0 then
                        Just (Ui.rect { x = n, y = 0, w = model.size, h = model.size } Color.black)

                    else
                        Nothing
                )
                model.cells
            )
    """
  end

  defp lambda_draw_at_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Layout =
        { cell : Int
        , gap : Int
        }


    type alias Model =
        { slots : List Int
        , layout : Layout
        }


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
        ( { slots = [ 0, 1, 2 ], layout = { cell = 8, gap = 1 } }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    drawAt : Layout -> Int -> Ui.RenderOp
    drawAt layout n =
        Ui.fillRect { x = n, y = 0, w = layout.cell, h = layout.cell } Color.black


    view model =
        Ui.toUiNode
            (List.map
                (\\slot -> drawAt model.layout slot)
                model.slots
            )
    """
  end

  defp cons_indexed_map_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        { cells : List Int }


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
        ( { cells = [ 0, 1, 2 ] }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    cellOp : Int -> Int -> Ui.RenderOp
    cellOp i _n =
        Ui.rect { x = i * 4, y = 0, w = 2, h = 2 } Color.black


    view model =
        Ui.clear Color.white
            :: List.indexedMap cellOp model.cells
            |> Ui.toUiNode
    """
  end

  defp indexed_map_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        { cells : List Int }


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
        ( { cells = [ 0, 1, 2 ] }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    cellOp : Int -> Int -> Ui.RenderOp
    cellOp i _n =
        Ui.rect { x = i * 4, y = 0, w = 2, h = 2 } Color.black


    view model =
        Ui.toUiNode (List.indexedMap cellOp model.cells)
    """
  end

  defp maybe_case_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Point =
        { x : Int
        , y : Int
        }


    type alias Pts =
        { tip : Point
        , tail : Point
        }


    type alias Model =
        { center : Point
        , maybePts : Maybe Pts
        }


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
        ( { center = { x = 72, y = 84 }, maybePts = Just { tip = { x = 1, y = 2 }, tail = { x = 3, y = 4 } } }
        , Cmd.none
        )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode (drawOps model.center model.maybePts)


    drawOps : Point -> Maybe Pts -> List Ui.RenderOp
    drawOps center maybePts =
        case maybePts of
            Nothing ->
                []

            Just payload ->
                [ Ui.line center payload.tip Color.black ]
    """
  end

  defp refute_list_loop_cursor(body) when is_binary(body) do
    refute body =~ "ElmcValue *direct_cursor_"
  end

  defp refute_plan_stream_fallback(result) do
    diags =
      Enum.concat([
        Map.get(result, :layout_coercion_diagnostics, []),
        Map.get(result, :informational_diagnostics, []),
        Map.get(result, :blocking_diagnostics, [])
      ])

    refute Enum.any?(diags, fn
             %{"code" => "plan_stream_fallback"} -> true
             %{code: "plan_stream_fallback"} -> true
             _ -> false
           end)
  end
end
