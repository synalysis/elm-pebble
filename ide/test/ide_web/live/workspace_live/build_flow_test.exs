defmodule IdeWeb.WorkspaceLive.BuildFlowTest do
  use ExUnit.Case, async: true

  alias IdeWeb.WorkspaceLive.BuildFlow

  test "package failure explains Aplite memory overflow" do
    reason =
      {:pebble_build_failed,
       %{
         cwd: "/tmp/app",
         command: "pebble build",
         exit_code: 1,
         output: "region `APP' overflowed by 1234 bytes"
       }}

    output = BuildFlow.render_package_failure(reason, ["aplite", "basalt"])

    assert output =~ "PBW packaging failed"
    assert output =~ "memory-region overflow"
    assert output =~ "Aplite is enabled"
    assert output =~ "region `APP' overflowed"
  end

  test "package output issues promote linker overflow details" do
    output = """
    [135/136] Linking aplite | cprogram: build/src/c/elmc/c/elmc_generated.c.57.o -> build/aplite/pebble-app.elf
    ld: build/aplite/pebble-app.elf section `.text' will not fit in region `APP'
    ld: region `APP' overflowed by 12076 bytes
    collect2: error: ld returned 1 exit status
    """

    assert [
             %{
               title: "PBW too large for Aplite",
               message: message,
               detail: "target=aplite overflow=12076 bytes"
             }
           ] = BuildFlow.package_output_issues(output)

    assert message =~ "Aplite is enabled"
  end

  test "package output issues use overflowing target, not earlier link target" do
    output = """
    [133/136] Linking gabbro | cprogram: build/src/c/elmc/c/elmc_generated.c.57.o -> build/gabbro/pebble-app.elf
    [135/136] Linking aplite | cprogram: build/src/c/elmc/c/elmc_generated.c.57.o -> build/aplite/pebble-app.elf
    ld: build/aplite/pebble-app.elf section `.text' will not fit in region `APP'
    ld: region `APP' overflowed by 12076 bytes
    collect2: error: ld returned 1 exit status
    """

    assert [
             %{
               title: "PBW too large for Aplite",
               detail: "target=aplite overflow=12076 bytes"
             }
           ] = BuildFlow.package_output_issues(output)
  end
end
