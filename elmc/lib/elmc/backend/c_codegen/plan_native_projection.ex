defmodule Elmc.Backend.CCodegen.PlanNativeProjection do
  @moduledoc false

  alias Elmc.Backend.C.Lower.NativeReturn
  alias Elmc.Backend.CCodegen.{Fusion, FunctionEmit, Host, Native.AngleMinute, Native.FunctionCall, RcRequired, Types, Util}
  alias Elmc.Backend.Plan

  @type projection_kind :: :native_int | :native_bool

  @spec eligible?(Types.function_decl(), String.t(), Types.function_decl_map()) :: boolean()
  def eligible?(decl, module_name, decl_map) do
    Plan.primary_lowered?(decl, module_name, decl_map) and
      is_nil(NativeReturn.cached_kind({module_name, decl.name})) and
      RcRequired.rc_required?(module_name, decl.name) and
      not Fusion.rc_native_fusion?(module_name, decl.name, Map.get(decl, :expr), decl_map) and
      projection_kind(decl) in [:native_int, :native_bool] and
      not NativeReturn.value_return?({module_name, decl.name})
  end

  @spec supersedes_boxed_emit?(Types.function_decl(), String.t(), Types.function_decl_map()) :: boolean()
  def supersedes_boxed_emit?(decl, module_name, decl_map) do
    eligible?(decl, module_name, decl_map) and match?({:ok, _}, direct_native_body(decl, module_name, decl_map))
  end

  @spec projection_kind(Types.function_decl()) :: projection_kind | :boxed
  def projection_kind(%{type: type}) when is_binary(type) do
    case Host.function_return_type(type) do
      "Int" -> :native_int
      "Bool" -> :native_bool
      _ -> :boxed
    end
  end

  def projection_kind(_), do: :boxed

  @spec emit(Types.function_decl(), String.t(), Types.function_decl_map()) :: String.t()
  def emit(decl, module_name, decl_map) do
    c_name = Util.module_fn_name(module_name, decl.name)
    kind = projection_kind(decl)
    out_c_type = FunctionCall.c_return_type(kind)
    params = FunctionCall.params(decl, module_name, decl_map)

    body =
      case direct_native_body(decl, module_name, decl_map) do
        {:ok, expr} ->
          """
          *out = #{expr};
          return RC_SUCCESS;
          """
          |> String.trim()

        :error ->
          extract = if kind == :native_int, do: "elmc_as_int", else: "elmc_as_bool"
          call_args = boxed_call_args(decl, params)

          """
          ElmcValue *boxed = NULL;
          RC Rc = #{c_name}(#{call_args});
          if (Rc != RC_SUCCESS) return Rc;
          *out = #{extract}(boxed);
          elmc_release(boxed);
          return RC_SUCCESS;
          """
          |> String.trim()
      end

    """
    static RC #{c_name}_native(#{out_c_type} *out#{params_suffix(params)}) {
      #{body}
    }
    """
    |> String.trim()
  end

  @spec prototype(Types.function_decl(), String.t(), Types.function_decl_map()) :: String.t()
  def prototype(decl, module_name, decl_map) do
    c_name = Util.module_fn_name(module_name, decl.name)
    kind = projection_kind(decl)
    out_c_type = FunctionCall.c_return_type(kind)
    params = FunctionCall.params(decl, module_name, decl_map)

    "static RC #{c_name}_native(#{out_c_type} *out#{params_suffix(params)});"
  end

  defp direct_native_body(%{expr: expr} = decl, module_name, decl_map) do
    cond do
      AngleMinute.body_expr?(expr) ->
        with [minute | _] <- decl.args || [],
             minute_c <- native_param_ref(minute, decl, module_name, decl_map) do
          {:ok, "elmc_angle_from_minute(#{minute_c})"}
        else
          _ -> :error
        end

      true ->
        :error
    end
  end

  defp native_param_ref(name, decl, module_name, decl_map) when is_binary(name) do
    FunctionEmit.c_arg_bindings(decl.args || [])
    |> Enum.find_value(fn
      {^name, c_arg, _idx} -> c_arg
      _ -> nil
    end)
    |> case do
      nil -> FunctionCall.params(decl, module_name, decl_map) |> first_param_name()
      c_arg -> c_arg
    end
  end

  defp first_param_name(params) when is_binary(params) do
    params
    |> String.split(",")
    |> List.first()
    |> case do
      nil -> "arg0"
      segment -> segment |> String.trim() |> String.split() |> List.last()
    end
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
