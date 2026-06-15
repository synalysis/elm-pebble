defmodule ElmEx.IR.ImportResolution do
  @moduledoc """
  Resolves import aliases and unqualified names to fully qualified `Module.name` strings.

  IR and downstream compilers must only see canonical qualified targets, never
  app-specific import aliases such as `Platform.*` for `Pebble.Platform.*`.
  """

  @type lookup :: %{
          optional(:alias_map) => %{String.t() => String.t()},
          optional(:import_unqualified_map) => map(),
          optional(:local_call_names) => MapSet.t(String.t()),
          optional(:current_module) => String.t()
        }

  @doc """
  Resolves a call or value reference to its fully qualified `Module.name` form.
  """
  @spec resolve(String.t(), lookup()) :: String.t()
  def resolve(target, lookup) when is_binary(target) do
    alias_map = Map.get(lookup, :alias_map, %{})
    import_unqualified_map = Map.get(lookup, :import_unqualified_map, %{})
    local_call_names = Map.get(lookup, :local_call_names, MapSet.new())
    current_module = Map.get(lookup, :current_module)

    case String.split(target, ".", parts: 2) do
      [prefix, rest] ->
        case Map.get(alias_map, prefix) do
          nil ->
            target

          real_module ->
            # Only expand import aliases for `Alias.member` calls. Targets like
            # `Companion.Internal.watchToPhoneTag` are already fully qualified module
            # paths and must not treat the first segment as an alias (e.g. `Companion`
            # aliased to `Pebble.Internal.Companion` would otherwise become
            # `Pebble.Internal.Companion.Internal.watchToPhoneTag`).
            if String.contains?(rest, ".") do
              target
            else
              "#{real_module}.#{rest}"
            end
        end

      [single] ->
        cond do
          MapSet.member?(local_call_names, single) and is_binary(current_module) ->
            "#{current_module}.#{single}"

          true ->
            case Map.get(import_unqualified_map, single) do
              module when is_binary(module) and module != "" ->
                "#{module}.#{single}"

              :ambiguous ->
                target

              _ ->
                target
            end
        end

      _other ->
        target
    end
  end

  @doc """
  Walks an IR expression tree and rewrites call targets to fully qualified names.
  """
  @spec normalize_expr(term(), lookup()) :: term()
  def normalize_expr(nil, _lookup), do: nil

  def normalize_expr(%{op: :qualified_call, target: target, args: args} = expr, lookup) do
    %{expr | target: resolve(target, lookup), args: normalize_list(args, lookup)}
  end

  def normalize_expr(%{op: :qualified_call1, target: target} = expr, lookup) do
    %{expr | target: resolve(target, lookup)}
  end

  def normalize_expr(%{op: :constructor_call, target: target, args: args} = expr, lookup) do
    %{expr | target: resolve(target, lookup), args: normalize_list(args, lookup)}
  end

  def normalize_expr(%{op: :call, name: name, args: args} = expr, lookup) when is_binary(name) do
    resolved = resolve(name, lookup)

    if String.contains?(resolved, ".") do
      %{op: :qualified_call, target: resolved, args: normalize_list(args, lookup)}
    else
      %{expr | name: resolved, args: normalize_list(args, lookup)}
    end
  end

  def normalize_expr(%{op: :call, args: args} = expr, lookup) do
    %{expr | args: normalize_list(args, lookup)}
  end

  def normalize_expr(%{} = expr, lookup) do
    Enum.into(expr, %{}, fn
      {key, child} when is_map(child) -> {key, normalize_expr(child, lookup)}
      {key, children} when is_list(children) -> {key, normalize_list(children, lookup)}
      {key, other} -> {key, other}
    end)
  end

  def normalize_expr(other, _lookup), do: other

  @spec normalize_list(list() | nil, lookup()) :: list() | nil
  defp normalize_list(nil, _lookup), do: nil

  defp normalize_list(items, lookup) when is_list(items) do
    Enum.map(items, &normalize_expr(&1, lookup))
  end
end
