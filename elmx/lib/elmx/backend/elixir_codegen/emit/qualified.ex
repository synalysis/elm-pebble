defmodule Elmx.Backend.ElixirCodegen.Emit.Qualified do
  @moduledoc """
  Lowers IR `qualified_call` nodes to runtime Elixir.

  Resolution order: `QualifiedRewrite` → Pebble rewrites → `Qualified.PebbleUi` →
  `Qualified.List` / `String` / `Collections` → `compile_qualified_call_fallback/4`
  (stdlib IR, `Qualified.Basics`, `Qualified.Bitwise`, then string fallback).

  Domain helpers live under `Emit.Qualified.*`; shared types in `Emit.Qualified.Context`.
  String codegen fragments: `Stdlib.QualifiedCodegen`.
  """

  alias Elmx.Backend.CrossModuleCall
  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Basics, as: QualifiedBasics
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Bitwise, as: QualifiedBitwise
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Collections, as: QualifiedCollections
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Context
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.List, as: QualifiedList
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.PebbleUi, as: QualifiedPebbleUi
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.String, as: QualifiedString
  alias Elmx.Backend.QualifiedRewrite
  alias Elmx.Runtime.Pebble
  alias Elmx.Runtime.Pebble.SpecialValues
  alias Elmx.Runtime.Stdlib

  @type env :: Context.env()
  @type emit_counter :: Context.emit_counter()
  @type ir_arg_list :: Context.ir_arg_list()
  @type compile_expr_result :: Context.compile_expr_result()
  @type qualified_result :: Context.qualified_result()

  def compile_qualified_call1(%{target: target}, env, counter) when is_binary(target) do
    case Elmx.Backend.ElixirCodegen.Emit.Helpers.compile_constructor_reference(target, env, counter) do
      {:ok, code, env, c} ->
        {code, env, c}

      :error ->
        case SpecialValues.rewrite(target, []) do
          {:ok, rewritten} ->
            Elmx.Backend.ElixirCodegen.Emit.compile_expr(rewritten, env, counter)

          :error ->
            case Stdlib.special_call(target, "") do
              {:ok, code} ->
                {code, env, counter}

              :error ->
                raise Elmx.Backend.UnsupportedOpError,
                  op: :qualified_call1,
                  expr: %{target: target}
            end
        end
    end
  end

  def compile_qualified_call(%{target: target, args: args}, env, counter) do
    case QualifiedRewrite.rewrite(target, args) do
      {:ok, rewritten} ->
        Elmx.Backend.ElixirCodegen.Emit.compile_expr(rewritten, env, counter)

      :error ->
        case Pebble.rewrite_qualified_call(target, args) do
          {:ok, rewritten} ->
            Elmx.Backend.ElixirCodegen.Emit.compile_expr(rewritten, env, counter)

          :error ->
            dispatch_qualified(target, args, env, counter)
        end
    end
  end

  defp dispatch_qualified(target, args, env, counter) do
    case try_domain_qualified(target, args, env, counter) do
      {:ok, code, env, c} ->
        {code, env, c}

      :error ->
        compile_qualified_call_fallback(target, args, env, counter)
    end
  end

  defp try_domain_qualified(target, args, env, counter) do
    QualifiedPebbleUi.compile(target, args, env, counter)
    |> case do
      {:ok, _, _, _} = ok ->
        ok

      :error ->
        QualifiedList.compile(target, args, env, counter)
        |> case do
          {:ok, _, _, _} = ok ->
            ok

          :error ->
            QualifiedString.compile(target, args, env, counter)
            |> case do
              {:ok, _, _, _} = ok -> ok
              :error -> QualifiedCollections.compile(target, args, env, counter)
            end
        end
    end
  end

  defdelegate compile_pebble_ui_qualified(target, args, env, counter),
    to: QualifiedPebbleUi,
    as: :compile

  defdelegate pebble_ui_call(fun, args, env, counter), to: QualifiedPebbleUi

  defdelegate compile_list_qualified(target, args, env, counter),
    to: QualifiedList,
    as: :compile

  defdelegate compile_string_qualified(target, args, env, counter),
    to: QualifiedString,
    as: :compile

  defdelegate compile_collections_qualified(target, args, env, counter),
    to: QualifiedCollections,
    as: :compile

  @spec compile_qualified_call_fallback(String.t(), ir_arg_list(), env(), emit_counter()) ::
          compile_expr_result()
  def compile_qualified_call_fallback(target, args, env, counter) do
    case compile_stdlib_qualified_ir(target, args, env, counter) do
      {:ok, code, env, c} ->
        {code, env, c}

      :error ->
        case QualifiedBasics.compile(target, args, env, counter) do
          {:ok, code, env, c} ->
            {code, env, c}

          :error ->
            case QualifiedBitwise.compile(target, args, env, counter) do
              {:ok, code, env, c} ->
                {code, env, c}

              :error ->
                compile_qualified_call_fallback_string(target, args, env, counter)
            end
        end
    end
  end

  @doc false
  def compile_stdlib_qualified_ir(target, args, env, counter)
      when is_binary(target) and is_list(args) do
    if Stdlib.handles_qualified?(target) do
      {arg_code, env, c} =
        Elmx.Backend.ElixirCodegen.Emit.Helpers.compile_arg_list(args, env, counter)

      case Stdlib.qualified_call(target, IO.iodata_to_binary(arg_code)) do
        {:ok, code} -> {:ok, code, env, c}
        :error -> :error
      end
    else
      :error
    end
  end

  defdelegate compile_basics_qualified(target, args, env, counter), to: QualifiedBasics, as: :compile
  defdelegate compile_bitwise_qualified(target, args, env, counter), to: QualifiedBitwise, as: :compile

  @spec compile_qualified_call_fallback_string(String.t(), ir_arg_list(), env(), emit_counter()) ::
          compile_expr_result()
  def compile_qualified_call_fallback_string(target, args, env, counter) do
    {arg_code, env, c1} =
      Elmx.Backend.ElixirCodegen.Emit.Helpers.compile_arg_list(args, env, counter)

    arg_str = IO.iodata_to_binary(arg_code)

    case Stdlib.qualified_call(target, arg_str) do
      {:ok, code} ->
        {code, env, c1}

      :error ->
        case CrossModuleCall.compile_call(target, args, env, counter, &Helpers.compile_arg_parts/3) do
          {:ok, code, env, c2} ->
            {code, env, c2}

          :error ->
            if String.contains?(target, ".") do
              raise Elmx.Backend.UnsupportedOpError,
                op: :qualified_call,
                expr: %{target: target, args: args}
            else
              fn_name = Helpers.qualified_fn_name(target)
              module = Map.get(env, :module, "Main")
              {[Helpers.module_fn(module, fn_name), "(", arg_str, ")"], env, c1}
            end
        end
    end
  end
end
