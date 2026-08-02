defmodule Elmx.TestSupport.TeaPlaybookRunner do
  @moduledoc """
  Runs an `Elmx.TeaPlaybook` through `Elmx.Runtime.Executor` (debugger TEA path).

  `:drain_cmds` applies followups from pending commands — same callback tags the
  host C harness drains via `cmd.p0`, with no Msg-name guessing.
  """

  alias Elmx.Runtime.Executor
  alias Elmx.Runtime.Executor.Run
  alias Elmx.Runtime.Followups
  alias Elmx.Runtime.LaunchContext
  alias Elmx.TeaPlaybook

  @type result :: %{
          required(:playbook) => TeaPlaybook.t(),
          required(:steps) => [map()],
          required(:runtime_model) => map(),
          required(:view_output) => list(),
          required(:commands) => list()
        }

  @spec run!(TeaPlaybook.t(), module(), keyword()) :: result()
  def run!(playbook, module, opts \\ []) when is_atom(module) do
    watch_profile_id = Map.get(playbook, :watch_profile_id, "gabbro")

    launch_context =
      opts
      |> Keyword.get_lazy(:launch_context, fn -> default_launch_context(watch_profile_id) end)
      |> LaunchContext.normalize()

    state = %{
      launch_context: launch_context,
      runtime_model: %{},
      pending_commands: [],
      view_output: [],
      last_commands: []
    }

    elmx_steps = TeaPlaybook.to_elmx_steps(playbook)

    {step_results, final} =
      Enum.map_reduce(elmx_steps, state, fn step, acc ->
        {snapshot, next} = run_step(module, step, acc)
        {snapshot, next}
      end)

    %{
      playbook: playbook,
      steps: step_results,
      runtime_model: final.runtime_model,
      view_output: final.view_output,
      commands: final.last_commands
    }
  end

  @spec assert_expects!(result()) :: :ok
  def assert_expects!(%{playbook: playbook, view_output: view_output, steps: steps}) do
    expects = playbook.expects || %{}

    if Map.get(expects, :min_view_rows, 0) > 0 do
      min = expects[:min_view_rows]
      count = length(List.wrap(view_output))

      if count < min do
        raise "TeaPlaybook expect min_view_rows=#{min} got=#{count}"
      end
    end

    Enum.each(steps, fn step ->
      texts = Map.get(step, "expect_texts") || []

      Enum.each(List.wrap(texts), fn text ->
        unless view_contains_text?(Map.get(step, "view_output", []), text) do
          raise "TeaPlaybook step #{inspect(step["step_id"])} missing view text #{inspect(text)}"
        end
      end)
    end)

    case expects[:require_spy_texts] do
      texts when is_list(texts) ->
        Enum.each(texts, fn text ->
          unless view_contains_text?(view_output, text) do
            raise "TeaPlaybook expect require_spy_texts missing #{inspect(text)} in final view"
          end
        end)

      _ ->
        :ok
    end

    if Enum.any?(steps, & &1["error"]) do
      errors =
        steps
        |> Enum.filter(& &1["error"])
        |> Enum.map(& &1["error"])
        |> Enum.join("; ")

      raise "TeaPlaybook step errors: #{errors}"
    end

    :ok
  end

  defp view_contains_text?(rows, needle) when is_binary(needle) do
    rows
    |> List.wrap()
    |> Enum.any?(fn row ->
      text =
        cond do
          is_map(row) ->
            Map.get(row, "text") || Map.get(row, :text) || Map.get(row, "label") ||
              Map.get(row, :label) || ""

          is_binary(row) ->
            row

          true ->
            ""
        end

      is_binary(text) and String.contains?(text, needle)
    end)
  end

  defp run_step(module, %{op: :init} = step, acc) do
    {runtime_model, _source, cmd} =
      Run.init_execution(module, acc.launch_context, acc.runtime_model)

    commands = commands_from_cmd(cmd)
    next = %{acc | runtime_model: runtime_model, pending_commands: commands, last_commands: commands}
    {ok_snapshot(step, next), next}
  end

  defp run_step(module, %{op: :drain_cmds} = step, acc) do
    kinds = Map.get(step, :kinds, [])
    {next, applied} = drain_followups(module, acc, kinds, 4)
    snapshot = ok_snapshot(step, next) |> Map.put("drained", applied)
    {snapshot, next}
  end

  defp run_step(module, %{op: :update} = step, acc) do
    case Map.get(step, :action) do
      :direction_cycle ->
        run_direction_cycle(module, step, acc)

      :frame ->
        run_frame_loop(module, step, acc)

      _ ->
        message = Map.get(step, :message)
        value = Map.get(step, :message_value)

        if is_nil(message) do
          {Map.merge(ok_snapshot(step, acc), %{"error" => "missing message for update"}), acc}
        else
          {runtime_model, _source, cmd} =
            Run.step_execution(module, message, value, acc.runtime_model)

          commands = commands_from_cmd(cmd)

          next = %{
            acc
            | runtime_model: runtime_model,
              pending_commands: acc.pending_commands ++ commands,
              last_commands: commands
          }

          {ok_snapshot(step, next), next}
        end
    end
  end

  defp run_step(module, %{op: :view} = step, acc) do
    case Executor.view_generated(module, view_request(acc)) do
      {:ok, payload} ->
        view_output = list_field(payload, :view_output)
        next = %{acc | view_output: view_output}

        snapshot =
          ok_snapshot(step, next)
          |> Map.put("view_output", view_output)
          |> Map.put("expect_texts", Map.get(step, :expect_texts, []))

        case Map.get(step, :expect_texts, []) do
          texts when is_list(texts) and texts != [] ->
            missing = Enum.reject(texts, &view_contains_text?(view_output, &1))

            if missing == [] do
              {snapshot, next}
            else
              {Map.put(snapshot, "error", "missing view text: #{Enum.join(missing, ", ")}"), next}
            end

          _ ->
            {snapshot, next}
        end

      {:error, reason} ->
        {Map.merge(ok_snapshot(step, acc), %{"error" => inspect(reason)}), acc}
    end
  end

  defp run_step(_module, %{op: :subscriptions} = step, acc) do
    {ok_snapshot(step, acc), acc}
  end

  defp run_direction_cycle(module, step, acc) do
    count = Map.get(step, :count, 4)
    dirs = ["LeftPressed", "RightPressed", "UpPressed", "DownPressed"]

    Enum.reduce(0..(count - 1), {ok_snapshot(step, acc), acc}, fn i, {_snap, state} ->
      message = Enum.at(dirs, rem(i, 4))

      {runtime_model, _source, cmd} =
        Run.step_execution(module, message, nil, state.runtime_model)

      commands = commands_from_cmd(cmd)
      {drained, _applied} =
        drain_followups(
          module,
          %{state | runtime_model: runtime_model, pending_commands: commands},
          [],
          2
        )

      snap = ok_snapshot(step, drained) |> Map.put("message", message)
      {snap, drained}
    end)
  end

  defp run_frame_loop(module, step, acc) do
    count = Map.get(step, :count, 1)
    dt = Map.get(step, :dt_ms, 33)
    message = Map.get(step, :message) || "FrameTick"

    Enum.reduce(1..count, {ok_snapshot(step, acc), acc}, fn frame, {_snap, state} ->
      value = Elmx.TeaPlaybook.Samples.frame(frame, dt)

      {runtime_model, _source, cmd} =
        Run.step_execution(module, message, value, state.runtime_model)

      commands = commands_from_cmd(cmd)

      next = %{
        state
        | runtime_model: runtime_model,
          pending_commands: state.pending_commands ++ commands,
          last_commands: commands
      }

      {ok_snapshot(step, next) |> Map.put("frame", frame), next}
    end)
  end

  defp drain_followups(module, acc, kinds, rounds) do
    Enum.reduce_while(1..rounds, {acc, 0}, fn _, {state, applied} ->
      followups =
        state.pending_commands
        |> Followups.from_commands(source_root: "watch")
        |> Enum.filter(&followup_allowed?(&1, kinds))

      if followups == [] do
        {:halt, {state, applied}}
      else
        next =
          Enum.reduce(followups, %{state | pending_commands: []}, fn row, st ->
            message = Map.get(row, "message")
            value = Map.get(row, "message_value")

            if is_binary(message) and message != "" do
              {runtime_model, _source, cmd} =
                Run.step_execution(module, message, value, st.runtime_model)

              commands = commands_from_cmd(cmd)

              %{
                st
                | runtime_model: runtime_model,
                  pending_commands: st.pending_commands ++ commands,
                  last_commands: commands
              }
            else
              st
            end
          end)

        {:cont, {next, applied + length(followups)}}
      end
    end)
  end

  defp followup_allowed?(_row, []), do: true

  defp followup_allowed?(row, kinds) do
    command = Map.get(row, "command") || %{}
    kind = Map.get(command, "kind") || ""

    Enum.any?(kinds, fn
      :time ->
        String.contains?(kind, "time") or String.contains?(kind, "date") or
          String.contains?(to_string(Map.get(row, "message")), "Time") or
          String.contains?(to_string(Map.get(row, "message")), "Date")

      :storage ->
        String.contains?(kind, "storage")

      :random ->
        String.contains?(kind, "random") or
          String.contains?(to_string(Map.get(row, "message")), "Random")

      :health ->
        String.contains?(kind, "health") or
          String.contains?(to_string(Map.get(row, "message")), "Health") or
          String.contains?(to_string(Map.get(row, "message")), "Supported")

      _ ->
        true
    end)
  end

  defp commands_from_cmd(cmd) do
    Followups.flatten_commands(cmd)
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

  defp ok_snapshot(step, acc) do
    %{
      "step_id" => Map.get(step, :id),
      "op" => Atom.to_string(step.op),
      "message" => Map.get(step, :message),
      "action" => step |> Map.get(:action) |> atom_to_string(),
      "backend" => "elmx",
      "error" => nil,
      "commands" => acc.last_commands
    }
  end

  defp atom_to_string(nil), do: nil
  defp atom_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp list_field(map, key) do
    map
    |> Map.get(key, Map.get(map, Atom.to_string(key), []))
    |> List.wrap()
  end

  defp default_launch_context(watch_profile_id) do
    %{
      "reason" => 2,
      "watchModel" => "",
      "watchProfileId" => watch_profile_id,
      "screen" => %{
        "width" => 144,
        "height" => 168,
        "shape" => 1,
        "colorMode" => 2
      },
      "hasMicrophone" => false,
      "hasCompass" => false,
      "supportsHealth" => true
    }
  end
end
