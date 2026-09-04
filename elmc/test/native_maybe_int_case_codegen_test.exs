defmodule Elmc.NativeMaybeIntCaseCodegenTest do
  use ExUnit.Case

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Test.CCodegenExtract

  @moduletag timeout: 180_000

  test "Maybe record case on field access emits native Int function body" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/maybe_record_int_case_project", __DIR__)
    out_dir = Path.expand("tmp/maybe_record_int_case_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> maybe_record_int_case_source())

    assert {:ok, _result} =
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               plan_ir_mode: :primary,
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "static RC elmc_fn_Main_currentHour("

    body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_currentHour")
    assert body =~ "elmc_maybe_is_nothing"
    assert body =~ "ELMC_RECORD_GET_INDEX_INT"
    refute body =~ "switch ("

    caller_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_hourHandOffset")
    assert caller_body =~ "elmc_fn_Main_currentHour"
    refute caller_body =~ "elmc_new_int("
  end

  test "Maybe Int case emits native Int function body" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/maybe_int_case_project", __DIR__)
    out_dir = Path.expand("tmp/maybe_int_case_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> maybe_int_case_source())

    assert {:ok, _result} =
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               plan_ir_mode: :primary,
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    native_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_maybeIntBump")

    assert generated_c =~ "static RC elmc_fn_Main_maybeIntBump(elmc_int_t *out"
    assert native_body =~ "elmc_maybe_is_nothing"
    refute native_body =~ "elmc_new_int("
  end

  defp maybe_record_int_case_source do
    """


    type alias Clock =
        { hour : Int
        , minute : Int
        }


    type alias ClockModel =
        { now : Maybe Clock
        }


    currentHour : ClockModel -> Int
    currentHour model =
        case model.now of
            Just value ->
                modBy 12 value.hour

            Nothing ->
                0


    hourHandOffset : ClockModel -> Int
    hourHandOffset model =
        currentHour model * 30
    """
  end

  defp maybe_int_case_source do
    """


    maybeIntBump : Maybe Int -> Int
    maybeIntBump maybeValue =
        case maybeValue of
            Just n ->
                n + 1

            Nothing ->
                0
    """
  end
end
