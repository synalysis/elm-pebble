defmodule Ide.Test.TemplateElmxElmcParity.ElmxRunner do
  @moduledoc """
  Runs elmx parity steps via `Elmx.Runtime.Executor` directly (init/update/view/subs).

  Avoids the IDE debugger `RuntimeExecutor` stack (manifest checks, adapters, normalizers).
  """

  alias Elmx.Runtime.Executor
  alias Elmx.Runtime.Executor.Run
  alias Elmx.Runtime.Followups
  alias Elmx.Runtime.LaunchContext
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Test.TemplateElmxElmcParity.ExecutionPlan
  alias Ide.Test.TemplateElmxElmcParity.Types, as: ParityTypes

  @spec run!(ExecutionPlan.t(), keyword()) ::
          {:ok, [ParityTypes.parity_step()]} | {:error, ParityTypes.elmx_runner_error()}
  def run!(plan, opts \\ []) do
    with {:ok, module} <- resolve_module(opts, plan.template_key),
         {:ok, steps} <- run_plan(module, plan) do
      {:ok, steps}
    end
  end

  defp resolve_module(opts, template_key) do
    case Keyword.get(opts, :prepared) do
      %{elmx: %{module: module}} when is_atom(module) ->
        {:ok, module}

      _ ->
        project_dir = Keyword.fetch!(opts, :project_dir)
        revision = Keyword.get(opts, :revision, unique_revision(template_key))

        with {:ok, %Elmx.CompileResult{entry_module: module}} <-
               Elmx.compile_in_memory(project_dir, %{
                 entry_module: "Main",
                 revision: revision,
                 mode: :ide_runtime,
                 strip_dead_code: Keyword.get(opts, :strip_dead_code, true)
               }) do
          {:ok, module}
        end
    end
  end

  defp run_plan(module, plan) do
    launch_context =
      plan.watch_profile_id
      |> RuntimeSurfaces.launch_context_for("LaunchUser")
      |> LaunchContext.normalize()

    state = %{
      launch_context: launch_context,
      runtime_model: %{}
    }

    {steps, _state} =
      Enum.map_reduce(plan.steps, state, fn step, acc ->
        {result, next_acc} = run_step(module, step, acc)

        step_snapshot =
          result
          |> Map.put("step_id", step.id)
          |> Map.put("op", Atom.to_string(step.op))
          |> Map.put("message", Map.get(step, :message))
          |> Map.put("backend", "elmx")

        {step_snapshot, next_acc}
      end)

    {:ok, steps}
  end

  defp run_step(module, %{op: :init}, acc) do
    run_model_step(module, acc, fn ->
      Run.init_execution(module, acc.launch_context, acc.runtime_model)
    end)
  end

  defp run_step(module, %{op: :update} = step, acc) do
    run_model_step(module, acc, fn ->
      Run.step_execution(module, step.message, Map.get(step, :message_value), acc.runtime_model)
    end)
  end

  defp run_model_step(module, acc, run) do
    try do
      {runtime_model, _source, cmd} = run.()
      next_acc = %{acc | runtime_model: runtime_model}

      with {:ok, view_payload} <- Executor.view_generated(module, view_request(next_acc)) do
        subs = Executor.Subscriptions.evaluate(module, runtime_model)

        {init_update_result(runtime_model, cmd, view_payload, subs), next_acc}
      else
        {:error, reason} -> {error_step(reason), acc}
      end
    rescue
      e -> {error_step(Exception.message(e)), acc}
    end
  end

  defp run_step(module, %{op: :subscriptions}, acc) do
    subs =
      try do
        Executor.Subscriptions.evaluate(module, acc.runtime_model)
      rescue
        e -> {:error, Exception.message(e)}
      end

    case subs do
      {:error, reason} ->
        {error_step(reason), acc}

      list when is_list(list) ->
        view_payload =
          case Executor.view_generated(module, view_request(acc)) do
            {:ok, payload} -> payload
            _ -> %{}
          end

        {%{
           "active_subscriptions" => list,
           "model" => acc.runtime_model,
           "view_output" => list_field(view_payload, :view_output),
           "render_tree" =>
             render_tree_summary(Map.get(view_payload, :view_tree) || Map.get(view_payload, "view_tree")),
           "commands" => []
         }, acc}
    end
  end

  defp run_step(module, %{op: :view}, acc) do
    case Executor.view_generated(module, view_request(acc)) do
      {:ok, payload} ->
        {view_step(payload), acc}

      {:error, reason} ->
        {error_step(reason), acc}
    end
  end

  defp view_request(acc) do
    %{
      "current_model" => %{
        "launch_context" => acc.launch_context,
        "runtime_model" => acc.runtime_model
      },
      "source_root" => "watch"
    }
  end

  defp init_update_result(runtime_model, cmd, view_payload, subs) do
    %{
      "model" => runtime_model,
      "view_output" => list_field(view_payload, :view_output),
      "render_tree" =>
        render_tree_summary(Map.get(view_payload, :view_tree) || Map.get(view_payload, "view_tree")),
      "active_subscriptions" => subs,
      "commands" => commands_from_cmd(cmd),
      "error" => nil
    }
  end

  defp commands_from_cmd(cmd) do
    Followups.from_commands(cmd, source_root: "watch") ++ Followups.protocol_events(cmd)
  end

  defp view_step(payload) do
    %{
      "model" => nil,
      "view_output" => list_field(payload, :view_output),
      "render_tree" => render_tree_summary(Map.get(payload, :view_tree) || Map.get(payload, "view_tree")),
      "active_subscriptions" => [],
      "commands" => [],
      "error" => nil
    }
  end

  defp error_step(reason) do
    %{
      "model" => nil,
      "view_output" => [],
      "render_tree" => %{},
      "active_subscriptions" => [],
      "commands" => [],
      "error" => inspect(reason)
    }
  end

  defp render_tree_summary(nil), do: %{}

  defp render_tree_summary(tree) when is_map(tree) do
    node_types =
      tree
      |> collect_node_types([])
      |> Enum.sort()
      |> Enum.uniq()

    %{
      "root_type" => Map.get(tree, "type") || Map.get(tree, :type),
      "node_count" => length(node_types),
      "node_types" => node_types
    }
  end

  defp collect_node_types(%{"type" => type} = node, acc) when is_binary(type) do
    children = Map.get(node, "children") || Map.get(node, :children) || []

    Enum.reduce(List.wrap(children), [type | acc], &collect_node_types/2)
  end

  defp collect_node_types(%{type: type} = node, acc) when is_atom(type) do
    collect_node_types(Map.new(node, fn {k, v} -> {to_string(k), v} end), acc)
  end

  defp collect_node_types(_, acc), do: acc

  defp list_field(map, key) do
    map
    |> Map.get(key, Map.get(map, Atom.to_string(key), []))
    |> List.wrap()
  end

  defp unique_revision(template_key) do
    "parity-elmx-#{template_key}-" <> Integer.to_string(:erlang.unique_integer([:positive]))
  end
end
