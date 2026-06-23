defmodule Elmx.Runtime.Cmd.Storage do
  @moduledoc false

  alias Elmx.Runtime.Cmd.Wire
  alias Elmx.Runtime.Values
  alias Elmx.Types

  @spec storage_read_int(integer(), Types.elm_msg(), Types.wire_value()) :: Types.wire_cmd()
  def storage_read_int(key, callback, default) when is_integer(key) do
    {message, message_value} = Wire.callback_message_value(callback, default)

    %{
      "kind" => "cmd.storage.read_int",
      "package" => "elm-pebble/elm-watch",
      "key" => key,
      "message" => message,
      "message_value" => message_value,
      "value" => Values.wire_value(default)
    }
  end

  @spec storage_read_string(integer(), Types.elm_msg(), Types.wire_value()) :: Types.wire_cmd()
  def storage_read_string(key, callback, default) when is_integer(key) do
    {message, message_value} = Wire.callback_message_value(callback, default)

    %{
      "kind" => "cmd.storage.read_string",
      "package" => "elm-pebble/elm-watch",
      "key" => key,
      "message" => message,
      "message_value" => message_value,
      "value" => Values.wire_value(default)
    }
  end

  @spec storage_write_int(integer(), Types.wire_value()) :: Types.wire_cmd()
  def storage_write_int(key, value) when is_integer(key) do
    %{
      "kind" => "cmd.storage.write_int",
      "package" => "elm-pebble/elm-watch",
      "key" => key,
      "value" => Values.wire_value(value)
    }
  end

  @spec storage_write_string(integer(), Types.wire_value()) :: Types.wire_cmd()
  def storage_write_string(key, value) when is_integer(key) do
    %{
      "kind" => "cmd.storage.write_string",
      "package" => "elm-pebble/elm-watch",
      "key" => key,
      "value" => Values.wire_value(value)
    }
  end

  @spec storage_read_max_size(Types.elm_msg(), Types.wire_value()) :: Types.wire_cmd()
  def storage_read_max_size(callback, default) do
    {message, message_value} = Wire.callback_message_value(callback, default)

    %{
      "kind" => "cmd.storage.read_max_size",
      "package" => "elm-pebble/elm-watch",
      "message" => message,
      "message_value" => message_value,
      "value" => Values.wire_value(default)
    }
  end

  @spec storage_delete(integer()) :: Types.wire_cmd()
  def storage_delete(key) when is_integer(key) do
    %{
      "kind" => "cmd.storage.delete",
      "package" => "elm-pebble/elm-watch",
      "key" => key
    }
  end

end
