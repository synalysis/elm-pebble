defmodule Ide.Debugger.PackageCommandHandler do
  @moduledoc false

  alias Ide.Debugger
  alias Ide.Debugger.Types
  alias Ide.WatchModels

  @type runtime_state :: Debugger.runtime_state()

  @type followup_row :: Types.RuntimeFollowupRow.wire_row()

  @type handle_step :: %{
          optional(:message) => String.t(),
          optional(:message_value) => Types.protocol_wire_arg(),
          optional(String.t()) => Types.wire_input()
        }

  @type storage_command_summary :: %{
          required(:kind) => String.t(),
          required(:key) => String.t(),
          required(:type) => String.t()
        }

  @type handle_result ::
          {:handled, runtime_state(), Types.PackageCmdEventPayload.t(), handle_step() | nil}
          | :unhandled

  @spec handle(runtime_state(), String.t(), String.t(), followup_row()) :: handle_result()
  def handle(state, target_name, package, row) when is_map(state) and is_binary(target_name) do
    command = Map.get(row, "command") || Map.get(row, :command)
    source = Map.get(row, "source") || Map.get(row, :source)

    cond do
      subscription_command_row?(source, command) ->
        handle_subscription_command(state, target_name, package, row, command)

      storage_command?(command) ->
        handle_storage_command(state, target_name, package, row, command)

      effect_command?(source, command) ->
        handle_effect_command(state, target_name, package, command)

      true ->
        :unhandled
    end
  end

  def handle(_state, _target_name, _package, _row), do: :unhandled

  @spec subscription_command_row?(String.t() | nil, Types.cmd_call() | nil) :: boolean()
  defp subscription_command_row?("subscription_command", %{} = command) do
    command_kind(command) == "cmd.subscription.register"
  end

  defp subscription_command_row?(_source, _command), do: false

  @spec handle_subscription_command(
          runtime_state(),
          String.t(),
          String.t(),
          followup_row(),
          Types.cmd_call()
        ) ::
          handle_result()
  defp handle_subscription_command(state, target_name, package, row, command) do
    response_message = Map.get(row, "message") || Map.get(row, :message)
    message_value = Map.get(command, "message_value") || Map.get(command, :message_value)

    event_payload = %{
      target: target_name,
      package: package,
      response_message: response_message,
      command: %{
        kind: command_kind(command),
        target: Map.get(command, "target") || Map.get(command, :target),
        interval_ms: Map.get(command, "interval_ms") || Map.get(command, :interval_ms)
      },
      response: message_value
    }

    step =
      if is_binary(response_message) and response_message != "" do
        %{message: response_message, message_value: message_value}
      else
        nil
      end

    {:handled, state, event_payload, step}
  end

  @spec storage_command?(Types.cmd_call() | nil) :: boolean()
  defp storage_command?(%{} = command),
    do: String.starts_with?(command_kind(command), "cmd.storage.")

  defp storage_command?(_command), do: false

  @spec effect_command?(String.t() | nil, Types.cmd_call() | nil) :: boolean()
  defp effect_command?("effect_command", %{} = command) do
    command_kind(command) |> String.starts_with?("cmd.effect.")
  end

  defp effect_command?(_source, _command), do: false

  @spec handle_effect_command(
          runtime_state(),
          String.t(),
          String.t(),
          Types.cmd_call()
        ) :: handle_result()
  defp handle_effect_command(state, target_name, package, command) do
    next_state =
      if command_kind(command) == "cmd.effect.speaker" do
        Ide.Debugger.SpeakerEffects.enqueue(state, command)
      else
        state
      end

    event_payload = %{
      target: target_name,
      package: package,
      response_message: nil,
      command: command,
      simulated: true,
      detail: Map.get(command, "variant") || Map.get(command, :variant)
    }

    {:handled, next_state, event_payload, nil}
  end

  @spec handle_storage_command(
          runtime_state(),
          String.t(),
          String.t(),
          followup_row(),
          Types.cmd_call()
        ) ::
          handle_result()
  defp handle_storage_command(state, target_name, package, row, command) do
    kind = command_kind(command)

    cond do
      kind == "cmd.storage.read_max_size" ->
        value = watch_storage_max_bytes(state)
        response_message = Map.get(row, "message") || Map.get(row, :message)

        event_payload = %{
          target: target_name,
          package: package,
          response_message: response_message,
          command: %{kind: kind, key: nil, type: "int"},
          response: value
        }

        step = %{
          message: response_message,
          message_value: storage_message_value(command, row, value)
        }

        {:handled, state, event_payload, step}

      String.starts_with?(kind, "cmd.storage.read_") ->
        default_value = Map.get(command, "value") || Map.get(command, :value)
        value = storage_read_value(state, target_name, command, default_value)
        response_message = Map.get(row, "message") || Map.get(row, :message)

        event_payload = %{
          target: target_name,
          package: package,
          response_message: response_message,
          command: storage_command_event(command),
          response: value
        }

        step = %{
          message: response_message,
          message_value: storage_message_value(command, row, value)
        }

        {:handled, state, event_payload, step}

      String.starts_with?(kind, "cmd.storage.write_") ->
        value = Map.get(command, "value") || Map.get(command, :value)
        state = storage_put(state, target_name, command, value)

        event_payload = %{
          target: target_name,
          package: package,
          response_message: nil,
          command: storage_command_event(command),
          response: value
        }

        {:handled, state, event_payload, nil}

      kind == "cmd.storage.delete" ->
        state = storage_delete(state, target_name, command)

        event_payload = %{
          target: target_name,
          package: package,
          response_message: nil,
          command: storage_command_event(command)
        }

        {:handled, state, event_payload, nil}

      true ->
        :unhandled
    end
  end

  @spec command_kind(Types.cmd_call()) :: String.t()
  defp command_kind(command) when is_map(command) do
    case Map.get(command, "kind") || Map.get(command, :kind) do
      kind when is_binary(kind) -> kind
      kind when is_atom(kind) -> Atom.to_string(kind)
      _ -> ""
    end
  end

  @spec storage_read_value(
          runtime_state(),
          String.t(),
          Types.cmd_call(),
          Types.protocol_wire_arg()
        ) :: Types.protocol_wire_arg()
  defp storage_read_value(state, target_name, command, default_value) do
    entry =
      state
      |> Map.get(:storage, %{})
      |> Map.get(target_name, %{})
      |> Map.get(storage_key(command))

    case entry do
      %{"type" => stored_type, "value" => value} ->
        if stored_type == storage_type(command), do: value, else: default_value

      _ ->
        default_value
    end
  end

  @spec storage_put(
          runtime_state(),
          String.t(),
          Types.cmd_call(),
          Types.protocol_wire_arg()
        ) :: runtime_state()
  defp storage_put(state, target_name, command, value) do
    key = storage_key(command)
    type = storage_type(command)

    update_in(
      state,
      [Access.key(:storage, %{}), Access.key(target_name, %{})],
      fn target_storage ->
        Map.put(target_storage || %{}, key, %{"type" => type, "value" => value})
      end
    )
  end

  @spec storage_delete(runtime_state(), String.t(), Types.cmd_call()) :: runtime_state()
  defp storage_delete(state, target_name, command) do
    key = storage_key(command)

    update_in(
      state,
      [Access.key(:storage, %{}), Access.key(target_name, %{})],
      fn target_storage ->
        Map.delete(target_storage || %{}, key)
      end
    )
  end

  @spec storage_key(Types.cmd_call()) :: String.t()
  defp storage_key(command) when is_map(command) do
    command
    |> then(&(Map.get(&1, "key") || Map.get(&1, :key)))
    |> to_string()
  end

  @spec storage_type(Types.cmd_call()) :: String.t()
  defp storage_type(command) when is_map(command) do
    command
    |> command_kind()
    |> String.split("_")
    |> List.last()
    |> case do
      type when type in ["int", "string"] -> type
      _ -> "value"
    end
  end

  @spec storage_message_value(Types.cmd_call(), followup_row(), Types.protocol_wire_arg()) ::
          Types.protocol_wire_arg()
  defp storage_message_value(command, row, value) do
    command_value =
      Map.get(command, "message_value") || Map.get(command, :message_value) ||
        Map.get(row, "message_value") || Map.get(row, :message_value)

    replace_first_constructor_arg(command_value, value)
  end

  @spec replace_first_constructor_arg(
          Types.protocol_message_wire_value(),
          Types.protocol_wire_arg()
        ) :: Types.protocol_message_wire_value()
  defp replace_first_constructor_arg(%{"ctor" => ctor, "args" => args} = value, next)
       when is_binary(ctor) and is_list(args) do
    Map.put(value, "args", replace_first_list_value(args, next))
  end

  defp replace_first_constructor_arg(%{ctor: ctor, args: args} = value, next)
       when is_binary(ctor) and is_list(args) do
    %{value | args: replace_first_list_value(args, next)}
  end

  defp replace_first_constructor_arg({tag, _payload}, next) when is_integer(tag), do: {tag, next}
  defp replace_first_constructor_arg(value, _next), do: value

  @spec replace_first_list_value(list(), Types.protocol_wire_arg()) :: list()
  defp replace_first_list_value([], next), do: [next]
  defp replace_first_list_value([_head | tail], next), do: [next | tail]

  @spec storage_command_event(Types.cmd_call()) :: storage_command_summary()
  defp storage_command_event(command) when is_map(command) do
    %{
      kind: command_kind(command),
      key: Map.get(command, "key") || Map.get(command, :key),
      type: storage_type(command)
    }
  end

  @spec watch_storage_max_bytes(runtime_state()) :: pos_integer()
  defp watch_storage_max_bytes(state) when is_map(state) do
    profile_id = Map.get(state, :watch_profile_id) || WatchModels.default_id()
    WatchModels.storage_max_bytes(profile_id)
  end
end
