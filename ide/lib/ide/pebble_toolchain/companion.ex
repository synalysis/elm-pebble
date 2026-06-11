defmodule Ide.PebbleToolchain.Companion do
  @moduledoc false

  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer
  alias Ide.CompanionProtocol.WireSchema
  alias Ide.CompanionProtocolGenerator
  alias Ide.PebblePreferences
  alias Ide.PebbleToolchain.Command
  alias Ide.PebbleToolchain.Types

  @type toolchain_error :: Types.toolchain_error()

  @spec protocol_types_path(String.t(), boolean()) :: String.t() | nil
  def protocol_types_path(workspace_root, has_phone_companion) do
    if has_phone_companion do
      protocol_root_types = Path.join(workspace_root, "protocol/src/Companion/Types.elm")
      watch_root_types = Path.join(workspace_root, "watch/src/Companion/Types.elm")

      cond do
        File.exists?(protocol_root_types) ->
          protocol_root_types

        File.exists?(watch_root_types) ->
          watch_root_types

        true ->
          nil
      end
    end
  end

  @spec protocol_message_keys(String.t() | nil) ::
          {:ok, WireSchema.key_ids()} | {:error, toolchain_error()}
  def protocol_message_keys(nil), do: {:ok, %{}}

  def protocol_message_keys(protocol_elm) do
    case CompanionProtocolGenerator.message_keys(protocol_elm) do
      {:ok, keys} -> {:ok, keys}
      {:error, reason} -> {:error, {:companion_protocol_schema_failed, reason}}
    end
  end

  @spec generate_protocol(String.t() | nil, String.t(), String.t()) ::
          :ok | {:error, toolchain_error()}
  def generate_protocol(nil, _app_root, _compile_project_root), do: :ok

  def generate_protocol(protocol_elm, app_root, compile_project_root) do
    protocol_h = Path.join(app_root, "src/c/generated/companion_protocol.h")
    protocol_c = Path.join(app_root, "src/c/generated/companion_protocol.c")
    protocol_js = Path.join(app_root, "src/pkjs/companion-protocol.js")

    opts = [runtime_tags: protocol_runtime_tags(compile_project_root)]

    case CompanionProtocolGenerator.generate(
           protocol_elm,
           protocol_h,
           protocol_c,
           protocol_js,
           opts
         ) do
      :ok -> :ok
      {:error, reason} -> {:error, {:companion_protocol_generation_failed, reason}}
    end
  end

  @spec generate_protocol_elm_internal(String.t() | nil) ::
          :ok | {:error, toolchain_error()}
  def generate_protocol_elm_internal(nil), do: :ok

  def generate_protocol_elm_internal(protocol_elm) do
    internal_elm = Path.join(Path.dirname(protocol_elm), "Internal.elm")

    case CompanionProtocolGenerator.generate_elm_internal(protocol_elm, internal_elm) do
      :ok -> :ok
      {:error, reason} -> {:error, {:companion_protocol_elm_generation_failed, reason}}
    end
  end

  @spec compile_phone_companion(String.t(), String.t()) :: :ok | {:error, toolchain_error()}
  def compile_phone_companion(workspace_root, app_root) do
    case phone_companion_app_path(workspace_root) do
      nil ->
        :ok

      phone_app ->
        out_file = Path.join(app_root, "src/pkjs/elm-companion.js")

        with {:ok, elm_bin} <- Command.elm_bin(),
             :ok <- File.mkdir_p(Path.dirname(out_file)) do
          phone_root = Path.expand("../..", phone_app)

          {output, exit_code} =
            System.cmd(
              elm_bin,
              ["make", "src/CompanionApp.elm", "--optimize", "--output", out_file],
              cd: phone_root,
              stderr_to_stdout: true,
              env: [{"LC_ALL", "C"}]
            )

          if exit_code == 0 do
            :ok
          else
            {:error,
             {:phone_companion_elm_make_failed,
              %{
                command: "#{elm_bin} make src/CompanionApp.elm --optimize --output #{out_file}",
                output: output,
                exit_code: exit_code,
                cwd: phone_root
              }}}
          end
        end
    end
  end

  @spec extract_phone_preferences(String.t()) ::
          {:ok, PebblePreferences.schema() | nil} | {:error, toolchain_error()}
  def extract_phone_preferences(workspace_root) do
    case phone_companion_project_root(workspace_root) do
      nil -> {:ok, nil}
      phone_root -> PebblePreferences.extract(phone_root)
    end
  end

  @spec write_preferences_config(String.t(), PebblePreferences.schema() | nil) ::
          :ok | {:error, toolchain_error()}
  def write_preferences_config(app_root, preferences_schema) do
    if is_map(preferences_schema) do
      config_path = Path.join(app_root, "src/pkjs/generated/preferences.html")

      with :ok <- File.mkdir_p(Path.dirname(config_path)) do
        File.write(config_path, PebblePreferences.render_html(preferences_schema))
      end
    else
      :ok
    end
  end

  @spec write_generated_preferences_bridge(String.t(), PebblePreferences.schema() | nil) ::
          :ok | {:error, toolchain_error()}
  def write_generated_preferences_bridge(workspace_root, preferences_schema) do
    if is_map(preferences_schema) do
      with phone_root when is_binary(phone_root) <- phone_companion_project_root(workspace_root),
           source when is_binary(source) <-
             PebblePreferences.generated_bridge_source(preferences_schema) do
        path = Path.join(phone_root, PebblePreferences.generated_bridge_rel_path())

        with :ok <- File.mkdir_p(Path.dirname(path)) do
          File.write(path, source)
        end
      else
        nil -> :ok
      end
    else
      :ok
    end
  end

  @spec phone_companion_app_path(String.t()) :: String.t() | nil
  def phone_companion_app_path(workspace_root) do
    path = Path.join([workspace_root, "phone", "src", "CompanionApp.elm"])

    if File.exists?(path) and File.exists?(Path.join(workspace_root, "phone/elm.json")) do
      path
    end
  end

  @spec write_index(String.t(), String.t(), PebblePreferences.schema() | nil) ::
          :ok | {:error, toolchain_error()}
  def write_index(workspace_root, app_root, preferences_schema) do
    case phone_companion_app_path(workspace_root) do
      nil ->
        :ok

      _phone_app ->
        index_path = Path.join(app_root, "src/pkjs/index.js")

        with :ok <- File.mkdir_p(Path.dirname(index_path)),
             {:ok, content} <- companion_index_content(preferences_schema),
             :ok <- File.write(index_path, content) do
          :ok
        end
    end
  end

  @doc false
  def companion_index_js_for_preferences(preferences_schema) do
    case companion_index_content(preferences_schema) do
      {:ok, content} -> content
      {:error, reason} -> raise "companion_index_content failed: #{inspect(reason)}"
    end
  end

  @spec protocol_runtime_tags(String.t()) :: WireSchema.runtime_tags()
  defp protocol_runtime_tags(project_root) when is_binary(project_root) do
    with {:ok, project} <- Bridge.load_project(project_root),
         {:ok, ir} <- Lowerer.lower_project(project) do
      ir.modules
      |> Enum.find(&(&1.name == "Companion.Types"))
      |> case do
        nil ->
          %{}

        mod ->
          mod.unions
          |> Enum.map(fn {type, union} ->
            {type, Map.get(union, :tags, %{})}
          end)
          |> Map.new()
      end
    else
      _ -> %{}
    end
  end

  @spec phone_companion_project_root(String.t()) :: String.t() | nil
  defp phone_companion_project_root(workspace_root) do
    root = Path.join(workspace_root, "phone")

    if File.exists?(Path.join(root, "elm.json")) do
      root
    end
  end

  @spec companion_index_content(PebblePreferences.schema() | nil) ::
          {:ok, String.t()} | {:error, toolchain_error()}
  defp companion_index_content(preferences_schema) do
    with {:ok, template_root} <- Command.template_app_root() do
      template_path = Path.join(template_root, "src/pkjs/index.js")

      case File.read(template_path) do
        {:ok, source} ->
          preferences_url =
            if is_map(preferences_schema) do
              PebblePreferences.data_url(preferences_schema)
            end

          patched =
            String.replace(
              source,
              "var generatedConfigurationUrl = null;",
              "var generatedConfigurationUrl = #{Jason.encode!(preferences_url)};"
            )

          {:ok, patched}

        {:error, reason} ->
          {:error, {:read_companion_index_template_failed, reason}}
      end
    end
  end
end
