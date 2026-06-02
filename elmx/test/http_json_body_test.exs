defmodule Elmx.HttpJsonBodyTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Http
  alias Elmx.Runtime.Json.Encode

  test "Http.jsonBody builds json request body wire map" do
    value = Encode.object([{"x", Encode.int(1)}])

    assert %{"kind" => "json", "content_type" => "application/json", "body" => body} =
             Http.json_body([value])

    assert is_binary(body)
    assert String.contains?(body, "x")
  end

  test "special value rewrite for Http.jsonBody" do
    value = Encode.object([])

    assert {:ok, %{op: :runtime_call, function: "elmx_http_json_body"}} =
             Elmx.Runtime.Pebble.SpecialValues.Http.rewrite("Http.jsonBody", [value])
  end
end
