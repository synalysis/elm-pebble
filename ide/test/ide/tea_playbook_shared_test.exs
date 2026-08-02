defmodule Ide.TeaPlaybookSharedTest do
  use ExUnit.Case, async: false

  alias Elmx.TeaPlaybook
  alias Ide.Test.TeaPlaybook, as: IdePlaybook

  test "TeaPlaybook JSON round-trip stays elmx/elmc compatible" do
    playbook = TeaPlaybook.for_template("watchface_yes")
    json = IdePlaybook.to_json_map(playbook)
    restored = TeaPlaybook.from_json_map(json)

    assert restored.template == "watchface_yes"
    assert restored.mode == :watchface
    assert Enum.any?(restored.steps, &(&1.op == :update and &1.action == :from_phone))
    assert restored.expects[:min_scene_radial] == 2
  end

  test "TeaPlaybook projects to ExecutionPlan-compatible steps" do
    playbook = TeaPlaybook.for_template("game_2048")
    plan = IdePlaybook.to_execution_plan(playbook)

    assert plan.template_key == "game_2048"
    assert Enum.any?(plan.steps, &(&1.op == :init))
    assert Enum.any?(plan.steps, &(&1.message == "LeftPressed"))
    assert Enum.any?(plan.steps, &(&1.op == :view))
  end

  test "elmc and elmx step projections cover the same playbook actions" do
    playbook = TeaPlaybook.for_template("watchface_yes")
    elmx_steps = TeaPlaybook.to_elmx_steps(playbook)
    elmc_steps = TeaPlaybook.to_elmc_steps(playbook)

    assert Enum.any?(elmx_steps, &(Map.get(&1, :action) == :from_phone and Map.get(&1, :ctor) == "ProvideWeather"))
    assert {:from_phone, :provide_weather} in elmc_steps
    assert :view in elmc_steps
    assert Enum.any?(elmx_steps, &(&1.op == :view))
  end
end
