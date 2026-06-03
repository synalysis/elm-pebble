defmodule Elmx.Runtime.Pebble.Dispatch.Storage do
  @moduledoc false

  alias Elmx.Runtime.Cmd
  alias Elmx.Runtime.Values
  alias Elmx.Types

  @spec datalog_tag_value(Types.registry_args()) :: Types.wire_ctor()
  def datalog_tag_value([tag]) when is_integer(tag), do: Values.ctor("Tag", [tag])
  def datalog_tag_value(_), do: Values.ctor("Tag", [0])

  @spec datalog_log_int32_cmd(Types.registry_args()) :: Types.wire_cmd()
  def datalog_log_int32_cmd([tag, value]) when is_integer(value), do: Cmd.data_log_int32(tag, value)
  def datalog_log_int32_cmd(_), do: Cmd.none()

  @spec datalog_log_bytes_cmd(Types.registry_args()) :: Types.wire_cmd()
  def datalog_log_bytes_cmd([tag, bytes]) when is_list(bytes), do: Cmd.data_log_bytes(tag, bytes)
  def datalog_log_bytes_cmd(_), do: Cmd.none()

  @spec read_int_cmd(Types.registry_args()) :: Types.wire_cmd()
  def read_int_cmd([key, callback, default]) when is_integer(key),
    do: Cmd.storage_read_int(key, callback, default)

  def read_int_cmd([key, callback]) when is_integer(key),
    do: Cmd.storage_read_int(key, callback, 0)

  def read_int_cmd(_), do: Cmd.none()

  @spec read_string_cmd(Types.registry_args()) :: Types.wire_cmd()
  def read_string_cmd([key, callback, default]) when is_integer(key),
    do: Cmd.storage_read_string(key, callback, default)

  def read_string_cmd([key, callback]) when is_integer(key),
    do: Cmd.storage_read_string(key, callback, "")

  def read_string_cmd(_), do: Cmd.none()

  @spec write_int_cmd(Types.registry_args()) :: Types.wire_cmd()
  def write_int_cmd([key, value]) when is_integer(key), do: Cmd.storage_write_int(key, value)
  def write_int_cmd(_), do: Cmd.none()

  @spec write_string_cmd(Types.registry_args()) :: Types.wire_cmd()
  def write_string_cmd([key, value]) when is_integer(key), do: Cmd.storage_write_string(key, value)
  def write_string_cmd(_), do: Cmd.none()

  @spec delete_cmd(Types.registry_args()) :: Types.wire_cmd()
  def delete_cmd([key]) when is_integer(key), do: Cmd.storage_delete(key)
  def delete_cmd(_), do: Cmd.none()
end
