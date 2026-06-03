defmodule Elmx.Runtime.Handler do
  @moduledoc """
  Shared compile/invoke helper for `elmx_*` registry handlers.

  Emits `CodegenRefs.module_ref/1` paths so Intrinsics and Pebble registries stay aligned.
  """

  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Types

  @type t :: Types.runtime_handler()

  @type compile_opts :: [wrap_modules: [module()]]
  @type apply_opts :: [wrap_modules: [module()]]

  @spec compile(t(), [String.t() | iodata()], compile_opts()) :: String.t()
  def compile(handler, arg_codes, opts \\ []) do
    wrap_modules = Keyword.get(opts, :wrap_modules, [])
    compile_handler(handler, arg_codes, wrap_modules)
  end

  @spec invoke(t(), Types.registry_args(), apply_opts()) :: Types.runtime_dispatch_result()
  def invoke(handler, args, opts \\ []) do
    wrap_modules = Keyword.get(opts, :wrap_modules, [])
    apply_handler(handler, args, wrap_modules)
  end

  defp compile_handler({mod, fun}, arg_codes, wrap_modules) do
    args = Enum.map(arg_codes, &IO.iodata_to_binary/1)
    compile_call_expr(mod, fun, args, [], wrap_modules)
  end

  defp compile_handler({mod, fun, handler_opts}, arg_codes, wrap_modules) do
    args = reorder(arg_codes, handler_opts[:args]) |> Enum.map(&IO.iodata_to_binary/1)

    prefix =
      cond do
        target = handler_opts[:target] -> [inspect(target)]
        kind = handler_opts[:kind] -> [inspect(kind)]
        key = handler_opts[:key] -> [inspect(key)]
        true -> []
      end

    compile_call_expr(mod, fun, args, prefix, wrap_modules)
  end

  defp compile_call_expr(mod, fun, args, prefix, wrap_modules) do
    joined = Enum.join(args, ", ")
    arglist = if joined == "", do: "[]", else: "[#{joined}]"

    call_args =
      cond do
        prefix != [] -> Enum.join(prefix ++ [arglist], ", ")
        mod in wrap_modules -> arglist
        true -> joined
      end

    "#{module_ref(mod)}.#{fun}(#{call_args})"
  end

  defp apply_handler({mod, fun}, args, wrap_modules) do
    if mod in wrap_modules do
      apply(mod, fun, [args])
    else
      apply(mod, fun, args)
    end
  end

  defp apply_handler({mod, fun, handler_opts}, args, wrap_modules) do
    cond do
      target = handler_opts[:target] ->
        apply(mod, fun, [target, args])

      kind = handler_opts[:kind] ->
        apply(mod, fun, [kind, args])

      key = handler_opts[:key] ->
        apply(mod, fun, [key, args])

      order = handler_opts[:args] ->
        apply(mod, fun, reorder(args, order))

      mod in wrap_modules ->
        apply(mod, fun, [args])

      true ->
        apply(mod, fun, args)
    end
  end

  defp reorder(items, nil), do: items

  defp reorder(items, order) when is_list(order), do: Enum.map(order, &Enum.at(items, &1))

  defp module_ref(mod) when is_atom(mod), do: CodegenRefs.module_ref(mod)
end
