defmodule Elmc.ConditionalSubscriptionsCodegenTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.CCodegenExtract

  @drawing_template Path.expand(
                      "../../ide/priv/project_templates/watch_demo_drawing_showcase",
                      __DIR__
                    )

  setup do
    project_dir = Path.expand("tmp/conditional_subscriptions_project", __DIR__)
    out_dir = Path.expand("tmp/conditional_subscriptions_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(@drawing_template, project_dir)

    File.write!(
      Path.join(project_dir, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => [
          "src",
          "../../../../packages/elm-pebble/elm-watch/src"
        ],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    %{project_dir: project_dir, out_dir: out_dir}
  end

  test "conditional frame subscription in let still emits batch subscriptions", %{
    project_dir: project_dir,
    out_dir: out_dir
  } do
    assert {:ok, %{ir: ir}} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    layout = Elmc.Backend.Worker.subscription_analysis(ir, "Main")

    assert layout.model_dependent?
    assert layout.dynamic?
    refute layout.compact

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    subs_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_subscriptions")

    refute subs_body =~ "elmc_fn_Pebble_Events_batch"
    assert subs_body =~ "ELMC_SUBSCRIPTION_BUTTON_RAW"
    assert subs_body =~ "ELMC_PEBBLE_MSG_UPPRESSED"
    assert subs_body =~ "ELMC_PEBBLE_MSG_DOWNPRESSED"
    assert subs_body =~ "ELMC_SUBSCRIPTION_FRAME_BASE"
    assert subs_body =~ "ELMC_PEBBLE_MSG_FRAMETICK"
    assert subs_body =~ "elmc_list_from_values_take"
    assert subs_body =~ "elmc_fn_Main_currentPage("
    assert subs_body =~ "ELMC_FIELD_MAIN_MODEL_PAGEINDEX"

    current_page_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_currentPage")

    assert current_page_body =~ "plan block"
    assert current_page_body =~ "elmc_fn_Main_pages("
    assert current_page_body =~ "*out = elmc_maybe_with_default"

    pages_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_pages")

    assert pages_body =~ "plan_list_int_values_"
    assert pages_body =~ "elmc_list_from_int_array"
  end
end
