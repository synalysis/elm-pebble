defmodule Ide.PebblePreferences.AstExtract do
  @moduledoc false

  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.LetBindings
  alias ElmEx.Frontend.Module
  alias ElmEx.IR.PipeChain
  alias Ide.PebblePreferences

  @preferences_module "Pebble.Companion.Preferences"

  @color_constants %{
    "Pebble.Companion.Preferences.black" => "#000000",
    "Pebble.Companion.Preferences.white" => "#FFFFFF",
    "Pebble.Companion.Preferences.green" => "#55AA55",
    "Pebble.Companion.Preferences.blue" => "#5555FF",
    "Pebble.Companion.Preferences.yellow" => "#FFFF55"
  }

  @type preferences_error :: File.posix() | {:parse_failed, term()}

  @spec extract_file(String.t()) ::
          {:ok, PebblePreferences.schema() | nil} | {:error, preferences_error()}
  def extract_file(path) when is_binary(path) do
    with {:ok, source} <- File.read(path),
         true <- schema_candidate?(source),
         {:ok, mod} <- parse_module(path, source) do
      {:ok, extract_module(mod)}
    else
      false -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec schema_candidate?(String.t()) :: boolean()
  def schema_candidate?(source) when is_binary(source) do
    String.contains?(source, "Preferences.schema") or
      String.contains?(source, ".Schema ")
  end

  @spec extract_module(Module.t()) :: PebblePreferences.schema() | nil
  def extract_module(%Module{} = mod) do
    lookup = build_lookup(mod)

    case find_schema_binding(mod) do
      %{name: value_name, expr: expr} ->
        case interpret_schema_expr(normalize_expr(expr), lookup) do
          {:ok, %{title: title, sections: sections}} ->
            %{
              title: title,
              sections: sections,
              module: mod.name,
              value: value_name
            }

          _ ->
            nil
        end

      nil ->
        nil
    end
  end

  @spec companion_setting_mappings(String.t(), String.t()) :: [{String.t(), String.t()}]
  def companion_setting_mappings(source, path) when is_binary(source) and is_binary(path) do
    with {:ok, mod} <- parse_module(path, source) do
      mod
      |> find_send_settings_definition()
      |> case do
        nil -> []
        %{expr: expr} -> extract_send_settings_mappings(normalize_expr(expr))
      end
    else
      _ -> []
    end
  end

  @spec parse_module(String.t(), String.t()) ::
          {:ok, Module.t()} | {:error, preferences_error()}
  defp parse_module(path, source) do
    case GeneratedParser.parse_source(path, source) do
      {:ok, mod} -> {:ok, mod}
      {:error, reason} -> {:error, {:parse_failed, reason}}
    end
  end

  @spec build_lookup(Module.t()) :: map()
  defp build_lookup(%Module{import_entries: entries, declarations: decls}) do
    alias_name =
      entries
      |> List.wrap()
      |> Enum.find_value("Preferences", fn entry ->
        module = import_module_name(entry)

        if module == @preferences_module do
          case import_as_name(entry) do
            nil -> "Preferences"
            as -> as
          end
        end
      end)

    bindings =
      decls
      |> List.wrap()
      |> Enum.filter(fn decl ->
        Map.get(decl, :kind) == :function_definition and Map.get(decl, :args) == []
      end)
      |> Map.new(fn decl -> {decl.name, normalize_expr(Map.get(decl, :expr))} end)

    %{preferences_alias: alias_name, bindings: bindings}
  end

  @spec import_module_name(map()) :: String.t() | nil
  defp import_module_name(entry) when is_map(entry) do
    Map.get(entry, :module) || Map.get(entry, "module")
  end

  @spec import_as_name(map()) :: String.t() | nil
  defp import_as_name(entry) when is_map(entry) do
    Map.get(entry, :as) || Map.get(entry, "as")
  end

  @spec find_schema_binding(Module.t()) :: map() | nil
  defp find_schema_binding(%Module{declarations: decls} = mod) do
    lookup = build_lookup(mod)

    signatures =
      decls
      |> Enum.filter(fn decl ->
        Map.get(decl, :kind) == :function_signature and schema_signature?(Map.get(decl, :type))
      end)
      |> Map.new(fn decl -> {decl.name, decl} end)

    Enum.find_value(decls, fn decl ->
      with true <- Map.get(decl, :kind) == :function_definition,
           true <- Map.get(decl, :args) == [],
           name when is_binary(name) <- Map.get(decl, :name),
           true <- Map.has_key?(signatures, name) or schema_definition?(decl, lookup) do
        decl
      else
        _ -> nil
      end
    end)
  end

  @spec schema_signature?(String.t() | nil) :: boolean()
  defp schema_signature?(type) when is_binary(type) do
    String.contains?(type, ".Schema ") or String.match?(type, ~r/\.Schema\s*$/)
  end

  defp schema_signature?(_), do: false

  @spec schema_definition?(map(), map()) :: boolean()
  defp schema_definition?(decl, lookup) do
    case decl do
      %{expr: expr} -> expr |> normalize_expr() |> schema_expr?(lookup)
      _ -> false
    end
  end

  @spec schema_expr?(map(), map()) :: boolean()
  defp schema_expr?(%{op: :pipe_chain, base: base, steps: steps}, lookup) when is_list(steps) do
    schema_expr?(base, lookup) or
      Enum.any?(steps, fn step ->
        api_name = call_api_name(normalize_expr(step), lookup)
        api_name in ["schema", "section"]
      end)
  end

  defp schema_expr?(expr, lookup) do
    call_api_name(expr, lookup) == "schema"
  end

  @spec find_send_settings_definition(Module.t()) :: map() | nil
  defp find_send_settings_definition(%Module{declarations: decls}) do
    Enum.find(decls, fn decl ->
      Map.get(decl, :kind) == :function_definition and Map.get(decl, :name) == "sendSettings"
    end)
  end

  @spec extract_send_settings_mappings(map()) :: [{String.t(), String.t()}]
  defp extract_send_settings_mappings(expr) do
    expr
    |> list_items()
    |> Enum.flat_map(&mapping_from_list_item/1)
  end

  @spec list_items(map()) :: [map()]
  defp list_items(%{op: :list_literal, items: items}) when is_list(items), do: items
  defp list_items(_), do: []

  @spec mapping_from_list_item(map()) :: [{String.t(), String.t()}]
  defp mapping_from_list_item(%{op: op, target: target, args: args})
       when op in [:constructor_call, :qualified_call] and is_binary(target) and is_list(args) do
    constructor = target |> String.split(".") |> List.last()

    args
    |> Enum.filter(&settings_field_access?/1)
    |> Enum.flat_map(fn expr ->
      case settings_field_name(expr) do
        nil -> []
        field_id -> [{field_id, constructor}]
      end
    end)
  end

  defp mapping_from_list_item(_), do: []

  @spec settings_field_access?(map()) :: boolean()
  defp settings_field_access?(%{op: :field_access, arg: arg, field: field})
       when is_binary(arg) and is_binary(field),
       do: arg == "settings"

  defp settings_field_access?(_), do: false

  @spec settings_field_name(map()) :: String.t() | nil
  defp settings_field_name(%{op: :field_access, arg: "settings", field: field})
       when is_binary(field),
       do: field

  defp settings_field_name(_), do: nil

  @spec interpret_schema_expr(map(), map()) ::
          {:ok, %{title: String.t(), sections: [PebblePreferences.section()]}} | :error
  def interpret_schema_expr(expr, lookup) do
    expr = normalize_expr(expr)

    case expr do
      %{op: :pipe_chain, base: base, steps: steps} when is_list(steps) ->
        with {:ok, state} <- interpret_schema_call(base, lookup) do
          steps
          |> Enum.reduce({:ok, state}, fn
            step, {:ok, acc} ->
              apply_schema_step(step, acc, lookup)

            _step, :error ->
              :error
          end)
          |> case do
            {:ok, %{title: title, sections: sections}} ->
              {:ok, %{title: title, sections: sections}}

            _ ->
              :error
          end
        end

      expr ->
        with {:ok, %{title: title}} <- interpret_schema_call(expr, lookup) do
          {:ok, %{title: title, sections: []}}
        end
    end
  end

  @spec interpret_schema_call(map(), map()) :: {:ok, map()} | :error
  defp interpret_schema_call(expr, lookup) do
    case call_api(expr, "schema", lookup) do
      [title, _settings] when is_binary(title) ->
        {:ok, %{title: title, sections: []}}

      _ ->
        :error
    end
  end

  @spec apply_schema_step(map(), map(), map()) :: {:ok, map()} | :error
  defp apply_schema_step(step, %{title: _title, sections: sections} = state, lookup) do
    step = normalize_expr(step)

    case call_api(step, "section", lookup) do
      [section_title, lambda] when is_binary(section_title) ->
        with {:ok, fields} <- interpret_section_lambda(lambda, lookup) do
          {:ok, %{state | sections: sections ++ [%{title: section_title, fields: fields}]}}
        end

      _ ->
        :error
    end
  end

  @spec interpret_section_lambda(map(), map()) ::
          {:ok, [PebblePreferences.field()]} | :error
  defp interpret_section_lambda(%{op: :lambda, args: [_param], body: body}, lookup) do
    body
    |> normalize_expr()
    |> extract_section_fields(lookup)
    |> case do
      {:ok, fields} -> {:ok, fields}
      :error -> :error
    end
  end

  defp interpret_section_lambda(_, _), do: :error

  @spec extract_section_fields(map(), map()) :: {:ok, [PebblePreferences.field()]} | :error
  defp extract_section_fields(%{op: :pipe_chain, steps: steps}, lookup) when is_list(steps) do
    Enum.reduce_while(steps, {:ok, []}, fn step, {:ok, acc} ->
      case interpret_field_step(step, lookup) do
        {:ok, field} -> {:cont, {:ok, acc ++ [field]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp extract_section_fields(expr, lookup) do
    case interpret_field_step(expr, lookup) do
      {:ok, field} -> {:ok, [field]}
      :error -> :error
    end
  end

  @spec interpret_field_step(map(), map()) :: {:ok, PebblePreferences.field()} | :error
  defp interpret_field_step(step, lookup) do
    step = normalize_expr(step)

    case call_api(step, "field", lookup) do
      [field_id, control_expr] when is_binary(field_id) ->
        with {:ok, control} <- interpret_control(control_expr, lookup) do
          {:ok, %{id: field_id, label: control.label, control: Map.delete(control, :label)}}
        end

      _ ->
        :error
    end
  end

  @spec interpret_control(map(), map()) :: {:ok, map()} | :error
  defp interpret_control(expr, lookup) do
    expr = normalize_expr(expr)

    case expr do
      %{op: :pipe_chain, base: base, steps: [step | _]} ->
        with {:ok, control} <- interpret_control(base, lookup),
             send_to_watch when is_binary(send_to_watch) <-
               send_to_watch_from_step(step, lookup) do
          {:ok, Map.put(control, :send_to_watch, send_to_watch)}
        else
          _ -> interpret_control(PipeChain.desugar(expr), lookup)
        end

      expr ->
        interpret_control_call(expr, lookup)
    end
  end

  @spec send_to_watch_from_step(map(), map()) :: String.t() | nil
  defp send_to_watch_from_step(step, lookup) do
    case call_api(normalize_expr(step), "sendToWatch", lookup) do
      [constructor] when is_binary(constructor) -> constructor
      _ -> nil
    end
  end

  @spec interpret_control_call(map(), map()) :: {:ok, map()} | :error
  defp interpret_control_call(expr, lookup) do
    cond do
      match = call_api(expr, "toggle", lookup) ->
        [label, default] = match

        with {:ok, bool} <- bool_literal(default) do
          {:ok, %{type: "toggle", label: label, default: bool}}
        end

      match = call_api(expr, "text", lookup) ->
        [label, default] = match
        {:ok, %{type: "text", label: label, default: default}}

      match = call_api(expr, "number", lookup) ->
        [label, default] = match
        {:ok, %{type: "number", label: label, default: numeric_literal(default)}}

      match = call_api(expr, "slider", lookup) ->
        [label, options] = match

        with {:ok, opts} <- record_options(options) do
          {:ok,
           Map.merge(%{type: "slider", label: label}, opts)}
        end

      match = call_api(expr, "color", lookup) ->
        [label, default] = match
        {:ok, %{type: "color", label: label, default: color_literal(default, lookup)}}

      match = call_api(expr, "choice", lookup) ->
        [label, options_expr] = match

        with {:ok, options} <- choice_options(options_expr, lookup) do
          default =
            case List.first(options) do
              nil -> nil
              option -> option.value
            end

          {:ok,
           %{
             type: "choice",
             label: label,
             default: default,
             options: options
           }}
        end

      true ->
        :error
    end
  end

  @spec choice_options(map() | String.t(), map()) :: {:ok, [map()]} | :error
  defp choice_options(%{op: :list_literal, items: items}, lookup) when is_list(items) do
    items
    |> Enum.reduce({:ok, []}, fn
      item, {:ok, acc} ->
        case choice_option(item, lookup) do
          {:ok, option} -> {:ok, acc ++ [option]}
          :error -> :error
        end

      _item, :error ->
        :error
    end)
  end

  defp choice_options(%{op: :var, name: name}, lookup) when is_binary(name) do
    choice_options_from_binding(name, lookup)
  end

  defp choice_options(name, lookup) when is_binary(name) do
    choice_options_from_binding(name, lookup)
  end

  defp choice_options(_, _), do: :error

  @spec choice_options_from_binding(String.t(), map()) :: {:ok, [map()]} | :error
  defp choice_options_from_binding(name, lookup) when is_binary(name) do
    case lookup |> Map.get(:bindings, %{}) |> Map.get(name) do
      nil ->
        :error

      expr ->
        choice_options(normalize_expr(expr), lookup)
    end
  end

  @spec choice_option(map(), map()) :: {:ok, map()} | :error
  defp choice_option(expr, lookup) do
    case call_api(normalize_expr(expr), "choiceOption", lookup) do
      [constructor, value, label] when is_binary(value) and is_binary(label) ->
        {:ok,
         %{
           value: value,
           label: label,
           constructor: constructor_name(constructor)
         }}

      _ ->
        :error
    end
  end

  @spec constructor_name(term()) :: String.t() | nil
  defp constructor_name(target) when is_binary(target),
    do: target |> String.split(".") |> List.last()

  defp constructor_name(_), do: nil

  @spec record_options(map()) :: {:ok, map()} | :error
  defp record_options(%{op: :record_literal, fields: fields}) when is_list(fields) do
    opts =
      Enum.reduce(fields, %{}, fn field, acc ->
        name = field |> Map.get(:name) |> to_string()
        expr = Map.get(field, :expr)

        if name in ["min", "max", "step", "default"] do
          Map.put(acc, name, numeric_literal(expr))
        else
          acc
        end
      end)

    if Map.has_key?(opts, "min") and Map.has_key?(opts, "max") and Map.has_key?(opts, "step") and
         Map.has_key?(opts, "default") do
      {:ok,
       %{
         min: opts["min"],
         max: opts["max"],
         step: opts["step"],
         default: opts["default"]
       }}
    else
      :error
    end
  end

  defp record_options(_), do: :error

  @spec color_literal(term(), map()) :: String.t()
  defp color_literal(expr, lookup) do
    case expr do
      value when is_binary(value) ->
        value

      expr ->
        target = call_target(expr)

        cond do
          is_binary(target) ->
            resolved = resolve_target(target, lookup)
            Map.get(@color_constants, resolved, "#000000")

          true ->
            "#000000"
        end
    end
  end

  @spec bool_literal(term()) :: {:ok, boolean()} | :error
  defp bool_literal(true), do: {:ok, true}
  defp bool_literal(false), do: {:ok, false}

  defp bool_literal(%{op: :constructor_ref, target: target}) when target in ["True", "False"],
    do: {:ok, target == "True"}

  defp bool_literal("True"), do: {:ok, true}
  defp bool_literal("False"), do: {:ok, false}
  defp bool_literal(_), do: :error

  @spec numeric_literal(term()) :: float()
  defp numeric_literal(%{op: :int_literal, value: value}) when is_integer(value), do: value * 1.0

  defp numeric_literal(%{op: :float_literal, value: value}) when is_number(value), do: value * 1.0

  defp numeric_literal(value) when is_integer(value), do: value * 1.0
  defp numeric_literal(value) when is_float(value), do: value
  defp numeric_literal(_), do: 0.0

  @spec call_api(map(), String.t(), map()) :: [term()] | nil
  defp call_api(expr, api_name, lookup) do
    expr = normalize_expr(expr)

    case call_target(expr) do
      target when is_binary(target) ->
        if preferences_api?(target, api_name, lookup) do
          call_args(expr)
        end

      _ ->
        nil
    end
  end

  @spec call_api_name(map(), map()) :: String.t() | nil
  defp call_api_name(expr, lookup) do
    case call_target(expr) do
      target when is_binary(target) ->
        preferences_api_name(target, lookup)

      _ ->
        nil
    end
  end

  @spec call_target(map()) :: String.t() | nil
  defp call_target(%{op: op, target: target})
       when op in [:qualified_call, :qualified_ref, :constructor_call, :constructor_ref] and
              is_binary(target),
       do: target

  defp call_target(%{op: :call, name: name}) when is_binary(name), do: name
  defp call_target(_), do: nil

  @spec call_args(map()) :: [term()]
  defp call_args(%{op: op, args: args})
       when op in [:qualified_call, :call, :constructor_call] and is_list(args) do
    Enum.map(args, &literal_value/1)
  end

  defp call_args(_), do: []

  @spec literal_value(term()) :: term()
  defp literal_value(%{op: :string_literal, value: value}) when is_binary(value), do: value

  defp literal_value(%{op: :int_literal, value: value}) when is_integer(value), do: value

  defp literal_value(%{op: :float_literal, value: value}) when is_number(value), do: value

  defp literal_value(%{op: :constructor_ref, target: target}) when is_binary(target), do: target

  defp literal_value(%{op: :constructor_call, target: target, args: args})
       when is_binary(target) and args in [[], nil],
       do: target

  defp literal_value(%{op: :constructor_call, target: target}) when is_binary(target), do: target

  defp literal_value(%{op: :qualified_ref, target: target}) when is_binary(target), do: target

  defp literal_value(%{op: :var, name: name}) when is_binary(name), do: name

  defp literal_value(%{op: :record_literal} = expr), do: expr
  defp literal_value(%{op: :list_literal} = expr), do: expr
  defp literal_value(%{op: :lambda} = expr), do: expr
  defp literal_value(value), do: value

  @spec preferences_api?(String.t(), String.t(), map()) :: boolean()
  defp preferences_api?(target, api_name, lookup) do
    preferences_api_name(target, lookup) == api_name
  end

  @spec preferences_api_name(String.t(), map()) :: String.t() | nil
  defp preferences_api_name(target, lookup) do
    resolved = resolve_target(target, lookup)

    if String.starts_with?(resolved, @preferences_module <> ".") do
      resolved
      |> String.trim_leading(@preferences_module <> ".")
      |> case do
        "" -> nil
        name -> name
      end
    else
      nil
    end
  end

  @spec resolve_target(String.t(), map()) :: String.t()
  defp resolve_target(target, %{preferences_alias: alias_name}) when is_binary(target) do
    case String.split(target, ".", parts: 2) do
      [^alias_name, rest] -> @preferences_module <> "." <> rest
      ["Pebble", rest] -> "Pebble." <> rest
      _ -> target
    end
  end

  @spec normalize_expr(map()) :: map()
  defp normalize_expr(%{op: :let_bindings} = expr), do: normalize_expr(LetBindings.expand(expr))

  defp normalize_expr(%{} = expr), do: expr
end
