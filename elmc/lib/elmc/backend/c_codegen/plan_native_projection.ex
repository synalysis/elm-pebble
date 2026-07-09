defmodule Elmc.Backend.CCodegen.PlanNativeProjection do
  @moduledoc false

  alias Elmc.Backend.C.Lower.NativeReturn
  alias Elmc.Backend.CCodegen.{Fusion, FunctionEmit, Host, Native.FunctionCall, RcRequired, Util}
  alias Elmc.Backend.Plan

  @type projection_kind :: :native_int | :native_bool

  @spec eligible?(map(), String.t(), map()) :: boolean()
  def eligible?(decl, module_name, decl_map) do
    Plan.primary_lowered?(decl, module_name, decl_map) and
      is_nil(NativeReturn.cached_kind({module_name, decl.name})) and
      RcRequired.rc_required?(module_name, decl.name) and
      not Fusion.rc_native_fusion?(module_name, decl.name, Map.get(decl, :expr), decl_map) and
      projection_kind(decl) in [:native_int, :native_bool]
  end

  @spec projection_kind(map()) :: projection_kind | :boxed
  def projection_kind(%{type: type}) when is_binary(type) do
    case Host.function_return_type(type) do
      "Int" -> :native_int
      "Bool" -> :native_bool
      _ -> :boxed
    end
  end

  def projection_kind(_), do: :boxed

  @spec emit(map(), String.t(), map()) :: String.t()
  def emit(decl, module_name, decl_map) do
    c_name = Util.module_fn_name(module_name, decl.name)
    kind = projection_kind(decl)
    out_c_type = FunctionCall.c_return_type(kind)
    extract = if kind == :native_int, do: "elmc_as_int", else: "elmc_as_bool"
    params = FunctionCall.params(decl, module_name, decl_map)
    call_args = boxed_call_args(decl, params)

    """
    static RC #{c_name}_native(#{out_c_type} *out#{params_suffix(params)}) {
      ElmcValue *boxed = NULL;
      RC Rc = #{c_name}(#{call_args});
      if (Rc != RC_SUCCESS) return Rc;
      *out = #{extract}(boxed);
      elmc_release(boxed);
      return RC_SUCCESS;
    }
    """
    |> String.trim()
  end

  @spec prototype(map(), String.t(), map()) :: String.t()
  def prototype(decl, module_name, decl_map) do
    c_name = Util.module_fn_name(module_name, decl.name)
    kind = projection_kind(decl)
    out_c_type = FunctionCall.c_return_type(kind)
    params = FunctionCall.params(decl, module_name, decl_map)

    "static RC #{c_name}_native(#{out_c_type} *out#{params_suffix(params)});"
  end

  defp params_suffix(""), do: ""
  defp params_suffix(params), do: ", " <> params

  defp boxed_call_args(decl, params) do
    arg_names =
      FunctionEmit.c_arg_bindings(decl.args || [])
      |> Enum.map(fn {_arg, c_arg, _idx} -> c_arg end)
      |> Enum.join(", ")

    if params == "" do
      "&boxed"
    else
      "&boxed, " <> arg_names
    end
  end
end
