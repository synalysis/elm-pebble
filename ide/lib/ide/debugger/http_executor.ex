defmodule Ide.Debugger.HttpExecutor do
  @moduledoc """
  Executes evaluated `elm/http` command descriptors for the debugger.
  """

  alias ElmExecutor.Runtime.CoreIREvaluator

  @default_timeout_ms 10_000

  @type command :: map()
  @type result :: {:ok, map()} | {:error, term()}

  @spec execute(command(), map()) :: result()
  def execute(command, eval_context \\ %{})

  def execute(command, eval_context) when is_map(command) and is_map(eval_context) do
    with {:ok, response} <- request(command),
         {:ok, message_value} <-
           CoreIREvaluator.decode_http_response(command, response, eval_context) do
      {:ok,
       %{
         "message_value" => message_value,
         "message" => display_message(message_value),
         "response" => response
       }}
    end
  end

  def execute(_command, _eval_context), do: {:error, :invalid_http_command}

  @spec request(command()) :: {:ok, map()} | {:error, term()}
  defp request(command) do
    request_fun = Application.get_env(:ide, __MODULE__, []) |> Keyword.get(:request_fun)

    if is_function(request_fun, 1) do
      request_fun.(command)
    else
      default_request(command)
    end
  end

  @spec default_request(command()) :: {:ok, map()} | {:error, term()}
  defp default_request(command) do
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

  @spec request_body(term()) :: term()
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

  @spec response_body(term()) :: String.t()
  defp response_body(body) when is_binary(body), do: body

  defp response_body(body) do
    case Jason.encode(body) do
      {:ok, encoded} -> encoded
      _ -> to_string(body || "")
    end
  end

  @spec display_message(term()) :: String.t()
  defp display_message(%{"ctor" => ctor, "args" => args})
       when is_binary(ctor) and is_list(args) do
    args_text =
      args
      |> Enum.map(&inspect/1)
      |> Enum.join(" ")

    if args_text == "", do: ctor, else: "#{ctor} #{args_text}"
  end

  defp display_message(value), do: inspect(value)

  @spec map_value(term(), term()) :: term()
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
