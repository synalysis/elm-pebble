defmodule Ide.Debugger.PackageCommandHandler do
  @moduledoc false

  @type handle_result ::
          {:handled, map(), map(), map() | nil}
          | :unhandled

  @spec handle(map(), String.t(), term(), term()) :: handle_result()
  def handle(state, target_name, package, row) when is_map(state) and is_binary(target_name) do
    command = Map.get(row, "command") || Map.get(row, :command)

    if storage_command?(command) do
      handle_storage_command(state, target_name, package, row, command)
    else
      :unhandled
    end
  end

  def handle(_state, _target_name, _package, _row), do: :unhandled

  @spec storage_command?(term()) :: boolean()
  defp storage_command?(%{} = command),
    do: String.starts_with?(command_kind(command), "cmd.storage.")

  defp storage_command?(_command), do: false

  @spec handle_storage_command(map(), String.t(), term(), map(), map()) :: handle_result()
  defp handle_storage_command(state, target_name, package, row, command) do
    kind = command_kind(command)

    cond do
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

  @spec command_kind(term()) :: String.t()
  defp command_kind(command) when is_map(command) do
    case Map.get(command, "kind") || Map.get(command, :kind) do
      kind when is_binary(kind) -> kind
      kind when is_atom(kind) -> Atom.to_string(kind)
      _ -> ""
    end
  end

  defp command_kind(_command), do: ""

  @spec storage_read_value(map(), String.t(), map(), term()) :: term()
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

  @spec storage_put(map(), String.t(), map(), term()) :: map()
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

  @spec storage_delete(map(), String.t(), map()) :: map()
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

  @spec storage_key(map()) :: String.t()
  defp storage_key(command) when is_map(command) do
    command
    |> then(&(Map.get(&1, "key") || Map.get(&1, :key)))
    |> to_string()
  end

  @spec storage_type(map()) :: String.t()
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

  @spec storage_message_value(map(), map(), term()) :: term()
  defp storage_message_value(command, row, value) do
    command_value =
      Map.get(command, "message_value") || Map.get(command, :message_value) ||
        Map.get(row, "message_value") || Map.get(row, :message_value)

    replace_first_constructor_arg(command_value, value)
  end

  @spec replace_first_constructor_arg(term(), term()) :: term()
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

  @spec replace_first_list_value(list(), term()) :: list()
  defp replace_first_list_value([], next), do: [next]
  defp replace_first_list_value([_head | tail], next), do: [next | tail]

  @spec storage_command_event(map()) :: map()
  defp storage_command_event(command) when is_map(command) do
    %{
      kind: command_kind(command),
      key: Map.get(command, "key") || Map.get(command, :key),
      type: storage_type(command)
    }
  end
end
