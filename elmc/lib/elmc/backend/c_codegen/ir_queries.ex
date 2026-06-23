defmodule Elmc.Backend.CCodegen.IRQueries do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.CCodegen.Types

  @bundled_union_constructor_tags %{
    "Pebble.Platform.LaunchSystem" => 1,
    "Pebble.Platform.LaunchUser" => 2,
    "Pebble.Platform.LaunchPhone" => 3,
    "Pebble.Platform.LaunchWakeup" => 4,
    "Pebble.Platform.LaunchWorker" => 5,
    "Pebble.Platform.LaunchQuickLaunch" => 6,
    "Pebble.Platform.LaunchTimelineAction" => 7,
    "Pebble.Platform.LaunchSmartstrap" => 8,
    "Pebble.Platform.LaunchUnknown" => 9,
    "Pebble.Platform.Rectangular" => 1,
    "Pebble.Platform.Round" => 2,
    "Pebble.Platform.BlackWhite" => 1,
    "Pebble.Platform.Color" => 2,
    "Pebble.Health.StepCount" => 1,
    "Pebble.Health.ActiveSeconds" => 2,
    "Pebble.Health.WalkedDistanceMeters" => 3,
    "Pebble.Health.SleepSeconds" => 4,
    "Pebble.Health.RestfulSleepSeconds" => 5,
    "Pebble.Health.RestingKCalories" => 6,
    "Pebble.Health.ActiveKCalories" => 7,
    "Pebble.Health.HeartRateBPM" => 8,
    "Pebble.Health.SignificantUpdate" => 1,
    "Pebble.Health.MovementUpdate" => 2,
    "Pebble.Health.SleepUpdate" => 3
  }

  @bundled_health_metric_kernel_values %{
    "Pebble.Health.StepCount" => 0,
    "Pebble.Health.ActiveSeconds" => 1,
    "Pebble.Health.WalkedDistanceMeters" => 2,
    "Pebble.Health.SleepSeconds" => 3,
    "Pebble.Health.RestfulSleepSeconds" => 4,
    "Pebble.Health.RestingKCalories" => 5,
    "Pebble.Health.ActiveKCalories" => 6,
    "Pebble.Health.HeartRateBPM" => 7
  }

  @spec bundled_union_constructor_tags() :: %{String.t() => non_neg_integer()}
  def bundled_union_constructor_tags, do: @bundled_union_constructor_tags

  @spec bundled_health_metric_kernel_values() :: %{String.t() => non_neg_integer()}
  def bundled_health_metric_kernel_values, do: @bundled_health_metric_kernel_values

  @spec function_decl_map(IR.t()) :: Types.function_decl_map()
  def function_decl_map(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
    end)
    |> Map.new()
  end

  @spec record_alias_shape_map(IR.t()) :: %{optional({String.t(), String.t()}) => [String.t()]}
  def record_alias_shape_map(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :type_alias))
      |> Enum.flat_map(fn decl ->
        case Map.get(decl, :expr) do
          %{op: :record_alias, fields: fields} when is_list(fields) ->
            shape = fields |> Enum.map(&to_string/1)
            [{{mod.name, decl.name}, shape}]

          _ ->
            []
        end
      end)
    end)
    |> Map.new()
  end

  @spec record_alias_field_types_map(IR.t()) :: %{
          optional({String.t(), String.t()}) => map()
        }
  def record_alias_field_types_map(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :type_alias))
      |> Enum.flat_map(fn decl ->
        case Map.get(decl, :expr) do
          %{op: :record_alias, field_types: field_types} when is_map(field_types) ->
            [{{mod.name, decl.name}, field_types}]

          _ ->
            []
        end
      end)
    end)
    |> Map.new()
  end

  @spec union_type_name_set(IR.t()) :: MapSet.t(String.t())
  def union_type_name_set(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.unions
      |> Map.keys()
      |> Enum.flat_map(fn union_name ->
        qualified = "#{mod.name}.#{union_name}"
        [qualified, union_name]
      end)
    end)
    |> MapSet.new()
  end

  @spec constructor_tag_map(IR.t()) :: %{String.t() => non_neg_integer()}
  def constructor_tag_map(%IR{} = ir) do
    qualified =
      Enum.flat_map(ir.modules, fn mod ->
        mod.unions
        |> Map.values()
        |> Enum.flat_map(fn union ->
          union.tags
          |> Enum.map(fn {name, tag} -> {"#{mod.name}.#{name}", tag} end)
        end)
      end)

    unqualified =
      qualified
      |> Enum.group_by(fn {qualified_name, _tag} ->
        qualified_name |> String.split(".") |> List.last()
      end)
      |> Enum.flat_map(fn
        {name, [{_qualified_name, tag}]} -> [{name, tag}]
        {_name, _duplicates} -> []
      end)

    Map.merge(@bundled_union_constructor_tags, Map.new(qualified ++ unqualified))
  end

  @spec pebble_vector_resource_slot_map(IR.t()) :: %{String.t() => pos_integer()}
  def pebble_vector_resource_slot_map(%IR{} = ir) do
    pebble_resource_union_slot_map(ir, ["StaticVector", "AnimatedVector"])
  end

  @spec pebble_bitmap_resource_slot_map(IR.t()) :: %{String.t() => pos_integer()}
  def pebble_bitmap_resource_slot_map(%IR{} = ir) do
    pebble_resource_union_slot_map(ir, ["StaticBitmap"])
  end

  @spec pebble_animation_resource_slot_map(IR.t()) :: %{String.t() => pos_integer()}
  def pebble_animation_resource_slot_map(%IR{} = ir) do
    pebble_resource_union_slot_map(ir, ["AnimatedBitmap"])
  end

  @spec pebble_font_resource_slot_map(IR.t()) :: %{String.t() => pos_integer()}
  def pebble_font_resource_slot_map(%IR{} = ir) do
    pebble_resource_union_slot_map(ir, ["Font"])
  end

  @spec pebble_speaker_sample_resource_slot_map(IR.t()) :: %{String.t() => pos_integer()}
  def pebble_speaker_sample_resource_slot_map(%IR{} = ir) do
    pebble_resource_union_slot_map(ir, ["Sample"], ["Pebble.Speaker.Resources", "Speaker.Resources"])
  end

  @spec pebble_resource_union_slot_map(IR.t(), [String.t()]) :: %{String.t() => pos_integer()}
  defp pebble_resource_union_slot_map(%IR{} = ir, union_names) when is_list(union_names) do
    pebble_resource_union_slot_map(ir, union_names, ["Pebble.Ui.Resources", "Resources"])
  end

  @spec pebble_resource_union_slot_map(IR.t(), [String.t()], [String.t()]) ::
          %{String.t() => pos_integer()}
  defp pebble_resource_union_slot_map(%IR{} = ir, union_names, module_names)
       when is_list(union_names) and is_list(module_names) do
    ir.modules
    |> Enum.find_value(%{}, fn mod ->
      if mod.name in module_names do
        union_names
        |> Enum.flat_map(&union_ctor_names(mod, &1))
        |> Enum.reject(&no_resource_ctor?/1)
        |> Enum.with_index(1)
        |> Map.new(fn {name, index} -> {name, index} end)
      end
    end)
  end

  @spec enum_type_set(IR.t()) :: MapSet.t(String.t())
  def enum_type_set(%IR{} = ir) do
    qualified =
      Enum.flat_map(ir.modules, fn mod ->
        mod.unions
        |> Enum.filter(fn {_type_name, union} -> enum_union?(union) end)
        |> Enum.map(fn {type_name, _union} -> "#{mod.name}.#{type_name}" end)
      end)

    unqualified =
      qualified
      |> Enum.group_by(fn qualified_name ->
        qualified_name |> String.split(".") |> List.last()
      end)
      |> Enum.flat_map(fn
        {type_name, [_qualified_name]} -> [type_name]
        {_type_name, _duplicates} -> []
      end)

    MapSet.new(qualified ++ unqualified)
  end

  defp union_ctor_names(mod, union_name) when is_map(mod) and is_binary(union_name) do
    case Map.get(mod.unions, union_name) do
      %{tags: tags} when is_map(tags) ->
        tags
        |> Enum.sort_by(fn {_name, tag} -> tag end)
        |> Enum.map(fn {name, _tag} -> name end)

      _ ->
        []
    end
  end

  defp no_resource_ctor?(name) when is_binary(name), do: String.starts_with?(name, "No")

  defp enum_union?(%{payload_kinds: payload_kinds}) when is_map(payload_kinds) do
    payload_kinds != %{} and Enum.all?(Map.values(payload_kinds), &(&1 == :none))
  end

  defp enum_union?(_union), do: false
end
