defmodule Elmc.Backend.Plan.Lower.Port do
  @moduledoc false

  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Lower.Platform.Web, as: PlatformWeb
  alias Elmc.Backend.Plan.Types, as: PlanTypes

  @type direction :: :incoming | :outgoing

  @spec port_signature?(Context.t(), String.t(), String.t()) :: boolean()
  def port_signature?(ctx, module, name) do
    case Map.get(ctx.decl_map, {module, name}) do
      %{expr: nil} -> true
      _ -> port_name?(module, name)
    end
  end

  defp port_name?(module, name) do
    ports =
      module
      |> then(fn mod ->
        Map.get(Process.get(:elmc_module_ports, %{}), mod, [])
      end)

    name in ports
  end

  @spec direction_from_type(String.t() | nil) :: direction | :unknown
  def direction_from_type(type) when is_binary(type) do
    trimmed = String.trim(type)

    cond do
      callback_to_sub?(trimmed) -> :incoming
      payload_to_cmd?(trimmed) -> :outgoing
      true -> :unknown
    end
  end

  def direction_from_type(_), do: :unknown

  @spec compile_call(String.t(), String.t(), [map()], Context.t(), Builder.t()) ::
          {:ok, PlanTypes.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_call(module, name, args, ctx, b) do
    if port_signature?(ctx, module, name) do
      decl = Map.get(ctx.decl_map, {module, name}, %{})
      type = Map.get(decl, :type) || Map.get(decl, :return_type)

      port_key = qualified_name(module, name)

      case {direction_from_type(type), args} do
        {:incoming, [callback]} ->
          compile_incoming(port_key, callback, ctx, b)

        {:outgoing, [payload]} ->
          compile_outgoing(port_key, payload, ctx, b)

        _ ->
          :unsupported
      end
    else
      :unsupported
    end
  end

  @doc """
  Runtime key used to identify a port's queued Cmd/Sub value.

  The web target maps ports 1:1 onto real browser `app.ports.<name>` JS
  interop, so the key must stay the bare declared port name. Other targets
  (native/Pebble) have no such external contract; qualifying with the
  declaring module disambiguates same-named ports declared in different
  modules for debugger/introspection output.
  """
  @spec qualified_name(String.t(), String.t()) :: String.t()
  def qualified_name(module, name) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      name
    else
      "#{module}.#{name}"
    end
  end

  defp compile_incoming(port_name, callback, ctx, b) do
    value_ctx = Context.for_branch_arm(ctx)

    with {:ok, port_reg, b1} <-
           Expr.compile(%{op: :string_literal, value: port_name}, value_ctx, b),
         {:ok, callback_reg, b2} <- Expr.compile(callback, value_ctx, b1) do
      Expr.compile_runtime_builtin(:port_incoming_sub, [port_reg, callback_reg], ctx, b2)
    else
      _ -> :unsupported
    end
  end

  defp compile_outgoing(port_name, payload, ctx, b) do
    value_ctx = Context.for_branch_arm(ctx)

    with {:ok, port_reg, b1} <-
           Expr.compile(%{op: :string_literal, value: port_name}, value_ctx, b),
         {:ok, payload_reg, b2} <- Expr.compile(payload, value_ctx, b1) do
      Expr.compile_runtime_builtin(:port_outgoing, [port_reg, payload_reg], ctx, b2)
    else
      _ -> :unsupported
    end
  end

  defp callback_to_sub?(type) do
    String.match?(type, ~r/\)\s*->\s*Sub\b/)
  end

  defp payload_to_cmd?(type) do
    String.match?(type, ~r/->\s*Cmd\b/) and not callback_to_sub?(type)
  end
end
