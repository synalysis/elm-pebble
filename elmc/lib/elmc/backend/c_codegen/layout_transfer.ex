defmodule Elmc.Backend.CCodegen.LayoutTransfer do
  @moduledoc false

  alias Elmc.Backend.CCodegen.StoragePlan
  alias Elmc.Backend.CCodegen.Types

  @filter_targets ~w(
    List.filter
    Elm.Kernel.List.filter
  )

  @concat_targets [
    "List.append",
    "List.concat",
    "(++)",
    "Elm.Kernel.List.append",
    "Elm.Kernel.List.concat"
  ]

  @array_from_list ~w(Array.fromList Elm.Kernel.Array.fromList)
  @array_repeat ~w(Array.repeat Elm.Kernel.Array.repeat)
  @array_initialize ~w(Array.initialize Elm.Kernel.Array.initialize)

  @spec output_plan(String.t(), [Types.ir_expr()], StoragePlan.t() | nil, keyword()) ::
          StoragePlan.t()
  def output_plan(target, args, input_plan, opts \\ [])

  def output_plan(target, args, input_plan, opts) when is_binary(target) do
    elem_schema = Keyword.get(opts, :elem_schema)
    return_type = Keyword.get(opts, :return_type)

    cond do
      target in @filter_targets ->
        native_linked_for(elem_schema || plan_elem(input_plan))

      target in @concat_targets ->
        concat_plan(args, input_plan, elem_schema)

      target in @array_from_list ->
        preserve_or_compact(input_plan, elem_schema, access: :random)

      target in @array_repeat or target in @array_initialize ->
        compact_for_elem(elem_schema || plan_elem(input_plan), length: :known, access: :random)

      repeat_target?(target) ->
        repeat_plan(args, elem_schema || plan_elem(input_plan))

      true ->
        preserve_input(input_plan, elem_schema, return_type)
    end
  end

  def output_plan(_target, _args, input_plan, _opts), do: input_plan || StoragePlan.mixed()

  defp repeat_target?(target) do
    target in ~w(List.repeat Elm.Kernel.List.repeat)
  end

  defp repeat_plan([n, _value], elem_schema) do
    if known_length?(n) do
      compact_for_elem(elem_schema, length: :known)
    else
      native_linked_for(elem_schema)
    end
  end

  defp repeat_plan(_args, elem_schema), do: native_linked_for(elem_schema)

  defp concat_plan(_args, input_plan, elem_schema) do
    case input_plan do
      %StoragePlan{layout: :compact} = plan -> plan
      _ -> native_linked_for(elem_schema || plan_elem(input_plan))
    end
  end

  defp preserve_or_compact(input_plan, elem_schema, opts) do
    case input_plan do
      %StoragePlan{layout: :compact} = plan ->
        %{plan | access: Keyword.get(opts, :access, plan.access)}

      _ ->
        compact_for_elem(elem_schema, length: :unknown, access: Keyword.get(opts, :access, :random))
    end
  end

  defp preserve_input(nil, elem_schema, "List Float"),
    do: compact_for_elem(elem_schema || {:primitive, :float})

  defp preserve_input(nil, elem_schema, "List Int"),
    do: compact_for_elem(elem_schema || {:primitive, :int})

  defp preserve_input(%StoragePlan{} = plan, _elem, _type), do: plan
  defp preserve_input(_other, elem_schema, _type), do: compact_for_elem(elem_schema)

  defp compact_for_elem(elem, opts \\ [])

  defp compact_for_elem({:primitive, :float}, opts),
    do:
      StoragePlan.float_compact(
        length: Keyword.get(opts, :length, :unknown),
        access: Keyword.get(opts, :access, :sequential)
      )

  defp compact_for_elem({:primitive, :int}, opts),
    do: StoragePlan.int_compact(length: Keyword.get(opts, :length, :unknown), access: Keyword.get(opts, :access, :sequential))

  defp compact_for_elem({:record, mod, name}, opts),
    do: StoragePlan.record_compact(mod, name, length: Keyword.get(opts, :length, :unknown), access: Keyword.get(opts, :access, :sequential))

  defp compact_for_elem(_elem, _opts), do: StoragePlan.mixed()

  defp native_linked_for({:primitive, :int}), do: StoragePlan.int_native_linked()
  defp native_linked_for({:primitive, :float}), do: StoragePlan.float_native_linked()
  defp native_linked_for({:record, mod, name}), do: StoragePlan.record_compact(mod, name, length: :unknown)
  defp native_linked_for(_), do: StoragePlan.mixed()

  defp plan_elem(%StoragePlan{elem: elem}) when not is_nil(elem), do: elem
  defp plan_elem(_), do: nil

  defp known_length?(%{op: :int_literal, value: n}) when is_integer(n), do: true
  defp known_length?(_), do: false
end
