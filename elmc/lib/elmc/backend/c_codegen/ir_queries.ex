defmodule Elmc.Backend.CCodegen.IRQueries do
  @moduledoc false

  alias ElmEx.IR
  alias ElmEx.IR.TypeSignature
  alias ElmEx.IR.Types.{Module, UnionEntry}
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
    "Pebble.Health.SleepUpdate" => 3,
    # elm-nonempty-list (dependency unions are not always present in IR metadata)
    "List.Nonempty.Nonempty" => 1,
    # Spaxe/svg-pathd Segment(..) constructors (tag order from Svg.PathD.elm)
    "Svg.PathD.M" => 1,
    "Svg.PathD.L" => 2,
    "Svg.PathD.H" => 3,
    "Svg.PathD.V" => 4,
    "Svg.PathD.Z" => 5,
    "Svg.PathD.C" => 6,
    "Svg.PathD.S" => 7,
    "Svg.PathD.Q" => 8,
    "Svg.PathD.T" => 9,
    "Svg.PathD.A" => 10,
    "Svg.PathD.Md" => 11,
    "Svg.PathD.Ld" => 12,
    "Svg.PathD.Hd" => 13,
    "Svg.PathD.Vd" => 14,
    "Svg.PathD.Zd" => 15,
    "Svg.PathD.Cd" => 16,
    "Svg.PathD.Sd" => 17,
    "Svg.PathD.Qd" => 18,
    "Svg.PathD.Td" => 19,
    "Svg.PathD.Ad" => 20
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

  @spec svg_attribute_names(IR.t()) :: MapSet.t(String.t())
  def svg_attribute_names(%IR{} = ir) do
    ir
    |> virtual_dom_attribute_keys()
    |> Map.keys()
    |> MapSet.new()
  end

  @doc """
  Alias for `virtual_dom_attribute_keys/1` (historical name used by wasm seeding).
  """
  @spec svg_attribute_dom_names(IR.t()) :: %{optional(String.t()) => String.t()}
  def svg_attribute_dom_names(%IR{} = ir), do: virtual_dom_attribute_keys(ir)

  @doc """
  Map Elm helper names → DOM attribute key strings from IR.

  Not an SVG/camelCase converter. Packages like elm/svg define helpers as
  `fontWeight = VirtualDom.attribute "font-weight"`; we read that string
  literal from the decl body (any module). Built from pre-strip IR so
  dead-code removal of attribute modules still works.
  """
  @spec virtual_dom_attribute_keys(IR.t()) :: %{optional(String.t()) => String.t()}
  def virtual_dom_attribute_keys(%IR{} = ir) do
    ir
    |> function_decl_map()
    |> Enum.reduce(%{}, fn
      {{_module, name}, decl}, acc when is_binary(name) ->
        case virtual_dom_attribute_key_from_decl(decl) do
          {:ok, key} -> Map.put(acc, name, key)
          :error -> acc
        end

      _, acc ->
        acc
    end)
  end

  defp virtual_dom_attribute_key_from_decl(%{expr: expr}),
    do: virtual_dom_attribute_key_from_expr(expr)

  defp virtual_dom_attribute_key_from_decl(_), do: :error

  defp virtual_dom_attribute_key_from_expr(%{
         op: :qualified_call,
         target: "Elm.Kernel.VirtualDom.attribute",
         args: [%{op: :string_literal, value: key} | _]
       })
       when is_binary(key),
       do: {:ok, key}

  defp virtual_dom_attribute_key_from_expr(%{
         op: :qualified_call,
         target: "VirtualDom.attribute",
         args: [%{op: :string_literal, value: key} | _]
       })
       when is_binary(key),
       do: {:ok, key}

  # attributeNS "ns" "local" — use the local name for setAttribute (host may NS later).
  defp virtual_dom_attribute_key_from_expr(%{
         op: :qualified_call,
         target: target,
         args: [%{op: :string_literal}, %{op: :string_literal, value: local} | _]
       })
       when target in [
              "Elm.Kernel.VirtualDom.attributeNS",
              "VirtualDom.attributeNS"
            ] and is_binary(local),
       do: {:ok, local}

  defp virtual_dom_attribute_key_from_expr(_), do: :error

  @spec record_alias_shape_map(IR.t()) :: %{optional({String.t(), String.t()}) => [String.t()]}
  def record_alias_shape_map(%IR{} = ir) do
    named_shapes =
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

    # Include union constructor record payloads (e.g. Layout {inArrows, contents, ...})
    # so ambiguous field resolution can distinguish them from unrelated aliases that
    # share a field name (elm-pages Scaffold {path, contents}).
    named_shapes
    |> Kernel.++(union_constructor_record_shapes(ir))
    |> Map.new()
  end

  @spec inline_record_literal_shape_map(IR.t()) :: %{optional({String.t(), String.t()}) => [String.t()]}
  def inline_record_literal_shape_map(%IR{} = ir) do
    inline_record_shapes_from_type_aliases(ir)
    |> Kernel.++(union_constructor_record_shapes(ir))
    |> Map.new()
  end

  @spec union_constructor_payload_specs_map(IR.t()) :: %{{String.t(), String.t()} => String.t()}
  def union_constructor_payload_specs_map(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn %{name: mod, unions: unions} ->
      unions
      |> Enum.flat_map(fn {_union_name, entry} ->
        entry
        |> Map.get(:payload_specs, %{})
        |> Enum.flat_map(fn {ctor_name, spec} ->
          if is_binary(spec) and spec != "" do
            [{{mod, to_string(ctor_name)}, spec}]
          else
            []
          end
        end)
      end)
    end)
    |> Map.new()
  end

  @spec union_constructor_record_shapes(IR.t()) :: [{{String.t(), String.t()}, [String.t()]}]
  def union_constructor_record_shapes(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn %{name: mod, unions: unions} ->
      unions
      |> Enum.flat_map(fn {_union_name, entry} ->
        entry
        |> Map.get(:payload_specs, %{})
        |> Enum.flat_map(fn {ctor_name, spec} ->
          if is_binary(spec) and TypeSignature.record_type?(spec) do
            # Elm 0.19 stores record fields alphabetically; keep ctor payload shapes in
            # that order so writes (canonicalize_literal_fields) and reads agree.
            fields =
              spec
              |> TypeSignature.record_field_names()
              |> Enum.map(&to_string/1)
              |> Enum.sort()

            if fields != [] do
              [{{mod, to_string(ctor_name)}, fields}]
            else
              []
            end
          else
            []
          end
        end)
      end)
    end)
  end

  @spec inline_record_shapes_from_type_aliases(IR.t()) :: [{{String.t(), String.t()}, [String.t()]}]
  def inline_record_shapes_from_type_aliases(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :type_alias))
      |> Enum.flat_map(fn decl ->
        field_types =
          case Map.get(decl, :expr) do
            %{field_types: types} when is_map(types) -> types
            _ -> %{}
          end

        field_types
        |> Enum.flat_map(fn {field_name, type_str} when is_binary(field_name) and is_binary(type_str) ->
          type_str
          |> embedded_record_types()
          |> Enum.map(fn shape ->
            key = {mod.name, "#{decl.name}_#{field_name}"}
            {key, shape}
          end)
        end)
      end)
    end)
  end

  defp embedded_record_types(type) when is_binary(type) do
    type
    |> brace_record_fragments([])
    |> Enum.flat_map(fn fragment ->
      trimmed = String.trim(fragment)

      if TypeSignature.record_type?(trimmed) do
        names = TypeSignature.record_field_names(trimmed)

        if names != [] do
          [names]
        else
          []
        end
      else
        []
      end
    end)
    |> Enum.uniq()
  end

  defp brace_record_fragments(<<>>, acc), do: Enum.reverse(acc)

  defp brace_record_fragments(<<char, rest::binary>>, acc) when char in [?\s, ?\t, ?\n, ?\r] do
    brace_record_fragments(rest, acc)
  end

  defp brace_record_fragments(<<?{, rest::binary>>, acc) do
    case take_brace_record(rest, 1, "{") do
      {record, after_record} -> brace_record_fragments(after_record, [record | acc])
      :error -> brace_record_fragments(rest, acc)
    end
  end

  defp brace_record_fragments(<<_char, rest::binary>>, acc), do: brace_record_fragments(rest, acc)

  defp take_brace_record(_rest, 0, acc), do: {acc, ""}

  defp take_brace_record(<<>>, _depth, _acc), do: :error

  defp take_brace_record(<<?{, rest::binary>>, depth, acc),
    do: take_brace_record(rest, depth + 1, acc <> "{")

  defp take_brace_record(<<?}, rest::binary>>, 1, acc),
    do: {acc <> "}", rest}

  defp take_brace_record(<<?}, rest::binary>>, depth, acc) when depth > 1,
    do: take_brace_record(rest, depth - 1, acc <> "}")

  defp take_brace_record(<<char, rest::binary>>, depth, acc),
    do: take_brace_record(rest, depth, acc <> <<char>>)

  @spec record_alias_field_types_map(IR.t()) :: Types.record_field_types_map()
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

  @spec module_ports_map(IR.t()) :: %{optional(String.t()) => [String.t()]}
  def module_ports_map(%IR{} = ir) do
    ir.modules
    |> Enum.map(fn mod ->
      ports =
        case Map.get(mod, :ports) do
          list when is_list(list) -> Enum.filter(list, &is_binary/1)
          _ -> []
        end

      {mod.name, ports}
    end)
    |> Map.new()
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

  @spec union_ctor_names(Module.t(), String.t()) :: [String.t()]
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

  @spec no_resource_ctor?(String.t()) :: boolean()
  defp no_resource_ctor?(name) when is_binary(name), do: String.starts_with?(name, "No")

  @spec enum_union?(UnionEntry.t()) :: boolean()
  defp enum_union?(%{payload_kinds: payload_kinds}) when is_map(payload_kinds) do
    payload_kinds != %{} and Enum.all?(Map.values(payload_kinds), &(&1 == :none))
  end

  defp enum_union?(_union), do: false
end
