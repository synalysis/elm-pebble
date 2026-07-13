defmodule Elmc.Backend.CCodegen.LayoutCoerceEmit do
  @moduledoc false

  alias Elmc.Backend.CCodegen.FusionSupport
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.LayoutSolver
  alias Elmc.Backend.CCodegen.StoragePlan
  alias Elmc.Backend.CCodegen.Types

  @type warning :: %{
          required(:source) => String.t(),
          required(:code) => String.t(),
          required(:severity) => String.t(),
          required(:message) => String.t(),
          required(:module) => String.t(),
          required(:function) => String.t(),
          required(:callee) => String.t(),
          required(:param) => String.t(),
          required(:from) => StoragePlan.layout(),
          required(:to) => StoragePlan.layout()
        }

  @type param_plan_map :: %{optional({String.t(), String.t(), String.t()}) => StoragePlan.t()}

  @spec maybe_coerce_expr(String.t(), StoragePlan.t(), StoragePlan.t(), keyword()) ::
          {String.t(), StoragePlan.t(), Types.layout_diagnostic() | nil}
  def maybe_coerce_expr(var, from_plan, to_plan, _opts \\ [])
      when is_binary(var) do
    {_code, coerced_var, _counter, _copied?} = emit_layout_copy(var, from_plan, to_plan, 0)
    {coerced_var, to_plan, diagnostic(from_plan, to_plan)}
  end

  @spec coerce_call_operand(
          String.t(),
          Types.ir_expr() | nil,
          String.t(),
          String.t(),
          String.t() | nil,
          Types.compile_env(),
          Types.compile_counter()
        ) :: {String.t(), String.t(), Types.compile_counter(), boolean()}
  def coerce_call_operand(var, arg_expr, callee_mod, callee_fun, param, env, counter)
      when is_binary(var) and is_binary(callee_mod) and is_binary(callee_fun) do
    with true <- is_binary(param),
         to_plan when is_map(to_plan) <- param_plan(callee_mod, callee_fun, param),
         true <- list_param_plan?(to_plan),
         from_plan <- expr_plan_for_call_arg(arg_expr, env) do
      emit_layout_copy(var, from_plan, to_plan, counter)
    else
      _ -> {"", var, counter, false}
    end
  end

  @spec emit_layout_copy(String.t(), StoragePlan.t(), StoragePlan.t(), Types.compile_counter()) ::
          {String.t(), String.t(), Types.compile_counter(), boolean()}
  def emit_layout_copy(var, from_plan, to_plan, counter)
      when is_binary(var) and is_integer(counter) do
    cond do
      from_plan.layout == to_plan.layout ->
        {"", var, counter, false}

      copy_coercion?(from_plan, to_plan) ->
        emit_int_list_copy(var, from_plan, to_plan, counter)

      true ->
        {"", var, counter, false}
    end
  end

  @spec diagnostic(StoragePlan.t(), StoragePlan.t()) :: Types.layout_diagnostic() | nil
  def diagnostic(from_plan, to_plan) do
    cond do
      from_plan.layout == to_plan.layout ->
        nil

      StoragePlan.compact_only?(from_plan) and StoragePlan.dual_path?(to_plan) ->
        %{
          source: "elmc/layout",
          code: "layout_coercion_required",
          from: from_plan.layout,
          to: :mixed
        }

      from_plan.layout != to_plan.layout and to_plan.layout != :mixed and from_plan.layout != :mixed ->
        %{
          source: "elmc/layout",
          code: "layout_coercion_required",
          from: from_plan.layout,
          to: to_plan.layout
        }

      true ->
        nil
    end
  end

  @spec collect_call_warnings(Types.function_decl_map(), param_plan_map()) :: [warning()]
  def collect_call_warnings(decl_map, param_plans) when is_map(decl_map) and is_map(param_plans) do
    decl_map
    |> Enum.flat_map(fn {{caller_mod, caller_fun}, decl} ->
      locals = param_locals(caller_mod, caller_fun, decl, param_plans)

      walk_expr(decl.expr, caller_mod, caller_fun, decl_map, param_plans, locals)
    end)
    |> Enum.uniq_by(&warning_key/1)
  end

  @spec format_compile_warnings([warning()]) :: [Types.compile_warning_json()]
  def format_compile_warnings(warnings) when is_list(warnings) do
    Enum.map(warnings, fn warning ->
      %{
        "type" => "layout-coercion",
        "source" => warning.source,
        "code" => warning.code,
        "severity" => warning.severity,
        "module" => warning.module,
        "function" => warning.function,
        "callee" => warning.callee,
        "param" => warning.param,
        "from" => Atom.to_string(warning.from),
        "to" => Atom.to_string(warning.to),
        "message" => warning.message
      }
    end)
  end

  defp warning_key(warning) do
    {warning.module, warning.function, warning.callee, warning.param, warning.from, warning.to}
  end

  defp walk_expr(nil, _caller_mod, _caller_fun, _decl_map, _param_plans, _locals), do: []

  defp walk_expr(expr, caller_mod, caller_fun, decl_map, param_plans, locals) when is_map(expr) do
    warnings =
      case expr do
        %{op: :let_in, name: name, value_expr: value, in_expr: body} when is_binary(name) ->
          value_warnings = walk_expr(value, caller_mod, caller_fun, decl_map, param_plans, locals)
          next_locals = Map.put(locals, name, value)
          body_warnings = walk_expr(body, caller_mod, caller_fun, decl_map, param_plans, next_locals)
          value_warnings ++ body_warnings

        %{op: :qualified_call, target: target, args: args} when is_binary(target) ->
          call_warnings(caller_mod, caller_fun, target, args, decl_map, param_plans, locals) ++
            fold_subexprs(expr, caller_mod, caller_fun, decl_map, param_plans, locals, [:op, :target])

        %{op: :call, name: name, args: args} when is_binary(name) ->
          call_warnings(caller_mod, caller_fun, name, args, decl_map, param_plans, locals) ++
            fold_subexprs(expr, caller_mod, caller_fun, decl_map, param_plans, locals, [:op, :name])

        _ ->
          fold_subexprs(expr, caller_mod, caller_fun, decl_map, param_plans, locals, [])
      end

    warnings
  end

  defp walk_expr(list, caller_mod, caller_fun, decl_map, param_plans, locals) when is_list(list) do
    Enum.flat_map(list, &walk_expr(&1, caller_mod, caller_fun, decl_map, param_plans, locals))
  end

  defp walk_expr(_other, _caller_mod, _caller_fun, _decl_map, _param_plans, _locals), do: []

  defp fold_subexprs(map, caller_mod, caller_fun, decl_map, param_plans, locals, skip_keys)
       when is_map(map) do
    map
    |> Enum.reject(fn {key, _} -> key in skip_keys end)
    |> Enum.flat_map(fn {_key, value} ->
      walk_expr(value, caller_mod, caller_fun, decl_map, param_plans, locals)
    end)
  end

  defp call_warnings(caller_mod, caller_fun, target, args, decl_map, param_plans, locals) do
    if FusionSupport.superseded_fusion_callee?({caller_mod, caller_fun}, callee_key(caller_mod, target), decl_map) do
      []
    else
      case resolve_callee(caller_mod, target) do
        {callee_mod, callee_fun} ->
          zip_param_warnings(
            caller_mod,
            caller_fun,
            callee_mod,
            callee_fun,
            args || [],
            decl_map,
            param_plans,
            locals
          )
      end
    end
  end

  defp callee_key(caller_mod, target) when is_binary(target) do
    {mod, fun} = resolve_callee(caller_mod, target)
    {mod, fun}
  end

  defp resolve_callee(caller_mod, target) when is_binary(target) do
    case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
      {mod, name} -> {mod, name}
      _ -> {caller_mod, FusionSupport.local_name(target)}
    end
  end

  defp zip_param_warnings(caller_mod, caller_fun, callee_mod, callee_fun, args, decl_map, param_plans, locals) do
    case Map.get(decl_map, {callee_mod, callee_fun}) do
      %{args: param_names} when is_list(param_names) ->
        param_names
        |> Enum.with_index()
        |> Enum.flat_map(fn {param, idx} ->
          with arg when is_map(arg) <- Enum.at(args, idx),
               to_plan when is_map(to_plan) <- Map.get(param_plans, {callee_mod, callee_fun, param}),
               true <- list_param_plan?(to_plan),
               from_plan <-
                 LayoutSolver.expr_plan(arg, decl_map, locals: locals, caller: {caller_mod, caller_fun}),
               diag when is_map(diag) <- diagnostic(from_plan, to_plan) do
            [
              %{
                source: diag.source,
                code: diag.code,
                severity: "warning",
                module: caller_mod,
                function: caller_fun,
                callee: "#{callee_mod}.#{callee_fun}",
                param: param,
                from: from_plan.layout,
                to: to_plan.layout,
                message:
                  "#{caller_mod}.#{caller_fun} passes #{from_plan.layout} list to " <>
                    "#{callee_mod}.#{callee_fun}(#{param}) expecting #{to_plan.layout}; " <>
                    "layout coercion may be required at runtime"
              }
            ]
          else
            _ -> []
          end
        end)

      _ ->
        []
    end
  end

  defp emit_int_list_copy(var, _from_plan, to_plan, counter) do
    coerced = "layout_coerced_#{counter}"
    next = counter + 1
    runtime_fn = copy_runtime_fn(to_plan)

    code = """
      ElmcValue *#{coerced} = NULL;
      if (#{var} && #{var}->tag == ELMC_TAG_INT_LIST) {
        RC _layout_coerce_rc_#{next} = #{runtime_fn}(&#{coerced}, #{var});
        if (_layout_coerce_rc_#{next} != RC_SUCCESS) {
          #{coerced} = elmc_retain(#{var});
        }
      } else {
        #{coerced} = elmc_retain(#{var});
      }
    """

    {code, coerced, next, true}
  end

  defp copy_runtime_fn(%StoragePlan{layout: :native_linked, elem: {:primitive, :int}}),
    do: "elmc_int_list_to_spine"

  defp copy_runtime_fn(%StoragePlan{layout: :boxed_cons, elem: {:primitive, :int}}),
    do: "elmc_int_list_to_cons"

  defp copy_runtime_fn(%StoragePlan{layout: :native_linked}), do: "elmc_int_list_to_spine"
  defp copy_runtime_fn(%StoragePlan{layout: :boxed_cons}), do: "elmc_int_list_to_cons"
  defp copy_runtime_fn(_), do: "elmc_int_list_to_cons"

  defp copy_coercion?(%StoragePlan{} = from, %StoragePlan{} = to) do
    StoragePlan.compact_only?(from) and to.layout in [:native_linked, :boxed_cons] and
      int_list_elem?(from) and int_list_elem?(to)
  end

  defp int_list_elem?(%StoragePlan{elem: {:primitive, :int}}), do: true
  defp int_list_elem?(%StoragePlan{elem: nil}), do: true
  defp int_list_elem?(_), do: false

  defp param_plan(callee_mod, callee_fun, param) do
    storage = Process.get(:elmc_storage_plans, %{param_plans: %{}})

    storage
    |> Map.get(:param_plans, %{})
    |> Map.get({callee_mod, callee_fun, param})
  end

  defp expr_plan_for_call_arg(arg_expr, env) when is_map(arg_expr) do
    decl_map = Map.get(env, :__program_decls__, %{})
    caller_mod = Map.get(env, :__module__, "Main")
    caller_fun = Map.get(env, :__function_name__, "")
    storage = Process.get(:elmc_storage_plans, %{param_plans: %{}})
    param_plans = Map.get(storage, :param_plans, %{})

    locals =
      case Map.get(decl_map, {caller_mod, caller_fun}) do
        decl when is_map(decl) -> param_locals(caller_mod, caller_fun, decl, param_plans)
        _ -> %{}
      end

    LayoutSolver.expr_plan(arg_expr, decl_map, locals: locals, caller: {caller_mod, caller_fun})
  end

  defp expr_plan_for_call_arg(_arg_expr, _env), do: StoragePlan.mixed()

  defp list_param_plan?(%StoragePlan{layout: layout, elem: elem})
       when layout in [:compact, :native_linked, :boxed_cons, :mixed] do
    match?({:primitive, _}, elem) or match?({:record, _, _}, elem) or elem == nil
  end

  defp list_param_plan?(_), do: false

  defp param_locals(caller_mod, caller_fun, %{args: arg_names}, param_plans)
       when is_list(arg_names) and is_map(param_plans) do
    Enum.reduce(arg_names, %{}, fn name, acc ->
      case Map.get(param_plans, {caller_mod, caller_fun, name}) do
        plan when is_map(plan) ->
          if list_param_plan?(plan), do: Map.put(acc, name, "List Int"), else: acc

        _ ->
          acc
      end
    end)
  end

  defp param_locals(_caller_mod, _caller_fun, _decl, _param_plans), do: %{}
end
