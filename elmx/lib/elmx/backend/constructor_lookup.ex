defmodule Elmx.Backend.ConstructorLookup do
  @moduledoc """
  Union constructor metadata derived from lowered `ElmEx.IR` (package/project unions).
  """

  alias ElmEx.IR

  @type entry :: %{
          module: String.t(),
          union_name: String.t(),
          union_type: String.t(),
          constructor: String.t(),
          qualified: String.t(),
          tag: pos_integer(),
          payload_kind: :none | :single | :multi | :function_like
        }

  @type t :: %{
          by_qualified: %{String.t() => entry()},
          by_unqualified: %{String.t() => entry()}
        }

  @typedoc "Lookup table or partial map with optional index fields (empty env uses `%{}`)."
  @type lookup_input :: t() | %{
          optional(:by_qualified) => %{optional(String.t()) => entry()},
          optional(:by_unqualified) => %{optional(String.t()) => entry()}
        }

  @spec from_ir(IR.t()) :: t()
  def from_ir(%IR{modules: modules}) do
    entries =
      Enum.flat_map(modules, fn mod ->
        unions = Map.get(mod, :unions) || %{}

        Enum.flat_map(unions, fn {union_name, union_info} ->
          tags = Map.get(union_info, :tags) || %{}
          payload_kinds = Map.get(union_info, :payload_kinds) || %{}

          Enum.map(tags, fn {constructor, tag} ->
            %{
              module: mod.name,
              union_name: to_string(union_name),
              union_type: "#{mod.name}.#{union_name}",
              constructor: to_string(constructor),
              qualified: "#{mod.name}.#{constructor}",
              tag: tag,
              payload_kind: Map.get(payload_kinds, constructor, :none)
            }
          end)
        end)
      end)

    %{
      by_qualified: Map.new(entries, &{&1.qualified, &1}),
      by_unqualified:
        entries
        |> Enum.group_by(& &1.constructor)
        |> Enum.map(fn {name, list} ->
          case list do
            [one] -> {name, one}
            many -> {name, pick_unqualified_entry(many)}
          end
        end)
        |> Map.new()
    }
  end

  @spec resolve(lookup_input(), String.t(), String.t() | nil) :: entry() | nil
  def resolve(lookup, name, current_module) when is_binary(name) and is_map(lookup) do
    by_qualified = Map.get(lookup, :by_qualified, %{})
    by_unqualified = Map.get(lookup, :by_unqualified, %{})

    cond do
      String.contains?(name, ".") ->
        Map.get(by_qualified, name) ||
          Map.get(by_qualified, resolve_alias(name, current_module))

      true ->
        Map.get(by_qualified, qualified_name(current_module, name)) ||
          Map.get(by_unqualified, name)
    end
  end

  defp qualified_name(nil, name), do: name
  defp qualified_name("", name), do: name
  defp qualified_name(module, name), do: "#{module}.#{name}"

  defp resolve_alias(target, nil), do: target

  defp resolve_alias(target, module) do
    case String.split(target, ".", parts: 2) do
      [prefix, rest] when prefix == module -> "#{module}.#{rest}"
      _ -> target
    end
  end

  defp pick_unqualified_entry([entry | _]), do: entry

  @spec payload_kind(lookup_input() | nil, String.t(), String.t() | nil) ::
          :none | :single | :multi | :function_like | nil
  def payload_kind(nil, _name, _module), do: nil

  def payload_kind(lookup, name, current_module) when is_binary(name) and is_map(lookup) do
    case resolve(lookup, name, current_module) do
      %{payload_kind: kind} -> kind
      _ -> nil
    end
  end

  @doc """
  True when a constructor's declared payload is a single value but IR supplies
  multiple expressions (parenthesized tuple application), so emit wraps them.
  """
  @spec wrap_flattened_payload?(lookup_input(), String.t(), String.t() | nil, pos_integer()) :: boolean()
  def wrap_flattened_payload?(_lookup, ctor, _module, arg_count)
      when ctor in ["Ok", "Err", "Just"] and arg_count > 1,
      do: true

  def wrap_flattened_payload?(lookup, name, current_module, arg_count) when arg_count > 1 do
    payload_kind(lookup, name, current_module) == :single
  end

  def wrap_flattened_payload?(_lookup, _name, _module, _arg_count), do: false
end
