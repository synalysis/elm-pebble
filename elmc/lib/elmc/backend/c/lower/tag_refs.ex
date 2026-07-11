defmodule Elmc.Backend.C.Lower.TagRefs do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Plan.Types.Block

  @spec switch_arm_tag(term()) :: integer() | nil
  def switch_arm_tag({tag, _target}) when is_integer(tag), do: tag
  def switch_arm_tag({tag, _target, _ctor}) when is_integer(tag), do: tag
  def switch_arm_tag(_), do: nil

  @spec switch_arm_target(term()) :: non_neg_integer() | nil
  def switch_arm_target({_tag, target}) when is_integer(target), do: target
  def switch_arm_target({_tag, target, _ctor}) when is_integer(target), do: target
  def switch_arm_target(_), do: nil

  @spec switch_arm_ctor(term()) :: String.t() | nil
  def switch_arm_ctor({_tag, _target, ctor}) when is_binary(ctor), do: ctor
  def switch_arm_ctor(_), do: nil

  @spec union_tag_ref(integer(), String.t() | nil, String.t() | nil) :: String.t()
  def union_tag_ref(tag, ctor_name, module \\ nil) when is_integer(tag) do
    macros = Process.get(:elmc_union_constructor_macros, %{})

    ctor_name
    |> union_ctor_candidates(module)
    |> Enum.find_value(fn name -> Map.get(macros, name) end) ||
      Integer.to_string(tag)
  end

  @spec const_int_ref(integer(), String.t() | nil, String.t() | nil) :: String.t()
  def const_int_ref(value, ctor_name, module \\ nil) when is_integer(value) do
    union_tag_ref(value, ctor_name, module)
  end

  @spec build_plan_state_labels(FunctionPlan.t()) :: %{non_neg_integer() => String.t()}
  def build_plan_state_labels(%{blocks: blocks}) when is_list(blocks) do
    incoming = incoming_block_counts(blocks)

    blocks
    |> Enum.reduce(%{0 => "ENTRY"}, fn block, acc ->
      acc
      |> apply_switch_arm_labels(block)
      |> apply_block_role_labels(block, incoming)
    end)
  end

  @spec plan_state_ref(map(), non_neg_integer(), map()) :: String.t()
  def plan_state_ref(%{module: module, name: name}, block_id, labels) when is_integer(block_id) do
    case Map.get(labels, block_id) do
      label when is_binary(label) ->
        plan_state_macro(module, name, label)

      _ ->
        Integer.to_string(block_id)
    end
  end

  @spec emit_plan_state_enum(map(), map()) :: String.t()
  def emit_plan_state_enum(%{} = plan, labels) when is_map(labels) do
    blocks = Map.get(plan, :blocks, [])
    block_ids =
      (blocks |> Enum.map(& &1.id)) ++ Map.keys(labels)
      |> Enum.uniq()
      |> Enum.sort()

    lines =
      Enum.map(block_ids, fn id ->
        "#{plan_state_ref(plan, id, labels)} = #{id}"
      end)

    """
    enum {
      #{Enum.join(lines, ",\n  ")}
    };
    """
    |> String.trim()
  end

  defp apply_switch_arm_labels(acc, %Block{terminator: {:switch_tag, _, arms, default_id}}) do
    acc =
      Enum.reduce(arms, acc, fn arm, labels ->
        target = switch_arm_target(arm)

        label =
          case switch_arm_ctor(arm) do
            name when is_binary(name) -> "#{ctor_label(name)}_#{target}"
            _ -> "ARM_#{target}"
          end

        Map.put(labels, target, label)
      end)

    if is_integer(default_id) do
      Map.put_new(acc, default_id, "DEFAULT_#{default_id}")
    else
      acc
    end
  end

  defp apply_switch_arm_labels(acc, _block), do: acc

  defp apply_block_role_labels(acc, %Block{id: id, terminator: {:ret, _}}, _incoming) do
    Map.put(acc, id, "RETURN_#{id}")
  end

  defp apply_block_role_labels(acc, %Block{id: id}, incoming) do
    if Map.get(incoming, id, 0) >= 3 do
      Map.put_new(acc, id, "MERGE_#{id}")
    else
      acc
    end
  end

  defp incoming_block_counts(blocks) do
    Enum.reduce(blocks, %{}, fn %Block{terminator: term}, counts ->
      Enum.reduce(explicit_branch_targets(term), counts, fn target, acc ->
        Map.update(acc, target, 1, &(&1 + 1))
      end)
    end)
  end

  defp explicit_branch_targets({:br, target}) when is_integer(target), do: [target]

  defp explicit_branch_targets({:br_if, then_id, else_id, _}) do
    [then_id, else_id]
  end

  defp explicit_branch_targets({:switch_tag, _, arms, default_id}) do
    arm_targets = Enum.map(arms, &switch_arm_target/1)
    arm_targets ++ List.wrap(default_id)
  end

  defp explicit_branch_targets(_), do: []

  defp plan_state_macro(module, name, label) when is_binary(label) do
    mod_s = module |> Util.safe_c_suffix() |> String.upcase()
    fn_s = name |> Util.safe_c_suffix() |> String.upcase()
    label_s = label |> Util.safe_c_suffix() |> String.upcase()
    "ELMC_PLAN_STATE_#{mod_s}_#{fn_s}_#{label_s}"
  end

  defp ctor_label(name) when is_binary(name) do
    name
    |> String.split(".")
    |> List.last()
    |> Util.safe_c_suffix()
    |> String.upcase()
  end

  defp union_ctor_candidates(nil, _module), do: []

  defp union_ctor_candidates(name, module) when is_binary(name) do
    short = name |> String.split(".") |> List.last()

    module_qualified =
      if is_binary(module) and not String.contains?(name, ".") do
        "#{module}.#{short}"
      end

    [module_qualified, name, short, unique_qualified_union_ctor(short)]
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp unique_qualified_union_ctor(short_name) when is_binary(short_name) do
    tags = Process.get(:elmc_constructor_tags, %{})

    matches =
      tags
      |> Map.keys()
      |> Enum.filter(fn key -> String.ends_with?(key, "." <> short_name) end)

    case matches do
      [qualified] -> qualified
      _ -> nil
    end
  end
end
