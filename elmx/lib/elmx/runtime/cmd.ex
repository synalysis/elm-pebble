defmodule Elmx.Runtime.Cmd do
  @moduledoc """
  Wire-format `Cmd` values for debugger runtime command maps.
  """

  alias Elmx.Runtime.Values
  alias Elmx.Types

  @spec none() :: Types.wire_cmd()
  def none, do: %{"kind" => "none", "commands" => []}

  @spec batch([Types.wire_cmd() | term()]) :: Types.wire_cmd()
  def batch(commands) when is_list(commands) do
    %{
      "kind" => "batch",
      "commands" =>
        commands
        |> List.flatten()
        |> Enum.map(&normalize/1)
        |> Enum.reject(&match?(%{"kind" => "none"}, &1))
    }
  end

  @spec timer_after(non_neg_integer(), term()) :: Types.wire_cmd()
  def timer_after(ms, message) when is_integer(ms) do
    {name, message_value} = message_wire(message)

    %{
      "kind" => "cmd.timer.after",
      "package" => "pebble/cmd",
      "delay_ms" => ms,
      "message" => name,
      "message_value" => message_value
    }
  end

  @spec storage_read_int(integer(), term(), term()) :: Types.wire_cmd()
  def storage_read_int(key, callback, default) when is_integer(key) do
    {message, message_value} = callback_message_value(callback, default)

    %{
      "kind" => "cmd.storage.read_int",
      "package" => "elm-pebble/elm-watch",
      "key" => key,
      "message" => message,
      "message_value" => message_value,
      "value" => Values.wire_value(default)
    }
  end

  @spec storage_read_string(integer(), term(), term()) :: Types.wire_cmd()
  def storage_read_string(key, callback, default) when is_integer(key) do
    {message, message_value} = callback_message_value(callback, default)

    %{
      "kind" => "cmd.storage.read_string",
      "package" => "elm-pebble/elm-watch",
      "key" => key,
      "message" => message,
      "message_value" => message_value,
      "value" => Values.wire_value(default)
    }
  end

  @spec storage_write_int(integer(), term()) :: Types.wire_cmd()
  def storage_write_int(key, value) when is_integer(key) do
    %{
      "kind" => "cmd.storage.write_int",
      "package" => "elm-pebble/elm-watch",
      "key" => key,
      "value" => Values.wire_value(value)
    }
  end

  @spec storage_write_string(integer(), term()) :: Types.wire_cmd()
  def storage_write_string(key, value) when is_integer(key) do
    %{
      "kind" => "cmd.storage.write_string",
      "package" => "elm-pebble/elm-watch",
      "key" => key,
      "value" => Values.wire_value(value)
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

  @spec data_log_int32(term(), integer()) :: Types.wire_cmd()
  def data_log_int32(tag, value) when is_integer(value) do
    case data_log_tag_id(tag) do
      {:ok, tag_id} ->
        %{
          "kind" => "cmd.data_log.int32",
          "package" => "pebble/datalog",
          "tag" => tag_id,
          "value" => value
        }

      :error ->
        none()
    end
  end

  @spec data_log_bytes(term(), list()) :: Types.wire_cmd()
  def data_log_bytes(tag, bytes) when is_list(bytes) do
    case data_log_tag_id(tag) do
      {:ok, tag_id} ->
        %{
          "kind" => "cmd.data_log.bytes",
          "package" => "pebble/datalog",
          "tag" => tag_id,
          "bytes" => bytes
        }

      :error ->
        none()
    end
  end

  defp data_log_tag_id(%{"ctor" => "Tag", "args" => [tag]}) when is_integer(tag), do: {:ok, tag}
  defp data_log_tag_id(%{ctor: :Tag, args: [tag]}) when is_integer(tag), do: {:ok, tag}
  defp data_log_tag_id({:Tag, tag}) when is_integer(tag), do: {:ok, tag}
  defp data_log_tag_id(tag) when is_integer(tag), do: {:ok, tag}
  defp data_log_tag_id(_), do: :error

  @spec protocol_watch_to_phone(term()) :: Types.wire_cmd()
  def protocol_watch_to_phone(message) do
    {name, message_value} = message_wire(message)

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
  @spec companion_bridge(String.t(), String.t(), keyword()) :: Types.wire_cmd()
  def companion_bridge(api, op, opts \\ []) when is_binary(api) and is_binary(op) do
    module =
      case api do
        "storage" -> "Storage"
        "preferences" -> "PreferenceStore"
        other -> Macro.camelize(other)
      end

    callback = Keyword.get(opts, :callback)
    {callback_name, callback_value} = message_wire(callback || "Unknown")

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

  defp maybe_put_key(cmd, key) when is_binary(key), do: Map.put(cmd, "key", key)
  defp maybe_put_key(cmd, _), do: cmd

  defp maybe_put_field(cmd, _field, nil), do: cmd
  defp maybe_put_field(cmd, field, value), do: Map.put(cmd, field, Values.wire_value(value))

  @spec protocol_phone_to_watch(term()) :: Types.wire_cmd()
  def protocol_phone_to_watch(message) do
    {name, message_value} = message_wire(message)

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

  @spec device(String.t(), term(), term()) :: Types.wire_cmd()
  def device(kind, callback, value) when is_binary(kind) do
    {message, message_value} = callback_message_value(callback, value)

    %{
      "kind" => "cmd.device." <> kind,
      "package" => "elm-pebble/elm-watch",
      "message" => message,
      "message_value" => message_value,
      "value" => Values.wire_value(value)
    }
  end

  @doc """
  Synthetic followup row for dictation status/result messages (debugger stepping).
  """
  @spec dictation_followup(String.t(), term()) :: Types.wire_cmd()
  def dictation_followup(message, payload) when is_binary(message) do
    payload_wire = Values.wire_value(payload)

    %{
      "kind" => "cmd.dictation.followup",
      "package" => "pebble/dictation",
      "message" => message,
      "message_value" => %{"ctor" => message, "args" => [payload_wire]}
    }
  end

  @spec dictation_start() :: Types.wire_cmd()
  def dictation_start do
    batch([
      dictation_followup("DictationStatusChanged", :Starting),
      dictation_followup("DictationStatusChanged", :Recognizing),
      dictation_followup("DictationStatusChanged", :Finished),
      dictation_followup("DictationFinished", {:Ok, "Hello"})
    ])
  end

  @spec dictation_stop() :: Types.wire_cmd()
  def dictation_stop do
    dictation_followup("DictationFinished", {:Err, :Cancelled})
  end

  @doc """
  `Pebble.Compass.current` / `compass_peek` — delivers `GotHeading (Ok heading)` on the followup step.
  """
  @spec compass_peek(term()) :: Types.wire_cmd()
  def compass_peek(callback) do
    {message, _} = message_wire(callback)
    heading = %{"degrees" => 180.0, "isValid" => true}
    result_wire = Values.wire_value({:Ok, heading})

    %{
      "kind" => "cmd.device.compass_peek",
      "package" => "elm-pebble/elm-watch",
      "message" => message,
      "message_value" => %{"ctor" => message, "args" => [result_wire]},
      "value" => result_wire
    }
  end

  @doc """
  `Pebble.UnobstructedArea.currentBounds` — delivers unobstructed `Rect` on the followup step.
  """
  @spec unobstructed_bounds_peek(term()) :: Types.wire_cmd()
  def unobstructed_bounds_peek(callback) do
    {message, _} = message_wire(callback)
    bounds = %{"x" => 0, "y" => 0, "w" => 144, "h" => 168}
    bounds_wire = Values.wire_value(bounds)

    %{
      "kind" => "cmd.device.unobstructed_bounds_peek",
      "package" => "elm-pebble/elm-watch",
      "message" => message,
      "message_value" => %{"ctor" => message, "args" => [bounds_wire]},
      "value" => bounds_wire
    }
  end

  @spec normalize(term()) :: Types.wire_cmd()
  def normalize(%{"kind" => _} = cmd), do: cmd
  def normalize(%{kind: kind} = cmd), do: Map.new(cmd, fn {k, v} -> {to_string(k), v} end) |> Map.put("kind", to_string(kind))
  def normalize(cmd) when is_map(cmd), do: cmd
  def normalize(_), do: none()

  @spec message_wire(term()) :: {String.t(), Types.wire_ctor()}
  def message_wire(%{"ctor" => ctor, "args" => args}) when is_binary(ctor),
    do: {ctor, %{"ctor" => ctor, "args" => Values.wire_value(args || [])}}

  def message_wire(tuple) when is_tuple(tuple) do
    case Tuple.to_list(tuple) do
      [ctor | args] when is_atom(ctor) ->
        name = Atom.to_string(ctor)
        {name, %{"ctor" => name, "args" => Enum.map(args, &Values.wire_value/1)}}

      _ ->
        {"Unknown", %{"ctor" => "Unknown", "args" => [Values.wire_value(tuple)]}}
    end
  end

  def message_wire(ctor) when is_atom(ctor),
    do: {Atom.to_string(ctor), %{"ctor" => Atom.to_string(ctor), "args" => []}}

  def message_wire(ctor) when is_binary(ctor),
    do: {ctor, %{"ctor" => ctor, "args" => []}}

  def message_wire(tag) when is_integer(tag),
    do: {"tag:#{tag}", %{"ctor" => "tag:#{tag}", "args" => []}}

  def message_wire(other),
    do: {"Unknown", %{"ctor" => "Unknown", "args" => [Values.wire_value(other)]}}

  @doc """
  Builds `message` + `message_value` for device/storage followups.

  Nullary callback constructors (e.g. `ClockStyle24h`) get the command payload in `args`
  so debugger steps decode to `{:ClockStyle24h, true}` instead of `:ClockStyle24h`.
  """
  @spec callback_message_value(term(), term()) :: {String.t(), Types.wire_ctor()}
  def callback_message_value(callback, payload) do
    {message, message_value} = message_wire(callback)

    message_value =
      case message_value do
        %{"ctor" => ctor, "args" => []} when not is_nil(payload) ->
          %{"ctor" => ctor, "args" => [Values.wire_value(payload)]}

        %{ctor: ctor, args: []} when not is_nil(payload) ->
          %{"ctor" => to_string(ctor), "args" => [Values.wire_value(payload)]}

        other ->
          other
      end

    {message, message_value}
  end

  @doc """
  Pebble backlight cmd from `Maybe Bool` (Nothing → interaction, Just False → disable, Just True → enable).
  """
  @spec backlight_from_maybe(term()) :: Types.wire_cmd()
  def backlight_from_maybe(maybe) do
    mode =
      case maybe do
        :Nothing -> 0
        %{"ctor" => "Nothing"} -> 0
        %{ctor: :Nothing} -> 0
        {:Just, false} -> 1
        {:Just, true} -> 2
        %{"ctor" => "Just", "args" => [false]} -> 1
        %{"ctor" => "Just", "args" => [true]} -> 2
        %{ctor: :Just, args: [false]} -> 1
        %{ctor: :Just, args: [true]} -> 2
        _ -> 0
      end

    %{
      "kind" => "cmd.backlight",
      "package" => "pebble/cmd",
      "mode" => mode
    }
  end
end
