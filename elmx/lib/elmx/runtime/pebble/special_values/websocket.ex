defmodule Elmx.Runtime.Pebble.SpecialValues.Websocket do
  @moduledoc false
  # Lowers `mbr/elm-wss` (`WebsocketSimple`) to port runtime calls so companion
  # phone templates compile without emitting Bytes-heavy package bodies.

  @behaviour Elmx.Runtime.Pebble.SpecialValues.Dispatcher

  import Elmx.Runtime.Pebble.SpecialValues.Helpers

  alias Elmx.Types

  @spec rewrite(String.t(), Types.ir_arg_list()) :: Types.dispatch_result()
  def rewrite(target, args) when is_binary(target) and is_list(args) do
    case target do
      "WebsocketSimple.open" -> open(args)
      "WebsocketSimple.close" -> close(args)
      "WebsocketSimple.send" -> send(args)
      "WebsocketSimple.sendWithHandle" -> send_with_handle(args)
      "WebsocketSimple.subscribe" -> subscribe(args)
      "WebsocketSimple.subscribeWithHandle" -> subscribe(args)
      "WebsocketSimple.errorToString" -> error_to_string(args)
      "WebsocketSimple.errorKindToString" -> error_kind_to_string(args)
      "WebsocketSimple.handle" -> handle(args)
      "WebsocketSimple.handleToString" -> handle_to_string(args)
      _ -> :unmatched
    end
  end

  defp open([port, url]) do
    apply_command_port(port, "default", "open", open_payload(url))
  end

  defp open(_), do: :error

  defp close([port]) do
    apply_command_port(port, "default", "close", close_payload(nil))
  end

  defp close(_), do: :error

  defp send([port, cmd]) do
    with {:ok, {kind, data}} <- encode_cmd(cmd) do
      apply_command_port(port, "default", kind, data)
    end
  end

  defp send(_), do: :error

  defp send_with_handle([port, handle, cmd]) do
    with {:ok, handle_str} <- handle_string(handle),
         {:ok, {kind, data}} <- encode_cmd(cmd) do
      apply_command_port(port, handle_str, kind, data)
    end
  end

  defp send_with_handle(_), do: :error

  defp subscribe([port]) do
    apply_event_port(port)
  end

  defp subscribe(_), do: :error

  defp error_to_string([error]), do: ui_call("elmx_wss_error_to_string", [error])
  defp error_to_string(_), do: :error

  defp error_kind_to_string([kind]), do: ui_call("elmx_wss_error_kind_to_string", [kind])
  defp error_kind_to_string(_), do: :error

  defp handle([value]) when is_map(value) do
    # `Handle String` is a single-payload union; keep the string payload.
    {:ok, value}
  end

  defp handle(_), do: :error

  defp handle_to_string([value]) when is_map(value), do: {:ok, value}
  defp handle_to_string(_), do: :error

  defp apply_command_port(%{op: :var, name: name}, handle, kind, data)
       when is_binary(name) and is_binary(handle) and is_binary(kind) do
    {:ok,
     %{
       op: :call,
       name: name,
       args: [
         %{
           op: :list_literal,
           items: [
             %{op: :string_literal, value: handle},
             %{op: :string_literal, value: kind},
             data
           ]
         }
       ]
     }}
  end

  defp apply_command_port(_port, _handle, _kind, _data), do: :error

  defp apply_event_port(%{op: :var, name: name}) when is_binary(name) do
    {:ok,
     %{
       op: :call,
       name: name,
       args: [
         %{
           op: :lambda,
           args: ["raw"],
           body: %{
             op: :runtime_call,
             function: "elmx_wss_decode_event",
             args: [%{op: :var, name: "raw"}]
           }
         }
       ]
     }}
  end

  defp apply_event_port(_), do: :error

  defp open_payload(url) do
    %{
      op: :record_literal,
      fields: [
        %{name: "url", expr: url},
        %{name: "protocols", expr: %{op: :list_literal, items: []}}
      ]
    }
  end

  defp close_payload(nil) do
    %{
      op: :record_literal,
      fields: [
        %{name: "code", expr: %{op: :int_literal, value: 0}},
        %{name: "reason", expr: %{op: :string_literal, value: ""}}
      ]
    }
  end

  defp encode_cmd(%{op: :tuple2, left: %{op: :int_literal, union_ctor: ctor}, right: payload})
       when is_binary(ctor) do
    cond do
      String.ends_with?(ctor, ".Transmit") or ctor == "Transmit" ->
        {:ok, {"transmit", payload}}

      String.ends_with?(ctor, ".Open") or ctor == "Open" ->
        {:ok, {"open", open_from_payload(payload)}}

      String.ends_with?(ctor, ".Close") or ctor == "Close" ->
        {:ok, {"close", close_from_payload(payload)}}

      true ->
        :error
    end
  end

  defp encode_cmd(%{op: :constructor_call, target: target, args: args}) when is_binary(target) do
    cond do
      String.ends_with?(target, ".Transmit") or target == "Transmit" ->
        case args do
          [payload] -> {:ok, {"transmit", payload}}
          _ -> :error
        end

      String.ends_with?(target, ".Open") or target == "Open" ->
        case args do
          [url, protocols] ->
            {:ok,
             {"open",
              %{
                op: :record_literal,
                fields: [
                  %{name: "url", expr: url},
                  %{name: "protocols", expr: protocols}
                ]
              }}}

          [url] ->
            {:ok, {"open", open_payload(url)}}

          _ ->
            :error
        end

      String.ends_with?(target, ".Close") or target == "Close" ->
        case args do
          [] -> {:ok, {"close", close_payload(nil)}}
          [payload] -> {:ok, {"close", close_from_payload(payload)}}
          _ -> :error
        end

      true ->
        :error
    end
  end

  defp encode_cmd(_), do: :error

  defp open_from_payload(%{op: :tuple2, left: url, right: protocols}) do
    %{
      op: :record_literal,
      fields: [
        %{name: "url", expr: url},
        %{name: "protocols", expr: protocols}
      ]
    }
  end

  defp open_from_payload(url), do: open_payload(url)

  defp close_from_payload(%{op: :int_literal, value: 0}), do: close_payload(nil)
  defp close_from_payload(other) when is_map(other), do: other

  defp handle_string(%{op: :string_literal, value: value}) when is_binary(value),
    do: {:ok, value}

  defp handle_string(%{op: :tuple2, left: %{op: :int_literal}, right: %{op: :string_literal, value: value}})
       when is_binary(value),
       do: {:ok, value}

  defp handle_string(_), do: :error
end
