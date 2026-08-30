defmodule Elmc.Backend.Plan.Lower.SpecialValues.Stdlib.WebKernel do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias Elmc.Backend.Plan.Lower.SpecialValues.Helpers
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.Plan.Lower.Platform.Web, as: PlatformWeb
  alias Elmc.Backend.Wasm.WebKernelDiagnostics

  @behaviour Elmc.Backend.Plan.Lower.SpecialValues.Handler

  # Official `Regex.find` is `findAtMost` with Elm's `Random.maxInt`.
  @regex_find_all %{op: :int_literal, value: 2_147_483_647}

  @spec http_track_dom_sub(Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

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

  def special_value_from_target("Url.toString", [url]),
    do: %{op: :runtime_call, function: "elmc_url_to_string", args: [url]}

  def special_value_from_target("Url.toString", []),
    do: Helpers.runtime_fn_lambda("elmc_url_to_string", ["__url"])

  def special_value_from_target("Url.Builder.absolute", args) when is_list(args),
    do: runtime_arity("elmc_url_builder_absolute", ["__path", "__query"], args)

  def special_value_from_target("Url.Builder.relative", args) when is_list(args),
    do: runtime_arity("elmc_url_builder_relative", ["__path", "__query"], args)

  def special_value_from_target("Url.Builder.crossOrigin", args) when is_list(args),
    do: runtime_arity("elmc_url_builder_cross_origin", ["__pre", "__path", "__query"], args)

  def special_value_from_target("Url.Builder.custom", args) when is_list(args),
    do: runtime_arity("elmc_url_builder_custom", ["__root", "__path", "__query", "__frag"], args)

  def special_value_from_target("Url.Builder.string", args) when is_list(args),
    do: runtime_arity("elmc_url_builder_query_string", ["__key", "__value"], args)

  def special_value_from_target("Url.Builder.int", args) when is_list(args),
    do: runtime_arity("elmc_url_builder_query_int", ["__key", "__value"], args)

  def special_value_from_target("Url.Builder.toQuery", [params]),
    do: %{op: :runtime_call, function: "elmc_url_builder_to_query", args: [params]}

  def special_value_from_target("Url.Builder.toQuery", []),
    do: Helpers.runtime_fn_lambda("elmc_url_builder_to_query", ["__params"])

  # --- Time ---
  def special_value_from_target("Time.now", _args),
    do: %{op: :runtime_call, function: "elmc_time_now_millis", args: []}

  def special_value_from_target("Time.posixToMillis", [posix]), do: posix

  def special_value_from_target("Time.posixToMillis", []),
    do: %{op: :lambda, args: ["__p"], body: %{op: :var, name: "__p"}}

  def special_value_from_target("Time.millisToPosix", [ms]), do: ms

  def special_value_from_target("Time.millisToPosix", []),
    do: %{op: :lambda, args: ["__ms"], body: %{op: :var, name: "__ms"}}

  def special_value_from_target("Time.utc", _args),
    do: %{op: :runtime_call, function: "elmc_time_utc", args: []}

  def special_value_from_target("Time.customZone", [offset, eras]),
    do: %{op: :runtime_call, function: "elmc_time_custom_zone", args: [offset, eras]}

  def special_value_from_target("Time.customZone", [offset]),
    do: Helpers.runtime_fn_lambda("elmc_time_custom_zone", [offset], ["__eras"])

  def special_value_from_target("Time.customZone", []),
    do: Helpers.runtime_fn_lambda("elmc_time_custom_zone", ["__offset", "__eras"])

  def special_value_from_target("Time.toHour", args) when is_list(args),
    do: time_zone_posix("elmc_time_to_hour", args)

  def special_value_from_target("Time.toMinute", args) when is_list(args),
    do: time_zone_posix("elmc_time_to_minute", args)

  def special_value_from_target("Time.toSecond", args) when is_list(args),
    do: time_zone_posix("elmc_time_to_second", args)

  def special_value_from_target("Time.toMillis", args) when is_list(args),
    do: time_zone_posix("elmc_time_to_millis", args)

  def special_value_from_target("Time.toYear", args) when is_list(args),
    do: time_zone_posix("elmc_time_to_year", args)

  def special_value_from_target("Time.toDay", args) when is_list(args),
    do: time_zone_posix("elmc_time_to_day", args)

  def special_value_from_target("Time.toMonth", args) when is_list(args),
    do: time_zone_posix("elmc_time_to_month", args)

  def special_value_from_target("Time.toWeekday", args) when is_list(args),
    do: time_zone_posix("elmc_time_to_weekday", args)

  def special_value_from_target("Time.here", _args),
    do: %{op: :runtime_call, function: "elmc_time_here", args: []}

  def special_value_from_target("Time.getZoneName", _args),
    do: %{op: :runtime_call, function: "elmc_time_get_zone_name", args: []}

  def special_value_from_target("Elm.Kernel.Time.getZoneName", _args),
    do: %{op: :runtime_call, function: "elmc_time_get_zone_name", args: []}

  def special_value_from_target("Elm.Kernel.Time.now", _args),
    do: %{op: :runtime_call, function: "elmc_time_now_millis", args: []}

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

  def special_value_from_target("Http.request", args) when is_list(args),
    do: runtime_arity("elmc_http_command", ["__req"], args)

  def special_value_from_target("Http.riskyRequest", args) when is_list(args),
    do: runtime_arity("elmc_http_risky_command", ["__req"], args)

  def special_value_from_target("Http.get", args) when is_list(args),
    do: runtime_arity("elmc_http_command", ["__req"], args)

  def special_value_from_target("Http.post", args) when is_list(args),
    do: runtime_arity("elmc_http_command", ["__req"], args)

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

  def special_value_from_target("Http.fractionSent", args) when is_list(args),
    do: runtime_arity("elmc_http_fraction_sent", ["__progress"], args)

  def special_value_from_target("Http.fractionReceived", args) when is_list(args),
    do: runtime_arity("elmc_http_fraction_received", ["__progress"], args)

  def special_value_from_target("Http.emptyBody", _args),
    do: %{op: :runtime_call, function: "elmc_http_empty_body", args: []}

  def special_value_from_target("Http.header", args) when is_list(args),
    do: runtime_arity("elmc_http_pair", ["__key", "__value"], args)

  def special_value_from_target("Http.stringBody", args) when is_list(args),
    do: runtime_arity("elmc_http_pair", ["__mime", "__content"], args)

  def special_value_from_target("Http.bytesBody", args) when is_list(args),
    do: runtime_arity("elmc_http_pair", ["__mime", "__bytes"], args)

  def special_value_from_target("Http.fileBody", args) when is_list(args),
    do: runtime_arity("elmc_http_file_body", ["__file"], args)

  def special_value_from_target("Http.stringPart", args) when is_list(args),
    do: runtime_arity("elmc_http_pair", ["__name", "__value"], args)

  def special_value_from_target("Http.filePart", args) when is_list(args),
    do: runtime_arity("elmc_http_pair", ["__name", "__file"], args)

  def special_value_from_target("Http.bytesPart", args) when is_list(args),
    do: runtime_arity("elmc_http_bytes_part", ["__key", "__mime", "__bytes"], args)

  def special_value_from_target("Http.multipartBody", args) when is_list(args),
    do: runtime_arity("elmc_http_multipart_body", ["__parts"], args)

  def special_value_from_target("Elm.Kernel.Http.toFormData", args) when is_list(args),
    do: runtime_arity("elmc_http_to_form_data", ["__parts"], args)

  def special_value_from_target("Elm.Kernel.Http.bytesToBlob", args) when is_list(args),
    do: runtime_arity("elmc_http_bytes_to_blob", ["__mime", "__bytes"], args)

  def special_value_from_target("Http.jsonBody", [value]),
    do: %{
      op: :runtime_call,
      function: "elmc_http_pair",
      args: [
        %{op: :string_literal, value: "application/json"},
        %{
          op: :runtime_call,
          function: "elmc_json_encode_encode",
          args: [%{op: :int_literal, value: 0}, value]
        }
      ]
    }

  def special_value_from_target("Http.jsonBody", []),
    do: %{
      op: :lambda,
      args: ["__value"],
      body: special_value_from_target("Http.jsonBody", [%{op: :var, name: "__value"}])
    }

  def special_value_from_target("Http.task", args) when is_list(args),
    do: runtime_arity("elmc_http_task", ["__req"], args)

  def special_value_from_target("Http.riskyTask", args) when is_list(args),
    do: runtime_arity("elmc_http_risky_task", ["__req"], args)

  def special_value_from_target("Http.stringResolver", args) when is_list(args),
    do: runtime_arity("elmc_http_string_resolver", ["__toResult"], args)

  def special_value_from_target("Http.bytesResolver", args) when is_list(args),
    do: runtime_arity("elmc_http_bytes_resolver", ["__toResult"], args)

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

  def special_value_from_target("Http.expectString", args) when is_list(args),
    do: runtime_arity("elmc_http_expect_string", ["__toMsg"], args)

  def special_value_from_target("Http.expectJson", args) when is_list(args),
    do: runtime_arity("elmc_http_expect_json", ["__toMsg", "__decoder"], args)

  def special_value_from_target("Http.expectBytes", args) when is_list(args),
    do: runtime_arity("elmc_http_expect_bytes", ["__toMsg", "__decoder"], args)

  def special_value_from_target("Http.expectWhatever", args) when is_list(args),
    do: runtime_arity("elmc_http_expect_whatever", ["__toMsg"], args)

  def special_value_from_target("Http.expectStringResponse", args) when is_list(args),
    do: runtime_arity("elmc_http_expect_string_response", ["__toMsg", "__toResult"], args)

  def special_value_from_target("Http.expectBytesResponse", args) when is_list(args),
    do: runtime_arity("elmc_http_expect_bytes_response", ["__toMsg", "__toResult"], args)

  def special_value_from_target("Elm.Kernel.Http.mapExpect", args) when is_list(args),
    do: runtime_arity("elmc_http_map_expect", ["__func", "__expect"], args)

  def special_value_from_target("Http.mapExpect", args) when is_list(args),
    do: special_value_from_target("Elm.Kernel.Http.mapExpect", args)

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

  # Host Seq construction: plan getWidths releases the shared builders spine before
  # `Seq width builders` retains it (handle reuse → empty encode). Mirror kernel encode.
  def special_value_from_target("Bytes.Encode.sequence", [builders]),
    do: %{op: :runtime_call, function: "elmc_bytes_encode_sequence", args: [builders]}

  def special_value_from_target("Bytes.Encode.sequence", []),
    do: Helpers.runtime_fn_lambda("elmc_bytes_encode_sequence", ["__builders"])

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

  def special_value_from_target("File.Select.file", args) when is_list(args) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      case args do
        [mimes, to_msg] ->
          %{
            op: :runtime_call,
            function: "elmc_file_select",
            args: [to_msg, file_accept_expr(mimes)]
          }

        [mimes] ->
          %{
            op: :lambda,
            args: ["__toMsg"],
            body: %{
              op: :runtime_call,
              function: "elmc_file_select",
              args: [%{op: :var, name: "__toMsg"}, file_accept_expr(mimes)]
            }
          }

        [] ->
          %{
            op: :lambda,
            args: ["__mimes", "__toMsg"],
            body: %{
              op: :runtime_call,
              function: "elmc_file_select",
              args: [%{op: :var, name: "__toMsg"}, %{op: :var, name: "__mimes"}]
            }
          }

        _ ->
          nil
      end
    end
  end

  def special_value_from_target("File.Select.files", args) when is_list(args) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      case args do
        [mimes, to_msg] ->
          %{
            op: :runtime_call,
            function: "elmc_file_select_files",
            args: [to_msg, file_accept_expr(mimes)]
          }

        [mimes] ->
          %{
            op: :lambda,
            args: ["__toMsg"],
            body: %{
              op: :runtime_call,
              function: "elmc_file_select_files",
              args: [%{op: :var, name: "__toMsg"}, file_accept_expr(mimes)]
            }
          }

        [] ->
          %{
            op: :lambda,
            args: ["__mimes", "__toMsg"],
            body: %{
              op: :runtime_call,
              function: "elmc_file_select_files",
              args: [%{op: :var, name: "__toMsg"}, %{op: :var, name: "__mimes"}]
            }
          }

        _ ->
          nil
      end
    end
  end

  def special_value_from_target("File.Download.string", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_file_download", ["__name", "__mime", "__content"], args)

  def special_value_from_target("File.Download.bytes", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_file_download", ["__name", "__mime", "__content"], args)

  def special_value_from_target("File.Download.url", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_file_download_url", ["__href"], args)

  def special_value_from_target("File.decoder", _args) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{op: :runtime_call, function: "elmc_file_decoder", args: []}
    end
  end

  def special_value_from_target("Elm.Kernel.File.decoder", args),
    do: special_value_from_target("File.decoder", args)

  def special_value_from_target("File.name", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_file_name", ["__file"], args)

  def special_value_from_target("File.mime", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_file_mime", ["__file"], args)

  def special_value_from_target("File.size", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_file_size", ["__file"], args)

  def special_value_from_target("File.lastModified", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_file_last_modified", ["__file"], args)

  def special_value_from_target("File.toString", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_file_to_string", ["__file"], args)

  def special_value_from_target("File.toBytes", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_file_to_bytes", ["__file"], args)

  def special_value_from_target("File.toUrl", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_file_to_url", ["__file"], args)

  def special_value_from_target("Elm.Kernel.File.name", args),
    do: special_value_from_target("File.name", args)

  def special_value_from_target("Elm.Kernel.File.mime", args),
    do: special_value_from_target("File.mime", args)

  def special_value_from_target("Elm.Kernel.File.size", args),
    do: special_value_from_target("File.size", args)

  def special_value_from_target("Elm.Kernel.File.lastModified", args),
    do: special_value_from_target("File.lastModified", args)

  def special_value_from_target("Elm.Kernel.File.toString", args),
    do: special_value_from_target("File.toString", args)

  def special_value_from_target("Elm.Kernel.File.toBytes", args),
    do: special_value_from_target("File.toBytes", args)

  def special_value_from_target("Elm.Kernel.File.toUrl", args),
    do: special_value_from_target("File.toUrl", args)

  # Official elm/html: VirtualDom.on + Handler (Normal / MayStop / MayPrevent / Custom).
  def special_value_from_target("Html.Events.stopPropagationOn", args) when is_list(args),
    do: html_handler_event("VirtualDom.MayStopPropagation", args)

  def special_value_from_target("Html.Events.preventDefaultOn", args) when is_list(args),
    do: html_handler_event("VirtualDom.MayPreventDefault", args)

  def special_value_from_target("Html.Events.custom", args) when is_list(args),
    do: html_handler_event("VirtualDom.Custom", args)

  def special_value_from_target("VirtualDom.on", [event, handler]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{
        op: :html_cmd,
        kind: %{op: :int_literal, value: 8},
        params: [event, handler]
      }
    end
  end

  def special_value_from_target("Elm.Kernel.VirtualDom.on", args),
    do: special_value_from_target("VirtualDom.on", args)

  # Official elm/html: onInput / onCheck / onSubmit are Handler+decoder, not a
  # constant-msg listener. onInput always stopPropagation; onSubmit always
  # preventDefault.
  def special_value_from_target("Html.Events.onInput", args) when is_list(args) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      case args do
        [tagger] ->
          official_on_input(tagger)

        [] ->
          %{
            op: :lambda,
            args: ["__tagger"],
            body: official_on_input(%{op: :var, name: "__tagger"})
          }

        _ ->
          nil
      end
    end
  end

  def special_value_from_target("Html.Events.onCheck", args) when is_list(args) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      case args do
        [tagger] ->
          official_on_check(tagger)

        [] ->
          %{
            op: :lambda,
            args: ["__tagger"],
            body: official_on_check(%{op: :var, name: "__tagger"})
          }

        _ ->
          nil
      end
    end
  end

  def special_value_from_target("Html.Events.onSubmit", args) when is_list(args) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      case args do
        [msg] ->
          official_on_submit(msg)

        [] ->
          %{
            op: :lambda,
            args: ["__msg"],
            body: official_on_submit(%{op: :var, name: "__msg"})
          }

        _ ->
          nil
      end
    end
  end

  # --- Regex (browser) ---
  def special_value_from_target("Elm.Kernel.Regex.fromString", [pattern]),
    do: %{op: :runtime_call, function: "elmc_regex_from_string", args: [pattern]}

  def special_value_from_target("Elm.Kernel.Regex.fromString", []),
    do: Helpers.runtime_fn_lambda("elmc_regex_from_string", ["__pattern"])

  def special_value_from_target("Elm.Kernel.Regex.find", [regex, string]),
    do: %{
      op: :runtime_call,
      function: "elmc_regex_find_at_most",
      args: [@regex_find_all, regex, string]
    }

  def special_value_from_target("Elm.Kernel.Regex.find", [regex]),
    do: Helpers.runtime_fn_lambda("elmc_regex_find_at_most", [@regex_find_all, regex], ["__string"])

  def special_value_from_target("Elm.Kernel.Regex.find", []),
    do: Helpers.runtime_fn_lambda("elmc_regex_find_at_most", [@regex_find_all], ["__regex", "__string"])

  def special_value_from_target("Elm.Kernel.Regex.contains", [regex, string]),
    do: %{op: :runtime_call, function: "elmc_regex_contains", args: [regex, string]}

  def special_value_from_target("Elm.Kernel.Regex.contains", []),
    do: Helpers.runtime_fn_lambda("elmc_regex_contains", ["__regex", "__string"])

  def special_value_from_target("Elm.Kernel.Regex.replace", [regex, replacement, string]),
    do: %{op: :runtime_call, function: "elmc_regex_replace", args: [regex, replacement, string]}

  def special_value_from_target("Elm.Kernel.Regex.replace", []),
    do: Helpers.runtime_fn_lambda("elmc_regex_replace", ["__regex", "__replacement", "__string"])

  def special_value_from_target("Elm.Kernel.Regex.fromStringWith", args) when is_list(args),
    do: runtime_arity("elmc_regex_from_string_with", ["__options", "__pattern"], args)

  def special_value_from_target("Elm.Kernel.Regex.split", args) when is_list(args),
    do: runtime_arity("elmc_regex_split", ["__regex", "__string"], args)

  def special_value_from_target("Elm.Kernel.Regex.splitAtMost", args) when is_list(args),
    do: runtime_arity("elmc_regex_split_at_most", ["__n", "__regex", "__string"], args)

  def special_value_from_target("Elm.Kernel.Regex.findAtMost", args) when is_list(args),
    do: runtime_arity("elmc_regex_find_at_most", ["__n", "__regex", "__string"], args)

  def special_value_from_target("Elm.Kernel.Regex.replaceAtMost", args) when is_list(args),
    do: runtime_arity("elmc_regex_replace_at_most", ["__n", "__regex", "__replacer", "__string"], args)

  def special_value_from_target("Regex.fromString", args) when is_list(args),
    do: special_value_from_target("Elm.Kernel.Regex.fromString", args)

  def special_value_from_target("Regex.find", args) when is_list(args),
    do: special_value_from_target("Elm.Kernel.Regex.find", args)

  def special_value_from_target("Regex.contains", args) when is_list(args),
    do: special_value_from_target("Elm.Kernel.Regex.contains", args)

  def special_value_from_target("Regex.replace", args) when is_list(args),
    do: special_value_from_target("Elm.Kernel.Regex.replace", args)

  def special_value_from_target("Regex.fromStringWith", args) when is_list(args),
    do: special_value_from_target("Elm.Kernel.Regex.fromStringWith", args)

  def special_value_from_target("Regex.split", args) when is_list(args),
    do: special_value_from_target("Elm.Kernel.Regex.split", args)

  def special_value_from_target("Regex.splitAtMost", args) when is_list(args),
    do: special_value_from_target("Elm.Kernel.Regex.splitAtMost", args)

  def special_value_from_target("Regex.findAtMost", args) when is_list(args),
    do: special_value_from_target("Elm.Kernel.Regex.findAtMost", args)

  def special_value_from_target("Regex.replaceAtMost", args) when is_list(args),
    do: special_value_from_target("Elm.Kernel.Regex.replaceAtMost", args)

  # Official elm/regex: never = Elm.Kernel.Regex.never (JS /.^/ or /a^/).
  def special_value_from_target("Elm.Kernel.Regex.never", _args),
    do: %{op: :runtime_call, function: "elmc_regex_never", args: []}

  def special_value_from_target("Regex.never", args),
    do: special_value_from_target("Elm.Kernel.Regex.never", args)

  # Float.Extra.interpolateFrom start end t = start + t * (end - start)
  def special_value_from_target("Float.Extra.interpolateFrom", [start, finish, t]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{op: :runtime_call, function: "elmc_float_interpolate_from", args: [start, finish, t]}
    end
  end

  def special_value_from_target("Float.Extra.interpolateFrom", [start, finish]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      Helpers.runtime_fn_lambda("elmc_float_interpolate_from", [start, finish], ["__t"])
    end
  end

  def special_value_from_target("Float.Extra.interpolateFrom", [start]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      Helpers.runtime_fn_lambda("elmc_float_interpolate_from", [start], ["__end", "__t"])
    end
  end

  def special_value_from_target("Float.Extra.interpolateFrom", []) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      Helpers.runtime_fn_lambda("elmc_float_interpolate_from", ["__start", "__end", "__t"])
    end
  end

  def special_value_from_target("Elm.Kernel.WebGL.entity", args) when is_list(args) do
    web_only_runtime(
      "elmc_webgl_entity",
      ["__settings", "__vert", "__frag", "__mesh", "__uniforms"],
      args
    )
  end

  def special_value_from_target("Elm.Kernel.WebGL.toHtml", args) when is_list(args) do
    web_only_runtime("elmc_webgl_to_html", ["__options", "__facts", "__entities"], args)
  end

  # elm-explorations/linear-algebra kernels. Public Math.Vector*/Matrix4
  # wrappers stay as Elm; only Elm.Kernel.MJS.* rewrite to plan builtins.
  for {name, arity} <- Elmc.Backend.Wasm.ImportSignatures.mjs_kernel_value_arities() do
    target = "Elm.Kernel.MJS.#{name}"
    function = "elmc_mjs_#{name}"
    names = Enum.map(0..(arity - 1)//1, fn i -> "__#{i}" end)

    def special_value_from_target(unquote(target), args) when is_list(args) do
      web_only_runtime(unquote(function), unquote(names), args)
    end
  end

  def special_value_from_target(_target, _args), do: nil

  defp file_accept_expr(%{op: :list_literal, items: items}) when is_list(items) do
    joined =
      Enum.map(items, fn
        %{op: :string_literal, value: value} when is_binary(value) -> value
        _ -> nil
      end)

    if Enum.all?(joined, &is_binary/1) do
      %{op: :string_literal, value: Enum.join(joined, ",")}
    else
      %{op: :list_literal, items: items}
    end
  end

  defp file_accept_expr(other), do: other

  defp json_decode_map(f, decoder),
    do: %{op: :runtime_call, function: "elmc_json_decode_map", args: [f, decoder]}

  defp json_decode_succeed(value),
    do: %{op: :runtime_call, function: "elmc_json_decode_succeed", args: [value]}

  defp json_pair_always_true do
    %{
      op: :lambda,
      args: ["__x"],
      body: %{
        op: :tuple2,
        left: %{op: :var, name: "__x"},
        right: %{op: :constructor_call, target: "True", args: []}
      }
    }
  end

  defp html_target_value_decoder do
    %{
      op: :runtime_call,
      function: "elmc_json_decode_at",
      args: [
        %{
          op: :list_literal,
          items: [
            %{op: :string_literal, value: "target"},
            %{op: :string_literal, value: "value"}
          ]
        },
        %{op: :runtime_call, function: "elmc_json_decode_string_decoder", args: []}
      ]
    }
  end

  defp html_target_checked_decoder do
    %{
      op: :runtime_call,
      function: "elmc_json_decode_at",
      args: [
        %{
          op: :list_literal,
          items: [
            %{op: :string_literal, value: "target"},
            %{op: :string_literal, value: "checked"}
          ]
        },
        %{op: :runtime_call, function: "elmc_json_decode_bool_decoder", args: []}
      ]
    }
  end

  defp official_on_input(tagger) do
    html_handler_event("VirtualDom.MayStopPropagation", [
      %{op: :string_literal, value: "input"},
      json_decode_map(json_pair_always_true(), json_decode_map(tagger, html_target_value_decoder()))
    ])
  end

  defp official_on_submit(msg) do
    html_handler_event("VirtualDom.MayPreventDefault", [
      %{op: :string_literal, value: "submit"},
      json_decode_map(json_pair_always_true(), json_decode_succeed(msg))
    ])
  end

  defp official_on_check(tagger) do
    %{
      op: :html_cmd,
      kind: %{op: :int_literal, value: 8},
      params: [
        %{op: :string_literal, value: "change"},
        json_decode_map(tagger, html_target_checked_decoder())
      ]
    }
  end

  defp html_handler_event(ctor, args) when is_binary(ctor) and is_list(args) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      case args do
        [event, decoder] ->
          %{
            op: :html_cmd,
            kind: %{op: :int_literal, value: 8},
            params: [event, %{op: :constructor_call, target: ctor, args: [decoder]}]
          }

        [event] ->
          %{
            op: :lambda,
            args: ["__decoder"],
            body: %{
              op: :html_cmd,
              kind: %{op: :int_literal, value: 8},
              params: [
                event,
                %{
                  op: :constructor_call,
                  target: ctor,
                  args: [%{op: :var, name: "__decoder"}]
                }
              ]
            }
          }

        [] ->
          %{
            op: :lambda,
            args: ["__event", "__decoder"],
            body: %{
              op: :html_cmd,
              kind: %{op: :int_literal, value: 8},
              params: [
                %{op: :var, name: "__event"},
                %{
                  op: :constructor_call,
                  target: ctor,
                  args: [%{op: :var, name: "__decoder"}]
                }
              ]
            }
          }

        _ ->
          nil
      end
    end
  end

  defp runtime_arity(function, names, args)
       when is_binary(function) and is_list(names) and is_list(args) do
    n = length(names)
    taken = Enum.take(args, n)

    cond do
      length(taken) == n ->
        %{op: :runtime_call, function: function, args: taken}

      length(taken) < n ->
        Helpers.runtime_fn_lambda(function, taken, Enum.drop(names, length(taken)))

      true ->
        nil
    end
  end

  defp time_zone_posix(function, args) when is_binary(function) and is_list(args) do
    names = ["__zone", "__posix"]
    taken = Enum.take(args, 2)

    cond do
      length(taken) == 2 ->
        %{op: :runtime_call, function: function, args: taken}

      length(taken) < 2 ->
        Helpers.runtime_fn_lambda(function, taken, Enum.drop(names, length(taken)))

      true ->
        nil
    end
  end

  defp web_only_runtime(function, names, args)
       when is_binary(function) and is_list(names) and is_list(args) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      n = length(names)
      taken = Enum.take(args, n)

      cond do
        length(taken) == n ->
          %{op: :runtime_call, function: function, args: taken}

        length(taken) < n ->
          Helpers.runtime_fn_lambda(function, taken, Enum.drop(names, length(taken)))

        true ->
          nil
      end
    end
  end
end
