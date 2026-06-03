defmodule Elmx.Runtime.Cmd.Companion do
  @moduledoc false

  alias Elmx.Runtime.Cmd.Wire
  alias Elmx.Runtime.Values
  alias Elmx.Types

  @spec protocol_watch_to_phone(Types.elm_msg()) :: Types.wire_cmd()
  def protocol_watch_to_phone(message) do
    {name, message_value} = Wire.message_wire(message)

    %{
      "kind" => "protocol",
      "package" => "companion-protocol",
      "direction" => "watch_to_phone",
      "from" => "watch",
      "to" => "companion",
      "message" => name,
      "message_value" => message_value
    }
  end

  @doc """
  Companion platform bridge command (storage, preferences, weather, …).

  `target` uses `Pebble.Companion.<Module>.<op>` so IDE bridge request extraction matches Core IR.
  """
  @spec companion_bridge(String.t(), String.t(), Types.companion_bridge_opts()) :: Types.wire_cmd()
  def companion_bridge(api, op, opts \\ []) when is_binary(api) and is_binary(op) do
    module =
      case api do
        "storage" -> "Storage"
        "preferences" -> "PreferenceStore"
        other -> Macro.camelize(other)
      end

    callback = Keyword.get(opts, :callback)
    {callback_name, callback_value} = Wire.message_wire(callback || "Unknown")

    base = %{
      "kind" => "cmd.companion.bridge",
      "package" => "pebble/companion",
      "target" => "Pebble.Companion." <> module <> "." <> op,
      "name" => op,
      "api" => api,
      "op" => op,
      "callback_constructor" => callback_name
    }

    base
    |> maybe_put_key(Keyword.get(opts, :key))
    |> maybe_put_field("bridge_id", Keyword.get(opts, :bridge_id))
    |> maybe_put_field("payload", Keyword.get(opts, :payload))
    |> maybe_put_field("value", Keyword.get(opts, :value))
    |> maybe_put_field("message", callback_name)
    |> maybe_put_field("message_value", callback_value)
  end

  @spec protocol_phone_to_watch(Types.elm_msg()) :: Types.wire_cmd()
  def protocol_phone_to_watch(message) do
    {name, message_value} = Wire.message_wire(message)

    %{
      "kind" => "protocol",
      "package" => "companion-protocol",
      "direction" => "phone_to_watch",
      "from" => "companion",
      "to" => "watch",
      "message" => name,
      "message_value" => message_value
    }
  end

  def maybe_put_key(cmd, key) when is_binary(key), do: Map.put(cmd, "key", key)
  def maybe_put_key(cmd, _), do: cmd

  def maybe_put_field(cmd, _field, nil), do: cmd
  def maybe_put_field(cmd, field, value), do: Map.put(cmd, field, Values.wire_value(value))

end
