defmodule Ide.PebblePreferences do
  @moduledoc """
  Extracts typed Elm preference schemas and renders Pebble configuration pages.

  Schema extraction parses companion Elm with `ElmEx.Frontend.GeneratedParser` and
  walks the `Pebble.Companion.Preferences` builder AST. It does not infer behavior
  from labels or application-specific names.
  """

  alias Ide.PebblePreferences.AstExtract

  @generated_bridge_rel_path "src/Companion/GeneratedPreferences.elm"
  @preferences_stamp_name ".elmc-preferences.stamp"

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

  @type choice_option :: %{
          required(:value) => String.t(),
          required(:label) => String.t(),
          optional(:constructor) => String.t() | nil
        }

  @type field_control :: %{
          required(:type) => String.t(),
          optional(:default) => String.t() | integer() | float() | boolean() | nil,
          optional(:min) => number(),
          optional(:max) => number(),
          optional(:step) => number(),
          optional(:options) => [choice_option()],
          optional(:send_to_watch) => String.t()
        }

  @type companion_field_mappings :: %{optional(String.t()) => String.t()}

  @type field :: %{
          required(:id) => String.t(),
          required(:label) => String.t(),
          required(:control) => field_control()
        }

  @type preferences_error ::
          File.posix() | {:parse_failed, term()}

  @doc """
  Extracts a preferences schema from an Elm application root.

  Returns `{:ok, nil}` when the project has no preferences declaration.
  """
  @spec extract(String.t()) :: {:ok, schema() | nil} | {:error, preferences_error()}
  def extract(project_root) when is_binary(project_root) do
    with {:ok, files} <- preference_source_files(project_root) do
      files
      |> sort_schema_candidates()
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
  @spec extract_file(String.t()) :: {:ok, schema() | nil} | {:error, preferences_error()}
  def extract_file(path) when is_binary(path), do: AstExtract.extract_file(path)

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
        var initialValues = null;
        var form = document.getElementById("preferences");
        var sections = {};
        function fieldValue(field, fallback) {
          if (initialValues && Object.prototype.hasOwnProperty.call(initialValues, field.id)) {
            return initialValues[field.id];
          }
          return fallback;
        }
        function queryParam(name) {
          var search = window.location.search || "";
          if (search.charAt(0) === "?") search = search.substring(1);
          if (!search) return null;
          var parts = search.split("&");
          for (var i = 0; i < parts.length; i++) {
            var pair = parts[i];
            var eq = pair.indexOf("=");
            var key = eq >= 0 ? pair.substring(0, eq) : pair;
            if (decodeURIComponent(key.replace(/\\+/g, " ")) === name) {
              return eq >= 0 ? decodeURIComponent(pair.substring(eq + 1).replace(/\\+/g, " ")) : "";
            }
          }
          return null;
        }
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
            input.checked = !!fieldValue(field, control.default);
            label.appendChild(span);
            label.appendChild(input);
          } else {
            var span = document.createElement("span");
            span.textContent = field.label;
            var input = document.createElement(control.type === "choice" ? "select" : "input");
            input.id = field.id;
            if (control.type === "text") input.type = "text";
            if (control.type === "number") {
              input.type = "number";
              input.step = typeof control.step !== "undefined" ? control.step : "any";
            }
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
            var value = fieldValue(field, control.default);
            if (typeof value !== "undefined") input.value = value;
            label.appendChild(span);
            label.appendChild(input);
          }
          host.appendChild(label);
        }
        fields.forEach(addField);
        function closeWithResponse(response) {
          var returnTo = queryParam("return_to");
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
  @spec ensure_generated_bridge(String.t()) :: :ok | {:error, preferences_error()}
  def ensure_generated_bridge(phone_root) when is_binary(phone_root) do
    if preferences_inputs_unchanged?(phone_root) do
      :ok
    else
      phone_root
      |> do_ensure_generated_bridge()
      |> tap(fn
        :ok -> write_preferences_stamp(phone_root)
        {:error, _} -> :ok
      end)
    end
  end

  @spec do_ensure_generated_bridge(String.t()) :: :ok | {:error, preferences_error()}
  defp do_ensure_generated_bridge(phone_root) do
    with {:ok, schema} <- extract(phone_root),
         source when is_binary(source) <- generated_bridge_source(schema) do
      path = Path.join(phone_root, @generated_bridge_rel_path)

      with :ok <- File.mkdir_p(Path.dirname(path)) do
        File.write(path, source)
      end
    else
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
    import Pebble.Companion.Configuration as Configuration
    import Pebble.Companion.Phone as RawBridge
    import Pebble.Companion.Preferences as Preferences


    {-| Subscribe to configuration responses from the Pebble mobile app.

        subscriptions : Model -> Sub Msg
        subscriptions _ =
            GeneratedPreferences.onConfiguration PreferencesSaved

    `PreferencesSaved` receives a `Result String PreferencesSchema.Model`.
    -}
    onConfiguration toMsg =
        Configuration.onClosed <|
            \\maybeResponse ->
                toMsg <|
                    (Preferences.decodeResponse PreferencesSchema.#{value_name} maybeResponse
                        |> Result.mapError preferencesErrorToString)


    {-| Decode a raw bridge event produced when the configuration page closes.

        update msg model =
            case msg of
                FromBridge raw ->
                    case GeneratedPreferences.decodeConfigurationSaved raw of
                        Ok saved ->
                            -- Store or send `saved`.
                            ( { model | settings = saved }, Cmd.none )

                        Err message ->
                            ( { model | error = Just message }, Cmd.none )

    Prefer `onConfiguration` when wiring subscriptions directly.
    -}
    decodeConfigurationSaved value =
        Decode.decodeValue configurationResponseDecoder value
            |> Result.mapError Decode.errorToString
            |> Result.andThen
                (\\response ->
                    Preferences.decodeResponse PreferencesSchema.#{value_name} response
                        |> Result.mapError preferencesErrorToString
                )


    {-| Decode initial companion app flags into previously saved preferences.

        init : Flags -> ( Model, Cmd Msg )
        init flags =
            case GeneratedPreferences.decodeConfigurationFlags flags of
                Ok (Just saved) ->
                    ( { initialModel | settings = saved }, Cmd.none )

                Ok Nothing ->
                    ( initialModel, Cmd.none )

                Err message ->
                    ( { initialModel | error = Just message }, Cmd.none )

    The result is `Nothing` when no saved configuration is available yet.
    -}
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


    {-| Decode the optional `configurationResponse` string from companion flags.

    Most apps should use `decodeConfigurationFlags`, which also applies the
    generated typed preferences schema.
    -}
    configurationFlagsDecoder =
        Decode.field "configurationResponse" (Decode.nullable Decode.string)


    {-| Decode the raw `configuration.closed` bridge event response.

    Most apps should use `decodeConfigurationSaved`, which also converts the
    response into typed preferences.
    -}
    configurationResponseDecoder =
        Decode.field "event" Decode.string
            |> Decode.andThen
                (\\event ->
                    if event == "configuration.closed" then
                        Decode.at [ "payload", "response" ] (Decode.nullable Decode.string)

                    else
                        Decode.fail ("Unexpected bridge event: " ++ event)
                )


    {-| Convert typed preference decode errors into user-facing strings.

        message =
            GeneratedPreferences.preferencesErrorToString error

    This is already used by `decodeConfigurationSaved` and
    `decodeConfigurationFlags`.
    -}
    preferencesErrorToString error =
        case error of
            Preferences.InvalidJson message ->
                message

            Preferences.MissingResponse ->
                "Configuration closed without a response"
    """
  end

  def generated_bridge_source(_schema), do: nil

  @spec preference_source_files(String.t()) :: {:ok, [String.t()]} | {:error, preferences_error()}
  defp preference_source_files(project_root) do
    src = Path.join(project_root, "src")

    if File.dir?(src) do
      {:ok, Path.wildcard(Path.join([src, "**", "*.elm"]))}
    else
      {:ok, []}
    end
  end

  @spec sort_schema_candidates([String.t()]) :: [String.t()]
  defp sort_schema_candidates(files) when is_list(files) do
    Enum.sort_by(files, fn path ->
      base = Path.basename(path)

      cond do
        base == "CompanionPreferences.elm" -> {0, path}
        String.contains?(base, "Preferences") -> {1, path}
        true -> {2, path}
      end
    end)
  end

  @spec preferences_inputs_unchanged?(String.t()) :: boolean()
  defp preferences_inputs_unchanged?(phone_root) do
    stamp_path = Path.join(phone_root, @preferences_stamp_name)

    with {:ok, stamp_mtime} <- file_mtime(stamp_path),
         input_mtime when is_integer(input_mtime) <- preferences_inputs_mtime(phone_root) do
      stamp_mtime >= input_mtime
    else
      _ -> false
    end
  end

  @spec preferences_inputs_mtime(String.t()) :: non_neg_integer() | nil
  defp preferences_inputs_mtime(phone_root) do
    {:ok, files} = preference_source_files(phone_root)
    paths = [Path.join(phone_root, "elm.json") | files]

    paths
    |> Enum.reduce(0, fn path, max_mtime ->
      case file_mtime(path) do
        {:ok, mtime} -> max(max_mtime, mtime)
        _ -> max_mtime
      end
    end)
  end

  @spec write_preferences_stamp(String.t()) :: :ok
  defp write_preferences_stamp(phone_root) do
    stamp_path = Path.join(phone_root, @preferences_stamp_name)
    File.write!(stamp_path, Integer.to_string(preferences_inputs_mtime(phone_root) || 0))
    :ok
  end

  @spec file_mtime(String.t()) :: {:ok, non_neg_integer()} | :error
  defp file_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> {:ok, mtime}
      _ -> :error
    end
  end

  @spec enrich_schema_with_companion_mappings(schema(), [String.t()]) :: schema()
  defp enrich_schema_with_companion_mappings(schema, files)
       when is_map(schema) and is_list(files) do
    mappings =
      files
      |> Enum.flat_map(fn file ->
        case File.read(file) do
          {:ok, source} ->
            if companion_mapping_source?(source) do
              AstExtract.companion_setting_mappings(source, file)
            else
              []
            end

          _ ->
            []
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

  @spec companion_mapping_source?(String.t()) :: boolean()
  defp companion_mapping_source?(source) when is_binary(source) do
    String.contains?(source, "sendSettings")
  end

  @spec enrich_section_fields(section(), companion_field_mappings()) :: section()
  defp enrich_section_fields(section, mappings) when is_map(section) and is_map(mappings) do
    Map.update(section, :fields, [], fn fields ->
      Enum.map(fields, &enrich_field_control(&1, mappings))
    end)
  end

  defp enrich_section_fields(section, _mappings), do: section

  @spec enrich_field_control(field(), companion_field_mappings()) :: field()
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

  @spec escape_html(String.t()) :: String.t()
  defp escape_html(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
