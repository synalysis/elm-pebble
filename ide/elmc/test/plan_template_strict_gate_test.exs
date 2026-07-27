defmodule Elmc.PlanTemplateStrictGateTest do
  @moduledoc """
  Smoke gate: selected watch templates must compile with `plan_ir_strict: true`.

  Templates are fixtures only. Failures indicate missing **generic** plan lowering,
  not app bugs. See `docs/PLAN_IR_COVERAGE.md` for the coverage matrix and how to
  extend it.
  """

  use ExUnit.Case, async: false

  alias Elmc.TestSupport.{PlanStrictTemplates, TemplateCompile}

  @moduletag :slow

  # Templates verified to pass strict plan-primary (zero plan_primary_fallback).
  # Add a name here only after `plan_ir_strict: true` compiles cleanly.
  @strict_pass PlanStrictTemplates.names()

  for template <- @strict_pass do
    @tag template: template

    test "strict plan-primary compiles #{template}", %{template: template} do
      out_dir = Path.expand("tmp/plan_strict_gate/#{template}", __DIR__)

      assert {:ok, result} =
               TemplateCompile.compile_watch_template(template,
                 plan_ir_mode: :primary,
                 plan_ir_strict: true,
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
      end
    end
  end
end
