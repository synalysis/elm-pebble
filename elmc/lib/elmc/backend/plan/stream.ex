defmodule Elmc.Backend.Plan.Stream do
  @moduledoc """
  DirectRender scene-stream lowering via verified Plan SSA.

  Stream helpers push `render_cmd` values into `ElmcSceneWriter` instead of
  building boxed `List RenderOp` results. Used from `DirectRender.PlanStreamEmit`.
  """
  alias Elmc.Backend.Plan.Lower.Function

  @spec eligible_expr?(map() | term()) :: boolean()
  def eligible_expr?(%{op: :render_cmd}), do: true
  def eligible_expr?(%{op: :render_text_cmd}), do: true

  def eligible_expr?(%{op: :list_literal, items: items}) when is_list(items), do: items != []

  def eligible_expr?(%{op: :call, name: "__append__", args: [left, right]}),
    do: eligible_expr?(left) and eligible_expr?(right)

  def eligible_expr?(%{op: :if, then_expr: then, else_expr: else_expr}),
    do: eligible_expr?(then) and eligible_expr?(else_expr)

  def eligible_expr?(%{op: :if, then: then, else: else_expr}),
    do: eligible_expr?(then) and eligible_expr?(else_expr)

  def eligible_expr?(%{op: :let_in, in_expr: in_expr}), do: eligible_expr?(in_expr)

  def eligible_expr?(_), do: false

  @spec lower_function(map(), String.t(), map(), keyword()) ::
          {:ok, map()} | :unsupported | {:error, term()}
  def lower_function(decl, module_name, decl_map, opts \\ []) do
    expr = Map.get(decl, :expr)

    if eligible_expr?(expr) do
      Function.lower(
        decl,
        module_name,
        decl_map,
        Keyword.merge([stream_mode: true, rc_required: true], opts)
      )
    else
      :unsupported
    end
  end
end
