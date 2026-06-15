defmodule Elmx.Runtime.Stdlib.QualifiedCodegen do
  @moduledoc """
  Shared string fragments for qualified Elm stdlib lowering.

  `Stdlib.Qualified` calls these with parsed argument strings; `Emit.Qualified` compiles IR
  subtrees to strings first. Covers list HOF/fold, container-last APIs, `Result`/`Maybe`
  combinators, collection ops, Json decode builders, and `module_call`/`unary_call` for
  Math/Chars/Bitwise/Task/Process emit lowering.
  """

  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Types

  @type expr_code :: String.t() | iodata()
  @type opts :: Types.qualified_codegen_opts()

  @doc """
  Lowers `List.map`-style hops: `Core.<core_fun>(fun, list)` or a one-arg list lambda.
  """
  @spec list_hof(String.t(), expr_code(), expr_code() | nil, opts()) :: {:ok, String.t()}
  def list_hof(core_fun, fun_expr, list_expr \\ nil, opts \\ []) when is_binary(core_fun) do
    mod_ref = module_ref(Keyword.get(opts, :module, Elmx.Runtime.Core))
    fun = IO.iodata_to_binary(fun_expr)
    list_param = Keyword.get(opts, :list_param, "elmx_list")

    code =
      case list_expr do
        nil ->
          "fn #{list_param} -> #{mod_ref}.#{core_fun}(#{fun}, #{list_param}) end"

        container ->
          "#{mod_ref}.#{core_fun}(#{fun}, #{IO.iodata_to_binary(container)})"
      end

    {:ok, code}
  end

  @doc """
  Lowers `List.foldl` / `List.foldr`: full call or partial lambdas over acc/list params.
  """
  @spec list_fold(String.t(), expr_code(), expr_code() | nil, expr_code() | nil, opts()) ::
          {:ok, String.t()}
  def list_fold(core_fun, fun_expr, acc_expr \\ nil, list_expr \\ nil, opts \\ [])
      when is_binary(core_fun) do
    mod_ref = module_ref(Keyword.get(opts, :module, Elmx.Runtime.Core))
    fun = IO.iodata_to_binary(fun_expr)
    acc_param = Keyword.get(opts, :acc_param, "elmx_acc")
    list_param = Keyword.get(opts, :list_param, "elmx_list")

    code =
      cond do
        list_expr != nil and acc_expr != nil ->
          "#{mod_ref}.#{core_fun}(#{fun}, #{IO.iodata_to_binary(acc_expr)}, #{IO.iodata_to_binary(list_expr)})"

        acc_expr != nil ->
          acc = IO.iodata_to_binary(acc_expr)
          "fn #{list_param} -> #{mod_ref}.#{core_fun}(#{fun}, #{acc}, #{list_param}) end"

        true ->
          "fn #{acc_param}, #{list_param} -> #{mod_ref}.#{core_fun}(#{fun}, #{acc_param}, #{list_param}) end"
      end

    {:ok, code}
  end

  @doc """
  Lowers `Dict.*` / `Set.*` / `Array.*` qualified calls to `Core.Collections`.
  """
  @spec collection_call(module() | String.t(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()}
  def collection_call(module, prefix, op, arg_code)
      when is_binary(prefix) and is_binary(op) and is_binary(arg_code) do
    mod = if is_atom(module), do: CodegenRefs.module_ref(module), else: module
    fun = prefix <> "_" <> Macro.underscore(op)
    {:ok, "#{mod}.#{fun}(#{arg_code})"}
  end

  @doc """
  Calls `mod.fun(prefix_args..., container)` or a one-arg container lambda when `container` is nil.

  Used for `Dict.get`, `List.member`, `Set.member`, and similar container-last APIs.
  """
  @spec with_container(module() | String.t(), String.t(), [expr_code()], expr_code() | nil, opts()) ::
          {:ok, String.t()}
  def with_container(mod, fun, prefix_args, container_expr \\ nil, opts \\ [])
      when is_binary(fun) and is_list(prefix_args) do
    mod_ref = module_ref(mod)
    prefix = Enum.map_join(prefix_args, ", ", &IO.iodata_to_binary/1)
    container_param = Keyword.get(opts, :container_param, "elmx_dict")

    code =
      if container_expr do
        "#{mod_ref}.#{fun}(#{prefix}, #{IO.iodata_to_binary(container_expr)})"
      else
        "fn #{container_param} -> #{mod_ref}.#{fun}(#{prefix}, #{container_param}) end"
      end

    {:ok, code}
  end

  @doc """
  Calls `mod.fun(arg)` or `fn param -> mod.fun(param) end` for unary String helpers.
  """
  @spec unary_call(module() | String.t(), String.t(), expr_code() | nil, opts()) :: {:ok, String.t()}
  def unary_call(mod, fun, arg_expr \\ nil, opts \\ []) when is_binary(fun) do
    mod_ref = module_ref(mod)
    param = Keyword.get(opts, :param, "elmx_str")

    code =
      if arg_expr do
        "#{mod_ref}.#{fun}(#{IO.iodata_to_binary(arg_expr)})"
      else
        "fn #{param} -> #{mod_ref}.#{fun}(#{param}) end"
      end

    {:ok, code}
  end

  @doc """
  Lowers `mod.fun(arg1, arg2, …)` when all arguments are known (emit IR or stdlib strings).
  """
  @spec module_call(module() | String.t(), String.t(), [expr_code()]) :: {:ok, String.t()}
  def module_call(mod, fun, arg_exprs) when is_binary(fun) and is_list(arg_exprs) do
    mod_ref = module_ref(mod)
    args = Enum.map_join(arg_exprs, ", ", &IO.iodata_to_binary/1)
    {:ok, "#{mod_ref}.#{fun}(#{args})"}
  end

  @doc """
  Calls `mod.fun(fixed_args..., last)` or `fn last_param -> mod.fun(fixed, last_param) end`.
  """
  @spec combinator_last(module() | String.t(), String.t(), [expr_code()], expr_code() | nil, opts()) ::
          {:ok, String.t()}
  def combinator_last(mod, fun, prefix_args, last_expr \\ nil, opts \\ [])
      when is_binary(fun) and is_list(prefix_args) do
    mod_ref = module_ref(mod)
    prefix = Enum.map_join(prefix_args, ", ", &IO.iodata_to_binary/1)
    last_param = Keyword.get(opts, :last_param, "result")

    code =
      if last_expr do
        "#{mod_ref}.#{fun}(#{prefix}, #{IO.iodata_to_binary(last_expr)})"
      else
        "fn #{last_param} -> #{mod_ref}.#{fun}(#{prefix}, #{last_param}) end"
      end

    {:ok, code}
  end

  defp module_ref(mod) when is_atom(mod), do: CodegenRefs.module_ref(mod)
  defp module_ref(mod) when is_binary(mod), do: mod
end
