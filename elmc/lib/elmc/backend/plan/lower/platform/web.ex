defmodule Elmc.Backend.Plan.Lower.Platform.Web do
  @moduledoc """
  Web platform plan lowering (`html_cmd`, virtual DOM patch, browser subscriptions).

  Phase 2 scaffold — emits plan platform ops consumed by `Wasm.Lower.Instr`.
  """

  alias Elmc.Backend.Plan.{Builder, Context, Types}
  alias Elmc.Backend.Plan.Lower.{Expr, If, Lambda}

  @spec compile_html_cmd(Types.ir_expr(), Context.t(), Builder.t()) ::
          Types.compile_result_required()
  def compile_html_cmd(%{params: params} = expr, ctx, b) do
    with {:ok, param_regs, b1} <- compile_params_scratch(params, ctx, b) do
      compile_platform_op(:html_cmd, Map.get(expr, :kind), param_regs, ctx, b1)
    else
      _ -> :unsupported
    end
  end

  def compile_html_cmd(_, _, _), do: :unsupported

  @spec compile_dom_sub(Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_dom_sub(%{kind: kind, params: params}, ctx, b) do
    with {:ok, param_regs, b1} <- compile_params_scratch(params, ctx, b) do
      compile_platform_op(:dom_sub, kind, param_regs, ctx, b1)
    end
  end

  def compile_dom_sub(_, _, _), do: :unsupported

  @spec web_target?(keyword() | map()) :: boolean()
  def web_target?(opts) when is_list(opts), do: opts |> Map.new() |> web_target?()

  def web_target?(opts) when is_map(opts) do
    Map.get(opts, :web, false) == true and Elmc.Backend.Wasm.Targets.emit_wasm?(opts)
  end

  @html_kinds %{
    "text" => 1,
    "node" => 2,
    "map" => 3,
    "attribute" => 4,
    "style" => 5,
    "lazy" => 6,
    "nodeNS" => 7,
    "event" => 8,
    "keyedNode" => 9,
    "keyedNodeNS" => 10,
    "lazy2" => 11,
    "lazy3" => 12,
    "lazy4" => 13
  }

  @html_special_fns ~w(text map node)

  @html_event_targets %{
    {"Html.Events", "onClick"} => "click",
    {"Html.Events", "onInput"} => "input",
    {"Html.Events", "onSubmit"} => "submit",
    {"Html.Events", "onCheck"} => "change",
    {"Html.Events", "onFocus"} => "focus",
    {"Html.Events", "onBlur"} => "blur",
    {"Html.Events", "onMouseDown"} => "mousedown",
    {"Html.Events", "onMouseUp"} => "mouseup",
    {"Html.Events", "onMouseMove"} => "mousemove",
    {"Html.Events", "onKeyDown"} => "keydown",
    {"Html.Events", "onKeyUp"} => "keyup",
    {"Html.Events", "onDoubleClick"} => "dblclick",
    {"VirtualDom", "on"} => "custom"
  }

  @html_call_targets %{
    {"Html", "text"} => 1,
    {"VirtualDom", "text"} => 1,
    {"Elm.Kernel.VirtualDom", "text"} => 1,
    {"Html", "node"} => 2,
    {"VirtualDom", "node"} => 2,
    {"Elm.Kernel.VirtualDom", "node"} => 2,
    {"Html", "map"} => 3,
    {"VirtualDom", "map"} => 3,
    {"Elm.Kernel.VirtualDom", "nodeNS"} => 7,
    {"Html.Lazy", "lazy"} => 6,
    {"VirtualDom", "lazy"} => 6,
    {"Html.Lazy", "lazy2"} => 11,
    {"VirtualDom", "lazy2"} => 11,
    {"Html.Lazy", "lazy3"} => 12,
    {"VirtualDom", "lazy3"} => 12,
    {"Html.Lazy", "lazy4"} => 13,
    {"VirtualDom", "lazy4"} => 13,
    {"Html.Keyed", "node"} => 9,
    {"VirtualDom", "keyedNode"} => 9,
    {"Elm.Kernel.VirtualDom", "keyedNode"} => 9,
    {"Elm.Kernel.VirtualDom", "keyedNodeNS"} => 10
  }

  @kernel_modules MapSet.new(["Elm.Kernel.VirtualDom", "VirtualDom"])

  @browser_kinds %{
    "application" => 1,
    "load" => 2,
    "pushUrl" => 3,
    "replaceUrl" => 4,
    "setViewport" => 5,
    "element" => 6,
    "document" => 7,
    "worker" => 8,
    "focus" => 9,
    "back" => 10,
    "forward" => 11,
    "setTitle" => 12
  }

  @bytes_kernel_kinds %{
    "width" => 1,
    "read_u8" => 2,
    "read_u32" => 3,
    "read_bytes" => 4,
    "decode" => 5,
    "decodeFailure" => 6,
    "encode" => 8,
    "read_f64" => 9,
    "read_string" => 10
  }

  # Elm.Kernel.Bytes read_* and decodeFailure are decoder step functions:
  # `Bytes -> Int -> (Int, a)`. They must not run `bytes_cmd` when the decoder
  # is constructed — only when invoked during `Bytes.Decode.decode`.
  @bytes_read_step_kinds MapSet.new([2, 3, 4, 6, 9, 10])

  @json_kernel_kinds %{
    "wrap" => 1,
    "encode" => 2,
    "emptyObject" => 3,
    "emptyArray" => 4,
    "addField" => 5,
    "addEntry" => 6,
    "encodeNull" => 7,
    "run" => 8,
    "runOnString" => 9,
    "decodeString" => 10,
    "decodeBool" => 11,
    "decodeInt" => 12,
    "decodeFloat" => 13,
    "decodeValue" => 14,
    "decodeList" => 15,
    "decodeArray" => 16,
    "decodeNull" => 17,
    "decodeField" => 18,
    "decodeIndex" => 19,
    "decodeKeyValuePairs" => 20,
    "map1" => 21,
    "map2" => 22,
    "map3" => 23,
    "map4" => 24,
    "map5" => 25,
    "map6" => 26,
    "map7" => 27,
    "map8" => 28,
    "andThen" => 29,
    "oneOf" => 30,
    "succeed" => 31,
    "fail" => 32
  }

  @html_attr_aliases %{
    {"Html.Attributes", "class"} => "class",
    {"Html.Attributes", "href"} => "href",
    {"Html.Attributes", "id"} => "id",
    {"Html.Attributes", "title"} => "title",
    {"Html.Attributes", "target"} => "target",
    {"Html.Attributes", "rel"} => "rel",
    {"Html.Attributes", "alt"} => "alt",
    {"Html.Attributes", "src"} => "src",
    {"Html.Attributes", "type_"} => "type"
  }

  @spec rewrite_html_tag_function_decl(String.t(), map(), keyword() | map()) :: map()
  def rewrite_html_tag_function_decl(module, decl, opts \\ [])

  def rewrite_html_tag_function_decl("Html", %{name: name, expr: expr} = decl, opts) do
    with true <- web_target?(opts),
         true <- html_element_tag?(name),
         tag when is_binary(tag) <- html_tag_literal_from_node_partial(expr) do
      decl
      |> Map.put(:args, ["attrs", "children"])
      |> Map.put(:expr, %{
        op: :html_cmd,
        kind: %{op: :int_literal, value: 2},
        params: [
          %{op: :string_literal, value: tag},
          %{op: :var, name: "attrs"},
          %{op: :var, name: "children"}
        ]
      })
    else
      _ -> decl
    end
  end

  def rewrite_html_tag_function_decl(_module, decl, _opts), do: decl

  @html_map_modules MapSet.new(["Html", "VirtualDom", "Elm.Kernel.VirtualDom"])
  @html_map_param_names ["func", "node"]

  @spec rewrite_html_map_function_decl(String.t(), map(), keyword() | map()) :: map()
  def rewrite_html_map_function_decl(module, decl, opts \\ [])

  def rewrite_html_map_function_decl(module, %{name: "map"} = decl, opts) do
    cond do
      web_target?(opts) and MapSet.member?(@html_map_modules, module) and html_map_alias_decl?(decl) ->
        rewrite_html_map_two_arg_decl(decl)

      web_target?(opts) and match?([_, _], Map.get(decl, :args, [])) and
          MapSet.member?(@html_map_modules, module) ->
        rewrite_html_map_two_arg_decl(decl)

      true ->
        decl
    end
  end

  def rewrite_html_map_function_decl(_module, decl, _opts), do: decl

  @spec rewrite_partial_html_map_function_decl(String.t(), map(), keyword() | map()) :: map()
  def rewrite_partial_html_map_function_decl(_module, decl, opts \\ [])

  def rewrite_partial_html_map_function_decl(_module, decl, opts) do
    with true <- web_target?(opts),
         {:ok, mapper, html_var} <- html_map_partial(Map.get(decl, :expr)) do
      decl
      |> Map.put(:args, [html_var])
      |> Map.put(:expr, html_map_cmd_expr(mapper, html_var))
    else
      _ -> decl
    end
  end

  defp rewrite_html_map_two_arg_decl(decl) do
    param_names =
      case Map.get(decl, :args, []) do
        [fn_name, node_name] -> [fn_name, node_name]
        _ -> @html_map_param_names
      end

    [fn_name, node_name] = param_names

    decl
    |> Map.put(:args, param_names)
    |> Map.put(:expr, html_map_cmd_expr(%{op: :var, name: fn_name}, node_name))
  end

  defp html_map_cmd_expr(mapper_expr, html_name) when is_binary(html_name) do
    %{
      op: :html_cmd,
      kind: %{op: :int_literal, value: 3},
      params: [mapper_expr, %{op: :var, name: html_name}]
    }
  end

  defp html_map_alias_decl?(%{expr: %{op: :qualified_call, target: target, args: []}})
       when target in ["VirtualDom.map", "Elm.Kernel.VirtualDom.map"],
       do: true

  defp html_map_alias_decl?(_), do: false

  @spec rewrite_html_lazy_function_decl(String.t(), map(), keyword() | map()) :: map()
  def rewrite_html_lazy_function_decl(module, decl, opts \\ [])

  def rewrite_html_lazy_function_decl(module, %{name: "lazy"} = decl, opts)
      when module in ["Html.Lazy", "VirtualDom"] do
    if web_target?(opts) do
      Map.merge(decl, %{
        args: ["fn", "arg"],
        expr: %{
          op: :html_cmd,
          kind: %{op: :int_literal, value: 6},
          params: [%{op: :var, name: "fn"}, %{op: :var, name: "arg"}]
        }
      })
    else
      decl
    end
  end

  def rewrite_html_lazy_function_decl(_module, decl, _opts), do: decl

  @doc """
  Apply all web function-decl rewrites (tag helpers, Html.map, partial Html.map,
  Html.lazy). Idempotent. Used when lowering a function *body*.
  """
  @spec rewrite_function_decl(String.t(), map(), keyword() | map()) :: map()
  def rewrite_function_decl(module, decl, opts \\ []) when is_binary(module) and is_map(decl) do
    decl
    |> then(&rewrite_html_tag_function_decl(module, &1, opts))
    |> then(&rewrite_html_map_function_decl(module, &1, opts))
    |> then(&rewrite_partial_html_map_function_decl(module, &1, opts))
    |> then(&rewrite_html_lazy_function_decl(module, &1, opts))
  end

  @doc """
  Sync call-site arity with eta-expanded partial `Html.map` bindings
  (`wrap = Html.map identity` → 1-arg). Does **not** rewrite Html tag
  helpers in the map — those stay CAF-shaped for call sites; only the
  callee body rewrite (via `rewrite_function_decl/3`) eta-expands them.
  """
  @spec rewrite_decl_map(map(), keyword() | map()) :: map()
  def rewrite_decl_map(decl_map, opts \\ []) when is_map(decl_map) do
    Map.new(decl_map, fn
      {{module, _name} = key, decl} when is_binary(module) and is_map(decl) ->
        {key, rewrite_partial_html_map_function_decl(module, decl, opts)}

      other ->
        other
    end)
  end

  defp html_map_partial(%{
         op: :qualified_call,
         target: target,
         args: [mapper]
       })
       when target in ["Html.map", "VirtualDom.map", "Elm.Kernel.VirtualDom.map"] do
    {:ok, mapper, "html"}
  end

  defp html_map_partial(_), do: :error

  defp html_tag_literal_from_node_partial(%{
         op: :qualified_call,
         target: target,
         args: [%{op: :string_literal, value: tag}]
       })
       when target in ["Elm.Kernel.VirtualDom.node", "VirtualDom.node", "Html.node"] and is_binary(tag),
       do: tag

  defp html_tag_literal_from_node_partial(_), do: nil

  @spec compile_html_call(String.t(), String.t(), [Types.ir_expr()], Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_html_call(module, name, args, ctx, b) do
    opts = Process.get(:elmc_codegen_opts, %{})

    cond do
      web_target?(opts) and module == "Browser" and Map.has_key?(@browser_kinds, name) and is_list(args) ->
        compile_browser_cmd(name, args, ctx, b)

      web_target?(opts) and match?([_], args) and Map.has_key?(@html_event_targets, {module, name}) ->
        [msg] = args
        event_name = Map.fetch!(@html_event_targets, {module, name})
        compile_html_event(event_name, msg, ctx, b)

      # VirtualDom.on : String -> Handler msg -> Attribute msg (real 2-arg API)
      web_target?(opts) and module in ["VirtualDom", "Elm.Kernel.VirtualDom", "Html.Events"] and
          name == "on" and match?([_, _], args) ->
        [event, handler] = args
        compile_html_cmd(
          %{
            op: :html_cmd,
            kind: %{op: :int_literal, value: 8},
            params: [event, handler]
          },
          ctx,
          b
        )

      web_target?(opts) and module == "VirtualDom" and name == "on" and match?([_, _, _], args) ->
        [event, decoder, handler] = args
        compile_html_event_expr(event, decoder, handler, ctx, b)

      web_target?(opts) and match?([_], args) and Map.has_key?(@html_attr_aliases, {module, name}) ->
        [value] = args
        key = Map.fetch!(@html_attr_aliases, {module, name})
        compile_html_attr([%{op: :string_literal, value: key}, value], ctx, b)

      web_target?(opts) and module == "Html.Attributes" and name == "stringProperty" and
          match?([_, _], args) ->
        compile_html_property(args, ctx, b)

      web_target?(opts) and module == "Html.Attributes" and name == "attribute" and
          match?([_, _], args) ->
        compile_html_attr(args, ctx, b)

      web_target?(opts) and module == "Html.Attributes" and name == "style" and match?([_, _], args) ->
        compile_html_style(args, ctx, b)

      web_target?(opts) and module == "Html" and html_element_tag?(name) and match?([_, _], args) ->
        [attrs, children] = args

        compile_html_cmd(
          %{
            op: :html_cmd,
            kind: %{op: :int_literal, value: 2},
            params: [
              %{op: :string_literal, value: html_element_tag(name)},
              attrs,
              children
            ]
          },
          ctx,
          b
        )

      web_target?(opts) and module == "Svg.Attributes" and match?([_], args) ->
        [value] = args
        key = virtual_dom_attribute_key(name)
        compile_html_attr([%{op: :string_literal, value: key}, value], ctx, b)

      # Unqualified attribute helpers (e.g. after incomplete import resolution):
      # if the callee name was defined as VirtualDom.attribute "…", use that key.
      web_target?(opts) and match?([_], args) and virtual_dom_attribute_call?(module, name, ctx) ->
        [value] = args
        key = virtual_dom_attribute_key(name)
        compile_html_attr([%{op: :string_literal, value: key}, value], ctx, b)

      web_target?(opts) and module == "Svg" and svg_element_tag?(name) and match?([_, _], args) ->
        [attrs, children] = args

        compile_html_cmd(
          %{
            op: :html_cmd,
            kind: %{op: :int_literal, value: 7},
            params: [
              %{op: :string_literal, value: "http://www.w3.org/2000/svg"},
              %{op: :string_literal, value: svg_element_tag_name(name)},
              attrs,
              children
            ]
          },
          ctx,
          b
        )

      web_target?(opts) and module in ["Html.Lazy", "VirtualDom"] and name == "lazy" and
          match?([_, _], args) ->
        compile_html_cmd(
          %{
            op: :html_cmd,
            kind: %{op: :int_literal, value: 6},
            params: args
          },
          ctx,
          b
        )

      web_target?(opts) and module in ["Html", "VirtualDom", "Elm.Kernel.VirtualDom"] and name == "map" and
          length(args) < 2 ->
        :unsupported

      true ->
        with true <- web_target?(opts),
             kind when is_integer(kind) <- Map.get(@html_call_targets, {module, name}),
             true <- is_list(args) and args != [] do
          compile_html_cmd(
            %{
              op: :html_cmd,
              kind: %{op: :int_literal, value: kind},
              params: args
            },
            ctx,
            b
          )
        else
          _ -> :unsupported
        end
    end
  end

  @spec compile_kernel_call(String.t(), String.t(), [Types.ir_expr()], Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_kernel_call(module, name, args, ctx, b) do
    opts = Process.get(:elmc_codegen_opts, %{})

    cond do
      web_target?(opts) and module == "Elm.Kernel.VirtualDom" and
          name in ["noJavaScriptUri", "noJavaScriptOrHtmlUri", "noOnOrFormAction", "noScript"] and
          match?([_], args) ->
        [arg] = args
        Expr.compile(arg, ctx, b)

      web_target?(opts) and module in ["VirtualDom", "Elm.Kernel.VirtualDom"] and name == "on" and
          match?([_, _], args) ->
        [event, handler] = args

        compile_html_cmd(
          %{
            op: :html_cmd,
            kind: %{op: :int_literal, value: 8},
            params: [event, handler]
          },
          ctx,
          b
        )

      web_target?(opts) and module in ["VirtualDom", "Elm.Kernel.VirtualDom"] and name == "nodeNS" and
          match?([_, _, _], args) ->
        compile_html_cmd(
          %{
            op: :html_cmd,
            kind: %{op: :int_literal, value: 7},
            params: args
          },
          ctx,
          b
        )

      web_target?(opts) and module == "Elm.Kernel.VirtualDom" and name == "property" and
          match?([_, _], args) ->
        compile_html_attr(args, ctx, b)

      web_target?(opts) and module == "Elm.Kernel.VirtualDom" and name == "style" and
          match?([_, _], args) ->
        compile_html_style(args, ctx, b)

      web_target?(opts) and module == "Elm.Kernel.Browser" and is_list(args) ->
        compile_browser_cmd(name, args, ctx, b)

      web_target?(opts) and module == "Elm.Kernel.Json" and is_list(args) ->
        compile_json_kernel_call(name, args, ctx, b)

      web_target?(opts) and module == "Elm.Kernel.Bytes" and is_list(args) ->
        compile_bytes_kernel_call(name, args, ctx, b)

      web_target?(opts) and module == "Elm.Kernel.Parser" and is_list(args) ->
        compile_parser_kernel_call(name, args, ctx, b)

      true ->
        with true <- web_target?(opts),
             true <- MapSet.member?(@kernel_modules, module),
             kind when is_integer(kind) <- Map.get(@html_kinds, name),
             true <- is_list(args) do
          compile_html_cmd(
            %{
              op: :html_cmd,
              kind: %{op: :int_literal, value: kind},
              params: args
            },
            ctx,
            b
          )
        else
          _ -> :unsupported
        end
    end
  end

  @doc false
  @spec html_element_tag?(String.t()) :: boolean()
  def html_element_tag?(name) when is_binary(name) do
    name != "" and name not in @html_special_fns and Regex.match?(~r/^[a-z][a-z0-9_]*$/, name)
  end

  def html_element_tag?(_name), do: false

  @doc false
  @spec svg_element_tag?(String.t()) :: boolean()
  def svg_element_tag?(name) when is_binary(name) do
    tag = svg_element_tag_name(name)
    tag != "" and Regex.match?(~r/^[a-z][a-z0-9]*$/, tag)
  end

  def svg_element_tag?(_), do: false

  defp svg_element_tag_name(name) when is_binary(name) do
    name
    |> String.trim_trailing("_")
  end

  defp virtual_dom_attribute_call?(module, name, ctx)
       when is_binary(module) and is_binary(name) and is_map(ctx) do
    decl_map = Map.get(ctx, :decl_map, %{})
    attr_keys = Process.get(:elmc_svg_attribute_dom_names, %{})
    attr_names = Process.get(:elmc_svg_attribute_names, MapSet.new())

    not Map.has_key?(decl_map, {module, name}) and
      (Map.has_key?(attr_keys, name) or MapSet.member?(attr_names, name) or
         Map.has_key?(decl_map, {"Svg.Attributes", name}) or
         Map.has_key?(decl_map, {"Html.Attributes", name}))
  end

  defp virtual_dom_attribute_call?(_, _, _), do: false

  defp virtual_dom_attribute_key(name) when is_binary(name) do
    case Process.get(:elmc_svg_attribute_dom_names, %{}) do
      %{^name => key} when is_binary(key) -> key
      _ -> name
    end
  end

  @doc false
  @spec html_element_param_names(String.t(), String.t()) :: [String.t()] | nil
  def html_element_param_names("Html", name) when is_binary(name) do
    if html_element_tag?(name), do: ["attrs", "children"], else: nil
  end

  def html_element_param_names("Svg", name) when is_binary(name) do
    if svg_element_tag?(name), do: ["attrs", "children"], else: nil
  end

  def html_element_param_names(_module, _name), do: nil

  defp html_element_tag(name) when is_binary(name), do: String.trim_trailing(name, "_")

  defp compile_html_attr(params, ctx, b) when is_list(params) do
    compile_html_cmd(
      %{
        op: :html_cmd,
        kind: %{op: :int_literal, value: 4},
        params: params
      },
      ctx,
      b
    )
  end

  defp compile_html_style(params, ctx, b) when is_list(params) do
    compile_html_cmd(
      %{
        op: :html_cmd,
        kind: %{op: :int_literal, value: 5},
        params: params
      },
      ctx,
      b
    )
  end

  defp compile_html_property(params, ctx, b) when is_list(params) do
    compile_html_cmd(
      %{
        op: :html_cmd,
        kind: %{op: :int_literal, value: 14},
        params: params
      },
      ctx,
      b
    )
  end

  defp compile_html_event(event_name, msg, ctx, b) when is_binary(event_name) do
    compile_html_cmd(
      %{
        op: :html_cmd,
        kind: %{op: :int_literal, value: 8},
        params: [%{op: :string_literal, value: event_name}, msg]
      },
      ctx,
      b
    )
  end

  defp compile_html_event_expr(event, decoder, handler, ctx, b) do
    compile_html_cmd(
      %{
        op: :html_cmd,
        kind: %{op: :int_literal, value: 8},
        params: [event, decoder, handler]
      },
      ctx,
      b
    )
  end

  @spec compile_browser_cmd(String.t(), [Types.ir_expr()], Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_browser_cmd(name, params, ctx, b) when is_binary(name) and is_list(params) do
    with kind when is_integer(kind) <- Map.get(@browser_kinds, name),
         {:ok, param_regs, b1} <- compile_params_scratch(params, ctx, b) do
      compile_platform_op(:browser_cmd, %{op: :int_literal, value: kind}, param_regs, ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_json_kernel_call(name, params, ctx, b) when is_binary(name) and is_list(params) do
    with kind when is_integer(kind) <- Map.get(@json_kernel_kinds, name),
         {:ok, param_regs, b1} <- compile_params_scratch(params, ctx, b) do
      compile_platform_op(:json_cmd, %{op: :int_literal, value: kind}, param_regs, ctx, b1)
    else
      _ -> :unsupported
    end
  end

  @spec compile_bytes_cmd(Types.ir_expr(), Context.t(), Builder.t()) ::
          Types.compile_result_required()
  def compile_bytes_cmd(%{params: params} = expr, ctx, b) do
    with {:ok, param_regs, b1} <- compile_params_scratch(params, ctx, b) do
      compile_platform_op(:bytes_cmd, Map.get(expr, :kind), param_regs, ctx, b1)
    else
      _ -> :unsupported
    end
  end

  @parser_kernel_kinds %{
    "isSubString" => 1,
    "isSubChar" => 2
  }

  @spec compile_parser_cmd(Types.ir_expr(), Context.t(), Builder.t()) ::
          Types.compile_result_required()
  def compile_parser_cmd(%{params: params} = expr, ctx, b) do
    with {:ok, param_regs, b1} <- compile_params_scratch(params, ctx, b) do
      compile_platform_op(:parser_cmd, Map.get(expr, :kind), param_regs, ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_parser_kernel_call(name, params, ctx, b) when is_binary(name) and is_list(params) do
    with kind when is_integer(kind) <- Map.get(@parser_kernel_kinds, name) do
      with {:ok, param_regs, b1} <- compile_params_scratch(params, ctx, b) do
        compile_platform_op(:parser_cmd, %{op: :int_literal, value: kind}, param_regs, ctx, b1)
      end
    else
      _ -> :unsupported
    end
  end

  defp compile_bytes_kernel_call(name, params, ctx, b) when is_binary(name) and is_list(params) do
    with kind when is_integer(kind) <- Map.get(@bytes_kernel_kinds, name) do
      if MapSet.member?(@bytes_read_step_kinds, kind) do
        compile_bytes_read_step(kind, params, ctx, b)
      else
        with {:ok, param_regs, b1} <- compile_params_scratch(params, ctx, b) do
          compile_platform_op(:bytes_cmd, %{op: :int_literal, value: kind}, param_regs, ctx, b1)
        end
      end
    else
      _ -> :unsupported
    end
  end

  defp compile_bytes_read_step(kind, params, ctx, b) when is_integer(kind) and is_list(params) do
    with {:ok, capture_regs, b1} <- compile_bytes_capture_params(params, ctx, b),
         {:ok, ctx2, b2} <- bind_bytes_read_capture_locals(capture_regs, ctx, b1) do
      capture_names =
        capture_regs
        |> Enum.with_index()
        |> Enum.map(fn {_, idx} -> bytes_read_capture_name(idx) end)

      body = %{
        op: :bytes_cmd,
        kind: %{op: :int_literal, value: kind},
        params:
          Enum.map(capture_names, &%{op: :var, name: &1}) ++
            [
              %{op: :var, name: "__bytes__"},
              %{op: :var, name: "__offset__"}
            ]
      }

      Lambda.compile(
        %{op: :lambda, args: ["__bytes__", "__offset__"], body: body},
        ctx2,
        b2
      )
    else
      _ -> :unsupported
    end
  end

  defp bind_bytes_read_capture_locals(capture_regs, ctx, b) do
    Enum.reduce(Enum.with_index(capture_regs), {:ok, ctx, b}, fn {reg, idx}, {:ok, ctx_acc, b_acc} ->
      name = bytes_read_capture_name(idx)
      ctx1 = Context.put_local(ctx_acc, name, reg)
      b1 = Builder.bind_local(b_acc, name, reg)
      {:ok, ctx1, b1}
    end)
  end

  defp bytes_read_capture_name(idx) when is_integer(idx), do: "__bytes_read_arg_#{idx}__"

  defp compile_bytes_capture_params(params, ctx, b) when is_list(params) do
    Enum.reduce_while(params, {:ok, [], b}, fn param, {:ok, acc, b_acc} ->
      case compile_bytes_capture_param(param, ctx, b_acc) do
        {:ok, reg, b1} when is_integer(reg) -> {:cont, {:ok, acc ++ [reg], b1}}
        _ -> {:halt, :unsupported}
      end
    end)
  end

  defp compile_bytes_capture_param(%{op: :compare} = cmp, ctx, b) do
    If.compile(
      %{
        op: :if,
        cond: cmp,
        then_expr: %{op: :int_literal, value: 1},
        else_expr: %{op: :int_literal, value: 0}
      },
      ctx,
      b
    )
  end

  defp compile_bytes_capture_param(param, ctx, b) do
    scratch_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

    case Expr.compile(param, scratch_ctx, b) do
      {:ok, reg, b1} when is_integer(reg) -> {:ok, reg, b1}
      _ -> :unsupported
    end
  end

  defp compile_platform_op(op, kind, param_regs, ctx, b) do
    wrap_catch? = Builder.wrap_fallible_instr_catch?(b, ctx, true)
    b1 = if wrap_catch?, do: Builder.catch_begin(b), else: b

    {dest, b_dest} =
      if Context.function_tail?(ctx) do
        {:fn_out, b1}
      else
        Builder.fresh_reg(b1)
      end

    effects = borrow_only_platform_effects(dest, param_regs)

    {_, b2} =
      Builder.emit(b_dest, op, %{
        dest: dest,
        args: %{kind: normalize_kind(kind), params: param_regs},
        effects: effects
      })

    b3 = if wrap_catch?, do: Builder.catch_end(b2), else: b2

    if dest == :fn_out do
      {_, b4} =
        Builder.emit(b3, :publish, %{
          dest: :fn_out,
          args: %{},
          effects: Types.empty_effects()
        })

      {:ok, :fn_out, b4}
    else
      {:ok, dest, b3}
    end
  end

  defp borrow_only_platform_effects(dest, param_regs) do
    if is_integer(dest) do
      Types.fallible_effects(dest, param_regs, [])
    else
      %{produces: nil, consumes: [], borrows: param_regs, fallible: true}
    end
  end

  defp compile_params_scratch(params, ctx, b) when is_list(params) do
    scratch_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

    Enum.reduce_while(params, {:ok, [], b}, fn param, {:ok, acc, b_acc} ->
      case Expr.compile(param, scratch_ctx, b_acc) do
        {:ok, reg, b1} when is_integer(reg) -> {:cont, {:ok, acc ++ [reg], b1}}
        _ -> {:halt, :unsupported}
      end
    end)
  end

  defp normalize_kind(%{op: :int_literal, value: value}) when is_integer(value), do: value
  defp normalize_kind(%{op: :c_int_expr, value: value}), do: %{c_expr: value}
  defp normalize_kind(kind) when is_integer(kind), do: kind
  defp normalize_kind(kind), do: kind
end
