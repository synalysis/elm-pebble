defmodule Elmx.Runtime.Http do
  @moduledoc """
  Builds `elm/http` wire commands for debugger execution.
  """

  alias Elmx.Runtime.Values
  alias Elmx.Types

  @spec get(Types.registry_args()) :: Types.wire_cmd()
  def get([record]) when is_map(record) do
    url = field(record, "url")
    expect = field(record, "expect")

    request_descriptor(
      "GET",
      url,
      [],
      empty_body(),
      expect,
      field(record, "timeout"),
      field(record, "tracker")
    )
  end

  def get(_), do: Values.cmd_none()

  @spec post(Types.registry_args()) :: Types.wire_cmd()
  def post([record]) when is_map(record) do
    url = field(record, "url")
    expect = field(record, "expect")

    request_descriptor(
      "POST",
      url,
      [],
      field(record, "body") || empty_body(),
      expect,
      field(record, "timeout"),
      field(record, "tracker")
    )
  end

  def post(_), do: Values.cmd_none()

  @spec request(Types.registry_args()) :: Types.wire_cmd()
  def request([record]) when is_map(record) do
    request_descriptor(
      method_name(field(record, "method")),
      field(record, "url"),
      field(record, "headers") || [],
      field(record, "body") || empty_body(),
      field(record, "expect"),
      field(record, "timeout"),
      field(record, "tracker")
    )
  end

  def request(_), do: Values.cmd_none()

  @spec expect_string(Types.registry_args()) :: Types.http_expect() | Types.wire_cmd()
  def expect_string([to_msg, req]) when is_map(req) do
    put_expect(req, expect_descriptor("string", to_msg, nil))
  end

  def expect_string([to_msg]) do
    expect_descriptor("string", to_msg, nil)
  end

  def expect_string(_), do: expect_descriptor("string", "HttpResponse", nil)

  @spec expect_json(Types.registry_args()) :: Types.http_expect() | Types.wire_cmd()
  def expect_json([first, second, req]) when is_map(req) do
    {decoder, to_msg} = normalize_expect_json_args(first, second)
    put_expect(req, expect_descriptor("json", to_msg, decoder))
  end

  def expect_json([first, second]) do
    {decoder, to_msg} = normalize_expect_json_args(first, second)
    expect_descriptor("json", to_msg, decoder)
  end

  def expect_json(_), do: expect_descriptor("json", "HttpResponse", nil)

  @spec header(Types.registry_args()) :: %{required(String.t()) => String.t()}
  def header([name, value]) when is_binary(name) do
    %{"name" => name, "value" => to_string(value || "")}
  end

  def header(_), do: %{"name" => "", "value" => ""}

  @spec string_body(Types.registry_args()) :: Types.http_body()
  def string_body([content_type, body]) when is_binary(content_type) do
    %{
      "kind" => "string",
      "content_type" => content_type,
      "body" => to_string(body || "")
    }
  end

  def string_body(_), do: empty_body()

  @spec empty_body() :: Types.http_body()
  def empty_body(), do: %{"kind" => "empty"}

  @spec empty_body(Types.registry_args()) :: Types.http_body()
  def empty_body(_args), do: empty_body()

  @spec json_body([Types.json_value()]) :: Types.http_body()
  def json_body([value]) do
    %{
      "kind" => "json",
      "content_type" => "application/json",
      "body" => Elmx.Runtime.Json.Encode.encode(0, value)
    }
  end

  def json_body(_), do: empty_body()

  @spec request_descriptor(
          String.t(),
          String.t() | Types.wire_value(),
          [Types.wire_map()],
          Types.http_body(),
          Types.http_expect() | Types.wire_map() | function(),
          Types.wire_value() | nil,
          Types.wire_value() | nil
        ) :: Types.wire_cmd()
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

  defp expect_descriptor(kind, to_msg, decoder) do
    %{
      "kind" => kind,
      "to_msg" => message_ctor(to_msg),
      "decoder" => decoder
    }
  end

  defp put_expect(req, expect) when is_map(req) do
    Map.put(req, "expect", normalize_expect(expect))
  end

  defp normalize_expect(%{"kind" => _} = expect), do: expect
  defp normalize_expect(%{kind: kind} = expect) when is_binary(kind) or is_atom(kind) do
    normalize_expect(%{"kind" => to_string(kind), "to_msg" => Map.get(expect, :to_msg) || Map.get(expect, "to_msg"), "decoder" => Map.get(expect, :decoder) || Map.get(expect, "decoder")})
  end

  defp normalize_expect(expect) when is_function(expect, 1) do
    # Curried `Http.expectString Msg` applied at GET time — apply to a stub request.
    stub = %{
      "method" => "GET",
      "url" => "",
      "headers" => [],
      "body" => empty_body(),
      "timeout" => nil,
      "tracker" => nil
    }

    case expect.(stub) do
      %{"expect" => nested} when is_map(nested) -> normalize_expect(nested)
      %{expect: nested} when is_map(nested) -> normalize_expect(nested)
      %{"kind" => _} = descriptor -> descriptor
      descriptor when is_map(descriptor) -> normalize_expect(descriptor)
      _ -> %{"kind" => "string", "to_msg" => "HttpResponse", "decoder" => nil}
    end
  end

  defp normalize_expect(_), do: %{"kind" => "whatever", "to_msg" => "HttpResponse", "decoder" => nil}

  defp normalize_headers(headers) when is_list(headers) do
    headers
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn header ->
      %{
        "name" => to_string(field(header, "name") || ""),
        "value" => to_string(field(header, "value") || "")
      }
    end)
    |> Enum.reject(&(Map.get(&1, "name") == ""))
  end

  defp normalize_headers(_), do: []

  defp normalize_body(%{} = body), do: Map.put_new(stringify_keys(body), "kind", Map.get(body, "kind") || "empty")
  defp normalize_body(_), do: empty_body()

  defp method_name(%{"ctor" => ctor, "args" => _}) when is_binary(ctor), do: ctor
  defp method_name(%{ctor: ctor, args: _}) when is_atom(ctor), do: Atom.to_string(ctor)
  defp method_name({ctor, _}) when is_atom(ctor), do: Atom.to_string(ctor)
  defp method_name(method) when is_binary(method), do: method
  defp method_name(_), do: "GET"

  defp message_ctor(%{"ctor" => ctor, "args" => _}) when is_binary(ctor), do: ctor
  defp message_ctor(%{ctor: ctor, args: _}) when is_atom(ctor), do: Atom.to_string(ctor)
  defp message_ctor({ctor, _}) when is_atom(ctor), do: Atom.to_string(ctor)
  defp message_ctor(msg) when is_binary(msg), do: msg
  defp message_ctor(msg) when is_atom(msg), do: Atom.to_string(msg)

  defp message_ctor(fun) when is_function(fun, 1) do
    case Elmx.Runtime.Cmd.Wire.callback_ctor_name(fun) do
      ctor when is_binary(ctor) and ctor != "" -> ctor
      _ -> "HttpResponse"
    end
  end

  defp message_ctor(_), do: "HttpResponse"

  # Apps occasionally pass `(toMsg, decoder)` instead of `(decoder, toMsg)`; pick the
  # json decoder term when only one side carries `{:json_decoder, _}`.
  @type http_expect_arg :: Types.json_decoder() | Types.elm_msg() | Types.elm_value()

  @spec normalize_expect_json_args(http_expect_arg(), http_expect_arg()) ::
          {http_expect_arg(), http_expect_arg()}
  defp normalize_expect_json_args(first, second) do
    cond do
      json_decoder_term?(first) -> {first, second}
      json_decoder_term?(second) -> {second, first}
      true -> {first, second}
    end
  end

  @spec json_decoder_term?(Types.json_decoder() | Types.wire_map()) :: boolean()
  defp json_decoder_term?({:json_decoder, _}), do: true

  defp json_decoder_term?(value) when is_map(value) do
    case Map.get(value, "tag") || Map.get(value, :tag) do
      "json_decoder" -> true
      :json_decoder -> true
      _ -> false
    end
  end

  defp json_decoder_term?(_), do: false

  defp field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp maybe_option_value(nil), do: nil
  defp maybe_option_value(%{"ctor" => "Just", "args" => [value]}), do: value
  defp maybe_option_value(%{ctor: :Just, args: [value]}), do: value
  defp maybe_option_value(%{"ctor" => "Nothing"}), do: nil
  defp maybe_option_value(%{ctor: :Nothing}), do: nil
  defp maybe_option_value(value), do: value

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
