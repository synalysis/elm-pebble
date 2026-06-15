defmodule Elmx.Runtime.Cmd.Device do
  @moduledoc false

  alias Elmx.Runtime.Cmd
  alias Elmx.Runtime.Cmd.Wire
  alias Elmx.Runtime.Values
  alias Elmx.Types

  @spec timer_after(non_neg_integer(), Types.elm_msg()) :: Types.wire_cmd()
  def timer_after(ms, message) when is_integer(ms) do
    {name, message_value} = Wire.message_wire(message)

    %{
      "kind" => "cmd.timer.after",
      "package" => "pebble/cmd",
      "delay_ms" => ms,
      "message" => name,
      "message_value" => message_value
    }
  end

  @spec device(String.t(), Types.elm_msg(), Types.wire_value()) :: Types.wire_cmd()
  def device(kind, callback, value) when is_binary(kind) do
    {message, message_value} = Wire.callback_message_value(callback, value)

    %{
      "kind" => "cmd.device." <> kind,
      "package" => "elm-pebble/elm-watch",
      "message" => message,
      "message_value" => message_value,
      "value" => Values.wire_value(value)
    }
  end

  @doc """
  Delivers a message from a completed `Task.perform` on the next debugger step.
  """
  @spec task_immediate(Types.elm_msg()) :: Types.wire_cmd()
  def task_immediate(msg) do
    {message, message_value} = Wire.message_wire(msg)

    %{
      "kind" => "cmd.task.immediate",
      "package" => "elm/core",
      "message" => message,
      "message_value" => message_value
    }
  end

  @doc """
  Synthetic followup row for dictation status/result messages (debugger stepping).
  """
  @spec dictation_followup(String.t(), Types.elm_msg()) :: Types.wire_cmd()
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
    Cmd.batch([
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
  @spec compass_peek(Types.elm_msg()) :: Types.wire_cmd()
  def compass_peek(callback) do
    {message, _} = Wire.message_wire(callback)
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
  @spec unobstructed_bounds_peek(Types.elm_msg()) :: Types.wire_cmd()
  def unobstructed_bounds_peek(callback) do
    {message, _} = Wire.message_wire(callback)
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

end
