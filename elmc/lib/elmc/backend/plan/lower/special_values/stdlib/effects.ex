defmodule Elmc.Backend.Plan.Lower.SpecialValues.Stdlib.Effects do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias Elmc.Backend.CCodegen.{ConstantInt, UnsupportedSurface}
  alias Elmc.Backend.Plan.Lower.SpecialValues.Helpers
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.Plan.Lower.Platform.Web, as: PlatformWeb
  alias Elmc.Backend.Plan.Worker.Subscriptions

  @behaviour Elmc.Backend.Plan.Lower.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()
  def special_value_from_target("Debug.log", [label, value]),
    do: %{op: :runtime_call, function: "elmc_debug_log", args: [label, value]}

  def special_value_from_target("Debug.todo", [label]),
    do: %{op: :runtime_call, function: "elmc_debug_todo", args: [label]}

  def special_value_from_target("Debug.toString", [value]),
    do: %{op: :runtime_call, function: "elmc_debug_to_string", args: [value]}

  def special_value_from_target("Elm.Kernel.Debug.log", args),
    do: special_value_from_target("Debug.log", args)

  def special_value_from_target("Elm.Kernel.Debug.todo", args),
    do: special_value_from_target("Debug.todo", args)

  def special_value_from_target("Elm.Kernel.Debug.toString", args),
    do: special_value_from_target("Debug.toString", args)

  def special_value_from_target("Task.succeed", [value]),
    do: %{op: :runtime_call, function: "elmc_task_succeed", args: [value]}

  def special_value_from_target("Task.fail", [value]),
    do: %{op: :runtime_call, function: "elmc_task_fail", args: [value]}

  def special_value_from_target("Task.map", [f]),
    do: %{
      op: :lambda,
      args: ["__t"],
      body: %{op: :runtime_call, function: "elmc_task_map", args: [f, %{op: :var, name: "__t"}]}
    }

  def special_value_from_target("Task.map2", [f]),
    do: %{
      op: :lambda,
      args: ["__a", "__b"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_map2",
        args: [f, %{op: :var, name: "__a"}, %{op: :var, name: "__b"}]
      }
    }

  def special_value_from_target("Task.map2", [f, a]),
    do: %{
      op: :lambda,
      args: ["__b"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_map2",
        args: [f, a, %{op: :var, name: "__b"}]
      }
    }

  def special_value_from_target("Task.andThen", [f]),
    do: %{
      op: :lambda,
      args: ["__t"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_and_then",
        args: [f, %{op: :var, name: "__t"}]
      }
    }

  def special_value_from_target("Process.spawn", [task]),
    do: %{op: :runtime_call, function: "elmc_process_spawn", args: [task]}

  def special_value_from_target("Process.spawn", []),
    do: Helpers.runtime_fn_lambda("elmc_process_spawn", ["__task"])

  def special_value_from_target("Process.sleep", []),
    do: Helpers.runtime_fn_lambda("elmc_process_sleep", ["__ms"])

  def special_value_from_target("Process.sleep", [milliseconds]),
    do: %{op: :runtime_call, function: "elmc_process_sleep", args: [milliseconds]}

  def special_value_from_target("Elm.Kernel.Process.sleep", args),
    do: special_value_from_target("Process.sleep", args)

  def special_value_from_target("Process.kill", [pid]),
    do: %{op: :runtime_call, function: "elmc_process_kill", args: [pid]}

  def special_value_from_target("Process.kill", []),
    do: Helpers.runtime_fn_lambda("elmc_process_kill", ["__pid"])

  def special_value_from_target("Elm.Kernel.Scheduler.succeed", []),
    do: %{
      op: :lambda,
      args: ["__value"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_succeed",
        args: [%{op: :var, name: "__value"}]
      }
    }

  def special_value_from_target("Elm.Kernel.Scheduler.succeed", [value]),
    do: %{op: :runtime_call, function: "elmc_task_succeed", args: [value]}

  def special_value_from_target("Elm.Kernel.Scheduler.fail", []),
    do: %{
      op: :lambda,
      args: ["__error"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_fail",
        args: [%{op: :var, name: "__error"}]
      }
    }

  def special_value_from_target("Elm.Kernel.Scheduler.fail", [error]),
    do: %{op: :runtime_call, function: "elmc_task_fail", args: [error]}

  def special_value_from_target("Elm.Kernel.Scheduler.andThen", []),
    do: %{
      op: :lambda,
      args: ["__callback", "__task"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_and_then",
        args: [%{op: :var, name: "__callback"}, %{op: :var, name: "__task"}]
      }
    }

  def special_value_from_target("Elm.Kernel.Scheduler.andThen", [callback]),
    do: %{
      op: :lambda,
      args: ["__task"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_and_then",
        args: [callback, %{op: :var, name: "__task"}]
      }
    }

  def special_value_from_target("Elm.Kernel.Scheduler.andThen", [callback, task]),
    do: %{op: :runtime_call, function: "elmc_task_and_then", args: [callback, task]}

  def special_value_from_target("Elm.Kernel.Scheduler.onError", []),
    do: %{
      op: :lambda,
      args: ["__callback", "__task"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_on_error",
        args: [%{op: :var, name: "__callback"}, %{op: :var, name: "__task"}]
      }
    }

  def special_value_from_target("Elm.Kernel.Scheduler.onError", [callback]),
    do: %{
      op: :lambda,
      args: ["__task"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_on_error",
        args: [callback, %{op: :var, name: "__task"}]
      }
    }

  def special_value_from_target("Elm.Kernel.Scheduler.onError", [callback, task]),
    do: %{op: :runtime_call, function: "elmc_task_on_error", args: [callback, task]}

  def special_value_from_target("Elm.Kernel.Scheduler.spawn", []),
    do: %{
      op: :lambda,
      args: ["__task"],
      body: %{op: :runtime_call, function: "elmc_process_spawn", args: [%{op: :var, name: "__task"}]}
    }

  def special_value_from_target("Elm.Kernel.Scheduler.spawn", [task]),
    do: %{op: :runtime_call, function: "elmc_process_spawn", args: [task]}

  def special_value_from_target("Elm.Kernel.Scheduler.kill", []),
    do: %{
      op: :lambda,
      args: ["__id"],
      body: %{op: :runtime_call, function: "elmc_process_kill", args: [%{op: :var, name: "__id"}]}
    }

  def special_value_from_target("Elm.Kernel.Scheduler.kill", [id]),
    do: %{op: :runtime_call, function: "elmc_process_kill", args: [id]}

  def special_value_from_target("Elm.Kernel.Time.nowMillis", [_unit]),
    do: %{op: :runtime_call, function: "elmc_time_now_millis", args: []}

  def special_value_from_target("Elm.Kernel.Time.zoneOffsetMinutes", [_unit]),
    do: %{op: :runtime_call, function: "elmc_time_zone_offset_minutes", args: []}

  def special_value_from_target("Time.here", _args),
    do: %{op: :runtime_call, function: "elmc_time_here", args: []}

  def special_value_from_target("Time.getZoneName", _args),
    do: %{op: :runtime_call, function: "elmc_time_get_zone_name", args: []}

  def special_value_from_target("Elm.Kernel.Time.getZoneName", _args),
    do: %{op: :runtime_call, function: "elmc_time_get_zone_name", args: []}

  def special_value_from_target("Elm.Kernel.Time.every", [interval, to_msg]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{
        op: :dom_sub,
        kind: %{op: :int_literal, value: 1},
        params: [interval, to_msg]
      }
    else
      case ConstantInt.literal_value(interval, %{}) do
        {:ok, _} ->
          Helpers.subscription_special_value("Pebble.Frame.every", [interval, to_msg])

        :error ->
          UnsupportedSurface.unsupported_expr(%{
            kind: :sub,
            target: "Elm.Kernel.Time.every",
            arity: 2,
            detail: "interval must be int literal"
          })
      end
    end
  end

  def special_value_from_target("Time.every", [interval, to_msg]) do
    special_value_from_target("Elm.Kernel.Time.every", [interval, to_msg])
  end

  def special_value_from_target("Browser.Events.onResize", [to_msg]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{op: :dom_sub, kind: %{op: :int_literal, value: 2}, params: [to_msg]}
    else
      nil
    end
  end

  def special_value_from_target("Browser.Events.onVisibilityChange", [to_msg]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{op: :dom_sub, kind: %{op: :int_literal, value: 3}, params: [to_msg]}
    else
      nil
    end
  end

  def special_value_from_target("Browser.Events.onAnimationFrame", [to_msg]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{op: :dom_sub, kind: %{op: :int_literal, value: 4}, params: [to_msg]}
    else
      nil
    end
  end

  def special_value_from_target("Browser.Events.onAnimationFrameDelta", [to_msg]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{op: :dom_sub, kind: %{op: :int_literal, value: 11}, params: [to_msg]}
    else
      nil
    end
  end

  def special_value_from_target("Browser.Events.onMouseMove", [decoder]),
    do: browser_events_on_document("mousemove", decoder)

  def special_value_from_target("Browser.Events.onMouseUp", [decoder]),
    do: browser_events_on_document("mouseup", decoder)

  def special_value_from_target("Browser.Events.onMouseDown", [decoder]),
    do: browser_events_on_document("mousedown", decoder)

  def special_value_from_target("Browser.Events.onClick", [decoder]),
    do: browser_events_on_document("click", decoder)

  def special_value_from_target("Browser.Events.onKeyDown", [decoder]),
    do: browser_events_on_document("keydown", decoder)

  def special_value_from_target("Browser.Events.onKeyUp", [decoder]),
    do: browser_events_on_document("keyup", decoder)

  def special_value_from_target("Browser.Events.onKeyPress", [decoder]),
    do: browser_events_on_document("keypress", decoder)

  # Generic Browser.Events.on Document|Window name decoder
  def special_value_from_target("Browser.Events.on", [node, name, decoder]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{
        op: :dom_sub,
        kind: %{op: :int_literal, value: 10},
        params: [node, name, decoder]
      }
    else
      nil
    end
  end

  # Effect-manager entry: subscription (MySub node name decoder)
  def special_value_from_target("Browser.Events.subscription", [sub]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      case browser_events_mysub(sub) do
        {:ok, node, name, decoder} ->
          %{
            op: :dom_sub,
            kind: %{op: :int_literal, value: 10},
            params: [node, name, decoder]
          }

        :error ->
          nil
      end
    else
      nil
    end
  end

  def special_value_from_target("Browser.Dom.focus", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_browser_dom_focus", ["__id"], args)

  def special_value_from_target("Browser.Dom.blur", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_browser_dom_blur", ["__id"], args)

  def special_value_from_target("Browser.Dom.setTitle", [title]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{op: :browser_cmd, kind: %{op: :int_literal, value: 12}, params: [title]}
    else
      nil
    end
  end

  def special_value_from_target("Browser.Dom.setTitle", []) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{
        op: :lambda,
        args: ["__title"],
        body: %{
          op: :browser_cmd,
          kind: %{op: :int_literal, value: 12},
          params: [%{op: :var, name: "__title"}]
        }
      }
    else
      nil
    end
  end

  def special_value_from_target("Browser.Dom.getViewport", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_browser_get_viewport", [], args)

  def special_value_from_target("Browser.Dom.getViewportOf", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_browser_get_viewport_of", ["__id"], args)

  def special_value_from_target("Browser.Dom.setViewport", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_browser_set_viewport", ["__x", "__y"], args)

  def special_value_from_target("Browser.Dom.setViewportOf", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_browser_set_viewport_of", ["__id", "__x", "__y"], args)

  def special_value_from_target("Browser.Dom.getElement", args) when is_list(args),
    do: Helpers.web_only_runtime("elmc_browser_get_element", ["__id"], args)

  def special_value_from_target("Browser.Navigation.pushUrl", [key, url]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{op: :browser_cmd, kind: %{op: :int_literal, value: 3}, params: [key, url]}
    else
      nil
    end
  end

  def special_value_from_target("Browser.Navigation.replaceUrl", [key, url]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{op: :browser_cmd, kind: %{op: :int_literal, value: 4}, params: [key, url]}
    else
      nil
    end
  end

  def special_value_from_target("Browser.Navigation.load", [url]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{op: :browser_cmd, kind: %{op: :int_literal, value: 2}, params: [url]}
    else
      nil
    end
  end

  # Official elm/browser: `go = Elm.Kernel.Browser.go`,
  # `back key n = Elm.Kernel.Browser.go key -n`, `forward = Elm.Kernel.Browser.go`.
  # The Int is a history delta, not optional.
  def special_value_from_target("Elm.Kernel.Browser.go", args) when is_list(args),
    do: browser_history_go_cmd(16, args)

  def special_value_from_target("Browser.Navigation.go", args) when is_list(args),
    do: browser_history_go_cmd(16, args)

  def special_value_from_target("Browser.Navigation.back", args) when is_list(args),
    do: browser_history_go_cmd(10, args)

  def special_value_from_target("Browser.Navigation.forward", args) when is_list(args),
    do: browser_history_go_cmd(11, args)

  def special_value_from_target("Browser.Navigation.reload", _args) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{op: :browser_cmd, kind: %{op: :int_literal, value: 14}, params: []}
    else
      nil
    end
  end

  def special_value_from_target("Browser.Navigation.reloadAndSkipCache", _args) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{op: :browser_cmd, kind: %{op: :int_literal, value: 15}, params: []}
    else
      nil
    end
  end

  def special_value_from_target("Cmd.none", _args), do: %{op: :cmd_none}

  def special_value_from_target("Cmd.batch", [%{op: :list_literal, items: []}]),
    do: %{op: :cmd_none}

  def special_value_from_target("Cmd.batch", [%{op: :list_literal, items: [command]}]),
    do: command

  def special_value_from_target("Cmd.batch", [commands]),
    do: %{op: :runtime_call, function: "elmc_cmd_batch", args: [commands]}

  def special_value_from_target("Cmd.map", [f, cmd]),
    do: %{op: :runtime_call, function: "elmc_cmd_map", args: [f, cmd]}

  def special_value_from_target("Sub.none", _args), do: %{op: :sub_none}

  def special_value_from_target("Sub.batch", args) do
    case Subscriptions.subscription_batch_expr(args) do
      %{op: :unsupported} = unsupported ->
        unsupported

      %{op: :list_literal, items: items} = list_expr ->
        if Enum.any?(items, &match?(%{op: :pebble_sub}, &1)) do
          list_expr
        else
          %{op: :runtime_call, function: "elmc_sub_batch", args: [list_expr]}
        end

      nil ->
        case args do
          [%{op: :list_literal, items: []}] ->
            %{op: :sub_none}

          [%{op: :list_literal, items: [single]}] ->
            single

          [subs] ->
            %{op: :runtime_call, function: "elmc_sub_batch", args: [subs]}

          _ ->
            nil
        end
    end
  end

  def special_value_from_target("Sub.map", [f, sub]),
    do: %{op: :runtime_call, function: "elmc_sub_map", args: [f, sub]}

  def special_value_from_target("Debug.toString", []),
    do: %{
      op: :lambda,
      args: ["__v"],
      body: %{
        op: :runtime_call,
        function: "elmc_debug_to_string",
        args: [%{op: :var, name: "__v"}]
      }
    }

  def special_value_from_target("Debug.todo", []),
    do: Helpers.runtime_fn_lambda("elmc_debug_todo", ["__label"])

  def special_value_from_target("Debug.log", []),
    do: Helpers.runtime_fn_lambda("elmc_debug_log", ["__label", "__value"])

  def special_value_from_target("Debug.log", [label]),
    do: %{
      op: :lambda,
      args: ["__v"],
      body: %{
        op: :runtime_call,
        function: "elmc_debug_log",
        args: [label, %{op: :var, name: "__v"}]
      }
    }

  # --- elm/core: List ---
  def special_value_from_target("Task.map", [f, task]),
    do: %{op: :runtime_call, function: "elmc_task_map", args: [f, task]}

  def special_value_from_target("Task.map2", [f, a, b]),
    do: %{op: :runtime_call, function: "elmc_task_map2", args: [f, a, b]}

  def special_value_from_target("Task.map3", args) when is_list(args),
    do: task_map_n(3, args)

  def special_value_from_target("Task.map4", args) when is_list(args),
    do: task_map_n(4, args)

  def special_value_from_target("Task.map5", args) when is_list(args),
    do: task_map_n(5, args)

  def special_value_from_target("Task.sequence", []),
    do: Helpers.runtime_fn_lambda("elmc_task_sequence", ["__tasks"])

  def special_value_from_target("Task.sequence", [tasks]),
    do: %{op: :runtime_call, function: "elmc_task_sequence", args: [tasks]}

  def special_value_from_target("Task.andThen", [f, task]),
    do: %{op: :runtime_call, function: "elmc_task_and_then", args: [f, task]}

  def special_value_from_target("Task.onError", [f]),
    do: %{
      op: :lambda,
      args: ["__t"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_on_error",
        args: [f, %{op: :var, name: "__t"}]
      }
    }

  def special_value_from_target("Task.onError", [f, task]),
    do: %{op: :runtime_call, function: "elmc_task_on_error", args: [f, task]}

  # Official: onError (fail << func) task
  def special_value_from_target("Task.mapError", [f]),
    do: %{
      op: :lambda,
      args: ["__t"],
      body: special_value_from_target("Task.mapError", [f, %{op: :var, name: "__t"}])
    }

  def special_value_from_target("Task.mapError", [f, task]) do
    recover = %{
      op: :lambda,
      args: ["__err"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_fail",
        args: [
          %{op: :call, name: "__apply__", args: [f, %{op: :var, name: "__err"}]}
        ]
      }
    }

    %{op: :runtime_call, function: "elmc_task_on_error", args: [recover, task]}
  end

  def special_value_from_target("Task.perform", [to_msg]) do
    %{
      op: :lambda,
      args: ["__t"],
      body: special_value_from_target("Task.perform", [to_msg, %{op: :var, name: "__t"}])
    }
  end

  def special_value_from_target("Task.perform", [to_msg, task]) do
    mapped = %{op: :runtime_call, function: "elmc_task_map", args: [to_msg, task]}

    %{
      op: :tuple2,
      left: %{op: :int_literal, value: 1},
      right: mapped
    }
    |> then(&%{op: :runtime_call, function: "elmc_task_perform", args: [&1]})
  end

  # Official elm/core Task.attempt:
  #   task |> andThen (succeed << Ok) |> onError (succeed << Err) |> perform toMsg
  # Mapping Ok after onError (succeed << Err) produced Ok (Err x) instead of Err x.
  def special_value_from_target("Task.attempt", [to_msg]) do
    %{
      op: :lambda,
      args: ["__t"],
      body: special_value_from_target("Task.attempt", [to_msg, %{op: :var, name: "__t"}])
    }
  end

  def special_value_from_target("Task.attempt", [to_msg, task]) do
    ok_k = %{
      op: :lambda,
      args: ["__ok"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_succeed",
        args: [
          %{op: :constructor_call, target: "Ok", args: [%{op: :var, name: "__ok"}]}
        ]
      }
    }

    err_k = %{
      op: :lambda,
      args: ["__err"],
      body: %{
        op: :runtime_call,
        function: "elmc_task_succeed",
        args: [
          %{op: :constructor_call, target: "Err", args: [%{op: :var, name: "__err"}]}
        ]
      }
    }

    mapped = %{op: :runtime_call, function: "elmc_task_and_then", args: [ok_k, task]}
    recovered = %{op: :runtime_call, function: "elmc_task_on_error", args: [err_k, mapped]}
    special_value_from_target("Task.perform", [to_msg, recovered])
  end

  # --- elm/core: String (extended) ---

  def special_value_from_target(_target, _args), do: nil

  defp browser_history_go_cmd(kind, args) when is_integer(kind) and is_list(args) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      case args do
        [key, n] ->
          %{op: :browser_cmd, kind: %{op: :int_literal, value: kind}, params: [key, n]}

        [key] ->
          %{
            op: :lambda,
            args: ["__n"],
            body: %{
              op: :browser_cmd,
              kind: %{op: :int_literal, value: kind},
              params: [key, %{op: :var, name: "__n"}]
            }
          }

        [] ->
          %{
            op: :lambda,
            args: ["__key", "__n"],
            body: %{
              op: :browser_cmd,
              kind: %{op: :int_literal, value: kind},
              params: [%{op: :var, name: "__key"}, %{op: :var, name: "__n"}]
            }
          }

        _ ->
          nil
      end
    end
  end

  defp task_apply_expr do
    %{
      op: :lambda,
      args: ["__g", "__x"],
      body: %{
        op: :call,
        name: "__apply__",
        args: [%{op: :var, name: "__g"}, %{op: :var, name: "__x"}]
      }
    }
  end

  defp task_map2_expr(f, a, b),
    do: %{op: :runtime_call, function: "elmc_task_map2", args: [f, a, b]}

  defp task_map_n(n, args) when is_integer(n) and n >= 3 and is_list(args) do
    names = ["__f" | Enum.map(1..n, fn i -> "__t#{i}" end)]
    taken = Enum.take(args, n + 1)

    cond do
      length(taken) == n + 1 ->
        [f | tasks] = taken
        [a, b | rest] = tasks

        Enum.reduce(rest, task_map2_expr(f, a, b), fn task, acc ->
          task_map2_expr(task_apply_expr(), acc, task)
        end)

      length(taken) < n + 1 ->
        remaining = Enum.drop(names, length(taken))

        %{
          op: :lambda,
          args: remaining,
          body:
            task_map_n(
              n,
              taken ++ Enum.map(remaining, fn name -> %{op: :var, name: name} end)
            )
        }

      true ->
        nil
    end
  end

  # Official `onClick` / `onKeyDown` / … are `Decoder msg -> Sub msg` via
  # `on Document name decoder`, not Event -> msg.
  defp browser_events_on_document(name, decoder) when is_binary(name) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{
        op: :dom_sub,
        kind: %{op: :int_literal, value: 10},
        params: [
          %{op: :int_literal, value: 0},
          %{op: :string_literal, value: name},
          decoder
        ]
      }
    else
      nil
    end
  end

  @spec browser_events_mysub(map() | term()) ::
          {:ok, Types.ir_expr(), Types.ir_expr(), Types.ir_expr()} | :error

  defp browser_events_mysub(%{
         op: :constructor_call,
         target: target,
         args: [node, name, decoder]
       })
       when target in ["MySub", "Browser.Events.MySub"],
       do: {:ok, node, name, decoder}

  defp browser_events_mysub(%{
         op: :qualified_call,
         target: target,
         args: [node, name, decoder]
       })
       when target in ["MySub", "Browser.Events.MySub"],
       do: {:ok, node, name, decoder}

  defp browser_events_mysub(%{
         op: :tuple2,
         left: %{union_ctor: ctor},
         right: %{op: :tuple2, left: name, right: decoder}
       })
       when ctor in ["MySub", "Browser.Events.MySub"],
       do: {:ok, %{op: :int_literal, value: 0}, name, decoder}

  defp browser_events_mysub(%{
         op: :tuple2,
         left: %{union_ctor: ctor},
         right: %{op: :tuple2, left: node, right: %{op: :tuple2, left: name, right: decoder}}
       })
       when ctor in ["MySub", "Browser.Events.MySub"],
       do: {:ok, node, name, decoder}

  defp browser_events_mysub(_), do: :error
end
