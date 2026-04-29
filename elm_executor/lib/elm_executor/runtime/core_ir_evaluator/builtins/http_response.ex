defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.HttpResponse do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Builtins.JsonKernel

  @spec decode(term(), term(), map()) :: {:ok, term()} | {:error, term()}
  def decode(command, response, ops) when is_map(command) and is_map(response) and is_map(ops) do
    expect = field_value(command, "expect") || %{}

    result =
      case field_value(response, "error") do
        nil -> decode_successful_expect(expect, response, ops)
        error -> {:ok, ops.result_ctor.({:err, normalize_error(error)})}
      end

    with {:ok, http_result} <- result do
      to_message_value(field_value(expect, "to_msg"), http_result, ops)
    end
  end

  def decode(_command, _response, _ops), do: {:error, :invalid_http_response}

  @spec decode_successful_expect(term(), term(), map()) :: {:ok, term()} | {:error, term()}
  defp decode_successful_expect(expect, response, ops)
       when is_map(expect) and is_map(response) and is_map(ops) do
    status = field_value(response, "status")
    body = to_string(field_value(response, "body") || "")

    cond do
      is_integer(status) and (status < 200 or status >= 300) ->
        {:ok, ops.result_ctor.({:err, http_error("BadStatus", [status])})}

      field_value(expect, "kind") == "string" ->
        {:ok, ops.result_ctor.({:ok, body})}

      field_value(expect, "kind") == "json" ->
        with {:ok, json} <- Jason.decode(body),
             {:ok, decoded} <- JsonKernel.decode(field_value(expect, "decoder"), json, ops) do
          {:ok, ops.result_ctor.({:ok, decoded})}
        else
          {:error, reason} ->
            {:ok, ops.result_ctor.({:err, http_error("BadBody", [inspect(reason)])})}
        end

      true ->
        {:ok, ops.result_ctor.({:ok, nil})}
    end
  end

  defp decode_successful_expect(_expect, _response, _ops), do: {:error, :invalid_http_expect}

  @spec to_message_value(term(), term(), map()) :: {:ok, term()} | {:error, term()}
  defp to_message_value(nil, http_result, _ops), do: {:ok, http_result}

  defp to_message_value(to_msg, http_result, ops) when is_map(ops) do
    case ops.call.(to_msg, [http_result]) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> {:ok, ops.constructor_value.(to_msg, [http_result])}
    end
  end

  @spec normalize_error(term()) :: map()
  defp normalize_error(%{} = error) do
    ctor = field_value(error, "ctor") || field_value(error, "kind") || "NetworkError"
    args = field_value(error, "args")
    args = if is_list(args), do: args, else: []
    http_error(to_string(ctor), args)
  end

  defp normalize_error(kind) when is_atom(kind),
    do: http_error(kind |> Atom.to_string() |> camelize_error(), [])

  defp normalize_error(kind) when is_binary(kind), do: http_error(camelize_error(kind), [])
  defp normalize_error(_), do: http_error("NetworkError", [])

  @spec camelize_error(String.t()) :: String.t()
  defp camelize_error("bad_url"), do: "BadUrl"
  defp camelize_error("timeout"), do: "Timeout"
  defp camelize_error("network_error"), do: "NetworkError"
  defp camelize_error("bad_status"), do: "BadStatus"
  defp camelize_error("bad_body"), do: "BadBody"
  defp camelize_error(kind), do: kind

  @spec http_error(String.t(), list()) :: map()
  defp http_error(ctor, args), do: %{"ctor" => ctor, "args" => args}

  @spec field_value(term(), term()) :: term()
  defp field_value(map, key) when is_map(map) and is_binary(key) do
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

  defp field_value(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp field_value(_map, _key), do: nil
end
