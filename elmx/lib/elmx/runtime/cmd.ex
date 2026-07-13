defmodule Elmx.Runtime.Cmd do
  @moduledoc """
  Wire-format `Cmd` values for debugger runtime command maps.
  """

  alias Elmx.Runtime.Cmd.{Companion, Device, Effects, Storage, Wire}
  alias Elmx.Types

  @spec none() :: Types.wire_cmd()
  def none, do: %{"kind" => "none", "commands" => []}

  @spec batch([Types.wire_cmd_input()]) :: Types.wire_cmd()
  def batch(commands) when is_list(commands) do
    %{
      "kind" => "batch",
      "commands" =>
        commands
        |> List.flatten()
        |> Enum.map(&Wire.normalize/1)
        |> Enum.reject(&match?(%{"kind" => "none"}, &1))
    }
  end

  @spec timer_after(non_neg_integer(), Types.elm_msg()) :: Types.wire_cmd()
  defdelegate timer_after(ms, message), to: Device

  @spec storage_read_int(integer(), Types.elm_msg(), Types.wire_value()) :: Types.wire_cmd()
  defdelegate storage_read_int(key, callback, default), to: Storage

  @spec storage_read_string(integer(), Types.elm_msg(), Types.wire_value()) :: Types.wire_cmd()
  defdelegate storage_read_string(key, callback, default), to: Storage

  @spec storage_write_int(integer(), Types.wire_value()) :: Types.wire_cmd()
  defdelegate storage_write_int(key, value), to: Storage

  @spec storage_write_string(integer(), Types.wire_value()) :: Types.wire_cmd()
  defdelegate storage_write_string(key, value), to: Storage

  @spec storage_delete(integer()) :: Types.wire_cmd()
  defdelegate storage_delete(key), to: Storage

  @spec storage_read_max_size(Types.elm_msg(), Types.wire_value()) :: Types.wire_cmd()
  defdelegate storage_read_max_size(callback, default), to: Storage

  @spec data_log_int32(Types.data_log_tag(), integer()) :: Types.wire_cmd()
  def data_log_int32(tag, value) when is_integer(value) do
    case Wire.data_log_tag_id(tag) do
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

  @spec data_log_bytes(Types.wire_ctor() | integer(), [byte() | integer()]) :: Types.wire_cmd()
  def data_log_bytes(tag, bytes) when is_list(bytes) do
    case Wire.data_log_tag_id(tag) do
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

  @spec protocol_watch_to_phone(Types.elm_msg()) :: Types.wire_cmd()
  defdelegate protocol_watch_to_phone(message), to: Companion

  @spec protocol_watch_to_phone_tag_value(integer(), integer()) :: Types.wire_cmd()
  defdelegate protocol_watch_to_phone_tag_value(tag, value), to: Companion

  @spec companion_bridge(String.t(), String.t(), Types.companion_bridge_opts()) :: Types.wire_cmd()
  defdelegate companion_bridge(api, op, opts \\ []), to: Companion

  @spec protocol_phone_to_watch(Types.elm_msg()) :: Types.wire_cmd()
  defdelegate protocol_phone_to_watch(message), to: Companion

  @spec device(String.t(), Types.elm_msg(), Types.wire_value()) :: Types.wire_cmd()
  defdelegate device(kind, callback, value), to: Device

  @spec task_immediate(Types.elm_msg()) :: Types.wire_cmd()
  defdelegate task_immediate(msg), to: Device

  @spec dictation_followup(String.t(), Types.elm_msg()) :: Types.wire_cmd()
  defdelegate dictation_followup(message, payload), to: Device

  @spec dictation_start() :: Types.wire_cmd()
  defdelegate dictation_start(), to: Device

  @spec dictation_stop() :: Types.wire_cmd()
  defdelegate dictation_stop(), to: Device

  @spec compass_peek(Types.elm_msg()) :: Types.wire_cmd()
  defdelegate compass_peek(callback), to: Device

  @spec unobstructed_bounds_peek(Types.elm_msg()) :: Types.wire_cmd()
  defdelegate unobstructed_bounds_peek(callback), to: Device

  @spec normalize(Types.wire_cmd()) :: Types.wire_cmd()
  defdelegate normalize(cmd), to: Wire

  @spec message_wire(Types.elm_msg()) :: {String.t(), Types.wire_value() | Types.wire_map()}
  defdelegate message_wire(message), to: Wire

  @spec callback_message_value(Types.elm_msg(), Types.wire_value()) ::
          {String.t(), Types.wire_map()}
  defdelegate callback_message_value(callback, payload), to: Wire

  @spec subscription_register(String.t(), Types.subscription_register_opts()) :: Types.wire_cmd()
  defdelegate subscription_register(target, opts \\ []), to: Effects

  @spec effect(String.t(), Types.effect_cmd_opts()) :: Types.wire_cmd()
  defdelegate effect(kind, opts \\ []), to: Effects

  @spec backlight_from_maybe(Types.maybe_like()) :: Types.wire_cmd()
  defdelegate backlight_from_maybe(maybe), to: Effects
end
