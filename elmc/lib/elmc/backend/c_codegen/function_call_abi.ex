defmodule Elmc.Backend.CCodegen.FunctionCallAbi do
  @moduledoc false

  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.RcRequired
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.Plan

  @spec argv_abi?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def argv_abi?(decl, module_name, decl_map) do
    if direct_plan_call_abi?(decl, module_name, decl_map) do
      false
    else
      argv_abi_legacy?(decl, module_name, decl_map)
    end
  end

  defp argv_abi_legacy?(decl, module_name, decl_map) do
    emit_wrapper? =
      Process.get(:elmc_wrapper_targets, MapSet.new())
      |> MapSet.member?({module_name, decl.name})

    worker_abi? =
      emit_wrapper? or RcRequired.platform_worker_rc_abi?(module_name, decl.name, decl_map)

    native_scalar? = NativeFunctionCall.native_scalar_fn?(decl, module_name, decl_map)
    worker_abi? or native_scalar?
  end

  @spec argv_abi?(Types.function_decl_key(), Types.function_decl_map()) :: boolean()
  def argv_abi?({module_name, name}, decl_map) do
    case Map.get(decl_map, {module_name, name}) do
      decl when is_map(decl) -> argv_abi?(decl, module_name, decl_map)
      _ -> true
    end
  end

  @spec param_c_arg(non_neg_integer(), [String.t() | map()]) :: String.t()
  def param_c_arg(index, params) when is_integer(index) and is_list(params) do
    names =
      Enum.map(params, fn
        %{name: name} when is_binary(name) -> name
        name when is_binary(name) -> name
        _ -> "_"
      end)

    FunctionEmit.c_arg_bindings(names)
    |> Enum.at(index)
    |> then(fn {_arg, c_arg, _idx} -> c_arg end)
  end

  @spec retain_param?(Types.function_declaration()) :: boolean()
  def retain_param?(%{ownership: ownership}) when is_list(ownership),
    do: :retain_arg in ownership

  def retain_param?(_), do: true

  @spec primary_lowered?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def primary_lowered?(decl, module_name, decl_map) do
    Plan.primary_lowered?(decl, module_name, decl_map)
  end

  @spec primary_lowered?(Types.function_decl_key(), Types.function_decl_map()) :: boolean()
  def primary_lowered?({module_name, name}, decl_map) do
    case Map.get(decl_map, {module_name, name}) do
      decl when is_map(decl) -> primary_lowered?(decl, module_name, decl_map)
      _ -> false
    end
  end

  @worker_entry_points ~w(init update subscriptions)

  @doc """
  Plan-primary functions that are not partial-application wrappers use direct
  parameter ABI in both definitions and `call_fn` sites.

  When `emit_wrapper?` is `true`, the query targets the argv partial-application
  shim and always returns `false`. Otherwise plan-primary lowered functions use
  direct ABI even if they appear in `wrapper_targets` (the canonical definition
  is direct; wrappers are separate).
  """
  @spec direct_plan_call_abi?(
          Types.function_declaration(),
          String.t(),
          Types.function_decl_map(),
          boolean() | nil
        ) :: boolean()
  def direct_plan_call_abi?(decl, module_name, decl_map, emit_wrapper? \\ nil) do
    plan_primary? =
      Plan.plan_ir_mode(Process.get(:elmc_codegen_opts, [])) == :primary and
        primary_lowered?(decl, module_name, decl_map)

    case emit_wrapper? do
      true -> false
      false -> plan_primary?
      nil -> plan_primary?
    end
  end

  @spec direct_entry_abi?(Types.function_declaration(), String.t(), Types.function_decl_map(), keyword()) ::
          boolean()
  def direct_entry_abi?(decl, module_name, decl_map, opts \\ []) do
    direct_plan_call_abi?(decl, module_name, decl_map) or
      (decl.name in @worker_entry_points and
         Plan.primary_lowered?(decl, module_name, decl_map, opts))
  end

  @spec emit_argv_setup(String.t(), [String.t()]) :: {String.t(), String.t(), non_neg_integer()}
  def emit_argv_setup(prefix, arg_refs) do
    argc = length(arg_refs)
    args_var = "#{prefix}_argv_#{System.unique_integer([:positive])}"
    arg_list = Enum.join(arg_refs, ", ")

    setup =
      "ElmcValue *#{args_var}[#{max(argc, 1)}] = { #{arg_list} };"

    {setup, args_var, argc}
  end
end
