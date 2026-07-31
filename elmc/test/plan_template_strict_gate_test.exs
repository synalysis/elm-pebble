defmodule Elmc.PlanTemplateStrictGateTest do
  @moduledoc """
  Smoke gate: selected watch templates must compile with `plan_ir_strict: true`
  and the generated C must typecheck under host `cc` (`-Werror=int-conversion`).

  Templates are fixtures only. Failures indicate missing **generic** plan lowering
  or unsafe C emit, not app bugs. See `docs/PLAN_IR_COVERAGE.md`.
  """

  use ExUnit.Case, async: false

  alias Elmc.TestSupport.{GeneratedCTypecheck, HostSmoke, PlanStrictTemplates, TemplateCompile}

  @moduletag :slow

  # Templates verified to pass strict plan-primary (zero plan_primary_fallback).
  # Add a name here only after `plan_ir_strict: true` compiles cleanly.
  # Filtered by `ELMC_HOST_SMOKE_TEMPLATE` so `mix-test-per-template.sh` can
  # batch a few templates per BEAM (default 4) without compiling the full list.
  @strict_pass HostSmoke.templates(PlanStrictTemplates.names())

  for template <- @strict_pass do
    @tag template: template

    test "strict plan-primary compiles #{template}", %{template: template} do
      out_dir = Path.expand("tmp/plan_strict_gate/#{template}", __DIR__)

      assert {:ok, result} =
               TemplateCompile.compile_watch_template(template,
                 plan_ir_mode: :primary,
                 plan_ir_strict: true,
                 pebble_int32: true,
                 out_dir: out_dir
               )

      fallbacks =
        (result.layout_coercion_diagnostics || [])
        |> Enum.filter(&(&1["code"] == "plan_primary_fallback"))

      assert fallbacks == [],
             "expected zero plan_primary_fallback, got:\n#{inspect(fallbacks, pretty: true)}"

      c_path = Path.join(out_dir, "c/elmc_generated.c")

      if File.regular?(c_path) do
        unknown_count =
          c_path
          |> File.read!()
          |> then(&Regex.scan(~r/elmc_unknown\b/, &1))
          |> length()

        assert unknown_count == 0,
               "expected zero elmc_unknown in #{template}, got #{unknown_count}"

        GeneratedCTypecheck.assert_typechecks!(out_dir)
      end
    end
  end
end
