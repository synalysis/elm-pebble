defmodule Elmc.DataLogTagCodegenTest do
  use ExUnit.Case, async: true

  @source_fixture Path.expand("fixtures/simple_project", __DIR__)

  test "captured DataLog tag parameter is not constant-folded to module tag decl" do
    project_dir = Path.expand("tmp/datalog_tag_lambda_project", __DIR__)
    out_dir = Path.expand("tmp/datalog_tag_lambda_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(@source_fixture, project_dir)

    File.write!(
      Path.join(project_dir, "src/Main.elm"),
      File.read!(Path.join(project_dir, "src/Main.elm")) <> datalog_tag_lambda_source()
    )

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    cmd_lambda =
      generated_c
      |> String.split("static ElmcValue *elmc_lambda_")
      |> Enum.find(fn chunk -> chunk =~ "ELMC_PEBBLE_CMD_DATA_LOG_INT32" end)

    assert is_binary(cmd_lambda),
           "expected a lambda body that emits ELMC_PEBBLE_CMD_DATA_LOG_INT32"

    assert cmd_lambda =~ "const elmc_int_t tag ="
    assert cmd_lambda =~ "elmc_cmd2(ELMC_PEBBLE_CMD_DATA_LOG_INT32, tag, value)"
    refute cmd_lambda =~ "1 /* tag */"
  end

  defp datalog_tag_lambda_source do
    """


    import Pebble.DataLog as DataLog

    logTag : DataLog.Tag
    logTag =
        DataLog.tag 9001

    logOne : Int -> Cmd msg
    logOne value =
        DataLog.logInt32 logTag value

    mapLogs : List Int -> List (Cmd msg)
    mapLogs =
        List.map logOne
    """
  end
end
