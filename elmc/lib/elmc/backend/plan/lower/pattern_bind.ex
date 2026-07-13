defmodule Elmc.Backend.Plan.Lower.PatternBind do
  @moduledoc false

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr

  @spec bind(Types.pattern(), Context.t(), Builder.t(), integer()) ::
          {:ok, Context.t(), Builder.t()} | :unsupported
  def bind(pattern, ctx, b, subject_reg) when is_map(pattern) and is_integer(subject_reg) do
    do_bind(pattern, ctx, b, subject_reg)
  end

  defp do_bind(%{kind: :wildcard}, ctx, b, _subject_reg), do: {:ok, ctx, b}

  defp do_bind(%{kind: :int}, ctx, b, _subject_reg), do: {:ok, ctx, b}

  defp do_bind(%{kind: :string}, ctx, b, _subject_reg), do: {:ok, ctx, b}

  defp do_bind(%{kind: :var, name: name}, ctx, b, subject_reg) when is_binary(name) do
    {:ok, Context.put_local(ctx, name, subject_reg), Builder.bind_local(b, name, subject_reg)}
  end

  defp do_bind(%{kind: :tuple, elements: elements}, ctx, b, subject_reg)
       when is_list(elements) and length(elements) > 2 do
    do_bind(%{kind: :tuple, elements: nest_tuple_elements(elements)}, ctx, b, subject_reg)
  end

  defp do_bind(%{kind: :tuple, elements: [left, right]}, ctx, b, subject_reg) do
    with {:ok, ctx1, b1, _} <- bind_tuple_elem(left, :first, subject_reg, ctx, b),
         {:ok, ctx2, b2, _} <- bind_tuple_elem(right, :second, subject_reg, ctx1, b1) do
      {:ok, ctx2, b2}
    else
      _ -> :unsupported
    end
  end

  defp do_bind(
         %{kind: :constructor, name: name, arg_pattern: %{kind: :tuple, elements: [head, tail]}} =
           pattern,
         ctx,
         b,
         subject_reg
       )
       when is_binary(name) do
    if cons_pattern?(pattern) do
      bind_cons_pattern(head, tail, subject_reg, ctx, b)
    else
      with {:ok, payload_reg, b1} <- emit_ctor_payload(pattern, subject_reg, ctx, b),
           {:ok, ctx1, b2} <-
             do_bind(%{kind: :tuple, elements: [head, tail]}, ctx, b1, payload_reg) do
        {:ok, ctx1, b2}
      else
        _ -> :unsupported
      end
    end
  end

  defp do_bind(%{kind: :constructor, resolved_name: "List.::", arg_pattern: %{kind: :tuple, elements: [head, tail]}}, ctx, b, subject_reg) do
    bind_cons_pattern(head, tail, subject_reg, ctx, b)
  end

  defp do_bind(%{kind: :constructor, arg_pattern: nil, bind: nil}, ctx, b, _subject_reg) do
    {:ok, ctx, b}
  end

  defp do_bind(%{kind: :constructor, bind: bind, arg_pattern: nil} = pattern, ctx, b, subject_reg)
       when is_binary(bind) do
    {:ok, payload_reg, b1} = emit_ctor_payload(pattern, subject_reg, ctx, b)
    {:ok, Context.put_local(ctx, bind, payload_reg), Builder.bind_local(b1, bind, payload_reg)}
  end

  defp do_bind(%{kind: :constructor, bind: bind, arg_pattern: %{kind: :var, name: name}} = pattern, ctx, b, subject_reg)
       when is_binary(bind) do
    do_bind(Map.put(pattern, :arg_pattern, %{kind: :var, name: name}) |> Map.put(:bind, bind), ctx, b, subject_reg)
  end

  defp do_bind(%{kind: :constructor, arg_pattern: arg_pattern} = pattern, ctx, b, subject_reg)
       when is_map(arg_pattern) do
    with {:ok, payload_reg, b1} <- emit_ctor_payload(pattern, subject_reg, ctx, b),
         {:ok, ctx1, b2} <- do_bind(arg_pattern, ctx, b1, payload_reg) do
      {:ok, ctx1, b2}
    else
      _ -> :unsupported
    end
  end

  defp do_bind(%{kind: :constructor, bind: bind}, ctx, b, subject_reg) when is_binary(bind) do
    {:ok, Context.put_local(ctx, bind, subject_reg), Builder.bind_local(b, bind, subject_reg)}
  end

  defp do_bind(_, _ctx, _b, _subject_reg), do: :unsupported

  defp bind_tuple_elem(%{kind: :wildcard}, _which, _base, ctx, b), do: {:ok, ctx, b, nil}

  defp bind_tuple_elem(%{kind: :int}, _which, _base, ctx, b), do: {:ok, ctx, b, nil}

  defp bind_tuple_elem(%{kind: :string}, _which, _base, ctx, b), do: {:ok, ctx, b, nil}

  defp bind_tuple_elem(pattern, which, base, ctx, b) do
    with {:ok, reg, b1} <- emit_tuple_proj(base, which, b),
         {:ok, ctx1, b2} <- do_bind(pattern, ctx, b1, reg) do
      {:ok, ctx1, b2, reg}
    else
      _ -> :unsupported
    end
  end

  defp emit_ctor_payload(pattern, subject_reg, ctx, b) do
    if just_ctor?(pattern) do
      emit_maybe_just_payload(subject_reg, ctx, b)
    else
      emit_union_payload(subject_reg, ctx, b)
    end
  end

  defp emit_tuple_proj(base_reg, which, b) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :tuple_proj, %{
        dest: dest,
        args: %{base: base_reg, which: which},
        effects: %{
          produces: {:owned, dest},
          consumes: [],
          borrows: [base_reg],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  defp emit_union_payload(subject_reg, ctx, b) do
    Expr.compile_runtime_builtin(:union_payload, [subject_reg], ctx, b)
  end

  defp emit_maybe_just_payload(subject_reg, ctx, b) do
    Expr.compile_runtime_builtin(:maybe_just_payload, [subject_reg], ctx, b)
  end

  defp just_ctor?(pattern) do
    name = Map.get(pattern, :resolved_name) || Map.get(pattern, :name)
    is_binary(name) and short_name(name) == "Just"
  end

  defp short_name(name), do: name |> String.split(".") |> List.last()

  defp cons_pattern?(%{name: name}) when is_binary(name), do: short_name(name) == "::"
  defp cons_pattern?(%{resolved_name: "List.::"}), do: true
  defp cons_pattern?(_), do: false

  defp bind_cons_pattern(head, tail, subject_reg, ctx, b) do
    with {:ok, head_reg, b1} <- Expr.compile_runtime_builtin(:list_head, [subject_reg], ctx, b),
         {:ok, tail_reg, b2} <- Expr.compile_runtime_builtin(:list_tail, [subject_reg], ctx, b1),
         {:ok, ctx1, b3} <- do_bind(head, ctx, b2, head_reg),
         {:ok, ctx2, b4} <- do_bind(tail, ctx1, b3, tail_reg) do
      {:ok, ctx2, b4}
    else
      _ -> :unsupported
    end
  end

  defp nest_tuple_elements([left, right]), do: [left, right]

  defp nest_tuple_elements([left | rest]),
    do: [left, %{kind: :tuple, elements: nest_tuple_elements(rest)}]
end
