defmodule Ide.Debugger.ElmIntrospect.SourceIndex do
  @moduledoc false

  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.Module
  alias Ide.Debugger.ElmIntrospect.Types

  @spec function_type_index(Module.t(), [Types.import_entry()]) :: Types.function_types_index()
  def function_type_index(%Module{} = mod, import_entries) when is_list(import_entries) do
    roots = source_roots_for_module(mod)

    imported =
      import_entries
      |> Enum.map(&Map.get(&1, "module"))
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Enum.reduce(%{}, fn module_name, acc ->
        case parse_imported_module(module_name, roots) do
          {:ok, imported} -> Map.merge(acc, module_function_types(imported, module_name))
          _ -> acc
        end
      end)

    Map.merge(imported, module_function_types(mod, mod.name))
  end

  @spec module_function_types(Module.t(), String.t()) :: Types.function_types_index()
  defp module_function_types(%Module{declarations: declarations}, module_name)
       when is_binary(module_name) and is_list(declarations) do
    declarations
    |> Enum.reduce(%{}, fn decl, acc ->
      case decl do
        %{kind: kind, name: name, type: type}
        when kind in [:function_definition, :function_signature] and is_binary(name) and
               is_binary(type) ->
          args = function_param_names(decl)
          arity = function_arity_from_declaration(args, type)
          key = function_type_key(module_name, name, arity)
          Map.put(acc, key, type)

        _ ->
          acc
      end
    end)
  end

  defp module_function_types(_module, _module_name), do: %{}

  @spec function_type_key(String.t(), String.t(), non_neg_integer()) :: String.t()
  defp function_type_key(module_name, function_name, arity)
       when is_binary(module_name) and is_binary(function_name) and is_integer(arity) do
    module_name <> "|" <> function_name <> "|" <> Integer.to_string(arity)
  end

  @spec function_arity_from_declaration([String.t()], String.t()) :: non_neg_integer()
  defp function_arity_from_declaration(args, type) when is_list(args) and is_binary(type) do
    case args do
      [_ | _] = values -> length(values)
      _ -> arity_from_type_signature(type)
    end
  end

  @spec arity_from_type_signature(String.t()) :: non_neg_integer()
  defp arity_from_type_signature(type) when is_binary(type) do
    type
    |> String.split("->")
    |> length()
    |> Kernel.-(1)
    |> max(0)
  end

  @spec api_metadata(Module.t(), [Types.import_entry()]) :: Types.source_api_metadata()
  def api_metadata(%Module{} = mod, import_entries) when is_list(import_entries) do
    entries = import_entries
    roots = source_roots_for_module(mod)

    modules =
      entries
      |> Enum.map(&Map.get(&1, "module"))
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    function_args =
      modules
      |> Enum.flat_map(fn module_name ->
        case parse_imported_module(module_name, roots) do
          {:ok, imported} -> module_function_args(module_name, imported)
          _ -> []
        end
      end)
      |> Map.new()

    alias_modules =
      entries
      |> Enum.reduce(%{}, fn entry, acc ->
        module_name = Map.get(entry, "module")
        alias_name = Map.get(entry, "as")

        acc
        |> put_module_alias(module_name, module_name)
        |> put_module_alias(alias_name, module_name)
        |> put_module_alias(module_short_name(module_name), module_name)
      end)

    unqualified =
      entries
      |> Enum.reduce(%{}, fn entry, acc ->
        case Map.get(entry, "exposing") do
          names when is_list(names) ->
            Enum.reduce(names, acc, fn name, inner_acc ->
              if is_binary(name),
                do: Map.put(inner_acc, name, Map.get(entry, "module")),
                else: inner_acc
            end)

          _ ->
            acc
        end
      end)

    %{aliases: alias_modules, functions: function_args, unqualified: unqualified}
  end

  @spec source_roots_for_module(Module.t()) :: [String.t()]
  defp source_roots_for_module(%Module{path: path}) when is_binary(path) do
    current_roots =
      path
      |> Path.expand()
      |> Path.dirname()
      |> path_ancestors()

    package_roots =
      [
        Ide.InternalPackages.pebble_elm_src_abs(),
        Ide.InternalPackages.pebble_companion_core_elm_src_abs(),
        Ide.InternalPackages.companion_protocol_elm_src_abs(),
        Ide.InternalPackages.elm_time_elm_src_abs(),
        Ide.InternalPackages.elm_random_elm_src_abs(),
        Ide.InternalPackages.shared_elm_abs()
      ]

    (current_roots ++ package_roots)
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  @spec path_ancestors(String.t()) :: [String.t()]
  defp path_ancestors(path) when is_binary(path) do
    Stream.unfold(Path.expand(path), fn
      "/" -> nil
      current -> {current, Path.dirname(current)}
    end)
    |> Enum.take(12)
  end

  @spec parse_imported_module(String.t(), [String.t()]) :: {:ok, Module.t()} | :error
  defp parse_imported_module(module_name, roots)
       when is_binary(module_name) and is_list(roots) do
    roots
    |> Enum.map(&Path.join(&1, module_file_path(module_name)))
    |> Enum.find(&File.exists?/1)
    |> case do
      nil ->
        :error

      path ->
        case GeneratedParser.parse_file(path) do
          {:ok, %Module{} = mod} -> {:ok, mod}
          _ -> :error
        end
    end
  end

  defp parse_imported_module(_module_name, _roots), do: :error

  @spec module_file_path(String.t()) :: String.t()
  defp module_file_path(module_name) when is_binary(module_name) do
    module_name
    |> String.split(".")
    |> Path.join()
    |> Kernel.<>(".elm")
  end

  @spec module_function_args(String.t(), Module.t()) :: [
          {{String.t(), String.t(), non_neg_integer()}, [String.t()]}
        ]
  defp module_function_args(module_name, %Module{declarations: declarations})
       when is_binary(module_name) and is_list(declarations) do
    declarations
    |> Enum.flat_map(fn
      %{kind: kind, name: name} = declaration
      when kind in [:function_definition, :function_signature] and is_binary(name) ->
        args = function_param_names(declaration)
        if args == [], do: [], else: [{{module_name, name, length(args)}, args}]

      _ ->
        []
    end)
  end

  @spec put_module_alias(%{optional(String.t()) => String.t()}, String.t(), String.t()) ::
          %{optional(String.t()) => String.t()}
  defp put_module_alias(acc, alias_name, module_name)
       when is_map(acc) and is_binary(alias_name) and is_binary(module_name) and alias_name != "" do
    Map.put(acc, alias_name, module_name)
  end

  defp put_module_alias(acc, _alias_name, _module_name) when is_map(acc), do: acc

  @spec module_short_name(String.t()) :: String.t()
  defp module_short_name(module_name) when is_binary(module_name) do
    module_name |> String.split(".") |> List.last()
  end

  @spec function_param_names(Types.ast_declaration() | map()) :: [String.t()]
  defp function_param_names(%{args: args}) when is_list(args), do: args
  defp function_param_names(_), do: []

end
