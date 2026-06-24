defmodule ElmEx.DebuggerContract.EffectsFromCoreIR do
  @moduledoc false

  alias ElmEx.DebuggerContract
  alias ElmEx.DebuggerContract.EffectAnalysis
  alias ElmEx.DebuggerContract.EffectNormalize
  alias ElmEx.DebuggerContract.ExprCoerce
  alias ElmEx.DebuggerContract.Types
  alias ElmEx.CoreIR.Types, as: CoreIRTypes
  alias ElmEx.Frontend.AstContract.Types, as: AstTypes
  alias ElmEx.Frontend.Module

  @effect_field_keys ~w(
    subscription_calls
    subscription_ops
    init_cmd_ops
    init_cmd_calls
    update_cmd_ops
    update_cmd_calls
  )a

  @doc """
  Extracts effect metadata fields from a normalized Core IR document for the entry module.

  Reuses `EffectAnalysis` on Core IR expressions coerced to frontend AST shape.
  """
  @spec effect_fields(CoreIRTypes.wire_core_ir(), String.t()) :: Types.effect_fields()
  def effect_fields(core_ir, entry_module) when is_map(core_ir) and is_binary(entry_module) do
    core_ir
    |> modules_list()
    |> find_module(entry_module)
    |> case do
      %{} = core_mod -> effect_fields_for_module(core_mod)
      _ -> %{}
    end
  end

  @spec modules_list(CoreIRTypes.wire_core_ir() | map()) :: [CoreIRTypes.Module.wire_t()]
  def modules_list(%{"modules" => modules}) when is_list(modules), do: modules
  def modules_list(%{modules: modules}) when is_list(modules), do: modules
  def modules_list(_), do: []

  @spec find_module([CoreIRTypes.Module.wire_t()], String.t()) :: CoreIRTypes.Module.wire_t() | nil
  defp find_module(modules, entry) when is_list(modules) and is_binary(entry) do
    Enum.find(modules, fn
      %{"name" => ^entry} -> true
      %{name: ^entry} -> true
      _ -> false
    end)
  end

  @spec effect_fields_for_module(CoreIRTypes.Module.wire_t()) :: Types.effect_fields()
  defp effect_fields_for_module(core_mod) when is_map(core_mod) do
    mod = pseudo_module(core_mod)

    init_params = param_names(mod, "init")
    update_params = param_names(mod, "update")
    subscriptions_params = param_names(mod, "subscriptions")

    imports = Map.get(core_mod, "imports") || Map.get(core_mod, :imports) || []
    msg_tag_index = EffectNormalize.msg_tag_index_from_unions(core_mod)

    init_e = function_expr(mod, "init")
    update_e = function_expr(mod, "update")
    sub_e = function_expr(mod, "subscriptions")

    subscription_calls =
      sub_e
      |> calls_or_empty(&EffectAnalysis.extract_subscription_calls(&1, subscriptions_params, mod))
      |> EffectNormalize.normalize_subscription_calls(imports, msg_tag_index)

    %{
      "subscription_calls" => subscription_calls,
      "subscription_ops" =>
        calls_or_empty(sub_e, &EffectAnalysis.subscriptions_outline(&1, subscriptions_params)),
      "init_cmd_ops" =>
        calls_or_empty(init_e, &EffectAnalysis.init_cmd_ops_outline(&1, init_params)),
      "init_cmd_calls" =>
        calls_or_empty(init_e, &EffectAnalysis.init_cmd_calls_outline(&1, init_params)),
      "update_cmd_ops" =>
        calls_or_empty(update_e, &EffectAnalysis.update_cmd_ops_outline(&1, update_params)),
      "update_cmd_calls" =>
        calls_or_empty(update_e, &EffectAnalysis.update_cmd_calls_outline(&1, update_params))
    }
    |> Enum.reject(fn {_k, v} -> v in [nil, []] end)
    |> Map.new()
  end

  @spec calls_or_empty(Types.ast_expr() | nil, (Types.ast_expr() -> list())) :: list()
  defp calls_or_empty(%{} = expr, fun) when is_function(fun, 1), do: fun.(expr)
  defp calls_or_empty(_expr, _fun), do: []

  @spec pseudo_module(CoreIRTypes.Module.wire_t()) :: Module.t()
  defp pseudo_module(core_mod) when is_map(core_mod) do
    name = Map.get(core_mod, "name") || Map.get(core_mod, :name) || "Main"
    imports = Map.get(core_mod, "imports") || Map.get(core_mod, :imports) || []

    declarations =
      core_mod
      |> Map.get("declarations", Map.get(core_mod, :declarations, []))
      |> Enum.map(&declaration_to_frontend/1)
      |> Enum.reject(&is_nil/1)

    %Module{
      name: name,
      path: "core_ir",
      imports: imports,
      declarations: declarations
    }
  end

  @spec declaration_to_frontend(CoreIRTypes.Module.wire_declaration() | map()) ::
          AstTypes.declaration() | nil
  defp declaration_to_frontend(%{"kind" => "function", "name" => name} = decl)
       when is_binary(name) do
    %{
      kind: :function_definition,
      name: name,
      args: Map.get(decl, "args") || Map.get(decl, :args) || [],
      expr: ExprCoerce.to_ast(Map.get(decl, "expr") || Map.get(decl, :expr))
    }
  end

  defp declaration_to_frontend(%{kind: kind, name: name} = decl)
       when kind in ["function", :function] and is_binary(name) do
    declaration_to_frontend(%{
      "kind" => "function",
      "name" => name,
      "args" => Map.get(decl, :args) || Map.get(decl, "args"),
      "expr" => Map.get(decl, :expr) || Map.get(decl, "expr")
    })
  end

  defp declaration_to_frontend(_), do: nil

  @spec param_names(Module.t(), String.t()) :: [String.t()]
  defp param_names(%Module{} = mod, function_name) when is_binary(function_name) do
    case DebuggerContract.find_function_definition(mod, function_name) do
      %{args: args} when is_list(args) -> args
      _ -> []
    end
  end

  @spec function_expr(Module.t(), String.t()) :: Types.ast_expr() | nil
  defp function_expr(%Module{} = mod, function_name) when is_binary(function_name) do
    case DebuggerContract.find_function_definition(mod, function_name) do
      %{expr: %{} = expr} -> expr
      _ -> nil
    end
  end

  @doc false
  @spec effect_field_keys() :: [atom()]
  def effect_field_keys, do: @effect_field_keys
end
