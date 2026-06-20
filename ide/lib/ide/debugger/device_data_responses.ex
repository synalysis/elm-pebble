defmodule Ide.Debugger.DeviceDataResponses do
  @moduledoc false

  alias Ide.Debugger.CmdCall
  alias Ide.Debugger.DeviceData
  alias Ide.Debugger.DeviceDataHints
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @type apply_ctx :: %{
          required(:append_event) => (Types.runtime_state(),
                                      String.t(),
                                      Types.debugger_timeline_payload() ->
                                        Types.runtime_state()),
          required(:apply_step_once) => (Types.runtime_state(),
                                         Types.surface_target(),
                                         String.t(),
                                         Types.subscription_payload()
                                         | nil,
                                         String.t(),
                                         String.t() ->
                                           Types.runtime_state()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t())
        }

  @spec requests_for_surface(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload() | nil
        ) ::
          [Types.device_request()]
  def requests_for_surface(state, target, current_message, message_value \\ nil)

  def requests_for_surface(state, target, current_message, message_value)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(current_message) do
    surface = Surface.from_state(state, target)
    model = Surface.app_model(surface)
    ei = Surface.introspect(surface)

    DeviceData.requests_for_message(ei, model, current_message,
      message_constructor: &RuntimeModelMessages.wire_constructor/1,
      update_cmd_calls_filter: &filter_update_cmd_calls/2,
      expand_cmd_calls: &CmdCall.expand_helpers/2,
      message_value: message_value
    )
  end

  def requests_for_surface(_state, _target, _current_message, _message_value), do: []

  @spec apply_after_step(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.app_model(),
          String.t(),
          apply_ctx(),
          Types.subscription_payload() | nil
        ) :: Types.runtime_state()
  def apply_after_step(state, _target, _message, _model, "configuration", _ctx, _message_value),
    do: state

  def apply_after_step(state, target, message, _model, _message_source, ctx, message_value)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(message) and
             is_map(ctx) do
    apply_responses(state, target, message, message_value, ctx)
  end

  def apply_after_step(state, _target, _message, _model, _message_source, _ctx, _message_value),
    do: state

  @spec device_data_response_appended?(
          Types.runtime_state(),
          non_neg_integer(),
          Types.surface_target(),
          (Types.surface_target() -> String.t())
        ) :: boolean()
  def device_data_response_appended?(state, before_seq, target, source_root_for_target)
      when is_map(state) and is_integer(before_seq) and target in [:watch, :companion, :phone] and
             is_function(source_root_for_target, 1) do
    source_root = source_root_for_target.(target)

    state
    |> Map.get(:debugger_timeline, [])
    |> Enum.any?(fn
      %{seq: seq, target: ^source_root, message_source: "device_data"} when is_integer(seq) ->
        seq > before_seq

      %{"seq" => seq, "target" => ^source_root, "message_source" => "device_data"}
      when is_integer(seq) ->
        seq > before_seq

      _ ->
        false
    end)
  end

  def device_data_response_appended?(_state, _before_seq, _target, _source_root_for_target),
    do: false

  @spec apply_responses(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload() | nil,
          apply_ctx()
        ) :: Types.runtime_state()
  def apply_responses(state, target, message, message_value, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(message) and
             is_map(ctx) do
    requests_for_surface(state, target, message, message_value)
    |> Enum.reduce(state, fn req, acc ->
      target_name = ctx.source_root_for_target.(target)

      acc
      |> DeviceDataHints.apply_to_state(target, req)
      |> ctx.append_event.(
        "debugger.device_data",
        Ide.Debugger.Types.DeviceDataEventPayload.from_request(target_name, req)
      )
      |> apply_device_response_step(target, req, ctx)
      |> DeviceDataHints.apply_to_state(target, req)
    end)
  end

  @spec filter_update_cmd_calls([Types.cmd_call()], String.t() | nil) :: [Types.cmd_call()]
  def filter_update_cmd_calls(calls, current_ctor) when is_list(calls) do
    branch_scoped? =
      Enum.any?(calls, fn row ->
        is_binary(Map.get(row, "branch_constructor")) and Map.get(row, "branch_constructor") != ""
      end)

    if branch_scoped? and is_binary(current_ctor) and current_ctor != "" do
      Enum.filter(calls, fn row ->
        Map.get(row, "branch_constructor") == current_ctor
      end)
    else
      calls
    end
  end

  @spec apply_device_response_step(
          Types.runtime_state(),
          Types.surface_target(),
          Types.device_request(),
          apply_ctx()
        ) :: Types.runtime_state()
  defp apply_device_response_step(state, target, req, ctx)
       when is_map(state) and is_map(req) and is_map(ctx) do
    surface = Surface.from_state(state, target)
    model = Surface.app_model(surface)
    introspect = Surface.introspect(surface)
    ctor = Map.get(req, :response_message) || Map.get(req, "response_message")

    wire_value =
      DeviceData.response_wire_value(req) ||
        DeviceData.response_wire_for_callback(introspect, model, ctor, nil)

    step_message =
      cond do
        is_map(wire_value) and is_binary(ctor) and ctor != "" ->
          ctor

        true ->
          case DeviceData.response_message(req) do
            message when is_binary(message) and message != "" -> message
            _ -> ctor
          end
      end

    cond do
      is_binary(step_message) and step_message != "" and is_map(wire_value) ->
        ctx.apply_step_once.(
          state,
          target,
          step_message,
          wire_value,
          "device_data",
          "device_data"
        )

      is_binary(step_message) and step_message != "" ->
        ctx.apply_step_once.(
          state,
          target,
          step_message,
          wire_value,
          "device_data",
          "device_data"
        )

      true ->
        state
    end
  end
end
