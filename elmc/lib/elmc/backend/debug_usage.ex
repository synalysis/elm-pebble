defmodule Elmc.Backend.DebugUsage do
  @moduledoc false

  alias ElmEx.IR

  @debug_targets MapSet.new(["Debug.log", "Debug.todo", "Debug.toString"])

  @type usage :: %{
          required(:target) => String.t(),
          required(:module) => String.t(),
          required(:function) => String.t()
        }

  @type policy :: :error | :warn

  @spec collect(IR.t()) :: [usage()]
  def collect(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.flat_map(fn decl ->
        collect_expr(decl.expr, mod.name, decl.name)
      end)
    end)
    |> Enum.uniq()
  end

  @spec diagnostics([usage()], policy()) :: [map()]
  def diagnostics(usages, policy) when is_list(usages) and policy in [:error, :warn] do
    severity = if policy == :error, do: "error", else: "warning"
    code = if policy == :error, do: "debug_usage_not_allowed", else: "debug_usage_in_build"

    Enum.map(usages, fn %{target: target, module: module, function: function} ->
      %{
        "type" => "debug-usage",
        "source" => "elmc/debug",
        "code" => code,
        "severity" => severity,
        "module" => module,
        "function" => function,
        "file" => nil,
        "line" => nil,
        "column" => nil,
        "target" => target,
        "message" =>
          "#{target} is not allowed in production builds (used in #{module}.#{function}/0). " <>
            "Disable Production build in the emulator or remove Debug calls before publishing."
      }
    end)
  end

  @spec check(IR.t(), map()) :: :ok | {:warn, [map()]} | {:error, [map()]}
  def check(%IR{} = ir, opts) when is_map(opts) do
    if prod?(opts) do
      usages = collect(ir)

      case usages do
        [] ->
          :ok

        usages ->
          policy = debug_usage_policy(opts)
          diagnostics = diagnostics(usages, policy)

          case policy do
            :warn -> {:warn, diagnostics}
            :error -> {:error, diagnostics}
          end
      end
    else
      :ok
    end
  end

  @spec prod?(map()) :: boolean()
  def prod?(opts) when is_map(opts), do: Map.get(opts, :prod, false) == true

  @spec debug_usage_policy(map()) :: policy()
  def debug_usage_policy(opts) when is_map(opts) do
    case Map.get(opts, :debug_usage_policy, :error) do
      :warn -> :warn
      :warning -> :warn
      "warn" -> :warn
      "warning" -> :warn
      _ -> :error
    end
  end

  defp collect_expr(nil, _module, _function), do: []

  defp collect_expr(expr, module, function) when is_map(expr) do
    own =
      case expr do
        %{op: :qualified_call, target: target} when is_binary(target) ->
          if MapSet.member?(@debug_targets, target) do
            [%{target: target, module: module, function: function}]
          else
            []
          end

        _ ->
          []
      end

    child_usages =
      expr
      |> Map.values()
      |> Enum.flat_map(&collect_expr(&1, module, function))

    own ++ child_usages
  end

  defp collect_expr(values, module, function) when is_list(values) do
    Enum.flat_map(values, &collect_expr(&1, module, function))
  end

  defp collect_expr(_value, _module, _function), do: []
end
