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

  @spec lower(IR.t(), String.t(), Layout.t(), map() | keyword()) :: HostPlan.t()
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

    fail_kind =
      case fun_name do
        "init" -> :init_fail
        "update" -> :update_fail
        "subscriptions" -> :sub_fail
        _ -> :generic_fail
      end

    abi =
      if is_map(decl) and FunctionCallAbi.direct_entry_abi?(decl, entry_module, decl_map, opts) do
        :direct
      else
        :argc
      end

    %{
      safe_module: safe_module,
      fun: fun_name,
      abi: abi,
      arg_exprs: arg_exprs,
      rc_var: rc_var,
      fail_kind: fail_kind
    }
  end

  defp last_dispatch_cmd_cap(opts) do
    cond do
      # Watch size builds and prod pebble binaries do not keep the debugger
      # last-dispatch snapshot (~1.5 KiB BSS when cap=8).
      Map.get(opts, :pebble_int32) == true and Map.get(opts, :prod) == true ->
        0

      Elmc.Backend.SizeProfile.size?(opts) ->
        0

      true ->
        8
    end
  end

  @doc false
  @spec last_dispatch_cmd_cap_for_test(map()) :: non_neg_integer()
  def last_dispatch_cmd_cap_for_test(opts) when is_map(opts), do: last_dispatch_cmd_cap(opts)
end
