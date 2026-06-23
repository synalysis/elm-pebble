defmodule Elmc.Backend.CCodegen.SpecialValues.Stdlib.Effects do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Subscriptions
  alias Elmc.Backend.CCodegen.Types

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()
  def special_value_from_target("Debug.log", [label, value]),
    do: %{op: :runtime_call, function: "elmc_debug_log", args: [label, value]}

  def special_value_from_target("Debug.todo", [label]),
    do: %{op: :runtime_call, function: "elmc_debug_todo", args: [label]}

  def special_value_from_target("Debug.toString", [value]),
    do: %{op: :runtime_call, function: "elmc_debug_to_string", args: [value]}

  def special_value_from_target("Task.succeed", [value]),
    do: %{op: :runtime_call, function: "elmc_task_succeed", args: [value]}

  def special_value_from_target("Task.fail", [value]),
    do: %{op: :runtime_call, function: "elmc_task_fail", args: [value]}

  def special_value_from_target("Task.map", [f]),
    do: %{
      op: :lambda,
      args: ["__t"],
      body: %{op: :runtime_call, function: "elmc_task_map", args: [f, %{op: :var, name: "__t"}]}
    }

  def special_value_from_target("Task.map2", [f]),
    do: %{
      op: :lambda,
      args: ["__a", "__b"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_map2",
        args: [f, %{op: :var, name: "__a"}, %{op: :var, name: "__b"}]
      }
    }

  def special_value_from_target("Task.map2", [f, a]),
    do: %{
      op: :lambda,
      args: ["__b"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_map2",
        args: [f, a, %{op: :var, name: "__b"}]
      }
    }

  def special_value_from_target("Task.andThen", [f]),
    do: %{
      op: :lambda,
      args: ["__t"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_and_then",
        args: [f, %{op: :var, name: "__t"}]
      }
    }

  def special_value_from_target("Process.spawn", [task]),
    do: %{op: :runtime_call, function: "elmc_process_spawn", args: [task]}

  def special_value_from_target("Process.sleep", [milliseconds]),
    do: %{op: :runtime_call, function: "elmc_process_sleep", args: [milliseconds]}

  def special_value_from_target("Process.kill", [pid]),
    do: %{op: :runtime_call, function: "elmc_process_kill", args: [pid]}

  def special_value_from_target("Elm.Kernel.Time.nowMillis", [_unit]),
    do: %{op: :runtime_call, function: "elmc_time_now_millis", args: []}

  def special_value_from_target("Elm.Kernel.Time.zoneOffsetMinutes", [_unit]),
    do: %{op: :runtime_call, function: "elmc_time_zone_offset_minutes", args: []}

  def special_value_from_target("Elm.Kernel.Time.every", _args),
    do: %{op: :int_literal, value: 1}

  def special_value_from_target("Cmd.none", _args), do: %{op: :int_literal, value: 0}

  def special_value_from_target("Cmd.batch", [%{op: :list_literal, items: []}]),
    do: %{op: :int_literal, value: 0}

  def special_value_from_target("Cmd.batch", [%{op: :list_literal, items: [command]}]),
    do: command

  def special_value_from_target("Cmd.batch", [commands]),
    do: %{op: :runtime_call, function: "elmc_cmd_batch", args: [commands]}

  def special_value_from_target("Cmd.map", [f, cmd]),
    do: %{op: :runtime_call, function: "elmc_cmd_map", args: [f, cmd]}

  def special_value_from_target("Sub.none", _args), do: %{op: :int_literal, value: 0}

  def special_value_from_target("Sub.batch", args) do
    case Subscriptions.subscription_batch_expr(args) do
      %{op: :list_literal, items: items} = list_expr ->
        if Enum.any?(items, &match?(%{op: :pebble_sub}, &1)) do
          list_expr
        else
          %{op: :runtime_call, function: "elmc_sub_batch", args: [list_expr]}
        end

      nil ->
        case args do
          [%{op: :list_literal, items: []}] ->
            %{op: :int_literal, value: 0}

          [%{op: :list_literal, items: [single]}] ->
            single

          [subs] ->
            %{op: :runtime_call, function: "elmc_sub_batch", args: [subs]}

          _ ->
            nil
        end
    end
  end

  def special_value_from_target("Sub.map", [f, sub]),
    do: %{op: :runtime_call, function: "elmc_sub_map", args: [f, sub]}

  def special_value_from_target("Debug.toString", []),
    do: %{
      op: :lambda,
      args: ["__v"],
      body: %{
        op: :runtime_call,
        function: "elmc_debug_to_string",
        args: [%{op: :var, name: "__v"}]
      }
    }

  def special_value_from_target("Debug.log", [label]),
    do: %{
      op: :lambda,
      args: ["__v"],
      body: %{
        op: :runtime_call,
        function: "elmc_debug_log",
        args: [label, %{op: :var, name: "__v"}]
      }
    }

  # --- elm/core: List ---
  def special_value_from_target("Task.map", [f, task]),
    do: %{op: :runtime_call, function: "elmc_task_map", args: [f, task]}

  def special_value_from_target("Task.map2", [f, a, b]),
    do: %{op: :runtime_call, function: "elmc_task_map2", args: [f, a, b]}

  def special_value_from_target("Task.andThen", [f, task]),
    do: %{op: :runtime_call, function: "elmc_task_and_then", args: [f, task]}

  def special_value_from_target("Task.perform", [to_msg, task]),
    do: %{op: :runtime_call, function: "elmc_task_perform", args: [to_msg, task]}

  # --- elm/core: String (extended) ---

  def special_value_from_target(_target, _args), do: nil
end
