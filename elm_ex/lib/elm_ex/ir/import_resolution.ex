defmodule ElmEx.IR.ImportResolution do
  @moduledoc """
  Resolves import aliases and unqualified names to fully qualified `Module.name` strings.

  IR and downstream compilers must only see canonical qualified targets, never
  app-specific import aliases such as `Platform.*` for `Pebble.Platform.*`.
  """

  alias ElmEx.IR.Types.{Expr, Lookup}

  @type lookup :: Lookup.import_resolution_t() | Lookup.rewrite_t()

  @doc """
  Resolves a call or value reference to its fully qualified `Module.name` form.
  """
  @spec resolve(String.t(), lookup()) :: String.t()
  def resolve(target, lookup) when is_binary(target) do
    # Infix operators like `|.` contain a dot but are not module paths.
    if String.starts_with?(target, "|") do
      target
    else
      resolve_module_path(target, lookup)
    end
  end

  defp resolve_module_path(target, lookup) when is_binary(target) do
    alias_map = Map.get(lookup, :alias_map, %{})
    alias_member_map = Map.get(lookup, :alias_member_map, %{})
    import_unqualified_map = Map.get(lookup, :import_unqualified_map, %{})
    local_call_names = Map.get(lookup, :local_call_names, MapSet.new())
    current_module = Map.get(lookup, :current_module)

    case String.split(target, ".", parts: 2) do
      [prefix, rest] ->
        # Only expand import aliases for `Alias.member` calls. Targets like
        # `Companion.Internal.watchToPhoneTag` are already fully qualified module
        # paths and must not treat the first segment as an alias (e.g. `Companion`
        # aliased to `Pebble.Internal.Companion` would otherwise become
        # `Pebble.Internal.Companion.Internal.watchToPhoneTag`).
        if String.contains?(rest, ".") do
          target
        else
          case resolve_aliased_member(prefix, rest, alias_member_map, alias_map, import_unqualified_map) do
            nil -> target
            real_module -> "#{real_module}.#{rest}"
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

  defp resolve_aliased_member(prefix, member, alias_member_map, alias_map, import_unqualified_map)
       when is_binary(prefix) and is_binary(member) do
    case Map.get(alias_member_map, prefix) do
      %{} = members ->
        Map.get(members, member) || resolve_alias_module(prefix, member, alias_map, import_unqualified_map)

      _ ->
        resolve_alias_module(prefix, member, alias_map, import_unqualified_map)
    end
  end

  # When `import Foo exposing (bar)` and `import Other as Foo` coexist, `Foo.bar`
  # must stay on the home module that exposed `bar`, not the conflicting alias.
  # Only apply when the qualifier prefix is that home module (`Foo.bar`); unrelated
  # aliases such as `Tw.p` with bare `import Html exposing (p)` must keep Tailwind.p.
  defp resolve_alias_module(prefix, member, alias_map, import_unqualified_map)
       when is_binary(prefix) and is_binary(member) and is_map(alias_map) and is_map(import_unqualified_map) do
    case {Map.get(import_unqualified_map, member), Map.get(alias_map, prefix)} do
      {home_module, aliased_module}
      when is_binary(home_module) and is_binary(aliased_module) and home_module != aliased_module and
             prefix == home_module ->
        home_module

      {_home_module, aliased_module} when is_binary(aliased_module) ->
        aliased_module

      _ ->
        Map.get(alias_map, prefix)
    end
  end

  @doc """
  When import aliases lower to `field_access` on a module var (e.g. `Color.oxfordBlue`
  as `Color` + `.oxfordBlue`), expand to the canonical qualified target.
  """
  @spec resolve_imported_member(Expr.t(), String.t(), lookup()) :: {:ok, String.t()} | :error
  def resolve_imported_member(%{op: :var, name: prefix}, member, lookup)
      when is_binary(prefix) and is_binary(member) do
    original = "#{prefix}.#{member}"
    resolved = resolve(original, lookup)
    alias_map = Map.get(lookup, :alias_map, %{})

    cond do
      resolved != original and String.contains?(resolved, ".") ->
        {:ok, resolved}

      # `import Theme` / `as Theme` keeps the qualifier string identical, but the
      # prefix is still a module alias — treat `Theme.white` as that binding.
      Map.has_key?(alias_map, prefix) ->
        module = Map.fetch!(alias_map, prefix)
        {:ok, "#{module}.#{member}"}

      true ->
        :error
    end
  end

  def resolve_imported_member(_arg, _member, _lookup), do: :error

  @doc """
  Walks an IR expression tree and rewrites call targets to fully qualified names.
  """
  @spec normalize_expr(Expr.t() | Expr.wire_expr(), lookup()) :: Expr.t()
  def normalize_expr(nil, _lookup), do: nil

  def normalize_expr(%{op: :qualified_call, target: target, args: args} = expr, lookup) do
    %{expr | target: resolve(target, lookup), args: normalize_list(args, lookup)}
  end

  def normalize_expr(%{op: :qualified_call1, target: target} = expr, lookup) do
    %{expr | target: resolve(target, lookup)}
  end

  def normalize_expr(%{op: :qualified_ref, target: target} = expr, lookup) when is_binary(target) do
    %{expr | target: resolve(target, lookup)}
  end

  def normalize_expr(%{op: :qualified_var, target: target} = expr, lookup) when is_binary(target) do
    %{expr | target: resolve(target, lookup)}
  end

  def normalize_expr(%{op: :constructor_call, target: target, args: args} = expr, lookup) do
    %{expr | target: resolve(target, lookup), args: normalize_list(args, lookup)}
  end

  def normalize_expr(%{op: :constructor_ref, target: target} = expr, lookup) when is_binary(target) do
    %{expr | target: resolve(target, lookup)}
  end

  def normalize_expr(%{op: :partial_constructor, target: target, args: args} = expr, lookup)
      when is_binary(target) do
    %{expr | target: resolve(target, lookup), args: normalize_list(args, lookup)}
  end

  def normalize_expr(%{op: :field_access, arg: arg, field: field} = expr, lookup)
      when is_binary(field) do
    rewritten_arg = normalize_expr(arg, lookup)

    case resolve_imported_member(rewritten_arg, field, lookup) do
      {:ok, qualified_target} ->
        %{op: :qualified_call, target: qualified_target, args: []}

      :error ->
        %{expr | arg: rewritten_arg, field: field}
    end
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

  @spec normalize_list([Expr.t() | Expr.wire_expr()] | nil, lookup()) :: [Expr.t()] | nil
  defp normalize_list(nil, _lookup), do: nil

  defp normalize_list(items, lookup) when is_list(items) do
    Enum.map(items, &normalize_expr(&1, lookup))
  end
end
