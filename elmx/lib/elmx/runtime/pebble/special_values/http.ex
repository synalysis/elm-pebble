defmodule Elmx.Runtime.Pebble.SpecialValues.Http do
  @moduledoc false

  import Elmx.Runtime.Pebble.SpecialValues.Helpers

  alias Elmx.Types

  @spec rewrite(String.t(), Types.ir_arg_list()) :: Types.dispatch_result()
  def rewrite(target, args) when is_binary(target) and is_list(args) do
    case target do
      "Http.get" -> ui_call("elmx_http_get", args)
      "Http.post" -> ui_call("elmx_http_post", args)
      "Http.request" -> ui_call("elmx_http_request", args)
      "Http.expectString" -> expect_string(args)
      "Http.expectJson" -> expect_json(args)
      "Http.header" -> ui_call("elmx_http_header", args)
      "Http.stringBody" -> ui_call("elmx_http_string_body", args)
      "Http.emptyBody" -> ui_call("elmx_http_empty_body", args)
      _ -> :unmatched
    end
  end

  defp expect_string([to_msg, req]) do
    ui_call("elmx_http_expect_string", [to_msg, req])
  end

  defp expect_string([to_msg]) do
    ui_call("elmx_http_expect_string", [to_msg])
  end

  defp expect_string(_), do: :error

  defp expect_json([decoder, to_msg, req]) do
    ui_call("elmx_http_expect_json", [decoder, to_msg, req])
  end

  defp expect_json([decoder, to_msg]) do
    ui_call("elmx_http_expect_json", [decoder, to_msg])
  end

  defp expect_json(_), do: :error
end
