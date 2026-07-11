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
    assert layout.compact
    refute layout.dynamic?
    assert layout.has_frame
    assert layout.button_raw_count == 2

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    subs_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_subscriptions")

    refute subs_body =~ "elmc_fn_Pebble_Events_batch"
    assert subs_body =~ "ELMC_SUBSCRIPTION_BUTTON_RAW"
    assert subs_body =~ "ELMC_PEBBLE_MSG_UPPRESSED"
    assert subs_body =~ "ELMC_PEBBLE_MSG_DOWNPRESSED"
    assert subs_body =~ "ELMC_SUBSCRIPTION_FRAME_BASE"
    assert subs_body =~ "ELMC_PEBBLE_MSG_FRAMETICK"
    assert subs_body =~ "elmc_list_from_values_take"

    current_page_native =
      CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_currentPage_native")

    refute current_page_native =~ "elmc_fn_Main_pages"
    refute current_page_native =~ "list_length_cursor"
    assert current_page_native =~ "index & 7"
    assert current_page_native =~ "Main.pages[n] static table"
    assert current_page_native =~ "elmc_immortal_list_Main_pages_values"
    refute current_page_native =~ "elmc_new_int(native_mod_"
    refute current_page_native =~ "elmc_as_int(tmp_"
    refute current_page_native =~ "ElmcValue *tmp_"
    assert current_page_native =~ "elmc_immortal_list_Main_pages_values[native_mod_1]"
    assert current_page_native =~ "*out ="

    assert generated_c =~ "elmc_immortal_list_Main_pages_values"
    assert generated_c =~ "ELMC_RC_IMMORTAL"

    pages_fn =
      generated_c
      |> String.split("static ElmcValue *elmc_immortal_list_Main_pages_get(void) {", parts: 2)
      |> Enum.at(1)
      |> case do
        nil -> flunk("expected immortal static list prelude for Main.pages")
        rest -> String.split(rest, "static RC elmc_fn_Main_pages(", parts: 2) |> hd()
      end

    refute pages_fn =~ "elmc_list_from_int_array"

    pages_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_pages")

    assert pages_body =~ "elmc_immortal_list_Main_pages_get()"
    refute pages_body =~ "elmc_list_from_int_array"

    prev_index_native =
      generated_c
      |> String.split("static elmc_int_t elmc_fn_Main_prevIndex_native(const elmc_int_t index) {",
        parts: 2
      )
      |> Enum.at(1)
      |> String.split("static ElmcValue *elmc_fn_Main_nextIndex(", parts: 2)
      |> hd()

    refute prev_index_native =~ "elmc_fn_Main_pages"
    refute prev_index_native =~ "list_length_cursor"
    assert prev_index_native =~ "native_let_count_1 = 8 /* List.length Main.pages */"

    next_index_native =
      generated_c
      |> String.split("static elmc_int_t elmc_fn_Main_nextIndex_native(const elmc_int_t index) {",
        parts: 2
      )
      |> Enum.at(1)
      |> String.split("static ElmcValue *elmc_fn_Main_currentPage(", parts: 2)
      |> hd()

    refute next_index_native =~ "elmc_fn_Main_pages"
    refute next_index_native =~ "list_length_cursor"
    assert next_index_native =~ "index & 7"

    refute subs_body =~ "elmc_fn_Main_pages"
    assert subs_body =~ "elmc_fn_Main_currentPage_native"
    assert subs_body =~ "ELMC_FIELD_MAIN_MODEL_PAGEINDEX"
  end
end
