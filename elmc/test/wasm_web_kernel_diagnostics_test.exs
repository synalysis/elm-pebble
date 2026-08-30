defmodule Elmc.Backend.Wasm.WebKernelDiagnosticsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Wasm.WebKernelDiagnostics

  setup do
    on_exit(fn -> Process.delete(:elmc_web_kernel_diagnostics) end)
    :ok
  end

  test "detects cacheStrategy Just in getWithOptions record literal" do
    options = %{
      op: :record_literal,
      fields: [
        %{name: "url", expr: %{op: :string_literal, value: "https://example.com"}},
        %{name: "expect", expr: %{op: :int_literal, value: 0}},
        %{name: "headers", expr: %{op: :list_literal, items: []}},
        %{
          name: "cacheStrategy",
          expr: %{
            op: :tuple2,
            left: %{op: :int_literal, value: 1, union_ctor: "Maybe.Just"},
            right: %{op: :int_literal, value: 0}
          }
        }
      ]
    }

    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    assert :ok = WebKernelDiagnostics.maybe_warn_browser_cache_options(options)

    assert [%{"code" => "browser_http_cache_ignored", "severity" => "warning"}] =
             WebKernelDiagnostics.compile_diagnostics()
  end

  test "does not warn when cacheStrategy is Nothing" do
    options = %{
      op: :record_literal,
      fields: [
        %{
          name: "cacheStrategy",
          expr: %{op: :int_literal, value: 0, union_ctor: "Maybe.Nothing"}
        }
      ]
    }

    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    assert :ok = WebKernelDiagnostics.maybe_warn_browser_cache_options(options)
    assert WebKernelDiagnostics.compile_diagnostics() == []
  end
end

