defmodule Elmx.Runtime.Pebble.SpecialValues.Helpers do
  @moduledoc false

  alias Elmx.Runtime.Pebble.KernelTargets
  alias Elmx.Runtime.Pebble.Subscriptions
  alias Elmx.Types

  @spec ui_call(String.t(), Types.ir_arg_list()) :: Types.rewrite_result()
  def ui_call(function, args) when is_binary(function) and is_list(args) do
    {:ok, %{op: :runtime_call, function: function, args: args}}
  end

  @spec cmd_batch([term()]) :: Types.rewrite_result()
  def cmd_batch([%{op: :list_literal} = list]),
    do: {:ok, %{op: :runtime_call, function: "elmx_cmd_batch", args: [list]}}

  def cmd_batch([list]) when is_map(list),
    do: {:ok, %{op: :runtime_call, function: "elmx_cmd_batch", args: [list]}}

  def cmd_batch(_), do: :error

  @spec subscription_mask(String.t()) :: Types.rewrite_result()
  def subscription_mask(target) when is_binary(target) do
    case Subscriptions.mask(target) do
      nil -> :error
      value -> {:ok, %{op: :int_literal, value: value}}
    end
  end

  @spec subscription_batch([term()]) :: Types.rewrite_result()
  def subscription_batch([%{op: :list_literal, items: items}]) when is_list(items) do
    {:ok, %{op: :int_literal, value: Subscriptions.batch_mask(items)}}
  end

  def subscription_batch([list]) when is_map(list) do
    items = Map.get(list, :items) || Map.get(list, "items") || []
    {:ok, %{op: :int_literal, value: Subscriptions.batch_mask(items)}}
  end

  def subscription_batch(_), do: :error

  @spec frame_subscription([term()]) :: Types.rewrite_result()
  def frame_subscription(args),
    do: {:ok, %{op: :int_literal, value: Subscriptions.Frame.mask(args)}}

  @spec frame_fps_subscription([term()]) :: Types.rewrite_result()
  def frame_fps_subscription(args),
    do: {:ok, %{op: :int_literal, value: Subscriptions.Frame.fps_mask(args)}}

  @spec data_log_tag([term()]) :: Types.rewrite_result()
  def data_log_tag([value]), do: {:ok, %{op: :runtime_call, function: "elmx_datalog_tag", args: [value]}}
  def data_log_tag(_), do: :error

  @spec math_clamp([term()]) :: Types.rewrite_result()
  def math_clamp([lo, hi, value]) do
    {:ok, %{op: :runtime_call, function: "elmx_math_clamp", args: [lo, hi, value]}}
  end

  def math_clamp(_), do: :error

  @spec kernel_watch(String.t(), [term()]) :: Types.rewrite_result()
  def kernel_watch(name, args) when is_binary(name) and is_list(args) do
    KernelTargets.rewrite("Elm.Kernel.PebbleWatch." <> name, args)
  end

  @spec passthrough_arg([term()]) :: Types.rewrite_result()
  def passthrough_arg([value]), do: {:ok, value}
  def passthrough_arg(_), do: :error

  @spec companion_subscription_zero() :: Types.rewrite_result()
  def companion_subscription_zero, do: {:ok, %{op: :int_literal, value: 0}}

  @spec companion_phone_send([term()]) :: Types.rewrite_result()
  def companion_phone_send([callback, inner | _] = args) when is_list(args) do
    case phone_request_envelope_ir(inner) do
      {:ok, envelope} -> ui_call("elmx_companion_phone_send", [callback, envelope])
      :error -> ui_call("elmx_companion_phone_send", args)
    end
  end

  def companion_phone_send(args), do: ui_call("elmx_companion_phone_send", args)

  @spec companion_bridge_call(String.t(), String.t(), [term()]) :: Types.rewrite_result()
  def companion_bridge_call(api, op, args)
      when is_binary(api) and is_binary(op) and is_list(args) do
    callback = companion_bridge_callback(args)
    ui_call("elmx_companion_bridge_cmd", [string_literal_ir(api), string_literal_ir(op), callback])
  end

  @spec string_literal_ir(String.t()) :: Types.ir_expr()
  def string_literal_ir(value) when is_binary(value), do: %{op: :string_literal, value: value}

  defp phone_request_envelope_ir(%{op: :qualified_call, target: target, args: req_args})
       when target in [
              "Pebble.Companion.Phone.request",
              "Pebble.Companion.Phone.requestWithPayload"
            ] and
              is_list(req_args) do
    case target do
      "Pebble.Companion.Phone.request" ->
        with [id, api, op, _decode | _] <- req_args,
             {:ok, id} <- string_literal_ir_value(id),
             {:ok, api} <- string_literal_ir_value(api),
             {:ok, op} <- string_literal_ir_value(op) do
          {:ok, command_envelope_record(id, api, op, empty_payload_record())}
        else
          _ -> :error
        end

      "Pebble.Companion.Phone.requestWithPayload" ->
        with [id, api, op, payload, _decode | _] <- req_args,
             {:ok, id} <- string_literal_ir_value(id),
             {:ok, api} <- string_literal_ir_value(api),
             {:ok, op} <- string_literal_ir_value(op) do
          {:ok, command_envelope_record(id, api, op, payload)}
        else
          _ -> :error
        end
    end
  end

  defp phone_request_envelope_ir(_), do: :error

  defp string_literal_ir_value(%{op: :string_literal, value: value}) when is_binary(value), do: {:ok, value}
  defp string_literal_ir_value(_), do: :error

  defp command_envelope_record(id, api, op, payload)
       when is_binary(id) and is_binary(api) and is_binary(op) do
    %{
      op: :record_literal,
      fields: [
        {"id", %{op: :string_literal, value: id}},
        {"api", %{op: :string_literal, value: api}},
        {"op", %{op: :string_literal, value: op}},
        {"payload", payload}
      ]
    }
  end

  defp empty_payload_record, do: %{op: :record_literal, fields: []}

  defp companion_bridge_callback(args) when is_list(args) do
    args |> List.last() |> companion_bridge_callback_arg()
  end

  defp companion_bridge_callback_arg(%{op: :var} = callback), do: callback

  defp companion_bridge_callback_arg(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor) do
    string_literal_ir(union_ctor_short_name(ctor))
  end

  defp companion_bridge_callback_arg(%{"ctor" => ctor, "args" => _}) when is_binary(ctor),
    do: string_literal_ir(ctor)

  defp companion_bridge_callback_arg(callback) when is_binary(callback), do: string_literal_ir(callback)
  defp companion_bridge_callback_arg(_), do: string_literal_ir("Unknown")

  defp union_ctor_short_name(qualified) when is_binary(qualified) do
    qualified |> String.split(".") |> List.last()
  end
end
