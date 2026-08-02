defmodule Ide.Test.TeaPlaybook do
  @moduledoc """
  IDE bridge for shared `Elmx.TeaPlaybook` scenarios.

  Converts playbook steps into the shape used by `TemplateElmxElmcParity.ElmxRunner`
  / debugger Executor so curated TEA scripts stay one source for elmc host and elmx.
  """

  alias Elmx.TeaPlaybook
  alias Ide.Test.TemplateElmxElmcParity.ExecutionPlan

  @spec for_template(String.t()) :: TeaPlaybook.t()
  defdelegate for_template(template), to: TeaPlaybook

  @spec to_json_map(TeaPlaybook.t()) :: map()
  defdelegate to_json_map(playbook), to: TeaPlaybook

  @doc """
  Build a minimal ExecutionPlan-compatible map from a TeaPlaybook.

  Does not walk the full update-branch catalog — only the curated playbook steps.
  """
  @spec to_execution_plan(TeaPlaybook.t(), keyword()) :: map()
  def to_execution_plan(playbook, opts \\ []) do
    contract = Keyword.get(opts, :contract, %{})

    steps =
      playbook
      |> TeaPlaybook.to_elmx_steps()
      |> Enum.flat_map(&execution_steps/1)

    %{
      template_key: playbook.template,
      watch_profile_id: Map.get(playbook, :watch_profile_id, "gabbro"),
      contract: contract,
      steps: steps,
      expects: playbook.expects || %{},
      source: :tea_playbook
    }
  end

  defp execution_steps(%{op: :drain_cmds} = step) do
    # ElmxRunner does not drain; keep as update-less marker so callers can apply
    # followups, matching TeaPlaybookRunner.
    [
      %{
        id: step.id,
        op: :update,
        message: "__drain_cmds__",
        message_value: %{"kinds" => Enum.map(Map.get(step, :kinds, []), &to_string/1)},
        source: "tea_playbook_drain"
      }
    ]
  end

  defp execution_steps(%{op: :update, action: :direction_cycle} = step) do
    count = Map.get(step, :count, 4)
    dirs = ["LeftPressed", "RightPressed", "UpPressed", "DownPressed"]

    for i <- 0..(count - 1) do
      %{
        id: "#{step.id}:#{i}",
        op: :update,
        message: Enum.at(dirs, rem(i, 4)),
        message_value: nil,
        source: "tea_playbook"
      }
    end
  end

  defp execution_steps(%{op: :update, action: :frame} = step) do
    count = Map.get(step, :count, 1)
    dt = Map.get(step, :dt_ms, 33)

    for frame <- 1..count do
      %{
        id: "#{step.id}:#{frame}",
        op: :update,
        message: "FrameTick",
        message_value: Elmx.TeaPlaybook.Samples.frame(frame, dt),
        source: "tea_playbook"
      }
    end
  end

  defp execution_steps(%{op: op} = step)
       when op in [:init, :view, :subscriptions, :update] do
    [
      %{
        id: step.id,
        op: op,
        message: Map.get(step, :message),
        message_value: Map.get(step, :message_value),
        source: "tea_playbook"
      }
    ]
  end

  defp execution_steps(_), do: []

  @doc """
  Prefer a TeaPlaybook when one exists; otherwise fall back to full ExecutionPlan.build!.
  """
  @spec plan_for_project!(String.t(), String.t(), keyword()) :: map()
  def plan_for_project!(project_dir, template_key, opts \\ []) do
    underscore = String.replace(template_key, "-", "_")

    if underscore in TeaPlaybook.enabled_names() do
      playbook = TeaPlaybook.for_template(underscore)
      to_execution_plan(playbook, opts)
    else
      ExecutionPlan.build!(project_dir, template_key, opts)
    end
  end
end
