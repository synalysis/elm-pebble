defmodule Elmc.Backend.Plan.Lower.Call do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{FunctionEmit, Util}
  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.{CallCoerce, Cmd, Expr, Lambda, MaybeMap, Platform.Web, Port, Record, SpecialValues}
  alias Elmc.Backend.Plan.Types

  @browser_cmd_kind_names %{
    1 => "application",
    2 => "load",
    3 => "pushUrl",
    4 => "replaceUrl",
    5 => "setViewport",
    6 => "element",
    7 => "document",
    8 => "worker",
    9 => "focus",
    10 => "back",
    11 => "forward",
    12 => "setTitle"
  }

  @spec compile_call(Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | nil, Builder.t()} | :unsupported
  def compile_call(%{op: op} = expr, ctx, b)
      when op in [:qualified_call, :call] do
    target = Map.get(expr, :target) || Map.get(expr, :name)
    args = Map.get(expr, :args, [])

    cond do
      batch_target?(target) ->
        compile_batch_call(target, args, ctx, b)

      true ->
        compile_fn_call(expr, target, args, ctx, b)
    end
  end

  def compile_call(_, _, _), do: :unsupported

  defp compile_fn_call(expr, target, args, ctx, b) do
    cond do
      target == "__apply__" ->
        compile_apply_call(args, ctx, b)

      ui_to_ui_node?(target) ->
        compile_ui_to_ui_node(args, ctx, b)

      true ->
        compile_fn_call_default(expr, target, args, ctx, b)
    end
  end

  defp ui_to_ui_node?(target) when is_binary(target),
    do: target in ["Pebble.Ui.toUiNode", "PebbleUi.toUiNode", "Ui.toUiNode"]

  defp ui_to_ui_node?(_), do: false

  defp compile_ui_to_ui_node([ops], ctx, b) do
    with {:ok, [ops_reg], b1} <- Expr.compile_args([ops], ctx, b) do
      Expr.compile_runtime_builtin(:retain, [ops_reg], ctx, b1)
    end
  end

  defp compile_ui_to_ui_node(_, _, _), do: :unsupported

  # Generic function application for value-level call targets.
  # Used by lowerer rewrites (compose, partials, etc) when applying a computed function value.
  defp compile_apply_call([fn_expr, arg_expr], ctx, b) do
    case MaybeMap.field_accessor_lambda(fn_expr) do
      {:ok, field} ->
        with {:ok, arg_reg, b1} <- Expr.compile(arg_expr, ctx, b),
             {:ok, field_reg, b2} <-
               Record.emit_record_field_get(arg_reg, field, ctx, b1, arg_expr) do
          {:ok, field_reg, b2}
        else
          _ -> :unsupported
        end

      :error ->
        scratch_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}

        with {:ok, fn_reg, b1} when is_integer(fn_reg) <- Expr.compile(fn_expr, scratch_ctx, b) do
          compile_closure_call_from_reg(fn_reg, [arg_expr], ctx, b1)
        else
          _ -> :unsupported
        end
    end
  end

  # Defense: left-fold n-ary `__apply__` into nested binary applies (C codegen
  # already does this; IR compose nesting should prevent n-ary, but tolerate it).
  defp compile_apply_call([fn_expr | args], ctx, b)
       when is_list(args) and length(args) >= 2 do
    nested =
      Enum.reduce(args, fn_expr, fn arg, acc ->
        %{op: :call, name: "__apply__", args: [acc, arg]}
      end)

    Expr.compile(nested, ctx, b)
  end

  defp compile_apply_call(_, _ctx, _b), do: :unsupported

  defp compile_fn_call_default(_expr, target, args, ctx, b) do
    case call_rewrite(target, args) do
      %{op: :pebble_cmd} = rewritten ->
        Cmd.compile(rewritten, ctx, b)

      nil ->
        compile_fn_call_special_or_target(target, args, ctx, b)

      rewritten ->
        case compile_special_rewrite(rewritten, args, ctx, b) do
          :unsupported -> compile_fn_call_special_or_target(target, args, ctx, b)
          other -> other
        end
    end
  end

  defp compile_fn_call_special_or_target(target, args, ctx, b) do
    case try_compile_qualified_field_call(target, args, ctx, b) do
      {:ok, dest, b1} ->
        {:ok, dest, b1}

      :unsupported ->
        {module, name} = parse_target(target, ctx, ctx.decl_map)

        case SpecialValues.special_value_from_target("#{module}.#{name}", args) do
          nil ->
            compile_fn_call_target(module, name, args, ctx, b)

          rewritten ->
            case compile_special_rewrite(rewritten, args, ctx, b) do
              :unsupported -> compile_fn_call_target(module, name, args, ctx, b)
              other -> other
            end
        end
    end
  end

  defp try_compile_qualified_field_call(target, args, ctx, b)
       when is_binary(target) and is_list(args) do
    parts = String.split(target, ".", trim: true)
    decl_map = ctx.decl_map
    n = length(parts)

    if n < 3 do
      :unsupported
    else
      Enum.reduce_while(n - 2..1//-1, :unsupported, fn j, _acc ->
        module = parts |> Enum.take(j) |> Enum.join(".")
        binding = Enum.at(parts, j)
        fields = Enum.drop(parts, j + 1)

        if fields != [] and Map.has_key?(decl_map, {module, binding}) do
          case compile_module_binding_field_call(module, binding, fields, args, ctx, b) do
            {:ok, _, _} = ok -> {:halt, ok}
            _ -> {:cont, :unsupported}
          end
        else
          {:cont, :unsupported}
        end
      end)
      |> case do
        :unsupported -> :unsupported
        other -> other
      end
    end
  end

  defp try_compile_qualified_field_call(_, _, _, _), do: :unsupported

  defp compile_module_binding_field_call(module, binding, fields, args, ctx, b)
       when is_binary(module) and is_binary(binding) and is_list(fields) and is_list(args) do
    field_ir =
      Enum.reduce(fields, %{op: :qualified_ref, target: "#{module}.#{binding}"}, fn field, acc ->
        %{op: :field_access, arg: acc, field: field}
      end)

    with {:ok, callee_reg, b1} <- Expr.compile(field_ir, ctx, b) do
      if args == [] do
        {:ok, callee_reg, b1}
      else
        compile_closure_call_from_reg(callee_reg, args, ctx, b1)
      end
    else
      _ -> :unsupported
    end
  end

  defp compile_special_rewrite(%{op: :pebble_cmd} = rewritten, _args, ctx, b),
    do: Cmd.compile(rewritten, ctx, b)

  defp compile_special_rewrite(%{op: :browser_cmd} = rewritten, _args, ctx, b) do
    kind = Map.get(rewritten, :kind)
    params = Map.get(rewritten, :params, [])

    kind_int =
      case kind do
        value when is_integer(value) -> value
        %{op: :int_literal, value: value} when is_integer(value) -> value
        %{value: value} when is_integer(value) -> value
        _ -> nil
      end

    kind_name = kind_int && Map.get(@browser_cmd_kind_names, kind_int)

    if kind_name do
      Web.compile_browser_cmd(kind_name, params, ctx, b)
    else
      :unsupported
    end
  end

  defp compile_special_rewrite(%{op: :html_cmd} = rewritten, _args, ctx, b),
    do: Web.compile_html_cmd(rewritten, ctx, b)

  defp compile_special_rewrite(%{op: :dom_sub} = rewritten, _args, ctx, b),
    do: Web.compile_dom_sub(rewritten, ctx, b)

  defp compile_special_rewrite(
         %{op: :c_int_expr, value: "ELMC_PEBBLE_CMD_" <> _} = kind,
         args,
         ctx,
         b
       )
       when is_list(args) do
    Cmd.compile(%{op: :pebble_cmd, kind: kind, params: args}, ctx, b)
  end

  defp compile_special_rewrite(%{op: op} = rewritten, _args, ctx, b)
       when is_atom(op) and op != :unsupported,
       do: Expr.compile(rewritten, ctx, b)

  defp compile_special_rewrite(_rewritten, _args, _ctx, _b), do: :unsupported

  defp call_rewrite(target, args) do
    case SpecialValues.special_value_from_target(target, args) do
      %{op: :call, name: ^target, args: ^args} -> nil
      other -> other
    end
  end

  @spec compile_closure_call_from_reg(integer(), [Types.ir_expr()], Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_closure_call_from_reg(callee_reg, args, ctx, b) when is_integer(callee_reg) do
    do_compile_closure_call(callee_reg, args, ctx, b)
  end

  defp compile_fn_call_target(module, name, args, ctx, b) do
    {module, name} = rewrite_web_call_target(module, name)

    case Web.compile_html_call(module, name, args, ctx, b) do
      {:ok, dest, b1} ->
        {:ok, dest, b1}

      :unsupported ->
        case Web.compile_kernel_call(module, name, args, ctx, b) do
          {:ok, dest, b1} -> {:ok, dest, b1}
          :unsupported -> do_compile_fn_call_target(module, name, args, ctx, b)
        end
    end
  end

  defp do_compile_fn_call_target(module, name, args, ctx, b) do
    {module, name} = resolve_delegate_call_target(module, name, args, ctx.decl_map)

    case Port.compile_call(module, name, args, ctx, b) do
      {:ok, dest, b1} ->
        {:ok, dest, b1}

      :unsupported ->
        do_compile_fn_call_target_after_ports(module, name, args, ctx, b)
    end
  end

  defp do_compile_fn_call_target_after_ports(module, name, args, ctx, b) do
    cond do
      oversaturated_call?(ctx, module, name, args) ->
        compile_oversaturated_call(module, name, args, ctx, b)

      zero_arity_thunk_call?(ctx, module, name, args) ->
        compile_oversaturated_call(module, name, args, ctx, b)

      true ->
        # Locals/params may shadow *unqualified* / same-module bare names only.
        # Qualified `Html.Attributes.width` must not pick up a local `width`
        # (Scene3d.composite binds `(width, height)` then calls the Attributes helpers).
        with true <- local_callee_shadow_allowed?(module, ctx),
             {:ok, callee_reg, b_callee} <- closure_callee_reg(name, ctx, b),
             true <- args != [] do
          compile_closure_call(callee_reg, args, ctx, b_callee)
        else
          _ ->
            case Map.fetch(ctx.decl_map, {module, name}) do
              {:ok, decl} ->
                param_names = FunctionEmit.effective_decl_args(decl, module, ctx.decl_map) |> List.wrap()

                if length(param_names) > 0 and length(args) < length(param_names) do
                  compile_curried_lambda(module, name, param_names, args, ctx, b)
                else
                  with {:ok, arg_regs, b1} <- Expr.compile_args(args, ctx, b) do
                    {dest, b2} = dest_for_call(ctx, b1)
                    compile_fn_call_emit(module, name, arg_regs, dest, ctx, b2, args)
                  else
                    _ -> :unsupported
                  end
                end

              :error ->
                cond do
                  html_element_partial?(module, name, args) ->
                    compile_curried_lambda(module, name, ["attrs", "children"], args, ctx, b)

                  args == [] and zero_arg_fn_ref?(module) ->
                    compile_kernel_fn_ref(module, name, ctx, b)

                  true ->
                    with {:ok, arg_regs, b1} <- Expr.compile_args(args, ctx, b) do
                      {dest, b2} = dest_for_call(ctx, b1)
                      compile_fn_call_emit(module, name, arg_regs, dest, ctx, b2, args)
                    else
                      _ -> :unsupported
                    end
                end
            end
        end
    end
  end

  # Unqualified `width x` lowers as `{ctx.module, "width"}` and may apply a local.
  # Cross-module qualified targets must call the named decl, not a same-named local.
  defp local_callee_shadow_allowed?(module, ctx) when is_binary(module) do
    module == (ctx.module || "Main")
  end

  defp html_element_partial?(module, name, args)
       when is_binary(module) and is_binary(name) and is_list(args) do
    opts = Process.get(:elmc_codegen_opts, %{})

    Elmc.Backend.Plan.Lower.Platform.Web.web_target?(opts) and
      length(args) < 2 and
      ((module == "Html" and Elmc.Backend.Plan.Lower.Platform.Web.html_element_tag?(name)) or
         (module == "Svg" and Elmc.Backend.Plan.Lower.Platform.Web.svg_element_tag?(name)))
  end

  defp html_element_partial?(_, _, _), do: false

  # Do not special-value 0-arg Kernel refs into multi-arg `runtime_fn_lambda`s here:
  # those lambdas can be eta-folded into the enclosing Json.* wrapper and keep
  # placeholder names (`__f`, `__decoder`) instead of the wrapper's params.
  # Applied Kernel calls still hit SpecialValues via the normal call path; stubs
  # cover remaining missing `elmc_fn_Elm_Kernel_*` symbols.
  defp compile_kernel_fn_ref(module, name, ctx, b) do
    qualified = "#{module}.#{name}"

    case SpecialValues.special_value_from_target(qualified, []) do
      %{op: op} = rewritten when op != :unsupported ->
        compile_special_rewrite(rewritten, [], ctx, b)

      _ ->
        compile_kernel_fn_ref_lambda(module, name, ctx, b)
    end
  end

  defp compile_kernel_fn_ref_lambda(module, name, ctx, b) do
    qualified = "#{module}.#{name}"
    arg = "__kernel_fn_ref__"

    Lambda.compile(
      %{
        op: :lambda,
        args: [arg],
        body: %{
          op: :qualified_call,
          target: qualified,
          args: [%{op: :var, name: arg}]
        }
      },
      ctx,
      b
    )
  end

  # Package shims: elm-pages internal modules that are aliases of elm/browser / elm/core.
  defp rewrite_web_call_target("Pages.Internal.String", name), do: {"String", name}
  defp rewrite_web_call_target("Pages", "Internal.String." <> rest), do: {"String", rest}
  defp rewrite_web_call_target(module, name), do: {module, name}

  defp resolve_delegate_call_target(module, name, args, decl_map) when is_list(args) do
    decl = Map.get(decl_map, {module, name})

    # Compare against *effective* arity (type/delegate), not raw IR `args: []` on
    # elm/core aliases — otherwise `String.slice 1` looks oversaturated vs [] and
    # incorrectly jumps to the Kernel callee with a partial arg list.
    effective_arity =
      if is_map(decl) do
        decl
        |> FunctionEmit.effective_decl_args(module, decl_map)
        |> List.wrap()
        |> length()
      else
        0
      end

    if args != [] and is_map(decl) and length(args) > effective_arity do
      case FunctionEmit.delegate_call_target(decl, module, decl_map) do
        {dmod, dname} -> {dmod, dname}
        nil -> {module, name}
      end
    else
      {module, name}
    end
  end

  defp oversaturated_call?(ctx, module, name, args) when is_list(args) do
    case Map.fetch(ctx.decl_map, {module, name}) do
      {:ok, decl} ->
        param_names = FunctionEmit.effective_decl_args(decl, module, ctx.decl_map) |> List.wrap()
        length(param_names) > 0 and length(args) > length(param_names)

      _ ->
        false
    end
  end

  defp zero_arity_thunk_call?(ctx, module, name, args) when is_list(args) do
    case Map.fetch(ctx.decl_map, {module, name}) do
      {:ok, decl} ->
        # Use IR `args` (not type-inferred effective_decl_args). Bindings like
        # `WebGL.indexedTriangles = MeshIndexed3 {…}` have args: [] but a
        # multi-arrow type; effective_decl_args invents __eff_arg_* and would
        # skip this path, emitting call_fn(verts, indices) against a 0-param CAF.
        ir_params = Map.get(decl, :args, []) |> List.wrap()

        length(ir_params) == 0 and length(args) > 0 and closure_thunk_decl?(decl) and
          FunctionEmit.function_type_arity(decl) > 0

      _ ->
        false
    end
  end

  defp closure_thunk_decl?(decl) when is_map(decl) do
    closure_thunk_expr?(Map.get(decl, :expr))
  end

  defp closure_thunk_expr?(%{op: :lambda}), do: true

  # `WebGL.indexedTriangles = MeshIndexed3 {…}` — constructor value whose type is
  # still `List a -> List indices -> Mesh a`. Calls must load the CAF then
  # call_closure; a direct call_fn with args is ignored by wat2wasm arity fixup
  # and returns the unapplied closure as the "mesh".
  defp closure_thunk_expr?(%{op: :constructor_call}), do: true
  defp closure_thunk_expr?(%{op: :partial_constructor}), do: true
  defp closure_thunk_expr?(%{op: :make_closure}), do: true

  # Eta-reduced partials: `normalize = scaleTo (Quantity.float 1)`. IR args are
  # [] but the body is already an applied call returning a function. Empty-arg
  # `f = Other.g` aliases are intentionally excluded (delegate arity path).
  defp closure_thunk_expr?(%{op: :qualified_call, args: [_ | _]}), do: true
  defp closure_thunk_expr?(%{op: :call, args: [_ | _]}), do: true

  defp closure_thunk_expr?(%{op: op, body: body}) when op in [:let, :letrec] do
    closure_thunk_expr?(body)
  end

  defp closure_thunk_expr?(%{op: :let_in, in_expr: body}), do: closure_thunk_expr?(body)

  defp closure_thunk_expr?(_), do: false

  defp compile_oversaturated_call(module, name, args, ctx, b) do
    {:ok, decl} = Map.fetch(ctx.decl_map, {module, name})
    param_names = Map.get(decl, :args, []) |> List.wrap()
    arity = length(param_names)
    {prefix, suffix} = Enum.split(args, arity)
    # Skip params already saturated by a direct call; remaining curry slots
    # follow the decl type's arrows (e.g. zero-arity `tie` keeps Float first).
    expected_types =
      decl
      |> Map.get(:type)
      |> case do
        type when is_binary(type) ->
          type
          |> Elmc.Backend.CCodegen.TypeParsing.function_arg_types()
          |> Enum.drop(arity)

        _ ->
          []
      end

    with {:ok, prefix_regs, b1} <- Expr.compile_args(prefix, ctx, b),
         {dest, b2} = Builder.fresh_reg(b1),
         {:ok, callee_reg, b3} when is_integer(callee_reg) <-
           compile_fn_call_emit(module, name, prefix_regs, dest, ctx, b2, prefix) do
      apply_oversaturated_suffix(callee_reg, suffix, expected_types, arity, ctx, b3)
    else
      _ -> :unsupported
    end
  end

  defp apply_oversaturated_suffix(callee_reg, suffix, expected_types, 0, ctx, b) do
    apply_closure_args_sequential(callee_reg, suffix, expected_types, ctx, b)
  end

  defp apply_oversaturated_suffix(callee_reg, suffix, expected_types, _arity, ctx, b) do
    compile_closure_call(callee_reg, suffix, expected_types, ctx, b)
  end

  defp apply_closure_args_sequential(callee_reg, [], _expected_types, _ctx, b),
    do: {:ok, callee_reg, b}

  defp apply_closure_args_sequential(callee_reg, [arg], expected_types, ctx, b) do
    compile_closure_call(callee_reg, [arg], expected_types, ctx, b)
  end

  defp apply_closure_args_sequential(callee_reg, [arg | rest], expected_types, ctx, b) do
    scratch_ctx = %{ctx | dest_stack: [:scratch], function_tail: false}
    {type_here, types_rest} = peel_expected_type(expected_types)

    with {:ok, next_reg, b1} <-
           compile_closure_call(callee_reg, [arg], type_here, scratch_ctx, b),
         next when is_integer(next) <- next_reg do
      apply_closure_args_sequential(next, rest, types_rest, ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp peel_expected_type([type | rest]), do: {[type], rest}
  defp peel_expected_type(_), do: {[], []}

  defp closure_callee_reg(name, ctx, b) when is_binary(name) do
    case Context.local_reg(ctx, name) do
      reg when is_integer(reg) ->
        {:ok, reg, b}

      _ ->
        case Context.letrec_ref(ctx, name) do
          ref when is_binary(ref) ->
            compile_forward_ref_load(ref, ctx, b)

          _ ->
            closure_callee_reg_local(name, ctx, b)
        end
    end
  end

  defp closure_callee_reg_local(name, ctx, b) when is_binary(name) do
    case Context.local_reg(ctx, name) do
      reg when is_integer(reg) ->
        {:ok, reg, b}

      _ ->
        case Enum.find_index(ctx.params, &(&1 == name)) do
          idx when is_integer(idx) ->
            {reg, b1} = Builder.get_or_load_param(b, idx, name)
            {:ok, reg, b1}

          _ ->
            :error
        end
    end
  end

  defp compile_forward_ref_load(ref, ctx, b) when is_binary(ref) do
    Expr.compile_forward_ref_load(ref, ctx, b)
  end

  defp compile_closure_call(callee_reg, args, ctx, b) do
    do_compile_closure_call(callee_reg, args, [], ctx, b)
  end

  defp compile_closure_call(callee_reg, args, expected_types, ctx, b)
       when is_list(expected_types) do
    do_compile_closure_call(callee_reg, args, expected_types, ctx, b)
  end

  defp do_compile_closure_call(callee_reg, args, ctx, b) do
    do_compile_closure_call(callee_reg, args, [], ctx, b)
  end

  defp do_compile_closure_call(callee_reg, args, expected_types, ctx, b)
       when is_list(expected_types) do
    with {:ok, arg_regs, b1} <- Expr.compile_args(args, ctx, b) do
      {arg_regs, b1} =
        if expected_types != [] do
          CallCoerce.coerce_args_to_types(arg_regs, args, expected_types, ctx, b1)
        else
          CallCoerce.box_int_literal_args(arg_regs, args, ctx, b1)
        end

      {dest, b2} = dest_for_call(ctx, b1)
      {borrows, consumes} = Builder.partition_call_args(b2, [callee_reg | arg_regs])

      effects =
        if is_integer(dest) do
          Types.fallible_effects(dest, borrows, consumes)
        else
          %{produces: nil, consumes: consumes, borrows: borrows, fallible: true}
        end

      wrap_catch? = Builder.wrap_fallible_instr_catch?(b2, ctx, true)
      b3 = if wrap_catch?, do: Builder.catch_begin(b2), else: b2

      {_, b4} =
        Builder.emit(b3, :call_closure, %{
          dest: dest,
          args: %{callee: callee_reg, args: arg_regs},
          effects: effects
        })

      b5 = if wrap_catch?, do: Builder.catch_end(b4), else: b4
      result = if is_integer(dest), do: dest, else: dest
      {:ok, result, b5}
    else
      _ -> :unsupported
    end
  end

  defp compile_curried_lambda(module, name, param_names, partial_args, ctx, b) do
    remaining = Enum.drop(param_names, length(partial_args))

    body =
      case html_map_curried_body(module, name, partial_args, remaining) do
        {:ok, expr} ->
          expr

        :error ->
          qualified = "#{module}.#{name}"

          %{
            op: :qualified_call,
            target: qualified,
            args: partial_args ++ Enum.map(remaining, &%{op: :var, name: &1})
          }
      end

    Lambda.compile_lambda(remaining, body, [], ctx, b)
  end

  defp html_map_curried_body(module, "map", partial_args, remaining) do
    opts = Process.get(:elmc_codegen_opts, %{})

    with true <- Elmc.Backend.Plan.Lower.Platform.Web.web_target?(opts),
         true <- module in ["Html", "VirtualDom", "Elm.Kernel.VirtualDom"],
         [mapper | _] <- partial_args,
         [html_name | _] <- remaining do
      {:ok,
       %{
         op: :html_cmd,
         kind: %{op: :int_literal, value: 3},
         params: [mapper, %{op: :var, name: html_name}]
       }}
    else
      _ -> :error
    end
  end

  defp html_map_curried_body(_module, _name, _partial_args, _remaining), do: :error

  defp compile_batch_call(target, args, ctx, b) do
    case SpecialValues.special_value_from_target(target, args) do
      %{op: :sub_none} ->
        Expr.compile(%{op: :sub_none}, ctx, b)

      %{op: :list_literal} = list_expr ->
        compile_batch_list_to_runtime_batch(list_expr, target, ctx, b)

      %{op: :pebble_sub} = sub ->
        compile_batch_list_to_runtime_batch(%{op: :list_literal, items: [sub]}, target, ctx, b)

      %{
        op: :runtime_call,
        function: "elmc_sub_batch",
        args: [list_expr]
      } ->
        compile_batch_list_to_runtime_batch(list_expr, target, ctx, b)

      %{
        op: :runtime_call,
        function: "elmc_cmd_batch",
        args: [list_expr]
      } ->
        compile_batch_list_to_runtime_batch(list_expr, target, ctx, b)

      %{op: op} = rewritten when is_atom(op) and op != :unsupported ->
        compile_special_rewrite(rewritten, args, ctx, b)

      _ ->
        case args do
          [list_expr | _] ->
            compile_batch_list_to_runtime_batch(list_expr, target, ctx, b)

          _ ->
            :unsupported
        end
    end
  end

  defp compile_batch_list_to_runtime_batch(list_expr, target, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    with {:ok, list_reg, b1} <- compile_batch_list_arg(list_expr, operand_ctx, b) do
      Expr.compile_runtime_builtin(batch_builtin_id(target), [list_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_batch_list_arg(%{op: :list_literal, items: items}, ctx, b),
    do: Elmc.Backend.Plan.Lower.List.compile_literal(items, ctx, b)

  defp compile_batch_list_arg(expr, ctx, b), do: Expr.compile(expr, ctx, b)

  defp batch_target?(target) when is_binary(target) do
    String.ends_with?(target, ".batch") or target == "batch"
  end

  defp batch_target?(_), do: false

  defp batch_builtin_id(target) when is_binary(target) do
    cond do
      subscription_batch_target?(target) -> :sub_batch
      true -> :cmd_batch
    end
  end

  defp subscription_batch_target?(target) when is_binary(target) do
    target in [
      "Sub.batch",
      "Pebble.Events.batch",
      "Elm.Kernel.PebbleWatch.batch"
    ]
  end

  @spec compile_top_level_ref(String.t(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_top_level_ref(name, ctx, b) when is_binary(name) do
    module = ctx.module || "Main"

    case compile_top_level_ref_in(module, name, ctx, b) do
      {:ok, _, _} = ok ->
        ok

      :unsupported ->
        # Many common names are implicitly imported from `Basics` (and friends) in Elm.
        # Lowering operates on unqualified `:var` nodes, so we provide a small, generic
        # fallback lookup here when the current module doesn't define the name.
        compile_top_level_ref_in("Basics", name, ctx, b)
    end
  end

  defp compile_top_level_ref_in(module, name, ctx, b)
       when is_binary(module) and is_binary(name) do
    case Map.fetch(ctx.decl_map, {module, name}) do
      {:ok, decl} ->
        # elm/core aliases keep IR `args: []`; use type/delegate arity so `cons` /
        # `slice` as first-class values become closures, not zero-arg calls.
        case FunctionEmit.effective_decl_args(decl, module, ctx.decl_map) |> List.wrap() do
          [] ->
            {dest, b1} = dest_for_call(ctx, b)
            compile_fn_call_emit(module, name, [], dest, ctx, b1)

          param_names ->
            compile_top_level_closure(module, name, param_names, ctx, b)
        end

      :error ->
        :unsupported
    end
  end

  defp compile_top_level_closure(module, name, param_names, ctx, b) do
    qualified = "#{module}.#{name}"
    unique_names = Context.unique_param_names(param_names)

    body = %{
      op: :qualified_call,
      target: qualified,
      args: Enum.map(unique_names, &%{op: :var, name: &1})
    }

    Lambda.compile_lambda(unique_names, body, [], ctx, b)
  end

  @doc false
  def parse_target(target, ctx, decl_map \\ nil) when is_binary(target) do
    decl_map = decl_map || Map.get(ctx, :decl_map, %{})

    case Util.resolve_decl_key(target, decl_map) do
      {module, name} ->
        {module, name}

      nil ->
        case String.split(target, ".") do
          [name] ->
            {ctx.module || "Main", name}

          parts ->
            name = List.last(parts)
            full_module = parts |> Enum.drop(-1) |> Enum.join(".")

            cond do
              kernel_qualified_target?(full_module) ->
                {full_module, name}

              true ->
                case String.split(target, ".", parts: 2) do
                  [mod, rest] -> {mod, rest}
                  [single] -> {ctx.module || "Main", single}
                end
            end
        end
    end
  end

  defp kernel_qualified_target?(module_name) when is_binary(module_name) do
    module_name == "Elm.Kernel" or String.starts_with?(module_name, "Elm.Kernel.")
  end

  defp zero_arg_fn_ref?(module_name) when is_binary(module_name) do
    kernel_qualified_target?(module_name) or module_name == "Elm.JsArray"
  end

  defp dest_for_call(ctx, b) do
    case Context.dest_for_call(ctx) do
      :fn_out ->
        {:fn_out, b}

      :branch_out ->
        {:branch_out, b}

      :scratch ->
        Builder.fresh_reg(b)
    end
  end

  @doc false
  def compile_fn_call_emit(module, name, arg_regs, dest, ctx, b, arg_exprs \\ []) do
    {module, name} = rewrite_web_call_target(module, name)
    qualified = "#{module}.#{name}"
    arg_exprs = List.wrap(arg_exprs)

    case SpecialValues.special_value_from_target(qualified, arg_exprs) do
      %{op: op} = rewritten when op in [:runtime_call, :call, :lambda, :browser_cmd, :html_cmd, :bytes_cmd, :json_cmd, :dom_sub, :parser_cmd] ->
        case compile_special_rewrite(rewritten, arg_exprs, ctx, b) do
          :unsupported -> do_compile_fn_call_emit(module, name, arg_regs, dest, ctx, b, arg_exprs)
          other -> other
        end

      _ ->
        do_compile_fn_call_emit(module, name, arg_regs, dest, ctx, b, arg_exprs)
    end
  end

  defp do_compile_fn_call_emit(module, name, arg_regs, dest, ctx, b, arg_exprs) do
    {arg_regs, b0} =
      if is_list(arg_exprs) and arg_exprs != [] do
        Builder.reload_stale_param_args(b, ctx.params, arg_regs, arg_exprs)
      else
        {arg_regs, b}
      end

    {arg_regs, b0a} =
      if is_list(arg_exprs) and arg_exprs != [] do
        CallCoerce.coerce_fn_call_args(module, name, arg_regs, arg_exprs, ctx, b0)
      else
        {arg_regs, b0}
      end

    {borrows, consumes} = Builder.partition_call_args(b0a, arg_regs)

    effects =
      if is_integer(dest) do
        Types.fallible_effects(dest, borrows, consumes)
      else
        %{produces: nil, consumes: consumes, borrows: borrows, fallible: true}
      end

    wrap_catch? = Builder.wrap_fallible_instr_catch?(b0a, ctx, true)

    b1 =
      if wrap_catch? do
        Builder.catch_begin(b0a)
      else
        b0a
      end

    {_, b2} =
      Builder.emit(b1, :call_fn, %{
        dest: dest,
        args: %{module: module, name: name, args: arg_regs},
        effects: effects
      })

    b3 = if wrap_catch?, do: Builder.catch_end(b2), else: b2

  result =
    case dest do
      d when is_integer(d) -> d
      :fn_out -> :fn_out
      :branch_out -> :branch_out
    end

    {:ok, result, b3}
  end
end
