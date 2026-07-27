defmodule Elmc.Backend.Plan.TupleParamBind do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.CCodegen.{Host, TypeParsing, VarAnalysis}
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Tuple
  alias ElmEx.IR.TypeSignature

  @spec bind(map(), Context.t(), Builder.t()) :: {:ok, Context.t(), Builder.t()} | :unsupported
  def bind(%{expr: expr, args: args} = decl, ctx, b)
      when is_map(expr) and is_list(args) and is_map(ctx) do
    # Param projections are never the function result; force scratch destinations.
    bind_ctx = Context.for_branch_arm(ctx)
    param_types = param_types_by_name(decl, bind_ctx)
    body_used = VarAnalysis.used_vars(expr) |> MapSet.new()
    param_set = MapSet.new(args)

    result =
      Enum.reduce_while(Enum.with_index(args), {:ok, bind_ctx, b}, fn {param, idx}, {:ok, ctx_acc, b_acc} ->
        case Map.get(param_types, param) do
          type when is_binary(type) ->
            elem_types = TypeSignature.tuple_element_types(type)

            with names when is_list(names) and names != [] <- tuple_element_names(param, length(elem_types)),
                 used_names <-
                   Enum.filter(names, fn name ->
                     MapSet.member?(body_used, name) and not MapSet.member?(param_set, name)
                   end),
                 true <- used_names != [],
                 {:ok, ctx1, b1} <-
                   bind_projections(names, used_names, elem_types, param, idx, ctx_acc, b_acc) do
              {:cont, {:ok, ctx1, b1}}
            else
              _ -> {:cont, {:ok, ctx_acc, b_acc}}
            end

          _ ->
            {:cont, {:ok, ctx_acc, b_acc}}
        end
      end)

    case result do
      {:ok, ctx1, b1} ->
        {:ok, %{ctx1 | function_tail: ctx.function_tail, dest_stack: ctx.dest_stack}, b1}

      other ->
        other
    end
  end

  def bind(_, ctx, b), do: {:ok, ctx, b}

  @spec param_types_by_name(map(), Context.t()) :: %{optional(String.t()) => String.t()}
  defp param_types_by_name(decl, ctx) do
    local_types = ctx.local_types

    with type when is_binary(type) <- Map.get(decl, :type),
         arg_types when is_list(arg_types) <- TypeParsing.function_arg_types(type),
         args when is_list(args) <- Map.get(decl, :args) do
      args
      |> Enum.with_index()
      |> Enum.reduce(local_types, fn {param, idx}, acc ->
        case Enum.at(arg_types, idx) do
          t when is_binary(t) -> Map.put(acc, param, Host.normalize_type_name(t))
          _ -> acc
        end
      end)
      |> Map.merge(local_types)
    else
      _ -> local_types
    end
  end

  @doc false
  @spec tuple_element_names(String.t(), pos_integer()) :: [String.t()] | nil
  def tuple_element_names(_param, 0), do: nil

  def tuple_element_names(param, 2) when is_binary(param) do
    cond do
      String.contains?(param, "__") ->
        case String.split(param, "__", parts: 2) do
          [left, right] when left != "" and right != "" -> [left, right]
          _ -> nil
        end

      String.contains?(param, "_") ->
        case :binary.match(param, "_") do
          {idx, 1} when idx > 0 and idx < byte_size(param) - 1 ->
            [binary_part(param, 0, idx), binary_part(param, idx + 1, byte_size(param) - idx - 1)]

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  def tuple_element_names(param, count) when is_binary(param) and count > 2 do
    separator =
      cond do
        String.contains?(param, "__") -> "__"
        String.contains?(param, "_") -> "_"
        true -> nil
      end

    with sep when is_binary(sep) <- separator,
         parts <- String.split(param, sep),
         true <- length(parts) == count and Enum.all?(parts, &(&1 != "")) do
      parts
    else
      _ -> nil
    end
  end

  def tuple_element_names(_, _), do: nil

  @spec bind_projections(String.t(), String.t(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp bind_projections(names, used_names, elem_types, param, idx, ctx, b) do
    {param_reg, b0} = Builder.get_or_load_param(b, idx, param)
    ctx0 = Context.put_local(ctx, param, param_reg)
    b0a = Builder.bind_local(b0, param, param_reg)

    Enum.reduce_while(names, {:ok, ctx0, b0a}, fn name, {:ok, ctx_acc, b_acc} ->
      if name in used_names do
        elem_idx = Enum.find_index(names, &(&1 == name))

        proj_op =
          case elem_idx do
            0 -> :tuple_first_expr
            1 when length(names) == 2 -> :tuple_second_expr
            _ -> nil
          end

        with op when op != nil <- proj_op,
             {:ok, reg, b1} <-
               Tuple.compile(%{op: op, arg: %{op: :var, name: param}}, ctx_acc, b_acc),
             ctx1 <- put_elem_binding(ctx_acc, name, reg, Enum.at(elem_types, elem_idx)),
             b2 <- Builder.bind_local(b1, name, reg) do
          {:cont, {:ok, ctx1, b2}}
        else
          _ -> {:halt, :unsupported}
        end
      else
        {:cont, {:ok, ctx_acc, b_acc}}
      end
    end)
  end

  @spec put_elem_binding(Types.ir_expr(), String.t(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp put_elem_binding(ctx, name, reg, type) do
    ctx
    |> Context.put_local(name, reg)
    |> maybe_put_elem_type(name, type)
  end

  @spec maybe_put_elem_type(Types.ir_expr(), String.t(), String.t() | Types.ir_expr()) :: Types.ir_expr() | nil

  defp maybe_put_elem_type(ctx, name, type) when is_binary(type) and type != "" do
    Context.put_local_type(ctx, name, Host.normalize_type_name(type))
  end

  defp maybe_put_elem_type(ctx, _name, _type), do: ctx
end
