defmodule Elmc.Backend.Plan.Worker.Host.Lower do
  @moduledoc """
  Lower Elm IR + subscription layout into a `Plan.Worker.HostPlan`.
  """
  alias Elmc.Backend.CCodegen.FunctionCallAbi
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.Plan.Worker.HostPlan
  alias Elmc.Backend.Plan.Worker.Layout
  alias ElmEx.IR

  @worker_entry_rc_vars %{"subscriptions" => "sub_rc"}

  @spec lower(IR.t(), String.t(), Layout.t(), keyword()) :: HostPlan.t()
  def lower(%IR{} = ir, entry_module, %{} = layout, opts) do
    opts = Map.new(opts)
    safe_module = entry_module |> String.replace(".", "_")
    decl_map = IRQueries.function_decl_map(ir)
    declarations = entry_declarations(ir, entry_module)

    has_init = has_function?(declarations, "init")
    has_update = has_function?(declarations, "update")
    has_subscriptions = has_function?(declarations, "subscriptions")

    %HostPlan{
      entry_module: entry_module,
      layout: layout,
      init: entry_spec(has_init, safe_module, "init", entry_module, decl_map, ["flags"], opts, -3, """
      (void)flags;
        ElmcValue *result = elmc_int_zero();
      """),
      update:
        entry_spec(has_update, safe_module, "update", entry_module, decl_map, ["msg", "state->model"], opts, -4, """
        (void)msg;
          ElmcValue *result = elmc_int_zero();
        """),
      subscriptions:
        entry_spec(
          has_subscriptions,
          safe_module,
          "subscriptions",
          entry_module,
          decl_map,
          ["state->model"],
          opts,
          nil,
          """
          ElmcValue *result = elmc_int_zero();
          """
        ),
      model_dependent_subs?: has_subscriptions and Map.get(layout, :model_dependent?, true),
      last_dispatch_cmd_cap: last_dispatch_cmd_cap(opts)
    }
  end

  defp entry_declarations(%IR{} = ir, entry_module) do
    ir.modules
    |> Enum.find_value([], fn mod ->
      if mod.name == entry_module, do: mod.declarations, else: nil
    end)
  end

  defp has_function?(declarations, name) do
    Enum.any?(declarations, &(&1.kind == :function and &1.name == name))
  end

  defp entry_spec(true, safe_module, fun_name, entry_module, decl_map, arg_exprs, opts, _missing, _stub) do
    %{
      present?: true,
      call: entry_call(safe_module, fun_name, entry_module, decl_map, arg_exprs, opts)
    }
  end

  defp entry_spec(false, _safe, _fun, _entry, _decl_map, _args, _opts, missing_return, stub_c) do
    %{
      present?: false,
      missing_return: missing_return,
      stub_c: stub_c
    }
  end

  defp entry_call(safe_module, fun_name, entry_module, decl_map, arg_exprs, opts) do
    rc_var = Map.get(@worker_entry_rc_vars, fun_name, "#{fun_name}_rc")
    decl = Map.get(decl_map, {entry_module, fun_name})

    on_fail_c =
      case fun_name do
        "init" ->
          """
          if (init_rc != RC_SUCCESS) {
            ELMC_WORKER_LOG_RC_FAIL("worker init", init_rc);
            elmc_release(result);
            return -2;
          }
          """

        "update" ->
          """
          if (update_rc != RC_SUCCESS) {
            ELMC_WORKER_LOG_RC_FAIL("worker update", update_rc);
            elmc_release(result);
            return -2;
          }
          """

        "subscriptions" ->
          """
          if (sub_rc != RC_SUCCESS) {
            ELMC_WORKER_LOG_RC_FAIL("worker subscriptions", sub_rc);
            elmc_release(result);
            return 0;
          }
          """

        _ ->
          """
          if (#{rc_var} != RC_SUCCESS) {
            ELMC_WORKER_LOG_RC_FAIL("worker #{fun_name}", #{rc_var});
            elmc_release(result);
            return -2;
          }
          """
      end

    {abi, call_c} =
      if is_map(decl) and FunctionCallAbi.direct_entry_abi?(decl, entry_module, decl_map, opts) do
        args = Enum.join(arg_exprs, ", ")
        {:direct, "RC #{rc_var} = elmc_fn_#{safe_module}_#{fun_name}(&result, #{args});"}
      else
        argc = length(arg_exprs)
        args_init = Enum.join(arg_exprs, ", ")

        call =
          """
          ElmcValue *args[] = { #{args_init} };
            RC #{rc_var} = elmc_fn_#{safe_module}_#{fun_name}(&result, args, #{argc});
          """
          |> String.trim()

        {:argc, call}
      end

    %{
      safe_module: safe_module,
      fun: fun_name,
      abi: abi,
      arg_exprs: arg_exprs,
      rc_var: rc_var,
      on_fail_c: on_fail_c,
      call_c: call_c
    }
  end

  defp last_dispatch_cmd_cap(opts) do
    if Map.get(opts, :pebble_int32) == true and Map.get(opts, :prod) == true do
      0
    else
      8
    end
  end
end
