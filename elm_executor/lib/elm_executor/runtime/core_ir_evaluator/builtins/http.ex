defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Http do
  @moduledoc false

  @spec eval(String.t(), term()) :: {:ok, term()} | :no_builtin
  def eval("get", [request]) when is_map(request) do
    {:ok,
     request_descriptor(
       "GET",
       field_value(request, "url"),
       [],
       body("empty"),
       field_value(request, "expect"),
       nil,
       nil
     )}
  end

  def eval("post", [request]) when is_map(request) do
    {:ok,
     request_descriptor(
       "POST",
       field_value(request, "url"),
       [],
       field_value(request, "body") || body("empty"),
       field_value(request, "expect"),
       nil,
       nil
     )}
  end

  def eval("request", [request]) when is_map(request) do
    {:ok,
     request_descriptor(
       field_value(request, "method") || "GET",
       field_value(request, "url"),
       field_value(request, "headers") || [],
       field_value(request, "body") || body("empty"),
       field_value(request, "expect"),
       field_value(request, "timeout"),
       field_value(request, "tracker")
     )}
  end

  def eval("send", [to_msg, request]) when is_map(request),
    do: {:ok, put_expect_to_msg(request, to_msg)}

  def eval("expectstring", [to_msg]), do: {:ok, expect("string", to_msg, nil)}
  def eval("expectjson", [to_msg, decoder]), do: {:ok, expect("json", to_msg, decoder)}
  def eval("expectwhatever", [to_msg]), do: {:ok, expect("whatever", to_msg, nil)}
  def eval("emptybody", []), do: {:ok, body("empty")}

  def eval("stringbody", [content_type, request_body]) when is_binary(content_type) do
    {:ok,
     body("string", %{"content_type" => content_type, "body" => to_string(request_body || "")})}
  end

  def eval("jsonbody", [value]) do
    request_body =
      case Jason.encode(value) do
        {:ok, encoded} -> encoded
        _ -> "null"
      end

    {:ok,
     body("json", %{
       "content_type" => "application/json",
       "body" => request_body,
       "json" => value
     })}
  end

  def eval("header", [name, value]) when is_binary(name),
    do: {:ok, %{"name" => name, "value" => to_string(value || "")}}

  def eval(_function_name, _values), do: :no_builtin

  @spec request_descriptor(term(), term(), term(), term(), term(), term(), term()) :: map()
  defp request_descriptor(method, url, headers, request_body, expect, timeout, tracker) do
    %{
      "kind" => "http",
      "package" => "elm/http",
      "method" => method |> to_string() |> String.upcase(),
      "url" => to_string(url || ""),
      "headers" => normalize_headers(headers),
      "body" => normalize_body(request_body),
      "expect" => normalize_expect(expect),
      "timeout" => maybe_option_value(timeout),
      "tracker" => maybe_option_value(tracker)
    }
  end

  @spec expect(String.t(), term(), term()) :: map()
  defp expect(kind, to_msg, decoder),
    do: %{"kind" => kind, "to_msg" => to_msg, "decoder" => decoder}

  @spec body(String.t(), map()) :: map()
  defp body(kind, fields \\ %{}) when is_binary(kind) and is_map(fields),
    do: Map.put(fields, "kind", kind)

  @spec normalize_headers(term()) :: [map()]
  defp normalize_headers(headers) when is_list(headers) do
    headers
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn header ->
      %{
        "name" => to_string(field_value(header, "name") || ""),
        "value" => to_string(field_value(header, "value") || "")
      }
    end)
    |> Enum.reject(&(Map.get(&1, "name") == ""))
  end

  defp normalize_headers(_), do: []

  @spec normalize_body(term()) :: map()
  defp normalize_body(%{} = request_body) do
    %{
      "kind" => to_string(field_value(request_body, "kind") || "empty"),
      "content_type" => field_value(request_body, "content_type"),
      "body" => to_string(field_value(request_body, "body") || ""),
      "json" => field_value(request_body, "json")
    }
  end

  defp normalize_body(_), do: body("empty")

  @spec normalize_expect(term()) :: map() | nil
  defp normalize_expect(%{} = expect) do
    %{
      "kind" => to_string(field_value(expect, "kind") || "whatever"),
      "to_msg" => field_value(expect, "to_msg"),
      "decoder" => field_value(expect, "decoder")
    }
  end

  defp normalize_expect(_), do: nil

  @spec put_expect_to_msg(map(), term()) :: map()
  defp put_expect_to_msg(request, to_msg) when is_map(request) do
    expect =
      request
      |> field_value("expect")
      |> case do
        %{} = existing -> Map.put(existing, "to_msg", to_msg)
        _ -> expect("whatever", to_msg, nil)
      end

    Map.put(request, "expect", normalize_expect(expect))
  end

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

  @spec maybe_option_value(term()) :: term()
  defp maybe_option_value(nil), do: nil
  defp maybe_option_value(%{"ctor" => "Just", "args" => [value]}), do: value
  defp maybe_option_value(%{ctor: "Just", args: [value]}), do: value
  defp maybe_option_value(%{"ctor" => "Nothing"}), do: nil
  defp maybe_option_value(%{ctor: "Nothing"}), do: nil
  defp maybe_option_value(value), do: value
end
