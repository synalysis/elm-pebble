defmodule ElmExecutor.Runtime.CoreIREvaluator.Index do
  @moduledoc false

  alias ElmEx.CoreIR
  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes

  @spec index_functions(EvalTypes.core_ir() | nil) :: EvalTypes.function_index()
  def index_functions(%CoreIR{} = core_ir),
    do: index_functions(%{modules: core_ir.modules})

  def index_functions(%{modules: modules}) when is_list(modules),
    do: index_functions(%{"modules" => modules})

  def index_functions(%{"modules" => modules}) when is_list(modules) do
    Enum.reduce(modules, %{}, fn mod, acc ->
      module_name = to_string(generic_map_value(mod, "name") || "Main")
      decls = generic_map_value(mod, "declarations") || []

      Enum.reduce(decls, acc, fn decl, a ->
        if to_string(generic_map_value(decl, "kind") || "") == "function" do
          name = to_string(generic_map_value(decl, "name") || "")
          body = generic_map_value(decl, "expr")

          params =
            normalize_params(generic_map_value(decl, "params") || generic_map_value(decl, "args"))

          type = generic_map_value(decl, "type")

          Map.put(a, {module_name, name, length(params)}, %{
            module: module_name,
            name: name,
            params: params,
            body: body,
            type: if(is_binary(type), do: type, else: nil)
          })
        else
          a
        end
      end)
    end)
  end

  def index_functions(_), do: %{}

  @spec index_record_aliases(EvalTypes.core_ir() | nil) :: EvalTypes.record_aliases()
  def index_record_aliases(%{modules: modules}) when is_list(modules),
    do: index_record_aliases(%{"modules" => modules})

  def index_record_aliases(%{"modules" => modules}) when is_list(modules) do
    Enum.reduce(modules, %{}, fn mod, acc ->
      module_name = to_string(generic_map_value(mod, "name") || "Main")
      decls = generic_map_value(mod, "declarations") || []

      Enum.reduce(decls, acc, fn decl, a ->
        kind = to_string(generic_map_value(decl, "kind") || "")
        name = to_string(generic_map_value(decl, "name") || "")
        expr = generic_map_value(decl, "expr") || %{}
        fields = generic_map_value(expr, "fields") || []

        if kind == "type_alias" and record_alias_expr?(expr) and is_list(fields) do
          Map.put(a, {module_name, name}, Enum.map(fields, &to_string/1))
        else
          a
        end
      end)
    end)
  end

  def index_record_aliases(_), do: %{}

  @spec index_record_alias_field_types(EvalTypes.core_ir() | nil) :: EvalTypes.record_alias_field_types()
  def index_record_alias_field_types(%{modules: modules}) when is_list(modules),
    do: index_record_alias_field_types(%{"modules" => modules})

  def index_record_alias_field_types(%{"modules" => modules}) when is_list(modules) do
    Enum.reduce(modules, %{}, fn mod, acc ->
      module_name = to_string(generic_map_value(mod, "name") || "Main")
      decls = generic_map_value(mod, "declarations") || []

      Enum.reduce(decls, acc, fn decl, a ->
        kind = to_string(generic_map_value(decl, "kind") || "")
        name = to_string(generic_map_value(decl, "name") || "")
        expr = generic_map_value(decl, "expr") || %{}
        field_types = generic_map_value(expr, "field_types") || %{}

        if kind == "type_alias" and record_alias_expr?(expr) and is_map(field_types) do
          Map.put(a, {module_name, name}, stringify_map_values(field_types))
        else
          a
        end
      end)
    end)
  end

  def index_record_alias_field_types(_), do: %{}

  @spec index_constructor_tags(EvalTypes.core_ir() | nil) :: EvalTypes.constructor_tags()
  def index_constructor_tags(%{modules: modules}) when is_list(modules),
    do: index_constructor_tags(%{"modules" => modules})

  def index_constructor_tags(%{"modules" => modules}) when is_list(modules) do
    Enum.flat_map(modules, fn mod ->
      module_name = to_string(generic_map_value(mod, "name") || "Main")
      unions = generic_map_value(mod, "unions") || %{}
      update_module? = module_has_update?(mod)

      Enum.flat_map(unions, fn {union_name, union} ->
        tags = generic_map_value(union, "tags") || %{}

        Enum.flat_map(tags, fn {ctor, tag} ->
          if is_integer(tag) do
            payload_specs = generic_map_value(union, "payload_specs") || %{}

            [
              %{
                module: module_name,
                union: to_string(union_name),
                ctor: to_string(ctor),
                tag: tag,
                payload_spec: generic_map_value(payload_specs, ctor),
                update_module?: update_module?
              }
            ]
          else
            []
          end
        end)
      end)
    end)
  end

  def index_constructor_tags(_), do: []

  @spec module_has_update?(map()) :: boolean()
  defp module_has_update?(mod) when is_map(mod) do
    mod
    |> generic_map_value("declarations")
    |> case do
      decls when is_list(decls) ->
        Enum.any?(decls, fn decl ->
          is_map(decl) and to_string(generic_map_value(decl, "kind") || "") == "function" and
            generic_map_value(decl, "name") == "update"
        end)

      _ ->
        false
    end
  end

  @spec record_alias_expr?(EvalTypes.expr()) :: boolean()
  defp record_alias_expr?(expr) when is_map(expr) do
    (expr["op"] || expr[:op]) in [:record_alias, "record_alias"]
  end

  @spec generic_map_value(map(), String.t() | atom()) :: EvalTypes.runtime_value() | nil
  defp generic_map_value(map, key) when is_map(map) and is_binary(key) do
    map = if Map.has_key?(map, :__struct__), do: Map.from_struct(map), else: map

    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(map, fn
          {atom_key, value} when is_atom(atom_key) ->
            if Atom.to_string(atom_key) == key, do: {:ok, value}, else: nil

          _ ->
            nil
        end)
        |> case do
          {:ok, value} -> value
          nil -> nil
        end
    end
  end

  defp generic_map_value(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  @spec stringify_map_values(map()) :: map()
  defp stringify_map_values(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  @spec normalize_params(list() | map() | nil) :: [String.t()]
  defp normalize_params(params) when is_list(params) do
    params
    |> Enum.map(fn p ->
      cond do
        is_binary(p) ->
          p

        is_map(p) ->
          case p["name"] || p[:name] || p["var"] || p[:var] || p["target"] || p[:target] do
            name when is_binary(name) -> name
            _ -> ""
          end

        true ->
          ""
      end
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_params(_), do: []
end
