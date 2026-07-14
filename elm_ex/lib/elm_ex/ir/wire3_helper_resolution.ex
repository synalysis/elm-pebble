defmodule ElmEx.IR.Wire3HelperResolution do
  @moduledoc """
  Synthesizes missing Lamdera Wire3 `w3_encode_*` / `w3_decode_*` helpers that
  elm-pages generated sources reference but do not define.

  Lamdera's compiler injects these at compile time from union types. When
  `elmc` loads generated Elm directly, we recover compatible helpers from
  existing `encode*ForClient` / `encode*` functions in the same module.
  """

  @wire3_prefix "w3_"

  @spec augment_function_definitions(String.t(), [map()], map()) :: [map()]
  def augment_function_definitions(module_name, function_defs, union_meta \\ %{})
      when is_list(function_defs) do
    defined = MapSet.new(function_defs, & &1.name)
    referenced = collect_wire3_refs(function_defs)
    missing = MapSet.difference(referenced, defined) |> Enum.sort()

    defs_by_name = Map.new(function_defs, &{&1.name, &1})

    missing
    |> Enum.flat_map(fn helper_name ->
      synthesize_helper(module_name, helper_name, defs_by_name, union_meta)
    end)
    |> case do
      [] -> function_defs
      synthetic -> function_defs ++ synthetic
    end
  end

  @spec union_meta_from_lowerer(map()) :: map()
  def union_meta_from_lowerer(unions) when is_map(unions) do
    constructor_tags =
      unions
      |> Map.values()
      |> Enum.flat_map(fn info ->
        info |> Map.get(:tags, %{}) |> Enum.to_list()
      end)
      |> Map.new()

    constructor_arity =
      unions
      |> Map.values()
      |> Enum.flat_map(fn info ->
        info
        |> Map.get(:payload_kinds, %{})
        |> Enum.map(fn {name, kind} ->
          {name, payload_arity_for_kind(kind)}
        end)
      end)
      |> Map.new()

    %{constructor_tags: constructor_tags, constructor_arity: constructor_arity}
  end

  defp payload_arity_for_kind(:unit), do: 0
  defp payload_arity_for_kind(:record), do: 1
  defp payload_arity_for_kind(:tuple), do: 1
  defp payload_arity_for_kind(:custom), do: 1
  defp payload_arity_for_kind(_), do: 1

  defp synthesize_helper(module_name, "w3_encode_" <> type_name = helper_name, defs_by_name, _union_meta) do
    for_client = "encode#{type_name}ForClient"
    plain = "encode#{type_name}"

    cond do
      Map.has_key?(defs_by_name, helper_name) ->
        []

      Map.has_key?(defs_by_name, for_client) ->
        [delegate_definition(module_name, helper_name, for_client, defs_by_name[for_client])]

      Map.has_key?(defs_by_name, plain) ->
        case build_tagged_encoder_from_plain(defs_by_name[plain]) do
          {:ok, expr} -> [wire3_definition(helper_name, expr, defs_by_name[plain])]
          :error -> []
        end

      true ->
        []
    end
  end

  defp synthesize_helper("Pages.Internal.ResponseSketch", "w3_decode_ResponseSketch" = helper_name, _defs_by_name, union_meta) do
    response_sketch_wire3_decode(helper_name, union_meta)
  end

  defp synthesize_helper(_module_name, "w3_decode_" <> type_name = helper_name, defs_by_name, union_meta) do
    if Map.has_key?(defs_by_name, helper_name) do
      []
    else
      source =
        cond do
          Map.has_key?(defs_by_name, "encode#{type_name}ForClient") ->
            defs_by_name["encode#{type_name}ForClient"]

          Map.has_key?(defs_by_name, "w3_encode_" <> type_name) ->
            defs_by_name["w3_encode_" <> type_name]

          Map.has_key?(defs_by_name, "encode#{type_name}") ->
            case build_tagged_encoder_from_plain(defs_by_name["encode#{type_name}"]) do
              {:ok, expr} -> %{defs_by_name["encode#{type_name}"] | expr: expr}
              :error -> nil
            end

          true ->
            nil
        end

      case source do
        %{expr: expr} ->
          case build_tag_decoder(expr, helper_name, union_meta) do
            {:ok, decode_defs} ->
              decode_defs

            :error ->
              []
          end

        _ ->
          []
      end
    end
  end

  defp synthesize_helper(_module_name, _helper_name, _defs_by_name, _union_meta), do: []

  defp delegate_definition(module_name, helper_name, target_name, source_def) do
    param = first_param_name(source_def)

    wire3_definition(
      helper_name,
      qualified_call("#{module_name}.#{target_name}", [var(param)]),
      source_def
    )
  end

  defp wire3_definition(name, expr, source_def) do
    %{
      kind: :function_definition,
      name: name,
      args: source_def.args || [],
      expr: expr,
      span: Map.get(source_def, :span)
    }
  end

  defp build_tagged_encoder_from_plain(%{expr: %{op: :case, branches: branches}} = source_def)
       when is_list(branches) and branches != [] do
    tags = alphabetical_tags(branches)

    tagged_branches =
      Enum.map(branches, fn branch ->
        constructor = constructor_name(branch.pattern)

        tag =
          case Map.get(tags, constructor) do
            n when is_integer(n) -> n
            _ -> nil
          end

        if is_integer(tag) do
          %{branch | expr: wrap_with_tag(branch.expr, tag)}
        else
          branch
        end
      end)

    {:ok, %{source_def.expr | branches: tagged_branches}}
  end

  defp build_tagged_encoder_from_plain(_), do: :error

  defp build_tag_decoder(%{op: :case, branches: branches}, helper_name, union_meta)
       when is_list(branches) do
    specs =
      branches
      |> Enum.map(&parse_tagged_encode_branch/1)
      |> Enum.reject(&is_nil/1)

    if specs == [] do
      :error
    else
      tag_switch_name = "#{helper_name}__tagSwitch"

      decode_branches =
        Enum.map(specs, fn
          {:tag_only, tag, constructor} ->
            %{
              pattern: %{kind: :int, value: tag},
              expr:
                qualified_call("Bytes.Decode.succeed", [
                  decoder_constructor_value(constructor, union_meta)
                ])
            }

          {:tagged_payload, tag, constructor, encode_target} ->
            decode_target = wire_encode_to_decode_target(encode_target)

            %{
              pattern: %{kind: :int, value: tag},
              expr:
                qualified_call("Bytes.Decode.map", [
                  decoder_constructor_value(constructor, union_meta, 1),
                  qualified_call(decode_target, [])
                ])
            }
        end)

      tag_switch_expr = %{
        op: :case,
        subject: var("tag"),
        branches:
          decode_branches ++
            [
              %{
                pattern: %{kind: :wildcard},
                expr: qualified_call("Bytes.Decode.fail", [])
              }
            ]
      }

      decoder_expr =
        qualified_call("Bytes.Decode.andThen", [
          %{op: :var, name: tag_switch_name},
          qualified_call("Bytes.Decode.unsignedInt8", [])
        ])

      {:ok,
       [
         %{
           kind: :function_definition,
           name: tag_switch_name,
           args: ["tag"],
           expr: tag_switch_expr
         },
         %{
           kind: :function_definition,
           name: helper_name,
           args: [],
           expr: decoder_expr
         }
       ]}
    end
  end

  defp build_tag_decoder(_, _, _), do: :error

  defp decoder_constructor_value(name, union_meta, callback_arity \\ nil) when is_binary(name) do
    tags = Map.get(union_meta, :constructor_tags, %{})
    arities = Map.get(union_meta, :constructor_arity, %{})
    tag = Map.get(tags, name)
    meta_arity = Map.get(arities, name, 1)

    arity =
      cond do
        is_integer(callback_arity) and callback_arity >= 0 -> callback_arity
        true -> meta_arity
      end

    cond do
      arity == 0 ->
        %{op: :constructor_call, target: name, args: []}

      is_integer(tag) ->
        %{
          op: :partial_constructor,
          target: name,
          tag: tag,
          args: [],
          arity: arity
        }

      true ->
        %{op: :constructor_call, target: name, args: []}
    end
  end

  defp parse_tagged_encode_branch(%{pattern: pattern, expr: expr}) do
    constructor = constructor_name(pattern)

    cond do
      match_tagged_payload?(expr) ->
        {tag, encode_target} = extract_tagged_payload(expr)
        {:tagged_payload, tag, constructor, encode_target}

      match_tag_only?(expr) ->
        tag = extract_tag_only(expr)
        {:tag_only, tag, constructor}

      true ->
        nil
    end
  end

  defp match_tagged_payload?(%{
         op: :qualified_call,
         target: "Lamdera.Wire3.encodeSequenceWithoutLength",
         args: [%{op: :list_literal, items: items}]
       })
       when is_list(items) and length(items) >= 2,
       do: true

  defp match_tagged_payload?(_), do: false

  defp extract_tagged_payload(%{
         op: :qualified_call,
         target: "Lamdera.Wire3.encodeSequenceWithoutLength",
         args: [%{op: :list_literal, items: [tag_expr, payload_expr | _]}]
       }) do
    {extract_tag_only(tag_expr), extract_payload_encode_target(payload_expr)}
  end

  defp match_tag_only?(%{op: :qualified_call, target: "Bytes.Encode.unsignedInt8", args: [tag_expr]}),
    do: match_int_literal?(tag_expr)

  defp match_tag_only?(_), do: false

  defp extract_tag_only(%{op: :qualified_call, target: "Bytes.Encode.unsignedInt8", args: [tag_expr]}),
    do: int_literal_value(tag_expr)

  defp extract_payload_encode_target(%{op: :qualified_call, target: target, args: _}),
    do: target

  defp extract_payload_encode_target(_), do: nil

  defp wrap_with_tag(expr, tag) do
    qualified_call("Lamdera.Wire3.encodeSequenceWithoutLength", [
      %{
        op: :list_literal,
        items: [
          qualified_call("Bytes.Encode.unsignedInt8", [%{op: :int_literal, value: tag}]),
          expr
        ]
      }
    ])
  end

  defp alphabetical_tags(branches) do
    branches
    |> Enum.map(&constructor_name(&1.pattern))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
    |> Enum.with_index()
    |> Map.new()
  end

  defp constructor_name(%{kind: :constructor, name: name}) when is_binary(name), do: name
  defp constructor_name(_), do: nil

  defp wire_encode_to_decode_target(target) when is_binary(target),
    do: String.replace(target, "w3_encode_", "w3_decode_")

  defp collect_wire3_refs(decls) do
    decls
    |> Enum.flat_map(fn
      %{expr: expr} when not is_nil(expr) -> collect_wire3_refs_from_expr(expr)
      _ -> []
    end)
    |> MapSet.new()
  end

  defp collect_wire3_refs_from_expr(expr) when is_map(expr) do
    base =
      case expr do
        %{op: :var, name: name} when is_binary(name) ->
          if String.starts_with?(name, @wire3_prefix), do: [name], else: []

        %{op: :qualified_call, target: _target} ->
          []

        _ ->
          []
      end

    expr
    |> Map.values()
    |> Enum.flat_map(fn
      child when is_map(child) -> collect_wire3_refs_from_expr(child)
      children when is_list(children) -> Enum.flat_map(children, &collect_wire3_refs_from_expr/1)
      _ -> []
    end)
    |> then(&(base ++ &1))
  end

  defp collect_wire3_refs_from_expr(children) when is_list(children),
    do: Enum.flat_map(children, &collect_wire3_refs_from_expr/1)

  defp collect_wire3_refs_from_expr(_), do: []

  @doc """
  Ensures per-route (and other cross-module) `w3_*` helpers referenced from
  synthesized decoders exist on their target modules.
  """
  @spec augment_cross_module_wire3([map()], map()) :: [map()]
  def augment_cross_module_wire3(modules, union_meta \\ %{}) when is_list(modules) do
    needed =
      modules
      |> Enum.flat_map(&module_wire3_call_targets/1)
      |> Enum.group_by(fn {mod, _} -> mod end, fn {_, name} -> name end)
      |> Map.new(fn {mod, names} -> {mod, names |> Enum.uniq() |> MapSet.new()} end)

    Enum.map(modules, fn mod ->
      case Map.get(needed, mod.name) do
        %MapSet{} = required -> ensure_module_wire3_helpers(mod, required, union_meta)
        _ -> mod
      end
    end)
  end

  defp module_wire3_call_targets(%{name: _name, declarations: decls}) when is_list(decls) do
    decls
    |> Enum.filter(&(&1.kind == :function))
    |> Enum.flat_map(fn decl ->
      decl
      |> Map.get(:expr)
      |> collect_cross_module_wire3_targets([])
    end)
    |> Enum.uniq()
  end

  defp module_wire3_call_targets(_), do: []

  defp collect_cross_module_wire3_targets(nil, acc), do: acc

  defp collect_cross_module_wire3_targets(%{op: :qualified_call, target: target} = expr, acc)
       when is_binary(target) do
    acc = wire3_qualified_target(target) ++ acc
    traverse_expr_children(Map.delete(expr, :target), acc)
  end

  defp collect_cross_module_wire3_targets(%{} = expr, acc) do
    traverse_expr_children(expr, acc)
  end

  defp collect_cross_module_wire3_targets(_, acc), do: acc

  defp traverse_expr_children(expr, acc) when is_map(expr) do
    Enum.reduce(expr, acc, fn
      {_key, child}, acc_child when is_map(child) ->
        collect_cross_module_wire3_targets(child, acc_child)

      {_key, children}, acc_child when is_list(children) ->
        Enum.reduce(children, acc_child, fn
          child, acc_item when is_map(child) -> collect_cross_module_wire3_targets(child, acc_item)
          _, acc_item -> acc_item
        end)

      _, acc_child ->
        acc_child
    end)
  end

  defp ensure_module_wire3_helpers(mod, %MapSet{} = required, union_meta) do
    existing =
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(& &1.name)
      |> MapSet.new()

    missing =
      required
      |> MapSet.difference(existing)
      |> MapSet.to_list()
      |> Enum.sort()

    if missing == [] do
      mod
    else
      defs_by_name = module_defs_by_name(mod)

      new_decls =
        Enum.flat_map(missing, fn helper_name ->
          case synthesize_helper(mod.name, helper_name, defs_by_name, union_meta) do
            [] -> trivial_wire3_decl(mod, helper_name)
            defs -> Enum.map(defs, &frontend_def_to_ir_decl/1)
          end
        end)

      %{mod | declarations: mod.declarations ++ new_decls}
    end
  end

  defp module_defs_by_name(mod) do
    mod.declarations
    |> Enum.filter(&(&1.kind == :function))
    |> Map.new(fn decl ->
      {decl.name,
       %{
         kind: :function_definition,
         name: decl.name,
         args: decl.args || [],
         expr: decl.expr
       }}
    end)
  end

  defp frontend_def_to_ir_decl(%{name: name, args: args, expr: expr}) do
    %{kind: :function, name: name, args: args || [], type: nil, expr: expr}
  end

  defp trivial_wire3_decl(mod, "w3_decode_" <> type_name) do
    case wire3_type_alias_shape(mod, type_name) do
      :empty_record ->
        [
          %{
            kind: :function,
            name: "w3_decode_" <> type_name,
            args: [],
            type: nil,
            expr:
              qualified_call("Bytes.Decode.succeed", [
                %{op: :record_literal, fields: []}
              ])
          }
        ]

      :non_empty_record ->
        []

      _ ->
        []
    end
  end

  defp trivial_wire3_decl(mod, "w3_encode_" <> type_name) do
    case wire3_type_alias_shape(mod, type_name) do
      :empty_record ->
        [
          %{
            kind: :function,
            name: "w3_encode_" <> type_name,
            args: ["value"],
            type: nil,
            expr:
              qualified_call("Lamdera.Wire3.encodeSequenceWithoutLength", [
                %{op: :list_literal, items: []}
              ])
          }
        ]

      _ ->
        []
    end
  end

  defp trivial_wire3_decl(_mod, _helper_name), do: []

  defp wire3_type_alias_shape(mod, type_name) when is_binary(type_name) do
    case Enum.find(mod.declarations, &(&1.kind == :type_alias and &1.name == type_name)) do
      %{expr: nil} ->
        :empty_record

      %{expr: %{op: :record_alias, fields: []}} ->
        :empty_record

      %{expr: %{op: :tuple_alias, arity: 0}} ->
        :empty_record

      %{expr: %{op: :record_alias, fields: fields}} when is_list(fields) and fields != [] ->
        :non_empty_record

      _ ->
        :unknown
    end
  end

  defp response_sketch_wire3_decode(helper_name, union_meta) do
    data = var("w3_x_c_data")
    action = var("w3_x_c_action")
    shared = var("w3_x_c_shared")

    maybe_action = qualified_call("Lamdera.Wire3.decodeMaybe", [action])

    branches = [
      %{
        pattern: %{kind: :int, value: 0},
        expr:
          qualified_call("Bytes.Decode.map", [
            decoder_constructor_value("Action", union_meta, 1),
            action
          ])
      },
      %{
        pattern: %{kind: :int, value: 1},
        expr:
          qualified_call("Bytes.Decode.map3", [
            decoder_constructor_value("HotUpdate", union_meta, 3),
            data,
            shared,
            maybe_action
          ])
      },
      %{
        pattern: %{kind: :int, value: 2},
        expr:
          qualified_call("Bytes.Decode.map2", [
            decoder_constructor_value("NotFound", union_meta, 2),
            qualified_call("Pages.Internal.NotFoundReason.w3_decode_NotFoundReason", []),
            qualified_call("UrlPath.w3_decode_UrlPath", [])
          ])
      },
      %{
        pattern: %{kind: :int, value: 3},
        expr:
          qualified_call("Bytes.Decode.map", [
            decoder_constructor_value("Redirect", union_meta, 1),
            qualified_call("Lamdera.Wire3.decodeString", [])
          ])
      },
      %{
        pattern: %{kind: :int, value: 4},
        expr:
          qualified_call("Bytes.Decode.map2", [
            decoder_constructor_value("RenderPage", union_meta, 2),
            data,
            maybe_action
          ])
      }
    ]

    tag_switch_expr = %{
      op: :case,
      subject: var("tag"),
      branches:
        branches ++
          [
            %{
              pattern: %{kind: :wildcard},
              expr: qualified_call("Bytes.Decode.fail", [])
            }
          ]
    }

    decoder_expr =
      qualified_call("Bytes.Decode.andThen", [
        %{
          op: :lambda,
          args: ["tag"],
          body: tag_switch_expr
        },
        qualified_call("Bytes.Decode.unsignedInt8", [])
      ])

    [
      %{
        kind: :function_definition,
        name: helper_name,
        args: ["w3_x_c_data", "w3_x_c_action", "w3_x_c_shared"],
        expr: decoder_expr
      }
    ]
  end

  defp wire3_qualified_target(target) when is_binary(target) do
    parts = String.split(target, ".")

    case parts do
      [] ->
        []

      [_single] ->
        []

      parts ->
        name = List.last(parts)
        mod = parts |> Enum.drop(-1) |> Enum.join(".")

        if String.starts_with?(name, "w3_") do
          [{mod, name}]
        else
          []
        end
    end
  end

  defp first_param_name(%{args: [param | _]}) when is_binary(param), do: param
  defp first_param_name(%{args: []}), do: "value"
  defp first_param_name(_), do: "value"

  defp var(name), do: %{op: :var, name: name}

  defp qualified_call(target, args),
    do: %{op: :qualified_call, target: target, args: args}

  defp int_literal_value(%{op: :int_literal, value: value}) when is_integer(value), do: value
  defp int_literal_value(_), do: nil

  defp match_int_literal?(%{op: :int_literal, value: value}) when is_integer(value), do: true
  defp match_int_literal?(_), do: false
end
