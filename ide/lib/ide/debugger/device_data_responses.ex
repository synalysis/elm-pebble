defmodule Ide.Debugger.DeviceDataResponses do
  @moduledoc false

  alias Ide.Debugger.CmdCall
  alias Ide.Debugger.DeviceData
  alias Ide.Debugger.DeviceDataHints
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @type apply_ctx :: %{
          required(:append_event) =>
            (Types.runtime_state(), String.t(), map() -> Types.runtime_state()),
          required(:apply_step_once) =>
            (Types.runtime_state(), Types.surface_target(), String.t(),
             Types.subscription_payload() | map() | nil, String.t(), String.t() ->
               Types.runtime_state()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t())
        }

  @spec requests_for_surface(Types.runtime_state(), Types.surface_target(), String.t()) ::
          [Types.device_request()]
  def requests_for_surface(state, target, current_message)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(current_message) do
    surface = Surface.from_state(state, target)
    model = Surface.app_model(surface)
    ei = Surface.introspect(surface)

    DeviceData.requests_for_message(ei, model, current_message,
      message_constructor: &RuntimeModelMessages.wire_constructor/1,
      update_cmd_calls_filter: &filter_update_cmd_calls/2,
      expand_cmd_calls: &CmdCall.expand_helpers/2
    )
  end

  def requests_for_surface(_state, _target, _current_message), do: []

  @spec apply_after_step(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.app_model(),
          String.t(),
          apply_ctx()
        ) :: Types.runtime_state()
  def apply_after_step(state, _target, _message, _model, "configuration", _ctx), do: state

  def apply_after_step(state, target, message, _model, _message_source, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(message) and
             is_map(ctx) do
    apply_responses(state, target, message, ctx)
  end

  def apply_after_step(state, _target, _message, _model, _message_source, _ctx), do: state

  @spec apply_responses(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          apply_ctx()
        ) :: Types.runtime_state()
  def apply_responses(state, target, message, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(message) and
             is_map(ctx) do
    requests_for_surface(state, target, message)
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
        case Map.get(row, "branch_constructor") do
          nil -> true
          "" -> true
          ^current_ctor -> true
          _ -> false
        end
      end)
    else
      calls
    end
  end

  def filter_update_cmd_calls(calls, _current_ctor) when is_list(calls), do: calls

  @spec apply_device_response_step(Types.runtime_state(), Types.surface_target(), map(), apply_ctx()) ::
          Types.runtime_state()
  defp apply_device_response_step(state, target, req, ctx) when is_map(state) and is_map(req) and is_map(ctx) do
    response_message = DeviceData.response_message(req)
    wire_value = DeviceData.response_wire_value(req)

    if is_binary(response_message) and response_message != "" do
      ctx.apply_step_once.(state, target, response_message, wire_value, "device_data", "device_data")
    else
      state
    end
  end
end
