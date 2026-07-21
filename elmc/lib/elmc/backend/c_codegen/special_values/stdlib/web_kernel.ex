defmodule Elmc.Backend.CCodegen.SpecialValues.Stdlib.WebKernel do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues.Helpers
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.Plan.Lower.Platform.Web, as: PlatformWeb
  alias Elmc.Backend.Wasm.WebKernelDiagnostics

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  defp http_track_dom_sub(tracker, toMsg) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{
        op: :dom_sub,
        kind: %{op: :int_literal, value: 9},
        params: [tracker, toMsg]
      }
    else
      nil
    end
  end

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()

  # --- Pages.Internal.String → String (elm-pages shims) ---
  for {from, to} <- [
        {"Pages.Internal.String.dropLeft", "String.dropLeft"},
        {"Pages.Internal.String.dropRight", "String.dropRight"},
        {"Pages.Internal.String.endsWith", "String.endsWith"},
        {"Pages.Internal.String.fromInt", "String.fromInt"},
        {"Pages.Internal.String.join", "String.join"},
        {"Pages.Internal.String.split", "String.split"},
        {"Pages.Internal.String.startsWith", "String.startsWith"},
        {"Pages.Internal.String.chopEnd", "String.chopEnd"},
        {"Pages.Internal.String.chopStart", "String.chopStart"},
        {"Pages.Internal.String.chopForwardSlashes", "String.chopForwardSlashes"}
      ] do
    def special_value_from_target(unquote(from), args),
      do: special_value_from_target(unquote(to), args)
  end

  # --- Array / JsArray kernel aliases ---
  def special_value_from_target("Array.unsafeGet", []),
    do: Helpers.runtime_fn_lambda("elmc_array_get", ["__index", "__array"])

  def special_value_from_target("Array.unsafeSet", []),
    do: Helpers.runtime_fn_lambda("elmc_array_set", ["__index", "__value", "__array"])

  def special_value_from_target("Array.singleton", [value]),
    do: %{op: :runtime_call, function: "elmc_array_initialize", args: [%{op: :int_literal, value: 1}, value]}

  def special_value_from_target("Array.singleton", []),
    do: Helpers.runtime_fn_lambda("elmc_array_initialize", ["__n", "__value"])

  # --- List ↔ Array ---
  def special_value_from_target("List.fromArray", [array]),
    do: %{op: :runtime_call, function: "elmc_array_to_list", args: [array]}

  def special_value_from_target("List.fromArray", []),
    do: Helpers.runtime_fn_lambda("elmc_array_to_list", ["__array"])

  def special_value_from_target("List.toArray", [list]),
    do: %{op: :runtime_call, function: "elmc_array_from_list", args: [list]}

  def special_value_from_target("List.toArray", []),
    do: Helpers.runtime_fn_lambda("elmc_array_from_list", ["__list"])

  # --- String ---
  def special_value_from_target("String.fromNumber", [n]),
    do: %{op: :runtime_call, function: "elmc_string_from_float", args: [n]}

  def special_value_from_target("String.fromNumber", []),
    do: Helpers.runtime_fn_lambda("elmc_string_from_float", ["__n"])

  # --- elm-pages String shims (not in elm/core) ---
  def special_value_from_target("String.chopEnd", [str, suffix]),
    do: %{op: :runtime_call, function: "elmc_string_chop_end", args: [str, suffix]}

  def special_value_from_target("String.chopEnd", []),
    do: Helpers.runtime_fn_lambda("elmc_string_chop_end", ["__str", "__suffix"])

  def special_value_from_target("String.chopStart", [str, prefix]),
    do: %{op: :runtime_call, function: "elmc_string_chop_start", args: [str, prefix]}

  def special_value_from_target("String.chopStart", []),
    do: Helpers.runtime_fn_lambda("elmc_string_chop_start", ["__str", "__prefix"])

  def special_value_from_target("String.chopForwardSlashes", [str]),
    do: %{op: :runtime_call, function: "elmc_string_chop_forward_slashes", args: [str]}

  def special_value_from_target("String.chopForwardSlashes", []),
    do: Helpers.runtime_fn_lambda("elmc_string_chop_forward_slashes", ["__str"])

  # --- Url ---
  def special_value_from_target("Url.percentEncode", [segment]),
    do: %{op: :runtime_call, function: "elmc_url_percent_encode", args: [segment]}

  def special_value_from_target("Url.percentEncode", []),
    do: Helpers.runtime_fn_lambda("elmc_url_percent_encode", ["__segment"])

  def special_value_from_target("Url.percentDecode", [segment]),
    do: %{op: :runtime_call, function: "elmc_url_percent_decode", args: [segment]}

  def special_value_from_target("Url.percentDecode", []),
    do: Helpers.runtime_fn_lambda("elmc_url_percent_decode", ["__segment"])

  # --- Time ---
  def special_value_from_target("Time.now", _args),
    do: %{op: :runtime_call, function: "elmc_time_now_millis", args: []}

  def special_value_from_target("Time.here", _args),
    do: %{op: :runtime_call, function: "elmc_time_here", args: []}

  def special_value_from_target("Elm.Kernel.Time.now", _args),
    do: %{op: :runtime_call, function: "elmc_time_now_millis", args: []}

  def special_value_from_target("Url.Builder.crossOrigin", [_name]),
    do: %{op: :string_literal, value: "anonymous"}

  def special_value_from_target("Url.fromString", [url]),
    do: %{op: :runtime_call, function: "elmc_url_from_string", args: [url]}

  def special_value_from_target("Url.fromString", []),
    do: Helpers.runtime_fn_lambda("elmc_url_from_string", ["__url"])

  # --- Http kernel (browser) ---
  def special_value_from_target("Http.command", [
        %{op: :tuple2, left: %{union_ctor: "Cancel"}, right: tracker}
      ]),
      do: %{op: :runtime_call, function: "elmc_http_cancel", args: [tracker]}

  def special_value_from_target("Http.command", [req]),
    do: %{op: :runtime_call, function: "elmc_http_command", args: [req]}

  def special_value_from_target("Http.command", []),
    do: Helpers.runtime_fn_lambda("elmc_http_command", ["__req"])

  def special_value_from_target("Http.cancel", [tracker]),
    do: %{op: :runtime_call, function: "elmc_http_cancel", args: [tracker]}

  def special_value_from_target("Http.cancel", []),
    do: Helpers.runtime_fn_lambda("elmc_http_cancel", ["__tracker"])

  def special_value_from_target("Http.subscription", [
        %{
          op: :tuple2,
          left: %{union_ctor: "MySub"},
          right: %{op: :tuple2, left: tracker, right: toMsg}
        }
      ]) do
    http_track_dom_sub(tracker, toMsg)
  end

  def special_value_from_target("Http.track", [tracker, toMsg]) do
    http_track_dom_sub(tracker, toMsg)
  end

  def special_value_from_target("Http.track", []),
    do: nil

  def special_value_from_target("Elm.Kernel.Http.emptyBody", [_req]),
    do: %{op: :runtime_call, function: "elmc_http_empty_body", args: []}

  def special_value_from_target("Elm.Kernel.Http.emptyBody", []),
    do: Helpers.runtime_fn_lambda("elmc_http_empty_body", ["__req"])

  def special_value_from_target("Elm.Kernel.Http.pair", [key, value]),
    do: %{op: :runtime_call, function: "elmc_http_pair", args: [key, value]}

  def special_value_from_target("Elm.Kernel.Http.pair", []),
    do: Helpers.runtime_fn_lambda("elmc_http_pair", ["__key", "__value"])

  def special_value_from_target("Elm.Kernel.Http.toDataView", [body]),
    do: %{op: :runtime_call, function: "elmc_http_to_data_view", args: [body]}

  def special_value_from_target("Elm.Kernel.Http.toDataView", []),
    do: Helpers.runtime_fn_lambda("elmc_http_to_data_view", ["__body"])

  def special_value_from_target("Elm.Kernel.Http.expect", [to_msg, decoder, req]),
    do: %{op: :runtime_call, function: "elmc_http_expect", args: [to_msg, decoder, req]}

  def special_value_from_target("Elm.Kernel.Http.expect", []),
    do: Helpers.runtime_fn_lambda("elmc_http_expect", ["__toMsg", "__decoder", "__req"])

  def special_value_from_target("Http.expect", args),
    do: special_value_from_target("Elm.Kernel.Http.expect", args)

  # --- File kernel (browser) ---
  def special_value_from_target("Elm.Kernel.File.download", [name, mime, content]),
    do: %{
      op: :runtime_call,
      function: "elmc_file_download_task",
      args: [name, mime, content]
    }

  def special_value_from_target("Elm.Kernel.File.download", []),
    do:
      Helpers.runtime_fn_lambda("elmc_file_download_task", ["__name", "__mime", "__content"])

  # --- BackendTask (browser: map to Task stubs; server loaders are DCE'd) ---
  def special_value_from_target("BackendTask.succeed", [value]),
    do: %{op: :runtime_call, function: "elmc_task_succeed", args: [value]}

  def special_value_from_target("BackendTask.succeed", []),
    do: Helpers.runtime_fn_lambda("elmc_task_succeed", ["__value"])

  def special_value_from_target("BackendTask.fail", [value]),
    do: %{op: :runtime_call, function: "elmc_task_fail", args: [value]}

  def special_value_from_target("BackendTask.fail", []),
    do: Helpers.runtime_fn_lambda("elmc_task_fail", ["__value"])

  def special_value_from_target("BackendTask.map", [f, task]),
    do: %{op: :runtime_call, function: "elmc_task_map", args: [f, task]}

  def special_value_from_target("BackendTask.map", []),
    do: Helpers.runtime_fn_lambda("elmc_task_map", ["__f", "__task"])

  def special_value_from_target("BackendTask.map2", [f, a, b]),
    do: %{op: :runtime_call, function: "elmc_task_map2", args: [f, a, b]}

  def special_value_from_target("BackendTask.map2", []),
    do: Helpers.runtime_fn_lambda("elmc_task_map2", ["__f", "__a", "__b"])

  def special_value_from_target("BackendTask.andThen", [f, task]),
    do: %{op: :runtime_call, function: "elmc_task_and_then", args: [f, task]}

  def special_value_from_target("BackendTask.andThen", []),
    do: Helpers.runtime_fn_lambda("elmc_task_and_then", ["__f", "__task"])

  def special_value_from_target("BackendTask.allowFatal", [task]),
    do: task

  def special_value_from_target("BackendTask.allowFatal", []),
    do: %{op: :lambda, args: ["__task"], body: %{op: :var, name: "__task"}}

  def special_value_from_target("BackendTask.combine", [_tasks]),
    do: %{op: :runtime_call, function: "elmc_task_succeed", args: [%{op: :list_literal, items: []}]}

  def special_value_from_target("BackendTask.combine", []),
    do: Helpers.runtime_fn_lambda("elmc_task_succeed", ["__tasks"])

  def special_value_from_target("BackendTask.Http.getJson", [url, decoder]),
    do: %{op: :runtime_call, function: "elmc_backend_task_http_get_json", args: [url, decoder]}

  def special_value_from_target("BackendTask.Http.getJson", []),
    do: Helpers.runtime_fn_lambda("elmc_backend_task_http_get_json", ["__url", "__decoder"])

  def special_value_from_target("BackendTask.Http.get", [url, expect]),
    do: %{op: :runtime_call, function: "elmc_backend_task_http_get", args: [url, expect]}

  def special_value_from_target("BackendTask.Http.get", []),
    do: Helpers.runtime_fn_lambda("elmc_backend_task_http_get", ["__url", "__expect"])

  def special_value_from_target("BackendTask.Http.getWithOptions", [options]) do
    WebKernelDiagnostics.maybe_warn_browser_cache_options(options)

    %{op: :runtime_call, function: "elmc_backend_task_http_get_with_options", args: [options]}
  end

  def special_value_from_target("BackendTask.Http.withMetadata", [combine_fn, original_expect]),
    do: %{
      op: :runtime_call,
      function: "elmc_backend_task_http_with_metadata",
      args: [combine_fn, original_expect]
    }

  def special_value_from_target("BackendTask.Http.withMetadata", []),
    do: Helpers.runtime_fn_lambda("elmc_backend_task_http_with_metadata", ["__combine", "__expect"])

  def special_value_from_target("BackendTask.Http.getWithOptions", []),
    do: Helpers.runtime_fn_lambda("elmc_backend_task_http_get_with_options", ["__options"])

  def special_value_from_target("BackendTask.Http.expectJson", [decoder]),
    do: %{op: :runtime_call, function: "elmc_backend_task_http_expect_json", args: [decoder]}

  def special_value_from_target("BackendTask.Http.expectJson", []),
    do: Helpers.runtime_fn_lambda("elmc_backend_task_http_expect_json", ["__decoder"])

  def special_value_from_target("BackendTask.Http.expectString", _args),
    do: %{op: :runtime_call, function: "elmc_backend_task_http_expect_string", args: []}

  def special_value_from_target("BackendTask.Http.expectWhatever", [value]),
    do: %{op: :runtime_call, function: "elmc_backend_task_http_expect_whatever", args: [value]}

  def special_value_from_target("BackendTask.Http.expectWhatever", []),
    do: Helpers.runtime_fn_lambda("elmc_backend_task_http_expect_whatever", ["__value"])

  def special_value_from_target("BackendTask.Http.expectBytes", [decoder]),
    do: %{op: :runtime_call, function: "elmc_backend_task_http_expect_bytes", args: [decoder]}

  def special_value_from_target("BackendTask.Http.expectBytes", []),
    do: Helpers.runtime_fn_lambda("elmc_backend_task_http_expect_bytes", ["__decoder"])

  def special_value_from_target("BackendTask.Http.emptyBody", _args),
    do: %{op: :runtime_call, function: "elmc_backend_task_http_empty_body", args: []}

  def special_value_from_target("BackendTask.Http.stringBody", [content_type, content]),
    do: %{op: :runtime_call, function: "elmc_backend_task_http_string_body", args: [content_type, content]}

  def special_value_from_target("BackendTask.Http.stringBody", []),
    do: Helpers.runtime_fn_lambda("elmc_backend_task_http_string_body", ["__content_type", "__content"])

  def special_value_from_target("BackendTask.Http.jsonBody", [value]),
    do: %{op: :runtime_call, function: "elmc_backend_task_http_json_body", args: [value]}

  def special_value_from_target("BackendTask.Http.jsonBody", []),
    do: Helpers.runtime_fn_lambda("elmc_backend_task_http_json_body", ["__value"])

  def special_value_from_target("BackendTask.Http.bytesBody", [content_type, content]),
    do: %{op: :runtime_call, function: "elmc_backend_task_http_bytes_body", args: [content_type, content]}

  def special_value_from_target("BackendTask.Http.bytesBody", []),
    do: Helpers.runtime_fn_lambda("elmc_backend_task_http_bytes_body", ["__content_type", "__content"])

  def special_value_from_target("BackendTask.Http.request", [req, expect]),
    do: %{op: :runtime_call, function: "elmc_backend_task_http_request", args: [req, expect]}

  def special_value_from_target("BackendTask.Http.request", []),
    do: Helpers.runtime_fn_lambda("elmc_backend_task_http_request", ["__req", "__expect"])

  def special_value_from_target("BackendTask.Http.post", [url, body, expect]),
    do: %{op: :runtime_call, function: "elmc_backend_task_http_post", args: [url, body, expect]}

  def special_value_from_target("BackendTask.Http.post", []),
    do: Helpers.runtime_fn_lambda("elmc_backend_task_http_post", ["__url", "__body", "__expect"])

  def special_value_from_target("BackendTask.File.jsonFile", args) when is_list(args),
    do: %{op: :runtime_call, function: "elmc_task_fail", args: [%{op: :string_literal, value: "BackendTask.File"}]}

  def special_value_from_target("BackendTask.Glob.fromString", args) when is_list(args),
    do: %{op: :runtime_call, function: "elmc_task_succeed", args: [%{op: :list_literal, items: []}]}

  # --- Task ---
  def special_value_from_target("Task.command", [task]),
    do: %{op: :runtime_call, function: "elmc_task_command", args: [task]}

  def special_value_from_target("Task.command", []),
    do: Helpers.runtime_fn_lambda("elmc_task_command", ["__task"])

  # --- Random (browser) ---
  def special_value_from_target("Random.generate", [to_msg, generator]),
    do: %{op: :runtime_call, function: "elmc_random_generate", args: [to_msg, generator]}

  def special_value_from_target("Elm.Kernel.Random.generate", [to_msg, generator]),
    do: %{op: :runtime_call, function: "elmc_random_generate", args: [to_msg, generator]}

  # --- File (browser) ---
  def special_value_from_target("Elm.Kernel.File.select", [to_msg, accept]),
    do: %{op: :runtime_call, function: "elmc_file_select", args: [to_msg, accept]}

  def special_value_from_target("Elm.Kernel.File.select", []),
    do: Helpers.runtime_fn_lambda("elmc_file_select", ["__toMsg", "__accept"])

  # --- Regex (browser) ---
  def special_value_from_target("Elm.Kernel.Regex.fromString", [pattern]),
    do: %{op: :runtime_call, function: "elmc_regex_from_string", args: [pattern]}

  def special_value_from_target("Elm.Kernel.Regex.fromString", []),
    do: Helpers.runtime_fn_lambda("elmc_regex_from_string", ["__pattern"])

  def special_value_from_target("Elm.Kernel.Regex.find", [regex, string]),
    do: %{op: :runtime_call, function: "elmc_regex_find", args: [regex, string]}

  def special_value_from_target("Elm.Kernel.Regex.find", []),
    do: Helpers.runtime_fn_lambda("elmc_regex_find", ["__regex", "__string"])

  def special_value_from_target("Elm.Kernel.Regex.contains", [regex, string]),
    do: %{op: :runtime_call, function: "elmc_regex_contains", args: [regex, string]}

  def special_value_from_target("Elm.Kernel.Regex.contains", []),
    do: Helpers.runtime_fn_lambda("elmc_regex_contains", ["__regex", "__string"])

  def special_value_from_target("Elm.Kernel.Regex.replace", [regex, replacement, string]),
    do: %{op: :runtime_call, function: "elmc_regex_replace", args: [regex, replacement, string]}

  def special_value_from_target("Elm.Kernel.Regex.replace", []),
    do: Helpers.runtime_fn_lambda("elmc_regex_replace", ["__regex", "__replacement", "__string"])

  def special_value_from_target(_target, _args), do: nil
end