defmodule Elmc.Backend.Plan.Lower.SpecialValues.FloatExtraTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.SpecialValues.Dispatcher

  setup do
    on_exit(fn -> Process.delete(:elmc_codegen_opts) end)
    :ok
  end

  test "web WASM rewrites Float.Extra.interpolateFrom to the runtime builtin" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    assert %{op: :runtime_call, function: "elmc_float_interpolate_from", args: [_, _, _]} =
             Dispatcher.special_value_from_target("Float.Extra.interpolateFrom", [
               %{op: :var, name: "start"},
               %{op: :var, name: "finish"},
               %{op: :var, name: "t"}
             ])
  end

  test "web WASM rewrites Elm.Kernel.WebGL.entity and toHtml to runtime builtins" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    settings = %{op: :var, name: "settings"}
    vert = %{op: :var, name: "vert"}
    frag = %{op: :var, name: "frag"}
    mesh = %{op: :var, name: "mesh"}
    uniforms = %{op: :var, name: "uniforms"}

    assert %{op: :runtime_call, function: "elmc_webgl_entity", args: [^settings, ^vert, ^frag, ^mesh, ^uniforms]} =
             Dispatcher.special_value_from_target("Elm.Kernel.WebGL.entity", [
               settings,
               vert,
               frag,
               mesh,
               uniforms
             ])

    assert %{
             op: :lambda,
             args: ["__mesh", "__uniforms"],
             body: %{op: :runtime_call, function: "elmc_webgl_entity"}
           } =
             Dispatcher.special_value_from_target("Elm.Kernel.WebGL.entity", [settings, vert, frag])

    assert %{op: :runtime_call, function: "elmc_webgl_to_html", args: [_, _, _]} =
             Dispatcher.special_value_from_target("Elm.Kernel.WebGL.toHtml", [
               %{op: :var, name: "options"},
               %{op: :var, name: "facts"},
               %{op: :var, name: "entities"}
             ])
  end

  test "web WASM rewrites partial Float.Extra.interpolateFrom to a runtime lambda" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})
    start = %{op: :var, name: "start"}
    finish = %{op: :var, name: "finish"}

    assert %{
             op: :lambda,
             args: ["__t"],
             body: %{
               op: :runtime_call,
               function: "elmc_float_interpolate_from",
               args: [^start, ^finish, %{op: :var, name: "__t"}]
             }
           } =
             Dispatcher.special_value_from_target("Float.Extra.interpolateFrom", [start, finish])

    assert %{
             op: :lambda,
             args: ["__end", "__t"],
             body: %{
               op: :runtime_call,
               function: "elmc_float_interpolate_from",
               args: [^start, %{op: :var, name: "__end"}, %{op: :var, name: "__t"}]
             }
           } =
             Dispatcher.special_value_from_target("Float.Extra.interpolateFrom", [start])
  end

  test "non-web targets leave Float.Extra.interpolateFrom unrewritten" do
    Process.put(:elmc_codegen_opts, %{targets: [:c]})

    assert is_nil(
             Dispatcher.special_value_from_target("Float.Extra.interpolateFrom", [
               %{op: :var, name: "start"},
               %{op: :var, name: "finish"},
               %{op: :var, name: "t"}
             ])
           )
  end

  test "web WASM rewrites Elm.Kernel.MJS kernels to runtime builtins" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})
    a = %{op: :var, name: "a"}
    b = %{op: :var, name: "b"}

    assert %{op: :runtime_call, function: "elmc_mjs_v3add", args: [^a, ^b]} =
             Dispatcher.special_value_from_target("Elm.Kernel.MJS.v3add", [a, b])

    assert %{
             op: :lambda,
             args: ["__1"],
             body: %{op: :runtime_call, function: "elmc_mjs_v3add", args: [^a, %{op: :var, name: "__1"}]}
           } =
             Dispatcher.special_value_from_target("Elm.Kernel.MJS.v3add", [a])

    assert %{op: :runtime_call, function: "elmc_mjs_m4x4identity", args: []} =
             Dispatcher.special_value_from_target("Elm.Kernel.MJS.m4x4identity", [])
  end

  test "non-web targets leave Elm.Kernel.MJS unrewritten" do
    Process.put(:elmc_codegen_opts, %{targets: [:c]})

    assert is_nil(
             Dispatcher.special_value_from_target("Elm.Kernel.MJS.v3add", [
               %{op: :var, name: "a"},
               %{op: :var, name: "b"}
             ])
           )
  end

  test "web WASM rewrites Browser.Dom tasks to runtime builtins" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})
    id = %{op: :var, name: "id"}
    x = %{op: :var, name: "x"}
    y = %{op: :var, name: "y"}

    assert %{op: :runtime_call, function: "elmc_browser_dom_focus", args: [^id]} =
             Dispatcher.special_value_from_target("Browser.Dom.focus", [id])

    assert %{op: :runtime_call, function: "elmc_browser_dom_blur", args: [^id]} =
             Dispatcher.special_value_from_target("Browser.Dom.blur", [id])

    assert %{op: :runtime_call, function: "elmc_browser_get_viewport", args: []} =
             Dispatcher.special_value_from_target("Browser.Dom.getViewport", [])

    assert %{op: :runtime_call, function: "elmc_browser_get_viewport_of", args: [^id]} =
             Dispatcher.special_value_from_target("Browser.Dom.getViewportOf", [id])

    assert %{op: :runtime_call, function: "elmc_browser_set_viewport", args: [^x, ^y]} =
             Dispatcher.special_value_from_target("Browser.Dom.setViewport", [x, y])

    assert %{op: :runtime_call, function: "elmc_browser_set_viewport_of", args: [^id, ^x, ^y]} =
             Dispatcher.special_value_from_target("Browser.Dom.setViewportOf", [id, x, y])

    assert %{op: :runtime_call, function: "elmc_browser_get_element", args: [^id]} =
             Dispatcher.special_value_from_target("Browser.Dom.getElement", [id])

    title = %{op: :string_literal, value: "hello"}

    assert %{op: :browser_cmd, kind: %{value: 12}, params: [^title]} =
             Dispatcher.special_value_from_target("Browser.Dom.setTitle", [title])

    assert %{op: :lambda, args: ["__title"], body: %{op: :browser_cmd, kind: %{value: 12}}} =
             Dispatcher.special_value_from_target("Browser.Dom.setTitle", [])

    to_msg = %{op: :var, name: "toMsg"}

    assert %{op: :dom_sub, kind: %{value: 2}, params: [^to_msg]} =
             Dispatcher.special_value_from_target("Browser.Events.onResize", [to_msg])

    assert %{op: :dom_sub, kind: %{value: 3}, params: [^to_msg]} =
             Dispatcher.special_value_from_target("Browser.Events.onVisibilityChange", [to_msg])

    decoder = %{op: :var, name: "decoder"}

    assert %{
             op: :dom_sub,
             kind: %{value: 10},
             params: [%{op: :int_literal, value: 0}, %{op: :string_literal, value: "click"}, ^decoder]
           } =
             Dispatcher.special_value_from_target("Browser.Events.onClick", [decoder])

    assert %{
             op: :dom_sub,
             kind: %{value: 10},
             params: [%{op: :int_literal, value: 0}, %{op: :string_literal, value: "keydown"}, ^decoder]
           } =
             Dispatcher.special_value_from_target("Browser.Events.onKeyDown", [decoder])

    assert %{
             op: :lambda,
             args: ["__y"],
             body: %{op: :runtime_call, function: "elmc_browser_set_viewport"}
           } =
             Dispatcher.special_value_from_target("Browser.Dom.setViewport", [x])
  end

  test "non-web targets leave Browser.Dom unrewritten" do
    Process.put(:elmc_codegen_opts, %{targets: [:c]})

    assert is_nil(Dispatcher.special_value_from_target("Browser.Dom.blur", [%{op: :var, name: "id"}]))
  end

  test "Task.attempt wraps Ok/Err then performs" do
    to_msg = %{op: :var, name: "toMsg"}
    task = %{op: :var, name: "task"}

    assert %{
             op: :runtime_call,
             function: "elmc_task_perform",
             args: [%{op: :tuple2, right: mapped}]
           } = Dispatcher.special_value_from_target("Task.attempt", [to_msg, task])

    assert %{
             op: :runtime_call,
             function: "elmc_task_map",
             args: [
               ^to_msg,
               %{
                 op: :runtime_call,
                 function: "elmc_task_on_error",
                 args: [
                   %{op: :lambda, args: ["__err"]},
                   %{
                     op: :runtime_call,
                     function: "elmc_task_and_then",
                     args: [%{op: :lambda, args: ["__ok"]}, ^task]
                   }
                 ]
               }
             ]
           } = mapped
  end

  test "Task.map3 and Task.sequence rewrite to map2 and sequence" do
    f = %{op: :var, name: "f"}
    a = %{op: :var, name: "a"}
    b = %{op: :var, name: "b"}
    c = %{op: :var, name: "c"}
    tasks = %{op: :var, name: "tasks"}

    assert %{
             op: :runtime_call,
             function: "elmc_task_map2",
             args: [
               %{op: :lambda, args: ["__g", "__x"]},
               %{op: :runtime_call, function: "elmc_task_map2", args: [^f, ^a, ^b]},
               ^c
             ]
           } = Dispatcher.special_value_from_target("Task.map3", [f, a, b, c])

    assert %{op: :runtime_call, function: "elmc_task_sequence", args: [^tasks]} =
             Dispatcher.special_value_from_target("Task.sequence", [tasks])
  end

  test "Html.Events target decoders rewrite to Json.Decode.at/field" do
    assert %{op: :runtime_call, function: "elmc_json_decode_at"} =
             Dispatcher.special_value_from_target("Html.Events.targetValue", [])

    assert %{op: :runtime_call, function: "elmc_json_decode_at"} =
             Dispatcher.special_value_from_target("Html.Events.targetChecked", [])

    assert %{op: :runtime_call, function: "elmc_json_decode_field"} =
             Dispatcher.special_value_from_target("Html.Events.keyCode", [])
  end

  test "web WASM rewrites preventDefaultOn / stopPropagationOn / custom to Handler unions" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})
    event = %{op: :string_literal, value: "click"}
    decoder = %{op: :var, name: "decoder"}

    assert %{
             op: :html_cmd,
             kind: %{value: 8},
             params: [
               ^event,
               %{op: :constructor_call, target: "VirtualDom.MayPreventDefault", args: [^decoder]}
             ]
           } =
             Dispatcher.special_value_from_target("Html.Events.preventDefaultOn", [event, decoder])

    assert %{
             op: :html_cmd,
             kind: %{value: 8},
             params: [
               ^event,
               %{op: :constructor_call, target: "VirtualDom.MayStopPropagation", args: [^decoder]}
             ]
           } =
             Dispatcher.special_value_from_target("Html.Events.stopPropagationOn", [event, decoder])

    assert %{
             op: :html_cmd,
             kind: %{value: 8},
             params: [
               ^event,
               %{op: :constructor_call, target: "VirtualDom.Custom", args: [^decoder]}
             ]
           } =
             Dispatcher.special_value_from_target("Html.Events.custom", [event, decoder])

    tagger = %{op: :var, name: "tagger"}

    assert %{
             op: :html_cmd,
             kind: %{value: 8},
             params: [
               %{op: :string_literal, value: "input"},
               %{op: :constructor_call, target: "VirtualDom.MayStopPropagation"}
             ]
           } =
             Dispatcher.special_value_from_target("Html.Events.onInput", [tagger])

    assert %{
             op: :html_cmd,
             kind: %{value: 8},
             params: [
               %{op: :string_literal, value: "submit"},
               %{op: :constructor_call, target: "VirtualDom.MayPreventDefault"}
             ]
           } =
             Dispatcher.special_value_from_target("Html.Events.onSubmit", [tagger])

    assert %{
             op: :html_cmd,
             kind: %{value: 8},
             params: [
               %{op: :string_literal, value: "change"},
               %{op: :runtime_call, function: "elmc_json_decode_map", args: [^tagger, _]}
             ]
           } =
             Dispatcher.special_value_from_target("Html.Events.onCheck", [tagger])
  end

  test "Url.Builder and Url.toString rewrite without a web target" do
    path = %{op: :var, name: "path"}
    query = %{op: :var, name: "query"}
    pre = %{op: :string_literal, value: "https://example.com"}
    url = %{op: :var, name: "url"}

    assert %{op: :runtime_call, function: "elmc_url_to_string", args: [^url]} =
             Dispatcher.special_value_from_target("Url.toString", [url])

    assert %{op: :runtime_call, function: "elmc_url_from_string", args: [^url]} =
             Dispatcher.special_value_from_target("Url.fromString", [url])

    assert %{op: :runtime_call, function: "elmc_url_percent_encode", args: [^url]} =
             Dispatcher.special_value_from_target("Url.percentEncode", [url])

    assert %{op: :runtime_call, function: "elmc_url_percent_decode", args: [^url]} =
             Dispatcher.special_value_from_target("Url.percentDecode", [url])

    assert %{op: :runtime_call, function: "elmc_regex_never", args: []} =
             Dispatcher.special_value_from_target("Regex.never", [])

    assert %{op: :runtime_call, function: "elmc_regex_never", args: []} =
             Dispatcher.special_value_from_target("Elm.Kernel.Regex.never", [])

    assert %{op: :runtime_call, function: "elmc_url_builder_absolute", args: [^path, ^query]} =
             Dispatcher.special_value_from_target("Url.Builder.absolute", [path, query])

    assert %{
             op: :runtime_call,
             function: "elmc_url_builder_cross_origin",
             args: [^pre, ^path, ^query]
           } =
             Dispatcher.special_value_from_target("Url.Builder.crossOrigin", [pre, path, query])

    refute match?(
             %{op: :string_literal, value: "anonymous"},
             Dispatcher.special_value_from_target("Url.Builder.crossOrigin", [pre])
           )

    assert %{op: :lambda, args: ["__path", "__query"]} =
             Dispatcher.special_value_from_target("Url.Builder.crossOrigin", [pre])

    assert %{op: :runtime_call, function: "elmc_url_builder_query_string"} =
             Dispatcher.special_value_from_target("Url.Builder.string", [
               %{op: :string_literal, value: "q"},
               %{op: :string_literal, value: "hat"}
             ])
  end

  test "Time.posixToMillis and millisToPosix are identity on this ABI" do
    posix = %{op: :var, name: "posix"}

    assert ^posix = Dispatcher.special_value_from_target("Time.posixToMillis", [posix])
    assert ^posix = Dispatcher.special_value_from_target("Time.millisToPosix", [posix])
  end

  test "Time calendar helpers rewrite without a web target" do
    zone = %{op: :var, name: "zone"}
    posix = %{op: :var, name: "posix"}

    assert %{op: :runtime_call, function: "elmc_time_utc", args: []} =
             Dispatcher.special_value_from_target("Time.utc", [])

    assert %{op: :runtime_call, function: "elmc_time_here", args: []} =
             Dispatcher.special_value_from_target("Time.here", [])

    assert %{op: :runtime_call, function: "elmc_time_get_zone_name", args: []} =
             Dispatcher.special_value_from_target("Time.getZoneName", [])

    assert %{op: :runtime_call, function: "elmc_time_get_zone_name", args: []} =
             Dispatcher.special_value_from_target("Elm.Kernel.Time.getZoneName", [
               %{op: :int_literal, value: 0}
             ])

    assert %{op: :runtime_call, function: "elmc_time_custom_zone", args: [^zone, _eras]} =
             Dispatcher.special_value_from_target("Time.customZone", [zone, %{op: :list_literal, items: []}])

    assert %{op: :runtime_call, function: "elmc_time_to_hour", args: [^zone, ^posix]} =
             Dispatcher.special_value_from_target("Time.toHour", [zone, posix])

    assert %{op: :lambda, args: ["__posix"], body: %{op: :runtime_call, function: "elmc_time_to_month"}} =
             Dispatcher.special_value_from_target("Time.toMonth", [zone])

    assert %{op: :lambda, args: ["__zone", "__posix"]} =
             Dispatcher.special_value_from_target("Time.toWeekday", [])
  end

  test "Process.sleep and Debug kernel aliases rewrite" do
    ms = %{op: :var, name: "ms"}
    label = %{op: :string_literal, value: "missing"}
    value = %{op: :var, name: "v"}

    assert %{op: :runtime_call, function: "elmc_process_sleep", args: [^ms]} =
             Dispatcher.special_value_from_target("Process.sleep", [ms])

    assert %{op: :runtime_call, function: "elmc_process_sleep", args: [^ms]} =
             Dispatcher.special_value_from_target("Elm.Kernel.Process.sleep", [ms])

    task = %{op: :var, name: "task"}
    pid = %{op: :var, name: "pid"}

    assert %{op: :runtime_call, function: "elmc_process_spawn", args: [^task]} =
             Dispatcher.special_value_from_target("Process.spawn", [task])

    assert %{op: :runtime_call, function: "elmc_process_kill", args: [^pid]} =
             Dispatcher.special_value_from_target("Process.kill", [pid])

    assert %{op: :lambda, args: ["__task"]} =
             Dispatcher.special_value_from_target("Process.spawn", [])

    assert %{op: :lambda, args: ["__pid"]} =
             Dispatcher.special_value_from_target("Process.kill", [])

    assert %{op: :runtime_call, function: "elmc_debug_todo", args: [^label]} =
             Dispatcher.special_value_from_target("Debug.todo", [label])

    assert %{op: :runtime_call, function: "elmc_debug_todo", args: [^label]} =
             Dispatcher.special_value_from_target("Elm.Kernel.Debug.todo", [label])

    assert %{op: :runtime_call, function: "elmc_debug_log", args: [^label, ^value]} =
             Dispatcher.special_value_from_target("Elm.Kernel.Debug.log", [label, value])
  end

  test "Task.onError rewrites to the scheduler builtin" do
    f = %{op: :var, name: "recover"}
    task = %{op: :var, name: "task"}

    assert %{op: :runtime_call, function: "elmc_task_on_error", args: [^f, ^task]} =
             Dispatcher.special_value_from_target("Task.onError", [f, task])
  end

  test "Task.mapError rewrites to onError plus fail" do
    f = %{op: :var, name: "toY"}
    task = %{op: :var, name: "task"}

    assert %{
             op: :runtime_call,
             function: "elmc_task_on_error",
             args: [%{op: :lambda, body: %{op: :runtime_call, function: "elmc_task_fail"}}, ^task]
           } =
             Dispatcher.special_value_from_target("Task.mapError", [f, task])

    assert %{op: :lambda, args: ["__t"]} =
             Dispatcher.special_value_from_target("Task.mapError", [f])
  end

  test "Json.Decode.map8 rewrites to the map8 builtin" do
    args = Enum.map(0..8, fn i -> %{op: :var, name: "a#{i}"} end)

    assert %{op: :runtime_call, function: "elmc_json_decode_map8", args: ^args} =
             Dispatcher.special_value_from_target("Json.Decode.map8", args)

    assert %{op: :lambda, args: ["__f", "__d1", "__d2", "__d3", "__d4", "__d5", "__d6", "__d7", "__d8"]} =
             Dispatcher.special_value_from_target("Json.Decode.map8", [])
  end

  test "File.decoder rewrites to the file decoder builtin on web" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    on_exit(fn ->
      Process.delete(:elmc_codegen_opts)
    end)

    assert %{op: :runtime_call, function: "elmc_file_decoder", args: []} =
             Dispatcher.special_value_from_target("File.decoder", [])

    assert %{op: :runtime_call, function: "elmc_file_decoder", args: []} =
             Dispatcher.special_value_from_target("Elm.Kernel.File.decoder", [])
  end

  test "Json.Decode.dict rewrites to the decode dict builtin" do
    decoder = %{op: :var, name: "decoder"}

    assert %{op: :runtime_call, function: "elmc_json_decode_dict", args: [^decoder]} =
             Dispatcher.special_value_from_target("Json.Decode.dict", [decoder])

    assert %{op: :lambda, args: ["__decoder"]} =
             Dispatcher.special_value_from_target("Json.Decode.dict", [])
  end

  test "Json.Encode.dict rewrites to the encode dict builtin" do
    key_fn = %{op: :var, name: "toKey"}
    val_fn = %{op: :var, name: "toValue"}
    dict = %{op: :var, name: "dict"}

    assert %{
             op: :runtime_call,
             function: "elmc_json_encode_dict",
             args: [^key_fn, ^val_fn, ^dict]
           } =
             Dispatcher.special_value_from_target("Json.Encode.dict", [key_fn, val_fn, dict])

    assert %{op: :lambda, args: ["__key_fn", "__val_fn", "__dict"]} =
             Dispatcher.special_value_from_target("Json.Encode.dict", [])
  end

  test "Regex.split and fromStringWith rewrite without a web target" do
    regex = %{op: :var, name: "regex"}
    string = %{op: :var, name: "s"}
    n = %{op: :int_literal, value: 2}
    options = %{op: :var, name: "opts"}

    assert %{op: :runtime_call, function: "elmc_regex_split", args: [^regex, ^string]} =
             Dispatcher.special_value_from_target("Regex.split", [regex, string])

    assert %{op: :runtime_call, function: "elmc_regex_split_at_most", args: [^n, ^regex, ^string]} =
             Dispatcher.special_value_from_target("Regex.splitAtMost", [n, regex, string])

    assert %{op: :runtime_call, function: "elmc_regex_find_at_most", args: [^n, ^regex, ^string]} =
             Dispatcher.special_value_from_target("Regex.findAtMost", [n, regex, string])

    assert %{op: :runtime_call, function: "elmc_regex_from_string_with", args: [^options, ^string]} =
             Dispatcher.special_value_from_target("Regex.fromStringWith", [options, string])

    assert %{
             op: :runtime_call,
             function: "elmc_regex_replace_at_most",
             args: [^n, ^regex, _replacer, ^string]
           } =
             Dispatcher.special_value_from_target("Regex.replaceAtMost", [
               n,
               regex,
               %{op: :var, name: "replacer"},
               string
             ])

    assert %{
             op: :runtime_call,
             function: "elmc_regex_find_at_most",
             args: [%{op: :int_literal, value: 2_147_483_647}, ^regex, ^string]
           } =
             Dispatcher.special_value_from_target("Regex.find", [regex, string])

    assert %{op: :runtime_call, function: "elmc_regex_from_string", args: [^string]} =
             Dispatcher.special_value_from_target("Regex.fromString", [string])
  end

  test "Http.request and riskyRequest rewrite to the http command" do
    req = %{op: :var, name: "req"}

    assert %{op: :runtime_call, function: "elmc_http_command", args: [^req]} =
             Dispatcher.special_value_from_target("Http.request", [req])

    assert %{op: :runtime_call, function: "elmc_http_risky_command", args: [^req]} =
             Dispatcher.special_value_from_target("Http.riskyRequest", [req])

    assert %{op: :runtime_call, function: "elmc_http_command", args: [^req]} =
             Dispatcher.special_value_from_target("Http.get", [req])

    progress = %{op: :var, name: "progress"}

    assert %{op: :runtime_call, function: "elmc_http_fraction_sent", args: [^progress]} =
             Dispatcher.special_value_from_target("Http.fractionSent", [progress])

    assert %{op: :runtime_call, function: "elmc_http_fraction_received", args: [^progress]} =
             Dispatcher.special_value_from_target("Http.fractionReceived", [progress])
  end

  test "Http.expect* rewrite to host expect records" do
    to_msg = %{op: :var, name: "toMsg"}
    decoder = %{op: :var, name: "decoder"}
    to_result = %{op: :var, name: "toResult"}

    assert %{op: :runtime_call, function: "elmc_http_expect_string", args: [^to_msg]} =
             Dispatcher.special_value_from_target("Http.expectString", [to_msg])

    assert %{
             op: :runtime_call,
             function: "elmc_http_expect_json",
             args: [^to_msg, ^decoder]
           } =
             Dispatcher.special_value_from_target("Http.expectJson", [to_msg, decoder])

    assert %{
             op: :runtime_call,
             function: "elmc_http_expect_bytes",
             args: [^to_msg, ^decoder]
           } =
             Dispatcher.special_value_from_target("Http.expectBytes", [to_msg, decoder])

    assert %{op: :runtime_call, function: "elmc_http_expect_whatever", args: [^to_msg]} =
             Dispatcher.special_value_from_target("Http.expectWhatever", [to_msg])

    assert %{
             op: :runtime_call,
             function: "elmc_http_expect_string_response",
             args: [^to_msg, ^to_result]
           } =
             Dispatcher.special_value_from_target("Http.expectStringResponse", [to_msg, to_result])

    assert %{
             op: :runtime_call,
             function: "elmc_http_expect_bytes_response",
             args: [^to_msg, ^to_result]
           } =
             Dispatcher.special_value_from_target("Http.expectBytesResponse", [to_msg, to_result])

    func = %{op: :var, name: "func"}
    expect = %{op: :var, name: "expect"}

    assert %{op: :runtime_call, function: "elmc_http_map_expect", args: [^func, ^expect]} =
             Dispatcher.special_value_from_target("Elm.Kernel.Http.mapExpect", [func, expect])

    assert %{op: :runtime_call, function: "elmc_http_map_expect", args: [^func, ^expect]} =
             Dispatcher.special_value_from_target("Http.mapExpect", [func, expect])
  end

  test "Http.task, resolvers, and body helpers rewrite to http runtime" do
    req = %{op: :var, name: "req"}
    to_result = %{op: :var, name: "toResult"}
    key = %{op: :string_literal, value: "X-A"}
    value = %{op: :string_literal, value: "1"}
    body = %{op: :var, name: "json"}

    assert %{op: :runtime_call, function: "elmc_http_task", args: [^req]} =
             Dispatcher.special_value_from_target("Http.task", [req])

    assert %{op: :runtime_call, function: "elmc_http_risky_task", args: [^req]} =
             Dispatcher.special_value_from_target("Http.riskyTask", [req])

    assert %{op: :runtime_call, function: "elmc_http_string_resolver", args: [^to_result]} =
             Dispatcher.special_value_from_target("Http.stringResolver", [to_result])

    assert %{op: :runtime_call, function: "elmc_http_bytes_resolver", args: [^to_result]} =
             Dispatcher.special_value_from_target("Http.bytesResolver", [to_result])

    assert %{op: :runtime_call, function: "elmc_http_empty_body", args: []} =
             Dispatcher.special_value_from_target("Http.emptyBody", [])

    assert %{op: :runtime_call, function: "elmc_http_pair", args: [^key, ^value]} =
             Dispatcher.special_value_from_target("Http.header", [key, value])

    assert %{
             op: :runtime_call,
             function: "elmc_http_pair",
             args: [
               %{op: :string_literal, value: "application/json"},
               %{op: :runtime_call, function: "elmc_json_encode_encode"}
             ]
           } =
             Dispatcher.special_value_from_target("Http.jsonBody", [body])

    file = %{op: :var, name: "file"}
    parts = %{op: :var, name: "parts"}
    mime = %{op: :string_literal, value: "image/png"}
    bytes = %{op: :var, name: "bytes"}

    assert %{op: :runtime_call, function: "elmc_http_file_body", args: [^file]} =
             Dispatcher.special_value_from_target("Http.fileBody", [file])

    assert %{op: :runtime_call, function: "elmc_http_pair", args: [^mime, ^bytes]} =
             Dispatcher.special_value_from_target("Http.bytesBody", [mime, bytes])

    assert %{op: :runtime_call, function: "elmc_http_multipart_body", args: [^parts]} =
             Dispatcher.special_value_from_target("Http.multipartBody", [parts])

    assert %{
             op: :runtime_call,
             function: "elmc_http_bytes_part",
             args: [^key, ^mime, ^bytes]
           } =
             Dispatcher.special_value_from_target("Http.bytesPart", [key, mime, bytes])
  end

  test "web WASM rewrites Navigation.reload and animation-frame delta" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    assert %{op: :browser_cmd, kind: %{value: 14}, params: []} =
             Dispatcher.special_value_from_target("Browser.Navigation.reload", [])

    assert %{op: :browser_cmd, kind: %{value: 15}, params: []} =
             Dispatcher.special_value_from_target("Browser.Navigation.reloadAndSkipCache", [])

    key = %{op: :var, name: "key"}
    n = %{op: :int_literal, value: 2}

    assert %{op: :browser_cmd, kind: %{value: 10}, params: [^key, ^n]} =
             Dispatcher.special_value_from_target("Browser.Navigation.back", [key, n])

    assert %{op: :browser_cmd, kind: %{value: 11}, params: [^key, ^n]} =
             Dispatcher.special_value_from_target("Browser.Navigation.forward", [key, n])

    assert %{op: :browser_cmd, kind: %{value: 16}, params: [^key, ^n]} =
             Dispatcher.special_value_from_target("Elm.Kernel.Browser.go", [key, n])

    assert %{op: :browser_cmd, kind: %{value: 16}, params: [^key, ^n]} =
             Dispatcher.special_value_from_target("Browser.Navigation.go", [key, n])

    assert %{op: :lambda, args: ["__n"], body: %{op: :browser_cmd, kind: %{value: 10}}} =
             Dispatcher.special_value_from_target("Browser.Navigation.back", [key])

    to_msg = %{op: :var, name: "toMsg"}

    assert %{op: :dom_sub, kind: %{value: 11}, params: [^to_msg]} =
             Dispatcher.special_value_from_target("Browser.Events.onAnimationFrameDelta", [to_msg])
  end

  test "web WASM rewrites File.Select.file and File.Download" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})
    to_msg = %{op: :var, name: "toMsg"}
    name = %{op: :var, name: "name"}
    mime = %{op: :var, name: "mime"}
    content = %{op: :var, name: "content"}
    href = %{op: :var, name: "href"}

    mimes = %{
      op: :list_literal,
      items: [
        %{op: :string_literal, value: "image/png"},
        %{op: :string_literal, value: "image/jpeg"}
      ]
    }

    assert %{
             op: :runtime_call,
             function: "elmc_file_select",
             args: [^to_msg, %{op: :string_literal, value: "image/png,image/jpeg"}]
           } =
             Dispatcher.special_value_from_target("File.Select.file", [mimes, to_msg])

    assert %{op: :runtime_call, function: "elmc_file_download", args: [^name, ^mime, ^content]} =
             Dispatcher.special_value_from_target("File.Download.string", [name, mime, content])

    assert %{op: :runtime_call, function: "elmc_file_download", args: [^name, ^mime, ^content]} =
             Dispatcher.special_value_from_target("File.Download.bytes", [name, mime, content])

    assert %{op: :runtime_call, function: "elmc_file_download_url", args: [^href]} =
             Dispatcher.special_value_from_target("File.Download.url", [href])

    assert %{
             op: :runtime_call,
             function: "elmc_file_select_files",
             args: [^to_msg, %{op: :string_literal, value: "image/png,image/jpeg"}]
           } =
             Dispatcher.special_value_from_target("File.Select.files", [mimes, to_msg])

    file = %{op: :var, name: "file"}

    assert %{op: :runtime_call, function: "elmc_file_name", args: [^file]} =
             Dispatcher.special_value_from_target("File.name", [file])

    assert %{op: :runtime_call, function: "elmc_file_mime", args: [^file]} =
             Dispatcher.special_value_from_target("File.mime", [file])

    assert %{op: :runtime_call, function: "elmc_file_size", args: [^file]} =
             Dispatcher.special_value_from_target("File.size", [file])

    assert %{op: :runtime_call, function: "elmc_file_last_modified", args: [^file]} =
             Dispatcher.special_value_from_target("File.lastModified", [file])

    assert %{op: :runtime_call, function: "elmc_file_to_string", args: [^file]} =
             Dispatcher.special_value_from_target("File.toString", [file])

    assert %{op: :runtime_call, function: "elmc_file_to_bytes", args: [^file]} =
             Dispatcher.special_value_from_target("File.toBytes", [file])

    assert %{op: :runtime_call, function: "elmc_file_to_url", args: [^file]} =
             Dispatcher.special_value_from_target("File.toUrl", [file])
  end

  test "non-web targets leave Navigation.reload and File.Select unrewritten" do
    Process.put(:elmc_codegen_opts, %{targets: [:c]})

    assert is_nil(Dispatcher.special_value_from_target("Browser.Navigation.reload", []))

    assert is_nil(
             Dispatcher.special_value_from_target("File.Select.file", [
               %{op: :list_literal, items: []},
               %{op: :var, name: "toMsg"}
             ])
           )

    assert is_nil(
             Dispatcher.special_value_from_target("Html.Events.preventDefaultOn", [
               %{op: :string_literal, value: "click"},
               %{op: :var, name: "decoder"}
             ])
           )

    assert is_nil(Dispatcher.special_value_from_target("Html.Events.onInput", [%{op: :var, name: "tagger"}]))
  end
end
