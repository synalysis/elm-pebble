defmodule Elmc.Backend.CCodegen.ListHofResolve do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Types

  @list_hof_targets ~w(List.head List.map List.filter List.tail List.isEmpty List.length)

  @identity_lambda %{
    op: :lambda,
    args: ["__fm_item"],
    body: %{op: :var, name: "__fm_item"}
  }

  @spec resolve_list_hof_call_args(String.t(), Types.special_value_args(), Types.compile_env()) ::
          Types.special_value_args()
  def resolve_list_hof_call_args("List.head", [list], env),
    do: [resolve_list_expr(list, env)]

  def resolve_list_hof_call_args("List.map", [fun, list], env),
    do: [fun, resolve_list_expr(list, env)]

  def resolve_list_hof_call_args("List.filter", [pred, list], env),
    do: [pred, resolve_list_expr(list, env)]

  def resolve_list_hof_call_args(_target, args, _env), do: args

  @spec list_hof_target?(String.t()) :: boolean()
  def list_hof_target?(target) when is_binary(target), do: target in @list_hof_targets
  def list_hof_target?(_target), do: false

  @spec resolve_list_expr(Types.ir_expr(), Types.compile_env()) :: Types.ir_expr()
  def resolve_list_expr(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    case EnvBindings.let_value_expr(env, name) do
      bound when is_map(bound) -> resolve_list_expr(bound, env)
      _ -> %{op: :var, name: name}
    end
  end

  def resolve_list_expr(expr, _env) when is_map(expr), do: expr
  def resolve_list_expr(expr, _env), do: expr

  @spec normalize_filter_map_fn(Types.ir_expr()) :: Types.ir_expr()
  def normalize_filter_map_fn(fn_expr) do
    if filter_map_identity?(fn_expr), do: @identity_lambda, else: fn_expr
  end

  @spec filter_map_identity?(Types.ir_expr()) :: boolean()
  def filter_map_identity?(%{op: :lambda, args: [arg], body: %{op: :var, name: name}})
      when is_binary(arg) and is_binary(name),
      do: arg == name

  def filter_map_identity?(%{op: :qualified_ref, target: "Basics.identity"}), do: true

  def filter_map_identity?(%{op: :qualified_call, target: "Basics.identity", args: []}), do: true

  # Unqualified `identity` from `import Basics exposing (identity)` lowers to a bare var.
  def filter_map_identity?(%{op: :var, name: "identity"}), do: true

  def filter_map_identity?(_expr), do: false
end
