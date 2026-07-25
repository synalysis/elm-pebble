defmodule Elmc.PlanLambdaInferredRecordFieldsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Lambda

  setup do
    # Anonymous scene-shaped literal: alphabetical runtime order.
    Process.put(:elmc_inline_record_literal_shapes, %{
      {"Scene3d", "scene"} => [
        "entities",
        "exposure",
        "lights",
        "toneMapping",
        "whiteBalance"
      ]
    })

    on_exit(fn -> Process.delete(:elmc_inline_record_literal_shapes) end)
    :ok
  end

  test "lambda field_access on anonymous scene param uses alphabetical indices" do
    # Mimics Scene3d.composite: List.concatMap (\scene -> … scene.lights / scene.entities)
    body = %{
      op: :record_literal,
      fields: [
        %{name: "lights", expr: %{op: :field_access, arg: %{op: :var, name: "scene"}, field: "lights"}},
        %{
          name: "entities",
          expr: %{op: :field_access, arg: %{op: :var, name: "scene"}, field: "entities"}
        }
      ]
    }

    ctx =
      Context.new(
        module: "Scene3d",
        function_name: "composite",
        params: ["arguments", "scenes"],
        rc_required: false
      )

    b = Builder.new("Scene3d", "composite", args: ["arguments", "scenes"], rc_required: false)

    assert {:ok, _reg, b1} = Lambda.compile_lambda(["scene"], body, [], ctx, b)
    [lam] = b1.lambdas

    gets =
      lam.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :record_get))
      |> Map.new(fn instr -> {instr.args[:field], instr.args[:field_index]} end)

    assert gets["entities"] =~ ~r/^0\b/
    assert gets["lights"] =~ ~r/^2\b/
    refute gets["lights"] =~ ~r/^0\b/
  end
end
