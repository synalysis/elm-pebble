defmodule Elmc.Backend.Plan.Lower.PatternBind do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr

  @spec bind(map(), Context.t(), Builder.t(), integer()) ::
          {:ok, Context.t(), Builder.t()} | :unsupported
  def bind(pattern, ctx, b, subject_reg) when is_map(pattern) and is_integer(subject_reg) do
    do_bind(pattern, ctx, b, subject_reg)
  end

  defp do_bind(%{kind: :wildcard}, ctx, b, _subject_reg), do: {:ok, ctx, b}

  defp do_bind(%{kind: :var, name: name}, ctx, b, subject_reg) when is_binary(name) do
    {:ok, Context.put_local(ctx, name, subject_reg), Builder.bind_local(b, name, subject_reg)}
  end

  defp do_bind(%{kind: :tuple, elements: elements}, ctx, b, subject_reg)
       when is_list(elements) and length(elements) > 2 do
    do_bind(%{kind: :tuple, elements: nest_tuple_elements(elements)}, ctx, b, subject_reg)
  end

  defp do_bind(%{kind: :tuple, elements: [left, right]}, ctx, b, subject_reg) do
    with {:ok, left_reg, b1} <- emit_tuple_proj(subject_reg, :first, b),
         {:ok, right_reg, b2} <- emit_tuple_proj(subject_reg, :second, b1),
         {:ok, ctx1, b3} <- do_bind(left, ctx, b2, left_reg),
         {:ok, ctx2, b4} <- do_bind(right, ctx1, b3, right_reg) do
      {:ok, ctx2, b4}
    else
      _ -> :unsupported
    end
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

  defp nest_tuple_elements([left, right]), do: [left, right]

  defp nest_tuple_elements([left | rest]),
    do: [left, %{kind: :tuple, elements: nest_tuple_elements(rest)}]
end
