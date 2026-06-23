defmodule Ide.Debugger.HttpExecutor do
  @moduledoc """
  Executes evaluated `elm/http` command descriptors for the debugger.
  """

  alias Elmx.Runtime.Json.Decode, as: JsonDecode
  alias Ide.Debugger.HttpSimulator
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.Types

  @default_timeout_ms 10_000

  @type command :: Types.cmd_call()
  @type http_response :: Types.http_simulated_response()
  @type execute_result :: %{
          required(String.t()) => Types.subscription_payload() | String.t() | http_response()
        }
  @type result :: {:ok, execute_result()} | {:error, Types.http_executor_error()}

  @spec execute(command(), Types.eval_context()) :: result()
  def execute(command, eval_context \\ %{})

  def execute(command, eval_context) when is_map(command) and is_map(eval_context) do
    with {:ok, response} <- request(command, eval_context),
         {:ok, message_value} <- decode_http_response(command, response, eval_context) do
      {:ok,
       %{
         "message_value" => message_value,
         "message" => display_message(message_value),
         "response" => response
       }}
    end
  end

  def execute(_command, _eval_context), do: {:error, :invalid_http_command}

  @spec request(command(), Types.eval_context()) ::
          {:ok, http_response()} | {:error, Types.http_executor_error()}
  defp request(command, eval_context) when is_map(eval_context) do
    weather =
      Map.get(eval_context, :simulator_weather) || Map.get(eval_context, "simulator_weather")

    case HttpSimulator.simulated_response(command, weather) do
      {:ok, response} ->
        {:ok, response}

      :skip ->
        configured_request(command)
    end
  end

  @spec configured_request(command()) ::
          {:ok, http_response()} | {:error, Types.http_executor_error()}
  defp configured_request(command) do
    request_fun = Application.get_env(:ide, __MODULE__, []) |> Keyword.get(:request_fun)

    if is_function(request_fun, 1) do
      request_fun.(command)
    else
      run_default_request(command)
    end
  end

  @spec run_default_request(command()) :: {:ok, http_response()}
  defp run_default_request(command) do
    options = req_options(command)

    case Req.request(options) do
      {:ok, %Req.Response{} = response} ->
        {:ok,
         %{
           "status" => response.status,
           "body" => response_body(response.body),
           "headers" => response.headers
         }}

      {:error, %Mint.TransportError{reason: :timeout}} ->
        {:ok, %{"error" => %{"ctor" => "Timeout", "args" => []}}}

      {:error, %Mint.TransportError{reason: :nxdomain}} ->
        {:ok, %{"error" => %{"ctor" => "BadUrl", "args" => [map_value(command, "url") || ""]}}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:ok, %{"error" => %{"ctor" => "Timeout", "args" => []}}}

      {:error, %Req.TransportError{reason: :nxdomain}} ->
        {:ok, %{"error" => %{"ctor" => "BadUrl", "args" => [map_value(command, "url") || ""]}}}

      {:error, reason} ->
        {:ok, %{"error" => %{"ctor" => "NetworkError", "args" => [inspect(reason)]}}}
    end
  end

  @spec req_options(command()) :: keyword()
  defp req_options(command) do
    method =
      command
      |> map_value("method")
      |> to_string()
      |> String.downcase()
      |> String.to_atom()

    body = map_value(command, "body")

    [
      method: method,
      url: map_value(command, "url") || "",
      headers: request_headers(command),
      body: request_body(body),
      receive_timeout: request_timeout(command),
      retry: false
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  @spec request_headers(command()) :: [{String.t(), String.t()}]
  defp request_headers(command) do
    explicit =
      command
      |> map_value("headers")
      |> case do
        headers when is_list(headers) ->
          Enum.flat_map(headers, fn
            %{} = header ->
              name = map_value(header, "name")
              value = map_value(header, "value")
              if is_binary(name) and name != "", do: [{name, to_string(value || "")}], else: []

            _ ->
              []
          end)

        _ ->
          []
      end

    case map_value(map_value(command, "body") || %{}, "content_type") do
      content_type when is_binary(content_type) and content_type != "" ->
        if Enum.any?(explicit, fn {name, _} -> String.downcase(name) == "content-type" end) do
          explicit
        else
          [{"content-type", content_type} | explicit]
        end

      _ ->
        explicit
    end
  end

  @type wire_value :: Types.wire_input()

  @spec request_body(Types.wire_map() | nil) :: String.t() | nil
  defp request_body(%{} = body) do
    case map_value(body, "kind") do
      "empty" -> nil
      _ -> map_value(body, "body") || ""
    end
  end

  defp request_body(_), do: nil

  @spec request_timeout(command()) :: pos_integer()
  defp request_timeout(command) do
    case map_value(command, "timeout") do
      seconds when is_number(seconds) and seconds > 0 -> round(seconds * 1000)
      _ -> @default_timeout_ms
    end
  end

  @spec response_body(String.t() | Types.wire_map() | list() | nil) :: String.t()
  defp response_body(body) when is_binary(body), do: body

  defp response_body(body) do
    case Jason.encode(body) do
      {:ok, encoded} -> encoded
      _ -> to_string(body || "")
    end
  end

  @spec decode_http_response(command(), http_response(), Types.eval_context()) ::
          {:ok, Types.protocol_message_wire_value()} | {:error, Types.http_executor_error()}
  defp decode_http_response(command, response, eval_context)
       when is_map(command) and is_map(response) and is_map(eval_context) do
    expect = map_value(command, "expect") || %{}
    to_msg = message_name(map_value(expect, "to_msg") || map_value(command, "message"))
    kind = map_value(expect, "kind") || "string"
    decoder = map_value(expect, "decoder")

    {:ok, %{"ctor" => to_msg, "args" => [http_result(kind, response, decoder, eval_context)]}}
  end

  defp decode_http_response(_command, _response, _eval_context),
    do: {:error, :invalid_http_command}

  @spec http_result(String.t(), http_response(), term(), Types.eval_context()) ::
          Types.protocol_ctor_value()
  defp http_result(kind, response, decoder, eval_context) when is_map(response) do
    case map_value(response, "error") do
      %{} = error ->
        %{"ctor" => "Err", "args" => [http_error(error)]}

      _ ->
        status = map_value(response, "status") || 0
        body = map_value(response, "body") || ""

        if is_integer(status) and status >= 200 and status < 300 do
          case decode_success_body(kind, body, decoder, eval_context) do
            {:ok, decoded} ->
              %{"ctor" => "Ok", "args" => [decoded]}

            {:error, {:bad_body, bad_body}} ->
              %{"ctor" => "Err", "args" => [%{"ctor" => "BadBody", "args" => [bad_body]}]}
          end
        else
          %{
            "ctor" => "Err",
            "args" => [
              %{
                "ctor" => "BadStatus",
                "args" => [
                  %{"url" => "", "status" => %{"code" => status, "message" => ""}, "body" => body}
                ]
              }
            ]
          }
        end
    end
  end

  @spec decode_success_body(String.t(), String.t(), term(), Types.eval_context()) ::
          {:ok, Types.wire_value()} | {:error, {:bad_body, String.t()}}
  defp decode_success_body(kind, body, decoder, eval_context) when kind in ["json", :json] do
    body_text = to_string(body || "")

    cond do
      match?({:json_decoder, _}, decoder) ->
        case JsonDecode.decode_value(decoder, body_text) do
          {:Ok, decoded} -> {:ok, normalize_json_decoded_body(decoded, eval_context)}
          {:Err, _} -> {:error, {:bad_body, body_text}}
        end

      true ->
        case Jason.decode(body_text) do
          {:ok, decoded} ->
            {:ok, normalize_json_decoded_body(decoded, eval_context)}

          _ ->
            {:error, {:bad_body, body_text}}
        end
    end
  end

  defp decode_success_body(_kind, body, _decoder, _eval_context),
    do: {:ok, to_string(body || "")}

  @spec normalize_json_decoded_body(Types.wire_value(), Types.eval_context()) :: Types.wire_value()
  defp normalize_json_decoded_body(decoded, eval_context) when is_map(decoded) do
    weather =
      Map.get(eval_context, :simulator_weather) || Map.get(eval_context, "simulator_weather")

    cond do
      weather_report_field_swap?(decoded) ->
        %{
          "temperature" => Map.get(decoded, "condition"),
          "condition" => wire_enum_ctor(Map.get(decoded, "temperature"))
        }

      is_map(weather) and map_size(weather) > 0 and weather_report_shape?(decoded) ->
        %{
          "temperature" => Map.get(weather, "temperatureC", 0) * 1.0,
          "condition" =>
            ProtocolEvents.weather_condition_from_settings(%{"weather" => weather})
        }

      true ->
        decoded
    end
  end

  defp normalize_json_decoded_body(decoded, _eval_context), do: decoded

  defp weather_report_field_swap?(%{"condition" => c, "temperature" => t})
       when is_number(c) and not is_number(t),
       do: true

  defp weather_report_field_swap?(_decoded), do: false

  defp weather_report_shape?(%{"temperature" => _, "condition" => _}), do: true
  defp weather_report_shape?(_decoded), do: false

  defp wire_enum_ctor(%{"ctor" => _} = value), do: value

  defp wire_enum_ctor(atom) when is_atom(atom),
    do: %{"ctor" => Atom.to_string(atom), "args" => []}

  defp wire_enum_ctor(_other), do: %{"ctor" => "Clear", "args" => []}

  @spec http_error(Types.wire_map()) :: Types.protocol_ctor_value()
  defp http_error(%{"ctor" => ctor, "args" => args}) when is_binary(ctor) and is_list(args),
    do: %{"ctor" => ctor, "args" => args}

  defp http_error(%{ctor: ctor, args: args}) when is_atom(ctor) and is_list(args),
    do: %{"ctor" => Atom.to_string(ctor), "args" => args}

  defp http_error(error) when is_map(error),
    do: %{"ctor" => "NetworkError", "args" => [inspect(error)]}

  @spec message_name(term()) :: String.t()
  defp message_name({:function_ref, name}) when is_binary(name), do: name
  defp message_name({:function_ref, _module, name}) when is_binary(name), do: name
  defp message_name(%{"ctor" => ctor}) when is_binary(ctor), do: ctor
  defp message_name(%{ctor: ctor}) when is_atom(ctor), do: Atom.to_string(ctor)
  defp message_name(value) when is_binary(value), do: value
  defp message_name(value) when is_atom(value), do: Atom.to_string(value)
  defp message_name(_value), do: "HttpResponse"

  @spec display_message(Types.protocol_message_wire_value() | String.t() | nil) :: String.t()
  defp display_message(%{"ctor" => ctor, "args" => args})
       when is_binary(ctor) and is_list(args) do
    args_text =
      args
      |> Enum.map(&inspect/1)
      |> Enum.join(" ")

    if args_text == "", do: ctor, else: "#{ctor} #{args_text}"
  end

  defp display_message(value), do: inspect(value)

  @spec map_value(Types.wire_map(), String.t()) :: wire_value()
  defp map_value(map, key) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        try do
          Map.get(map, String.to_existing_atom(key))
        rescue
          ArgumentError -> nil
        end
    end
  end

  defp map_value(_map, _key), do: nil
end
