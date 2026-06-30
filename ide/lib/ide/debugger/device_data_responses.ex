defmodule Ide.Debugger.DeviceDataResponses do
  @moduledoc false

  alias Ide.Debugger.CmdCall
  alias Ide.Debugger.DeviceData
  alias Ide.Debugger.DeviceDataHints
  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.Surface
  alias Ide.Debugger.TimelineMessage
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
  def apply_after_step(state, _target, _message, _model, "configuration", _ctx, _message_value, _followups),
    do: state

  def apply_after_step(state, target, message, _model, _message_source, ctx, message_value, runtime_followups)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(message) and
             is_map(ctx) and is_list(runtime_followups) do
    covered = RuntimeFollowups.covered_device_response_ctors(runtime_followups)
    requests = requests_for_surface(state, target, message, message_value)

    state
    |> apply_covered_device_previews(requests, covered, target)
    |> then(&apply_request_list(requests, &1, target, ctx))
  end

  def apply_after_step(state, target, message, _model, _message_source, ctx, message_value, _runtime_followups)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(message) and
             is_map(ctx) do
    apply_responses(state, target, message, message_value, ctx)
  end

  def apply_after_step(state, _target, _message, _model, _message_source, _ctx, _message_value, _followups),
    do: state

  @doc false
  @spec apply_after_step(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.app_model(),
          String.t(),
          apply_ctx(),
          Types.subscription_payload() | nil
        ) :: Types.runtime_state()
  def apply_after_step(state, target, message, model, message_source, ctx, message_value) do
    apply_after_step(state, target, message, model, message_source, ctx, message_value, [])
  end

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
    state
    |> requests_for_surface(target, message, message_value)
    |> apply_request_list(state, target, ctx)
  end

  @spec apply_init_device_responses(
          Types.runtime_state(),
          Types.surface_target(),
          apply_ctx()
        ) :: Types.runtime_state()
  def apply_init_device_responses(state, target, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    surface = Surface.from_state(state, target)
    model = Surface.app_model(surface)

    state
    |> requests_for_surface(target, "init")
    |> Enum.reject(&DeviceData.init_request_already_satisfied?(model, &1))
    |> apply_request_list(state, target, ctx)
  end

  def apply_init_device_responses(state, _target, _ctx), do: state

  @spec apply_covered_device_previews(
          Types.runtime_state(),
          [Types.device_request()],
          [String.t()],
          Types.surface_target()
        ) :: Types.runtime_state()
  defp apply_covered_device_previews(state, _requests, [], _target), do: state

  defp apply_covered_device_previews(state, requests, covered, target)
       when is_map(state) and is_list(requests) and is_list(covered) and covered != [] and
              target in [:watch, :companion, :phone] do
    requests
    |> Enum.filter(fn req ->
      ctor = device_request_response_ctor(req)
      is_binary(ctor) and ctor in covered
    end)
    |> Enum.reduce(state, fn req, acc ->
      DeviceDataHints.apply_to_state(acc, target, req)
    end)
  end

  @spec device_request_response_ctor(Types.device_request()) :: String.t() | nil
  defp device_request_response_ctor(req) when is_map(req) do
    ctor = Map.get(req, :response_message) || Map.get(req, "response_message")

    if is_binary(ctor) and ctor != "" do
      RuntimeModelMessages.wire_constructor(ctor) || ctor
    else
      nil
    end
  end

  defp device_request_response_ctor(_req), do: nil

  @spec apply_request_list(
          [Types.device_request()],
          Types.runtime_state(),
          Types.surface_target(),
          apply_ctx()
        ) :: Types.runtime_state()
  defp apply_request_list(requests, state, target, ctx)
       when is_list(requests) and is_map(state) and is_map(ctx) do
    Enum.reduce(requests, state, fn req, acc ->
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
  def filter_update_cmd_calls(calls, current_message) when is_list(calls) do
    branch_scoped? =
      Enum.any?(calls, fn row ->
        (is_binary(Map.get(row, "branch")) and Map.get(row, "branch") != "") or
          (is_binary(Map.get(row, "branch_constructor")) and
             Map.get(row, "branch_constructor") != "")
      end)

    if branch_scoped? and is_binary(current_message) and current_message != "" do
      Enum.filter(calls, fn row ->
        branch_pattern =
          case Map.get(row, "branch") do
            branch when is_binary(branch) and branch != "" -> branch
            _ -> Map.get(row, "branch_constructor")
          end

        case branch_pattern do
          branch when is_binary(branch) and branch != "" ->
            RuntimeModelMessages.update_branch_matches_message?(branch, current_message)

          _ ->
            true
        end
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
      case DeviceData.response_message(req) do
        message when is_binary(message) and message != "" -> message
        _ -> ctor
      end

    formatted_message =
      if is_binary(step_message) and step_message != "" and not is_nil(wire_value) do
        TimelineMessage.format(step_message, wire_value)
      else
        step_message
      end

    cond do
      is_binary(formatted_message) and formatted_message != "" and is_map(wire_value) ->
        ctx.apply_step_once.(
          state,
          target,
          formatted_message,
          wire_value,
          "device_data",
          "device_data"
        )

      is_binary(formatted_message) and formatted_message != "" ->
        ctx.apply_step_once.(
          state,
          target,
          formatted_message,
          wire_value,
          "device_data",
          "device_data"
        )

      true ->
        state
    end
  end
end
