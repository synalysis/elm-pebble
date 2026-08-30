defmodule Elmc.Backend.CCodegen.IRQueries do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


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
    # Must match Pebble SDK HealthMetric (0-based) and Pebble.Health.metricToInt.
    "Pebble.Health.StepCount" => 0,
    "Pebble.Health.ActiveSeconds" => 1,
    "Pebble.Health.WalkedDistanceMeters" => 2,
    "Pebble.Health.SleepSeconds" => 3,
    "Pebble.Health.RestfulSleepSeconds" => 4,
    "Pebble.Health.RestingKCalories" => 5,
    "Pebble.Health.ActiveKCalories" => 6,
    "Pebble.Health.HeartRateBPM" => 7,
    # Match pebble_app_template health_event_to_code / Health.Event declaration order.
    "Pebble.Health.SignificantUpdate" => 0,
    "Pebble.Health.MovementUpdate" => 1,
    "Pebble.Health.SleepUpdate" => 2,
    "Pebble.Health.HeartRateUpdate" => 3,
    "Pebble.Health.HrvUpdate" => 4,
    "Pebble.Touch.Started" => 0,
    "Pebble.Touch.Updated" => 1,
    "Pebble.Touch.Completed" => 2,
    "Pebble.Touch.Cancelled" => 3,
    "Pebble.Touch.Horizontal" => 0,
    "Pebble.Touch.Vertical" => 1,
    "Pebble.Touch.Up" => 0,
    "Pebble.Touch.Down" => 1,
    "Pebble.Touch.Left" => 2,
    "Pebble.Touch.Right" => 3,
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
    "Svg.PathD.Ad" => 20,
    # VirtualDom.Handler (declaration order; used when elm/virtual-dom is DCE'd)
    "VirtualDom.Normal" => 1,
    "VirtualDom.MayStopPropagation" => 2,
    "VirtualDom.MayPreventDefault" => 3,
    "VirtualDom.Custom" => 4,
    # Official elm/http Response constructors (underscore so they do not collide
    # with Http.Error). Seeded when the union is stripped from IR metadata.
    "Http.BadUrl_" => 1,
    "Http.Timeout_" => 2,
    "Http.NetworkError_" => 3,
    "Http.BadStatus_" => 4,
    "Http.GoodStatus_" => 5,
    # Official elm/json Error declaration order.
    "Json.Decode.Field" => 1,
    "Json.Decode.Index" => 2,
    "Json.Decode.OneOf" => 3,
    "Json.Decode.Failure" => 4
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

  @bundled_union_constructor_arities %{
    "Maybe.Just" => 1,
    "Maybe.Nothing" => 0,
    "Result.Ok" => 1,
    "Result.Err" => 1,
    "Json.Decode.Field" => 2,
    "Json.Decode.Index" => 2,
    "Json.Decode.OneOf" => 1,
    "Json.Decode.Failure" => 2
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

  @spec virtual_dom_attribute_key_from_decl(map() | term()) :: {:ok, String.t()} | :error

  defp virtual_dom_attribute_key_from_decl(%{expr: expr}),
    do: virtual_dom_attribute_key_from_expr(expr)

  defp virtual_dom_attribute_key_from_decl(_), do: :error

  @spec virtual_dom_attribute_key_from_expr(map() | term()) :: {:ok, String.t()} | :error

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

  # attributeNS "ns" "local" — local name for the DOM key map; NS lives in
  # `virtual_dom_attribute_ns/1` so emit can use html_cmd kind 20.
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

  defp virtual_dom_attribute_key_from_expr(%{op: :lambda, body: body}),
    do: virtual_dom_attribute_key_from_expr(body)

  defp virtual_dom_attribute_key_from_expr(_), do: :error

  @doc """
  Helper name → `{namespace, local}` for decls that are official
  `VirtualDom.attributeNS ns local` (including 2-arg partials and 1-arg lambdas).
  """
  @spec virtual_dom_attribute_ns(IR.t()) :: %{optional(String.t()) => {String.t(), String.t()}}
  def virtual_dom_attribute_ns(%IR{} = ir) do
    ir
    |> function_decl_map()
    |> Enum.reduce(%{}, fn
      {{_module, name}, decl}, acc when is_binary(name) ->
        case virtual_dom_attribute_ns_from_decl(decl) do
          {:ok, pair} -> Map.put(acc, name, pair)
          :error -> acc
        end

      _, acc ->
        acc
    end)
  end

  defp virtual_dom_attribute_ns_from_decl(%{expr: expr}),
    do: virtual_dom_attribute_ns_from_expr(expr)

  defp virtual_dom_attribute_ns_from_decl(_), do: :error

  defp virtual_dom_attribute_ns_from_expr(%{op: :lambda, body: body}),
    do: virtual_dom_attribute_ns_from_expr(body)

  defp virtual_dom_attribute_ns_from_expr(%{
         op: :qualified_call,
         target: target,
         args: [%{op: :string_literal, value: ns}, %{op: :string_literal, value: local} | _]
       })
       when target in [
              "Elm.Kernel.VirtualDom.attributeNS",
              "VirtualDom.attributeNS"
            ] and is_binary(ns) and is_binary(local),
       do: {:ok, {ns, local}}

  defp virtual_dom_attribute_ns_from_expr(_), do: :error

  @doc """
  `{module, helper}` → namespace for decls that are official
  `VirtualDom.keyedNodeNS ns` (including 1-arg partials / lambdas).
  """
  @spec virtual_dom_keyed_node_ns(IR.t()) :: %{optional({String.t(), String.t()}) => String.t()}
  def virtual_dom_keyed_node_ns(%IR{} = ir) do
    ir
    |> function_decl_map()
    |> Enum.reduce(%{}, fn
      {{module, name}, decl}, acc when is_binary(module) and is_binary(name) ->
        case keyed_node_ns_from_decl(decl) do
          {:ok, ns} -> Map.put(acc, {module, name}, ns)
          :error -> acc
        end

      _, acc ->
        acc
    end)
  end

  defp keyed_node_ns_from_decl(%{expr: expr}), do: keyed_node_ns_from_expr(expr)
  defp keyed_node_ns_from_decl(_), do: :error

  defp keyed_node_ns_from_expr(%{op: :lambda, body: body}),
    do: keyed_node_ns_from_expr(body)

  defp keyed_node_ns_from_expr(%{
         op: :qualified_call,
         target: target,
         args: [%{op: :string_literal, value: ns} | _]
       })
       when target in [
              "Elm.Kernel.VirtualDom.keyedNodeNS",
              "VirtualDom.keyedNodeNS"
            ] and is_binary(ns),
       do: {:ok, ns}

  defp keyed_node_ns_from_expr(_), do: :error

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
              names = fields |> Enum.map(&to_string/1)
              # Most aliases keep declaration order so elm-pages / Url / Model field
              # disambiguation stays stable. Scene3d.Types.Transformation is the
              # exception: package code and anonymous-style field_access assume Elm's
              # alphabetical layout (isRightHanded first, scale last). Declaration
              # order made .scale read pz (0) and .pz read scale (1) → zero modelScale
              # and translation z=1 → solid-white HeroScene after materials worked.
              shape =
                if elm_alphabetical_alias?(mod.name, decl.name, names) do
                  Enum.sort(names)
                else
                  names
                end

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

  # Aliases that must match Elm 0.19 alphabetical record layout end-to-end.
  @spec elm_alphabetical_alias?(String.t(), String.t(), [String.t()]) :: boolean()

  defp elm_alphabetical_alias?("Scene3d.Types", "Transformation", _names), do: true

  # WebGL mesh vertices: shader attribute maps are alphabetical (`normal` before
  # `position`). Declaration-order VertexWithNormal wrote [position, normal] so
  # the host bound normals as positions → collapsed caps / radial floor stripes
  # and notched tangram (body showing through shredded face cylinders).
  defp elm_alphabetical_alias?("Scene3d.Types", name, _names)
       when name in [
              "PlainVertex",
              "VertexWithNormal",
              "VertexWithUv",
              "VertexWithNormalAndUv",
              "VertexWithTangent"
            ],
       do: true

  # Same WebGL attribute contract for Mesh-local vertex aliases. Declaration
  # order TexturedFacetVertex is `{position, uv, normal}` — a false proper-superset
  # of `{position, normal}` that mapped collectSmooth `.normal`→2.
  defp elm_alphabetical_alias?("Scene3d.Mesh", name, _names)
       when name in ["TexturedFacetVertex", "TexturedTriangleVertex"],
       do: true

  defp elm_alphabetical_alias?(_mod, _name, _names), do: false

  @spec inline_record_literal_shape_map(IR.t()) :: %{optional({String.t(), String.t()}) => [String.t()]}
  def inline_record_literal_shape_map(%IR{} = ir) do
    base =
      inline_record_shapes_from_type_aliases(ir)
      |> Kernel.++(union_constructor_record_shapes(ir))
      # Nested anonymous records inside union payloads (e.g. Scene3d MeshWithNormals
      # TriangularMesh `{position, normal}` / `{position, normal, uv}`) must be
      # registered so unique_superset can pad trailing extension slots.
      |> Kernel.++(union_payload_embedded_record_shapes(ir))
      |> Map.new()

    Map.merge(base, literal_record_shape_map_from_bodies(ir, base))
  end

  # Anonymous record literals with no type alias (e.g. a `let`-bound helper
  # returning `{ id = .., val = {..} }`) never populate any shape table above.
  # Field access on a variable of unresolved origin — a case-bound `Just p`
  # payload, a `List.filter`/`List.head` result, etc. — then falls back to a
  # usage-only guess that only sees the *one* field actually read in that arm
  # (e.g. `p.val`), producing index 0 for a two-field record. Register the
  # field set as actually written at each literal so ambiguous-field lookups
  # in `Plan.Lower.Record` can recover the real layout.
  #
  # Elm stores anonymous records alphabetically. Skip any field set that
  # exactly matches, or is a proper subset of, an already-known shape so
  # unique-superset padding (Arrow.meander, Scene3d embeds) and named-alias
  # layouts keep taking priority over a same-length alphabetical guess.
  @spec literal_record_shape_map_from_bodies(IR.t(), map()) ::
          %{optional({String.t(), String.t()}) => [String.t()]}
  defp literal_record_shape_map_from_bodies(%IR{} = ir, known_shapes) do
    reference_shapes = Map.merge(Process.get(:elmc_record_alias_shapes, %{}), known_shapes)

    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.flat_map(fn decl ->
        decl
        |> Map.get(:expr)
        |> collect_record_literal_field_sets([])
        |> Enum.uniq()
        |> Enum.with_index()
        |> Enum.flat_map(fn {names, idx} ->
          if registrable_literal_shape?(names, reference_shapes) do
            [{{mod.name, "#{decl.name}@literal#{idx}"}, names}]
          else
            []
          end
        end)
      end)
    end)
    |> Map.new()
  end

  @spec collect_record_literal_field_sets(Types.ir_expr() | term(), [[String.t()]]) :: [
          [String.t()]
        ]
  defp collect_record_literal_field_sets(expr, acc) do
    acc =
      case expr do
        %{op: :record_literal, fields: fields} when is_list(fields) ->
          names =
            fields
            |> Enum.map(fn f -> Map.get(f, :name) || Map.get(f, :field) end)
            |> Enum.filter(&is_binary/1)
            |> Enum.sort()

          if names == [], do: acc, else: [names | acc]

        _ ->
          acc
      end

    case expr do
      list when is_list(list) -> Enum.reduce(list, acc, &collect_record_literal_field_sets/2)
      map when is_map(map) -> map |> Map.values() |> Enum.reduce(acc, &collect_record_literal_field_sets/2)
      _ -> acc
    end
  end

  @spec registrable_literal_shape?([String.t()], map()) :: boolean()
  defp registrable_literal_shape?(names, shapes) when is_list(names) and is_map(shapes) do
    name_set = MapSet.new(names)

    blockers =
      Enum.filter(shapes, fn {_key, shape} ->
        is_list(shape) and shape != [] and
          (fn shape_set ->
             MapSet.equal?(shape_set, name_set) or
               (MapSet.size(shape_set) > MapSet.size(name_set) and
                  MapSet.subset?(name_set, shape_set))
           end).(MapSet.new(shape, &to_string/1))
      end)

    blockers == []
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
          cond do
            is_binary(spec) ->
              # Keep "" for nullary so plan lowering can tell nullary nests
              # (`tuple2(UseMeshUvs, rest)`) from unary `(tag, payload)`.
              [{{mod, to_string(ctor_name)}, spec}]

            is_nil(spec) ->
              [{{mod, to_string(ctor_name)}, ""}]

            true ->
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

  @spec union_payload_embedded_record_shapes(IR.t()) :: [{{String.t(), String.t()}, [String.t()]}]

  defp union_payload_embedded_record_shapes(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn %{name: mod, unions: unions} ->
      unions
      |> Enum.flat_map(fn {union_name, entry} ->
        entry
        |> Map.get(:payload_specs, %{})
        |> Enum.flat_map(fn {ctor_name, spec} ->
          if is_binary(spec) do
            spec
            |> embedded_record_types()
            |> Enum.with_index()
            |> Enum.map(fn {shape, idx} ->
              # Elm stores anonymous / payload-embedded records alphabetically.
              # Declaration order made MeshWithNormals embeds `{position, normal}`
              # fight alphabetical VertexWithNormal writes and WebGL attribute maps.
              sorted = shape |> Enum.map(&to_string/1) |> Enum.sort()
              {{mod, "#{union_name}.#{ctor_name}_embed#{idx}"}, sorted}
            end)
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

  @spec embedded_record_types(String.t()) :: [[String.t()]]

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

  @spec brace_record_fragments(binary(), [binary()]) :: [binary()]

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


  @spec take_brace_record(binary(), non_neg_integer(), binary()) :: {binary(), binary()} | :error

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

  @doc """
  Constructor payload arity (`Idle` → 0, `Just a` → 1, `Pair Int Int` → 2).

  Official `Debug.toString` prints n-ary ctors as `Pair 1 2`, not `Pair (1,2)`.
  """
  @spec constructor_arity_map(IR.t()) :: %{String.t() => non_neg_integer()}
  def constructor_arity_map(%IR{} = ir) do
    qualified =
      Enum.flat_map(ir.modules, fn mod ->
        mod.unions
        |> Map.values()
        |> Enum.flat_map(fn union ->
          specs = Map.get(union, :payload_specs, %{})

          Enum.map(Map.get(union, :tags, %{}), fn {name, _tag} ->
            spec = Map.get(specs, name) || Map.get(specs, to_string(name))
            {"#{mod.name}.#{name}", Elmc.Backend.Pebble.Util.payload_arity_for_spec(spec)}
          end)
        end)
      end)

    unqualified =
      qualified
      |> Enum.group_by(fn {qualified_name, _arity} ->
        qualified_name |> String.split(".") |> List.last()
      end)
      |> Enum.flat_map(fn
        {name, [{_qualified_name, arity}]} -> [{name, arity}]
        {_name, _duplicates} -> []
      end)

    Map.merge(@bundled_union_constructor_arities, Map.new(qualified ++ unqualified))
  end

  @doc """
  Resolve a constructor name to its tag.

  Prefer exact / unique short-name hits. When a short name is shared across
  modules (e.g. `Group`), qualify via the call-site module (`Scene3d.Entity.Group`)
  and pick the candidate with the longest shared module prefix
  (`Scene3d.Types.Group`), never an unrelated package's ctor
  (`Benchmark.Benchmark.Group`).
  """
  @spec lookup_tag(%{optional(String.t()) => non_neg_integer()}, String.t()) ::
          non_neg_integer() | nil
  def lookup_tag(tags, target) when is_map(tags) and is_binary(target) do
    short = constructor_short_name(target)

    Map.get(tags, target) ||
      Map.get(tags, short) ||
      lookup_suffix_tag(tags, target, short)
  end

  def lookup_tag(_tags, _target), do: nil

  @spec lookup_suffix_tag(
          %{optional(String.t()) => non_neg_integer()},
          String.t(),
          String.t()
        ) :: non_neg_integer() | nil

  defp lookup_suffix_tag(tags, target, short) do
    suffix = "." <> short

    candidates =
      for {key, tag} <- tags,
          is_binary(key) and is_integer(tag),
          String.ends_with?(key, suffix),
          do: {key, tag}

    case candidates do
      [] ->
        nil

      [{_key, tag}] ->
        tag

      many ->
        target_mod = target |> String.split(".") |> Enum.drop(-1)

        scored =
          Enum.map(many, fn {key, tag} ->
            key_mod = key |> String.split(".") |> Enum.drop(-1)
            leading = shared_prefix_len(target_mod, key_mod)
            trailing = shared_prefix_len(Enum.reverse(target_mod), Enum.reverse(key_mod))
            {{leading, trailing}, String.length(key), key, tag}
          end)

        max_score = scored |> Enum.map(&elem(&1, 0)) |> Enum.max()

        # Refuse to guess among unrelated packages (no shared module segments).
        if max_score == {0, 0} do
          nil
        else
          {_score, _len, _key, tag} =
            scored
            |> Enum.filter(fn {score, _, _, _} -> score == max_score end)
            |> Enum.max_by(fn {_score, len, _key, _tag} -> len end)

          tag
        end
    end
  end

  @spec shared_prefix_len([String.t()], [String.t()]) :: non_neg_integer()

  defp shared_prefix_len(left, right) do
    left
    |> Enum.zip(right)
    |> Enum.take_while(fn {a, b} -> a == b end)
    |> length()
  end

  @spec constructor_short_name(String.t()) :: String.t()

  defp constructor_short_name(name), do: name |> String.split(".") |> List.last()

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

  @doc """
  Constructor names belonging to all-nullary enum unions.

  Used by plan Constructor to emit scalar tags (`const_int`) instead of
  `tuple2(tag, ())`. Mixed unions with some nullary ctors are excluded —
  those nullaries stay `tuple2(tag, unit)` for nested payload spines.
  """
  @spec enum_constructor_set(IR.t()) :: MapSet.t(String.t())
  def enum_constructor_set(%IR{} = ir) do
    qualified =
      Enum.flat_map(ir.modules, fn mod ->
        mod.unions
        |> Enum.filter(fn {_type_name, union} -> enum_union?(union) end)
        |> Enum.flat_map(fn {_type_name, union} ->
          union.tags
          |> Map.keys()
          |> Enum.map(fn name -> "#{mod.name}.#{name}" end)
        end)
      end)

    unqualified =
      qualified
      |> Enum.group_by(fn qualified_name ->
        qualified_name |> String.split(".") |> List.last()
      end)
      |> Enum.flat_map(fn
        {ctor_name, [_qualified_name]} -> [ctor_name]
        {_ctor_name, _duplicates} -> []
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
