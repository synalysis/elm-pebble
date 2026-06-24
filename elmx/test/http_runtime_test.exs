defmodule Elmx.HttpRuntimeTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Http
  alias Elmx.Runtime.LaunchContext

  test "Http.get builds elm/http command with string expect" do
    expect = Http.expect_string(["CatalogReceived"])

    cmd =
      Http.get([
        %{
          "url" => "https://example.test/data.json",
          "expect" => expect
        }
      ])

    assert cmd["kind"] == "http"
    assert cmd["package"] == "elm/http"
    assert cmd["method"] == "GET"
    assert cmd["url"] == "https://example.test/data.json"
    assert cmd["expect"]["kind"] == "string"
    assert cmd["expect"]["to_msg"] == "CatalogReceived"
  end

  test "Http.expectString preserves Msg constructor callback tag" do
    svg_received = fn result -> {:SvgReceived, result} end

    cmd =
      Http.get([
        %{
          "url" => "https://example.test/figure.svg",
          "expect" => Http.expect_string([svg_received])
        }
      ])

    assert cmd["expect"]["to_msg"] == "SvgReceived"
  end

  test "Http.expectJson accepts decoder and toMsg in either order" do
    decoder = {:json_decoder, {:field, "temperature_2m", {:json_decoder, :float}}}

    swapped =
      Http.expect_json([
        "WeatherReceived",
        decoder
      ])

    assert swapped["to_msg"] == "WeatherReceived"
    assert swapped["decoder"] == decoder

    canonical =
      Http.expect_json([
        decoder,
        "WeatherReceived"
      ])

    assert canonical["to_msg"] == "WeatherReceived"
    assert canonical["decoder"] == decoder
  end

  test "LaunchContext.launch_screen includes legacy is_color and is_round booleans" do
    screen =
      LaunchContext.normalize(%{
        "screen" => %{
          "width" => 144,
          "height" => 168,
          "shape" => "Round",
          "color_mode" => "BlackWhite"
        }
      })
      |> Map.fetch!("screen")

    assert screen["is_round"] == true
    assert screen["is_color"] == false
  end
end
