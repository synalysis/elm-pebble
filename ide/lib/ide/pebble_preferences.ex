defmodule Ide.PebblePreferences do
  @moduledoc """
  Extracts typed Elm preference schemas and renders Pebble configuration pages.

  The extractor recognizes the public `Pebble.Companion.Preferences` builder
  contract. It does not infer behavior from labels or application-specific names.
  """

  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer

  @generated_bridge_rel_path "src/Companion/GeneratedPreferences.elm"

  @type schema :: %{
          required(:title) => String.t(),
          required(:sections) => [section()],
          optional(:module) => String.t(),
          optional(:value) => String.t()
        }

  @type section :: %{
          required(:title) => String.t(),
          required(:fields) => [field()]
        }

  @type field :: %{
          required(:id) => String.t(),
          required(:label) => String.t(),
          required(:control) => map()
        }

  @doc """
  Extracts a preferences schema from an Elm application root.

  Returns `{:ok, nil}` when the project has no preferences declaration.
  """
  @spec extract(String.t()) :: {:ok, schema() | nil} | {:error, term()}
  def extract(project_root) when is_binary(project_root) do
    with :ok <- validate_elm_project(project_root),
         {:ok, files} <- preference_source_files(project_root) do
      files
      |> Enum.reduce_while({:ok, nil}, fn file, {:ok, nil} ->
        case extract_file(file) do
          {:ok, nil} -> {:cont, {:ok, nil}}
          {:ok, schema} -> {:halt, {:ok, enrich_schema_with_companion_mappings(schema, files)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  @doc false
  @spec extract_file(String.t()) :: {:ok, schema() | nil} | {:error, term()}
  def extract_file(path) when is_binary(path) do
    with {:ok, source} <- File.read(path) do
      if preference_source?(source) do
        source
        |> parse_source()
        |> case do
          {:ok, %{sections: []}} -> {:error, {:preferences_without_sections, path}}
          {:ok, schema} -> {:ok, schema}
          {:error, reason} -> {:error, {reason, path}}
        end
      else
        {:ok, nil}
      end
    end
  end

  @doc false
  @spec render_html(schema()) :: String.t()
  def render_html(%{title: title, sections: sections}) do
    fields_json =
      sections
      |> Enum.flat_map(fn section ->
        Enum.map(section.fields, &Map.put(&1, :section, section.title))
      end)
      |> Jason.encode!()

    """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{escape_html(title)}</title>
      <style>
        body{margin:0;background:#f2f2f2;color:#222;font:16px -apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif}
        header{background:#ff4700;color:white;padding:18px 16px;font-size:20px;font-weight:600}
        section{margin:16px 0;background:white;border-top:1px solid #ddd;border-bottom:1px solid #ddd}
        h2{margin:0;padding:10px 16px;background:#f7f7f7;color:#666;font-size:13px;text-transform:uppercase;letter-spacing:.04em}
        label{display:block;padding:14px 16px;border-top:1px solid #eee}
        label:first-of-type{border-top:0}
        .row{display:flex;align-items:center;justify-content:space-between;gap:12px}
        input,select{font:inherit}
        input[type=text],input[type=number],select{box-sizing:border-box;width:100%;margin-top:8px;padding:9px;border:1px solid #ccc;border-radius:4px;background:white}
        input[type=color]{width:52px;height:34px;border:1px solid #ccc;background:white}
        .actions{padding:16px}
        button{width:100%;border:0;border-radius:4px;background:#ff4700;color:white;padding:12px 14px;font:inherit;font-weight:600}
      </style>
    </head>
    <body>
      <header>#{escape_html(title)}</header>
      <form id="preferences"></form>
      <div class="actions"><button id="save" type="button">Save</button></div>
      <script>
        var fields = #{fields_json};
        var form = document.getElementById("preferences");
        var sections = {};
        function sectionFor(title) {
          if (sections[title]) return sections[title];
          var node = document.createElement("section");
          var heading = document.createElement("h2");
          heading.textContent = title || "Preferences";
          node.appendChild(heading);
          form.appendChild(node);
          sections[title] = node;
          return node;
        }
        function addField(field) {
          var host = sectionFor(field.section);
          var label = document.createElement("label");
          var control = field.control || {};
          if (control.type === "toggle") {
            label.className = "row";
            var span = document.createElement("span");
            span.textContent = field.label;
            var input = document.createElement("input");
            input.type = "checkbox";
            input.id = field.id;
            input.checked = !!control.default;
            label.appendChild(span);
            label.appendChild(input);
          } else {
            var span = document.createElement("span");
            span.textContent = field.label;
            var input = document.createElement(control.type === "choice" ? "select" : "input");
            input.id = field.id;
            if (control.type === "text") input.type = "text";
            if (control.type === "number") input.type = "number";
            if (control.type === "color") input.type = "color";
            if (control.type === "slider") {
              input.type = "range";
              input.min = control.min;
              input.max = control.max;
              input.step = control.step;
            }
            if (control.type === "choice") {
              (control.options || []).forEach(function(option) {
                var node = document.createElement("option");
                node.value = option.value;
                node.textContent = option.label;
                input.appendChild(node);
              });
            }
            if (typeof control.default !== "undefined") input.value = control.default;
            label.appendChild(span);
            label.appendChild(input);
          }
          host.appendChild(label);
        }
        fields.forEach(addField);
        function closeWithResponse(response) {
          var returnTo = new URLSearchParams(window.location.search).get("return_to");
          if (returnTo) {
            var separator = returnTo.indexOf("?") >= 0 && !returnTo.endsWith("?") && !returnTo.endsWith("&") ? "&" : "";
            document.location = returnTo + separator + "response=" + encodeURIComponent(response);
          } else {
            document.location = "pebblejs://close#" + encodeURIComponent(response);
          }
        }
        document.getElementById("save").addEventListener("click", function() {
          var values = {};
          fields.forEach(function(field) {
            var input = document.getElementById(field.id);
            var control = field.control || {};
            if (control.type === "toggle") values[field.id] = !!input.checked;
            else if (control.type === "number" || control.type === "slider") values[field.id] = Number(input.value);
            else values[field.id] = input.value;
          });
          closeWithResponse(JSON.stringify(values));
        });
      </script>
    </body>
    </html>
    """
  end

  @doc false
  @spec data_url(schema()) :: String.t()
  def data_url(schema) do
    "data:text/html;charset=utf-8," <> URI.encode(render_html(schema), &URI.char_unreserved?/1)
  end

  @doc false
  @spec generated_bridge_rel_path() :: String.t()
  def generated_bridge_rel_path, do: @generated_bridge_rel_path

  @doc false
  @spec ensure_generated_bridge(String.t()) :: :ok | {:error, term()}
  def ensure_generated_bridge(phone_root) when is_binary(phone_root) do
    with {:ok, schema} <- extract(phone_root),
         source when is_binary(source) <- generated_bridge_source(schema) do
      path = Path.join(phone_root, @generated_bridge_rel_path)

      with :ok <- File.mkdir_p(Path.dirname(path)) do
        File.write(path, source)
      end
    else
      {:ok, nil} -> :ok
      nil -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec generated_bridge_source(schema() | nil) :: String.t() | nil
  def generated_bridge_source(nil), do: nil

  def generated_bridge_source(%{module: module_name, value: value_name})
      when is_binary(module_name) and is_binary(value_name) do
    """
    module Companion.GeneratedPreferences exposing
        ( configurationResponseDecoder
        , decodeConfigurationFlags
        , decodeConfigurationSaved
        , onConfiguration
        , preferencesErrorToString
        )

    {-| Generated bridge for Pebble companion preferences.

    This module is derived from the project's `Pebble.Companion.Preferences`
    schema. Edit that schema instead of this file.
    -}

    import #{module_name} as PreferencesSchema
    import Json.Decode as Decode
    import Pebble.Companion.AppMessage as RawBridge
    import Pebble.Companion.Preferences as Preferences


    onConfiguration toMsg =
        RawBridge.onMessage (decodeConfigurationSaved >> toMsg)


    decodeConfigurationSaved value =
        Decode.decodeValue configurationResponseDecoder value
            |> Result.mapError Decode.errorToString
            |> Result.andThen
                (\\response ->
                    Preferences.decodeResponse PreferencesSchema.#{value_name} response
                        |> Result.mapError preferencesErrorToString
                )


    decodeConfigurationFlags value =
        Decode.decodeValue configurationFlagsDecoder value
            |> Result.mapError Decode.errorToString
            |> Result.andThen
                (\\response ->
                    case response of
                        Just saved ->
                            Preferences.decodeResponse PreferencesSchema.#{value_name} (Just saved)
                                |> Result.map Just
                                |> Result.mapError preferencesErrorToString

                        Nothing ->
                            Ok Nothing
                )


    configurationFlagsDecoder =
        Decode.field "configurationResponse" (Decode.nullable Decode.string)


    configurationResponseDecoder =
        Decode.field "event" Decode.string
            |> Decode.andThen
                (\\event ->
                    if event == "configuration.closed" then
                        Decode.at [ "payload", "response" ] (Decode.nullable Decode.string)

                    else
                        Decode.fail ("Unexpected bridge event: " ++ event)
                )


    preferencesErrorToString error =
        case error of
            Preferences.InvalidJson message ->
                message

            Preferences.MissingResponse ->
                "Configuration closed without a response"
    """
  end

  def generated_bridge_source(_schema), do: nil

  @spec validate_elm_project(String.t()) :: :ok | {:error, term()}
  defp validate_elm_project(project_root) do
    case Bridge.load_project(project_root) do
      {:ok, project} ->
        case Lowerer.lower_project(project) do
          {:ok, _ir} -> :ok
          {:error, reason} -> {:error, {:preferences_project_lower_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:preferences_project_load_failed, reason}}
    end
  end

  @spec preference_source_files(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  defp preference_source_files(project_root) do
    src = Path.join(project_root, "src")

    if File.dir?(src) do
      {:ok, Path.wildcard(Path.join([src, "**", "*.elm"]))}
    else
      {:ok, []}
    end
  end

  @spec preference_source?(String.t()) :: boolean()
  defp preference_source?(source) do
    String.contains?(source, "Pebble.Companion.Preferences") and
      String.contains?(source, "Preferences.schema")
  end

  @spec parse_source(String.t()) :: {:ok, schema()} | {:error, term()}
  defp parse_source(source) do
    module_name = module_name(source)
    value_name = schema_value_name(source)

    title =
      case Regex.run(~r/Preferences\.schema\s+"([^"]+)"/, source) do
        [_, value] -> unescape_elm_string(value)
        _ -> "Preferences"
      end

    lines = String.split(source, "\n")

    {sections, _current} =
      lines
      |> Enum.with_index()
      |> Enum.reduce({[], nil}, fn {line, index}, {sections, current_section} ->
        cond do
          section_title = capture(line, ~r/Preferences\.section\s+"([^"]+)"/) ->
            title = unescape_elm_string(section_title)
            {sections ++ [%{title: title, fields: []}], title}

          field_id = capture(line, ~r/Preferences\.field\s+"([^"]+)"/) ->
            field = parse_field(field_id, field_source_window(lines, index))
            {append_field(sections, current_section, field), current_section}

          true ->
            {sections, current_section}
        end
      end)

    {:ok, %{title: title, sections: sections, module: module_name, value: value_name}}
  end

  @spec module_name(String.t()) :: String.t()
  defp module_name(source) do
    case Regex.run(~r/^module\s+([A-Z][A-Za-z0-9_.]*)\s+exposing\b/m, source) do
      [_, name] -> name
      _ -> "CompanionPreferences"
    end
  end

  @spec schema_value_name(String.t()) :: String.t()
  defp schema_value_name(source) do
    case Regex.run(
           ~r/^([a-z][A-Za-z0-9_]*)\s*:\s*Preferences\.Schema\b[\s\S]*?\n\1\s*=\s*\n\s+Preferences\.schema\b/m,
           source
         ) do
      [_, name] ->
        name

      _ ->
        case Regex.run(~r/^([a-z][A-Za-z0-9_]*)\s*=\s*\n\s+Preferences\.schema\b/m, source) do
          [_, name] -> name
          _ -> "settings"
        end
    end
  end

  @spec parse_field(String.t(), String.t()) :: field()
  defp parse_field(id, source) do
    send_to_watch = capture(source, ~r/Preferences\.sendToWatch\s+"([^"]+)"/)

    cond do
      match = Regex.run(~r/Preferences\.toggle\s+"([^"]+)"\s+(True|False)/, source) ->
        [_, label, default] = match

        field(
          id,
          label,
          with_send_to_watch(%{type: "toggle", default: default == "True"}, send_to_watch)
        )

      match = Regex.run(~r/Preferences\.text\s+"([^"]+)"\s+"([^"]*)"/, source) ->
        [_, label, default] = match

        field(
          id,
          label,
          with_send_to_watch(
            %{type: "text", default: unescape_elm_string(default)},
            send_to_watch
          )
        )

      match = Regex.run(~r/Preferences\.number\s+"([^"]+)"\s+(-?\d+(?:\.\d+)?)/, source) ->
        [_, label, default] = match

        field(
          id,
          label,
          with_send_to_watch(%{type: "number", default: parse_float(default)}, send_to_watch)
        )

      match = Regex.run(~r/Preferences\.slider\s+"([^"]+)"/, source) ->
        [_, label] = match

        field(
          id,
          label,
          with_send_to_watch(
            %{
              type: "slider",
              min: source_number(source, "min", 0),
              max: source_number(source, "max", 100),
              step: source_number(source, "step", 1),
              default: source_number(source, "default", 0)
            },
            send_to_watch
          )
        )

      match = Regex.run(~r/Preferences\.color\s+"([^"]+)"\s+([^\s\)]+)/, source) ->
        [_, label, default] = match

        field(
          id,
          label,
          with_send_to_watch(%{type: "color", default: color_value(default)}, send_to_watch)
        )

      match = Regex.run(~r/Preferences\.choice\s+"([^"]+)"/, source) ->
        [_, label] = match

        options =
          ~r/Preferences\.choiceOption\s+[A-Z][A-Za-z0-9_\.]*\s+"([^"]+)"\s+"([^"]+)"/
          |> Regex.scan(source)
          |> Enum.map(fn [full, value, option_label] ->
            %{
              value: unescape_elm_string(value),
              label: unescape_elm_string(option_label),
              constructor: choice_constructor(full)
            }
          end)

        default =
          case List.first(options) do
            nil -> nil
            option -> option.value
          end

        field(
          id,
          label,
          with_send_to_watch(%{type: "choice", default: default, options: options}, send_to_watch)
        )

      true ->
        field(id, id, with_send_to_watch(%{type: "text", default: ""}, send_to_watch))
    end
  end

  @spec with_send_to_watch(map(), String.t() | nil) :: map()
  defp with_send_to_watch(control, constructor)
       when is_binary(constructor) and constructor != "" do
    Map.put(control, :send_to_watch, unescape_elm_string(constructor))
  end

  defp with_send_to_watch(control, _constructor), do: control

  @spec enrich_schema_with_companion_mappings(schema(), [String.t()]) :: schema()
  defp enrich_schema_with_companion_mappings(schema, files)
       when is_map(schema) and is_list(files) do
    mappings =
      files
      |> Enum.flat_map(fn file ->
        case File.read(file) do
          {:ok, source} -> companion_setting_mappings(source)
          _ -> []
        end
      end)
      |> Map.new()

    if map_size(mappings) == 0 do
      schema
    else
      update_in(schema, [:sections], fn sections ->
        Enum.map(sections || [], &enrich_section_fields(&1, mappings))
      end)
    end
  end

  defp enrich_schema_with_companion_mappings(schema, _files), do: schema

  @spec companion_setting_mappings(String.t()) :: [{String.t(), String.t()}]
  defp companion_setting_mappings(source) when is_binary(source) do
    ~r/\b([A-Z][A-Za-z0-9_\.]*)\s+settings\.([a-z][A-Za-z0-9_]*)\b/
    |> Regex.scan(source)
    |> Enum.map(fn [_, constructor, field_id] ->
      {field_id, constructor |> String.split(".") |> List.last()}
    end)
  end

  @spec enrich_section_fields(section(), map()) :: section()
  defp enrich_section_fields(section, mappings) when is_map(section) and is_map(mappings) do
    Map.update(section, :fields, [], fn fields ->
      Enum.map(fields, &enrich_field_control(&1, mappings))
    end)
  end

  defp enrich_section_fields(section, _mappings), do: section

  @spec enrich_field_control(field(), map()) :: field()
  defp enrich_field_control(field, mappings) when is_map(field) and is_map(mappings) do
    id = Map.get(field, :id)
    constructor = if is_binary(id), do: Map.get(mappings, id)
    control = Map.get(field, :control)

    if is_binary(constructor) and is_map(control) and is_nil(Map.get(control, :send_to_watch)) do
      put_in(field, [:control, :send_to_watch], constructor)
    else
      field
    end
  end

  defp enrich_field_control(field, _mappings), do: field

  @spec choice_constructor(String.t()) :: String.t() | nil
  defp choice_constructor(source) do
    case Regex.run(~r/Preferences\.choiceOption\s+([A-Z][A-Za-z0-9_\.]*)/, source) do
      [_, constructor] -> constructor |> String.split(".") |> List.last()
      _ -> nil
    end
  end

  @spec field_source_window([String.t()], non_neg_integer()) :: String.t()
  defp field_source_window(lines, index) do
    lines
    |> Enum.drop(index)
    |> Enum.take(14)
    |> Enum.reduce_while([], fn line, acc ->
      if acc != [] and String.contains?(line, "Preferences.field") do
        {:halt, acc}
      else
        {:cont, [line | acc]}
      end
    end)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @spec field(String.t(), String.t(), map()) :: field()
  defp field(id, label, control) do
    %{id: unescape_elm_string(id), label: unescape_elm_string(label), control: control}
  end

  @spec append_field([section()], String.t() | nil, field()) :: [section()]
  defp append_field([], nil, field), do: [%{title: "", fields: [field]}]
  defp append_field([], title, field), do: [%{title: title || "", fields: [field]}]

  defp append_field(sections, current, field) do
    {last, rest} = List.pop_at(sections, -1)

    cond do
      is_nil(last) ->
        append_field([], current, field)

      last.title == (current || "") ->
        rest ++ [%{last | fields: last.fields ++ [field]}]

      true ->
        sections ++ [%{title: current || "", fields: [field]}]
    end
  end

  @spec capture(String.t(), Regex.t()) :: String.t() | nil
  defp capture(source, regex) do
    case Regex.run(regex, source) do
      [_, value] -> value
      _ -> nil
    end
  end

  @spec source_number(String.t(), String.t(), number()) :: float()
  defp source_number(source, key, default) do
    case Regex.run(~r/#{key}\s*=\s*(-?\d+(?:\.\d+)?)/, source) do
      [_, value] -> parse_float(value)
      _ -> default * 1.0
    end
  end

  @spec parse_float(String.t()) :: float()
  defp parse_float(value) do
    case Float.parse(value) do
      {parsed, _} -> parsed
      :error -> 0.0
    end
  end

  @spec color_value(String.t()) :: String.t()
  defp color_value("\"" <> rest), do: rest |> String.trim_trailing("\"") |> unescape_elm_string()
  defp color_value("Preferences.black"), do: "#000000"
  defp color_value("Preferences.white"), do: "#FFFFFF"
  defp color_value("Preferences.green"), do: "#55AA55"
  defp color_value("Preferences.blue"), do: "#5555FF"
  defp color_value("Preferences.yellow"), do: "#FFFF55"
  defp color_value(_), do: "#000000"

  @spec unescape_elm_string(String.t()) :: String.t()
  defp unescape_elm_string(value) do
    value
    |> String.replace(~S{\"}, ~S{"})
    |> String.replace("\\\\", "\\")
  end

  @spec escape_html(String.t()) :: String.t()
  defp escape_html(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
