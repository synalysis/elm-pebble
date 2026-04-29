defmodule Ide.Debugger.HttpExecutorTest do
  use ExUnit.Case, async: false

  alias Ide.Debugger.HttpExecutor

  setup do
    previous = Application.get_env(:ide, HttpExecutor)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:ide, HttpExecutor)
      else
        Application.put_env(:ide, HttpExecutor, previous)
      end
    end)
  end

  test "executes injected HTTP request and decodes expectJson callback" do
    command = json_command()

    Application.put_env(:ide, HttpExecutor,
      request_fun: fn ^command ->
        {:ok, %{"status" => 200, "body" => ~s({"temperature":18})}}
      end
    )

    assert {:ok, result} = HttpExecutor.execute(command)

    assert result["message_value"] == %{
             "ctor" => "WeatherReceived",
             "args" => [%{"ctor" => "Ok", "args" => [18]}]
           }
  end

  test "maps bad status to Elm Http.BadStatus" do
    command = json_command()

    Application.put_env(:ide, HttpExecutor,
      request_fun: fn ^command ->
        {:ok, %{"status" => 503, "body" => "unavailable"}}
      end
    )

    assert {:ok, result} = HttpExecutor.execute(command)

    assert result["message_value"] == %{
             "ctor" => "WeatherReceived",
             "args" => [%{"ctor" => "Err", "args" => [%{"ctor" => "BadStatus", "args" => [503]}]}]
           }
  end

  test "maps bad JSON to Elm Http.BadBody" do
    command = json_command()

    Application.put_env(:ide, HttpExecutor,
      request_fun: fn ^command ->
        {:ok, %{"status" => 200, "body" => "not json"}}
      end
    )

    assert {:ok, result} = HttpExecutor.execute(command)

    assert %{"ctor" => "WeatherReceived", "args" => [%{"ctor" => "Err", "args" => [error]}]} =
             result["message_value"]

    assert error["ctor"] == "BadBody"
  end

  test "maps normalized network errors to Elm Http.NetworkError" do
    command = json_command()

    Application.put_env(:ide, HttpExecutor,
      request_fun: fn ^command ->
        {:ok, %{"error" => %{"ctor" => "NetworkError", "args" => []}}}
      end
    )

    assert {:ok, result} = HttpExecutor.execute(command)

    assert result["message_value"] == %{
             "ctor" => "WeatherReceived",
             "args" => [%{"ctor" => "Err", "args" => [%{"ctor" => "NetworkError", "args" => []}]}]
           }
  end

  defp json_command do
    %{
      "kind" => "http",
      "method" => "GET",
      "url" => "https://example.test/weather",
      "headers" => [],
      "body" => %{"kind" => "empty"},
      "expect" => %{
        "kind" => "json",
        "to_msg" => {:function_ref, "WeatherReceived"},
        "decoder" => {:json_decoder, {:field, "temperature", {:json_decoder, :float}}}
      }
    }
  end
end
