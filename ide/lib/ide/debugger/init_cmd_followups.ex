defmodule Ide.Debugger.InitCmdFollowups do
  @moduledoc """
  Derives runtime follow-up rows from parser `init_cmd_calls` when the executor
  does not return matching `followup_messages` (for example init `Http.get` via helpers).
  """

  alias Ide.Debugger.CmdCall
  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.Types

  @spec runtime_followup_rows(Types.elm_introspect()) :: [Types.runtime_followup_row()]
  def runtime_followup_rows(ei) when is_map(ei) do
    ei
    |> IntrospectAccess.cmd_calls("init_cmd_calls")
    |> CmdCall.expand_helpers(ei)
    |> Enum.filter(&http_cmd_call?/1)
    |> Enum.map(&cmd_call_to_followup/1)
    |> Enum.reject(&is_nil/1)
  end

  def runtime_followup_rows(_), do: []

  @spec merge_followups([Types.runtime_followup_row()], Types.elm_introspect()) ::
          [Types.runtime_followup_row()]
  def merge_followups(executor_followups, ei) when is_list(executor_followups) and is_map(ei) do
    init_rows = runtime_followup_rows(ei)

    executor_followups
    |> Enum.concat(init_rows)
    |> dedupe_http_followups()
  end

  def merge_followups(executor_followups, _ei) when is_list(executor_followups),
    do: executor_followups

  @spec http_cmd_call?(Types.cmd_call()) :: boolean()
  defp http_cmd_call?(%{} = row) do
    target = Map.get(row, "target") || Map.get(row, :target) || ""
    name = Map.get(row, "name") || Map.get(row, :name) || ""

    String.starts_with?(target, "Http.") or
      name in ["get", "post", "request", "send"] or
      String.contains?(target, "Http.")
  end

  defp http_cmd_call?(_), do: false

  @spec cmd_call_to_followup(Types.cmd_call()) :: Types.runtime_followup_row() | nil
  defp cmd_call_to_followup(%{} = row) do
    with %{} = command <- http_command_from_cmd_call(row),
         message when is_binary(message) <- callback_message(row) do
      %{
        "message" => message,
        "package" => "elm/http",
        "command" => command
      }
    else
      _ -> nil
    end
  end

  defp cmd_call_to_followup(_), do: nil

  @spec http_command_from_cmd_call(Types.cmd_call()) :: Types.TrackedHttpCommand.wire_map() | nil
  defp http_command_from_cmd_call(%{"target" => target, "arg_values" => [request | _]} = row)
       when is_map(request) and is_binary(target) do
    url = Map.get(request, "url") || Map.get(request, :url)

    if is_binary(url) and String.trim(url) != "" do
      %{
        "kind" => "http",
        "package" => "elm/http",
        "method" => http_method_from_target(target),
        "url" => url,
        "headers" => [],
        "body" => %{"kind" => "empty"},
        "expect" => %{
          "kind" => "string",
          "to_msg" => callback_to_msg_wire(row, request)
        }
      }
    end
  end

  defp http_command_from_cmd_call(_), do: nil

  defp callback_message(%{"callback_constructor" => ctor}) when is_binary(ctor) and ctor != "",
    do: ctor

  defp callback_message(%{"arg_values" => [request | _]}) when is_map(request) do
    request
    |> Map.get("expect")
    |> callback_ctor_from_expect()
  end

  defp callback_message(_), do: nil

  defp callback_ctor_from_expect(%{"$ctor" => ctor}) when is_binary(ctor), do: ctor

  defp callback_ctor_from_expect(%{"$args" => [inner | _]}) when is_map(inner) do
    callback_ctor_from_expect(inner)
  end

  defp callback_ctor_from_expect(%{"$call" => "Http.expectString", "$args" => [inner | _]}) do
    callback_ctor_from_expect(inner)
  end

  defp callback_ctor_from_expect(_), do: nil

  defp callback_to_msg_wire(row, request) do
    case callback_message(row) || callback_ctor_from_expect(Map.get(request, "expect")) do
      ctor when is_binary(ctor) and ctor != "" -> %{"ctor" => ctor, "args" => []}
      _ -> %{"ctor" => "HttpResponse", "args" => []}
    end
  end

  defp http_method_from_target("Http.get"), do: "GET"
  defp http_method_from_target("Http.post"), do: "POST"
  defp http_method_from_target("Http.request"), do: "GET"

  defp http_method_from_target(target) when is_binary(target) do
    target
    |> String.split(".")
    |> List.last()
    |> to_string()
    |> String.upcase()
  end

  defp dedupe_http_followups(rows) when is_list(rows) do
    Enum.reduce(rows, {[], MapSet.new()}, fn row, {acc, seen_urls} ->
      url = row |> Map.get("command") |> http_url()

      cond do
        is_binary(url) and MapSet.member?(seen_urls, url) ->
          {acc, seen_urls}

        is_binary(url) ->
          {[row | acc], MapSet.put(seen_urls, url)}

        true ->
          {[row | acc], seen_urls}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp http_url(%{"url" => url}) when is_binary(url), do: url
  defp http_url(%{url: url}) when is_binary(url), do: url
  defp http_url(_), do: nil
end
