defmodule Elmx.Runtime.MessageDecode do
  @moduledoc """
  Decodes debugger wire step messages into Elm `Msg` values for generated `update/2`.

  Accepts string message names, wire ctor maps (`"ctor"` / `"args"`), and companion
  payloads. Used by `Elmx.Runtime.Executor` on the IDE execution path.
  """

  alias Elmx.Runtime.MessageDecode.{Parse, Wire}
  alias Elmx.Types

  @spec decode(String.t() | Types.elm_msg(), Types.wire_value() | nil) :: Types.elm_msg()
  def decode(message, message_value \\ nil)

  def decode(message, message_value) do
    cond do
      not blank_message_value?(message_value) ->
        Wire.decode(message_value, message)

      is_binary(message) ->
        Parse.decode(message, default_frame_payload())

      true ->
        message
    end
  end

  @spec default_frame_payload() :: Types.frame_tick_payload()
  def default_frame_payload do
    %{"dtMs" => 33, "elapsedMs" => 33, "frame" => 1}
  end

  @doc false
  defdelegate wire_to_runtime(value), to: Wire, as: :to_runtime

  defp blank_message_value?(nil), do: true
  defp blank_message_value?(map) when is_map(map), do: map_size(map) == 0
  defp blank_message_value?(_), do: false
end
