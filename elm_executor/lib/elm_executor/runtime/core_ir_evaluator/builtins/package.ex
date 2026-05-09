defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Package do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Builtins.Cmd

  @spec eval(String.t(), String.t(), list(), map()) :: term()
  def eval("pebble.storage", function_name, values, ops),
    do: eval_storage_builtin(function_name, values, ops)

  def eval("pebble.time", function_name, values, ops),
    do: eval_device_builtin(function_name, values, ops)

  def eval("pebble.watchinfo", function_name, values, ops),
    do: eval_device_builtin(function_name, values, ops)

  def eval("pebble.cmd", function_name, values, ops),
    do: eval_device_builtin(function_name, values, ops)

  def eval("elm.kernel.pebblewatch", function_name, values, ops),
    do: eval_pebble_watch_kernel_builtin(function_name, values, ops)

  def eval("companion.phone", function_name, values, ops),
    do: eval_protocol_builtin("phone_to_watch", function_name, values, ops)

  def eval("companion.watch", function_name, values, ops),
    do: eval_protocol_builtin("watch_to_phone", function_name, values, ops)

  def eval(_module_name, _function_name, _values, _ops), do: :no_builtin

  @spec eval_protocol_builtin(String.t(), String.t(), list(), map()) :: {:ok, map()} | :no_builtin
  defp eval_protocol_builtin(direction, "sendphonetowatch", [message], ops)
       when direction == "phone_to_watch" and is_map(ops) do
    {:ok, protocol_command(direction, "companion", "watch", "PhoneToWatch", message, ops)}
  end

  defp eval_protocol_builtin(direction, "sendwatchtophone", [message], ops)
       when direction == "watch_to_phone" and is_map(ops) do
    {:ok, protocol_command(direction, "watch", "companion", "WatchToPhone", message, ops)}
  end

  defp eval_protocol_builtin(_direction, _function_name, _values, _ops), do: :no_builtin

  @spec eval_storage_builtin(String.t(), list(), map()) :: term()
  defp eval_storage_builtin(function_name, values, ops) do
    case function_name do
      "readint" -> storage_read_command("int", values, 0, ops)
      "readstring" -> storage_read_command("string", values, "", ops)
      "writeint" -> storage_write_command("int", values)
      "writestring" -> storage_write_command("string", values)
      "delete" -> storage_delete_command(values)
      _ -> :no_builtin
    end
  end

  @spec eval_pebble_watch_kernel_builtin(String.t(), list(), map()) :: term()
  defp eval_pebble_watch_kernel_builtin(function_name, values, ops) do
    case function_name do
      "none" ->
        Cmd.eval("none", values)

      "getcurrenttimestring" ->
        device_command("current_time_string", values, "12:00", ops)

      "getcurrentdatetime" ->
        device_command("current_date_time", values, current_date_time_value(), ops)

      "getbatterylevel" ->
        device_command("battery_level", values, 88, ops)

      "getconnectionstatus" ->
        device_command("connection_status", values, true, ops)

      "getclockstyle24h" ->
        device_command("clock_style_24h", values, true, ops)

      "gettimezoneisset" ->
        device_command("timezone_is_set", values, true, ops)

      "gettimezone" ->
        device_command("timezone", values, "UTC", ops)

      "getwatchmodel" ->
        device_command("watch_model", values, watch_model_value(), ops)

      "getfirmwareversion" ->
        device_command("firmware_version", values, firmware_version_value(), ops)

      "getcolor" ->
        device_command("watch_color", values, watch_color_value(), ops)

      "storagereadint" ->
        storage_read_command("int", values, 0, ops)

      "storagereadstring" ->
        storage_read_command("string", values, "", ops)

      "storagewriteint" ->
        storage_write_command("int", values)

      "storagewritestring" ->
        storage_write_command("string", values)

      "storagedelete" ->
        storage_delete_command(values)

      _ ->
        :no_builtin
    end
  end

  @spec eval_device_builtin(String.t(), list(), map()) :: term()
  defp eval_device_builtin(function_name, values, ops) do
    case function_name do
      "none" ->
        Cmd.eval("none", values)

      "currenttimestring" ->
        device_command("current_time_string", values, "12:00", ops)

      "currentdatetime" ->
        device_command("current_date_time", values, current_date_time_value(), ops)

      "getcurrentdatetime" ->
        device_command("current_date_time", values, current_date_time_value(), ops)

      "batterylevel" ->
        device_command("battery_level", values, 88, ops)

      "connectionstatus" ->
        device_command("connection_status", values, true, ops)

      "clockstyle24h" ->
        device_command("clock_style_24h", values, true, ops)

      "timezoneisset" ->
        device_command("timezone_is_set", values, true, ops)

      "timezone" ->
        device_command("timezone", values, "UTC", ops)

      "getmodel" ->
        device_command("watch_model", values, watch_model_value(), ops)

      "getfirmwareversion" ->
        device_command("firmware_version", values, firmware_version_value(), ops)

      "getcolor" ->
        device_command("watch_color", values, watch_color_value(), ops)

      _ ->
        :no_builtin
    end
  end

  @spec device_command(String.t(), list(), term(), map()) :: term()
  defp device_command(kind, [to_msg], value, ops) do
    with {:ok, message_value} <- ops.call.(to_msg, [value]) do
      {:ok,
       %{
         "kind" => "cmd.device.#{kind}",
         "package" => "elm-pebble/elm-watch",
         "message" => message_name(message_value),
         "message_value" => message_value,
         "value" => value
       }}
    end
  end

  defp device_command(_kind, _values, _value, _ops), do: :no_builtin

  @spec storage_read_command(String.t(), list(), term(), map()) :: term()
  defp storage_read_command(type, [key, to_msg], default_value, ops) when is_integer(key) do
    with {:ok, message_value} <- ops.call.(to_msg, [default_value]) do
      {:ok,
       %{
         "kind" => "cmd.storage.read_#{type}",
         "package" => "elm-pebble/elm-watch",
         "key" => key,
         "message" => message_name(message_value),
         "message_value" => message_value,
         "value" => default_value
       }}
    end
  end

  defp storage_read_command(_type, _values, _default_value, _ops), do: :no_builtin

  @spec storage_write_command(String.t(), list()) :: term()
  defp storage_write_command(type, [key, value]) when is_integer(key) do
    {:ok,
     %{
       "kind" => "cmd.storage.write_#{type}",
       "package" => "elm-pebble/elm-watch",
       "key" => key,
       "value" => value
     }}
  end

  defp storage_write_command(_type, _values), do: :no_builtin

  @spec storage_delete_command(list()) :: term()
  defp storage_delete_command([key]) when is_integer(key) do
    {:ok,
     %{
       "kind" => "cmd.storage.delete",
       "package" => "elm-pebble/elm-watch",
       "key" => key
     }}
  end

  defp storage_delete_command(_values), do: :no_builtin

  @spec protocol_command(String.t(), String.t(), String.t(), String.t(), term(), map()) :: map()
  defp protocol_command(direction, from, to, union, message, ops) do
    message_value = ops.normalize_union_value.(message, union)

    %{
      "kind" => "protocol",
      "package" => "companion-protocol",
      "direction" => direction,
      "from" => from,
      "to" => to,
      "message" => ops.debug_to_string.(message_value),
      "message_value" => message_value
    }
  end

  @spec message_name(term()) :: String.t()
  defp message_name(%{"ctor" => ctor}) when is_binary(ctor), do: ctor
  defp message_name(%{ctor: ctor}) when is_binary(ctor), do: ctor
  defp message_name({tag, _payload}) when is_integer(tag), do: "tag:#{tag}"
  defp message_name(tag) when is_integer(tag), do: "tag:#{tag}"
  defp message_name(_message_value), do: "StorageLoaded"

  @spec current_date_time_value() :: map()
  defp current_date_time_value do
    %{
      "year" => 2026,
      "month" => 1,
      "day" => 1,
      "dayOfWeek" => %{"ctor" => "Thursday", "args" => []},
      "hour" => 12,
      "minute" => 0,
      "second" => 0,
      "utcOffsetMinutes" => 0
    }
  end

  defp watch_model_value, do: %{"ctor" => "PebbleTime", "args" => []}
  defp firmware_version_value, do: %{"major" => 4, "minor" => 4, "patch" => 0}
  defp watch_color_value, do: %{"ctor" => "Black", "args" => []}
end
