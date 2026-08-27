defmodule Elmc.PlanTemplateStrictGateTest do
  @moduledoc """
  Smoke gate: selected watch templates must compile with `plan_ir_strict: true`
  and the generated C must typecheck under host `cc`.

  Shares `tmp/plan_gate_artifacts/<template>` with reachable/opcode gates.
  """

  use ExUnit.Case, async: false

  alias Elmc.TestSupport.{HostSmoke, PlanStrictTemplates, StrictCompileAssertions}

  @moduletag :slow

  @strict_pass HostSmoke.templates(PlanStrictTemplates.names())

  for template <- @strict_pass do
    @tag template: template

    test "strict plan-primary compiles #{template}", %{template: template} do
      result = StrictCompileAssertions.compile_template!(template)

      StrictCompileAssertions.assert_strict_compile!(
        result,
        StrictCompileAssertions.artifact_dir(template),
        typecheck: true,
        rc_shape: true
      )
    end
  end
end
