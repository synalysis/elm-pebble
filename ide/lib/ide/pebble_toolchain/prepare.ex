defmodule Ide.PebbleToolchain.Prepare do
  @moduledoc false

  import Bitwise, only: [&&&: 2, |||: 2]

  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer
  alias Ide.Compiler
  alias Ide.CompanionProtocol.WireSchema
  alias Ide.PebblePreferences
  alias Ide.PebbleToolchain.{Command, Companion, Emulator, Types}
  alias Ide.PebbleToolchain.Elmc, as: ToolchainElmc
  alias Ide.Resources.ResourceStore
  alias Ide.Resources.ResourceStore.Coercion

  @type project_slug :: Types.project_slug()
  @type opts :: Types.opts()
  @type wire_input :: Types.wire_input()
  @type toolchain_error :: Types.toolchain_error()
  @type pebble_package :: Types.pebble_package()
  @type pebble_media_entry :: Types.pebble_media_entry()
  @type core_ir_expr :: Types.core_ir_expr()

  @spec prepare_project_build_app(project_slug(), String.t(), String.t(), String.t(), opts()) ::
          {:ok, String.t(), String.t()} | {:error, toolchain_error()}
  def prepare_project_build_app(project_slug, workspace_root, target_type, project_name, opts) do
    source_roots = Keyword.get(opts, :source_roots)

    with {:ok, template_root} <- Command.template_app_root(),
         {:ok, compile_project_root} <- compile_project_root(workspace_root, source_roots),
         {:ok, app_root} <- ensure_build_app_root(workspace_root),
         :ok <- ResourceStore.ensure_generated_workspace(workspace_root),
         resolved_target_type <- infer_package_target_type(compile_project_root, target_type),
         has_phone_companion <- Companion.phone_companion_app_path(workspace_root) != nil,
         :ok <- copy_pebble_template(template_root, app_root, has_phone_companion),
         :ok <-
           write_emulator_build_flags(
             app_root,
             Keyword.put(opts, :target_type, resolved_target_type)
           ),
         {:ok, media_entries} <- stage_project_resources(workspace_root, app_root),
         {:ok, preferences_schema} <- Companion.extract_phone_preferences(workspace_root),
         protocol_elm <- Companion.protocol_types_path(workspace_root, has_phone_companion),
         {:ok, app_message_keys} <- Companion.protocol_message_keys(protocol_elm),
         :ok <-
           write_package_json(
             app_root,
             project_slug,
             resolved_target_type,
             project_name,
             opts,
             media_entries,
             app_message_keys,
             preferences_schema,
             has_phone_companion
           ),
         :ok <- Companion.generate_protocol_elm_internal(protocol_elm),
         :ok <- ToolchainElmc.generate_sources(compile_project_root, app_root, workspace_root),
         :ok <- Companion.generate_protocol(protocol_elm, app_root, compile_project_root),
         :ok <- ToolchainElmc.reprune_staged_runtime(app_root),
         :ok <- Companion.write_generated_preferences_bridge(workspace_root, preferences_schema),
         :ok <- Companion.write_preferences_config(app_root, preferences_schema),
         :ok <- Companion.compile_phone_companion(workspace_root, app_root),
         :ok <- Companion.write_index(workspace_root, app_root, preferences_schema) do
      {:ok, app_root, resolved_target_type}
    end
  end

  @spec infer_package_target_type(String.t(), String.t()) :: String.t()
  def infer_package_target_type(project_root, fallback) when is_binary(project_root) do
    case main_program_target(project_root) do
      {:ok, target} -> package_target_type_from_main_target(target, fallback)
      _ -> normalize_package_target_type(fallback)
    end
  end

  def infer_package_target_type(_project_root, fallback),
    do: normalize_package_target_type(fallback)

  @spec main_program_target(String.t()) :: {:ok, String.t()} | :error
  defp main_program_target(project_root) do
    with {:ok, project} <- Bridge.load_project(project_root),
         {:ok, ir} <- Lowerer.lower_project(project),
         %{} = main_module <- Enum.find(ir.modules, &(&1.name == "Main")),
         %{} = main_decl <- Enum.find(main_module.declarations, &(&1.name == "main")),
         target when is_binary(target) and target != "" <- expr_target(main_decl.expr) do
      {:ok, target}
    else
      _ -> :error
    end
  end

  @spec expr_target(core_ir_expr()) :: String.t() | nil
  defp expr_target(%{op: :qualified_call, target: target}) when is_binary(target), do: target

  defp expr_target(%{"op" => :qualified_call, "target" => target}) when is_binary(target),
    do: target

  defp expr_target(%{"op" => "qualified_call", "target" => target}) when is_binary(target),
    do: target

  defp expr_target(_), do: nil

  @spec package_target_type_from_main_target(String.t(), String.t()) :: String.t()
  defp package_target_type_from_main_target(target, fallback) when is_binary(target) do
    case target do
      "Pebble.Platform.watchface" -> "watchface"
      "PebblePlatform.watchface" -> "watchface"
      "Pebble.Platform.application" -> "app"
      "PebblePlatform.application" -> "app"
      _ -> normalize_package_target_type(fallback)
    end
  end

  @spec normalize_package_target_type(String.t()) :: String.t()
  defp normalize_package_target_type(value) when value in ["watchface", "watchapp", "app"],
    do: value

  defp normalize_package_target_type(_), do: "app"

  @spec normalize_workspace_root(String.t() | nil) ::
          {:ok, String.t()} | {:error, toolchain_error()}
  def normalize_workspace_root(path) when is_binary(path) and path != "" do
    abs = Path.expand(path)
    if File.dir?(abs), do: {:ok, abs}, else: {:error, {:workspace_root_not_found, abs}}
  end

  def normalize_workspace_root(_), do: {:error, :workspace_root_required}

  @spec compile_project_root(String.t(), [String.t()] | nil) ::
          {:ok, String.t()} | {:error, :compile_project_root_not_found}
  defp compile_project_root(workspace_root, source_roots) do
    case Compiler.resolve_elm_project_dir(workspace_root, source_roots) do
      root when is_binary(root) -> {:ok, root}
      _ -> {:error, :compile_project_root_not_found}
    end
  end

  @spec ensure_build_app_root(String.t()) :: {:ok, String.t()} | {:error, toolchain_error()}
  defp ensure_build_app_root(workspace_root) do
    app_root = Path.join(workspace_root, ".pebble-sdk/app")
    _ = File.rm_rf(app_root)

    case File.mkdir_p(app_root) do
      :ok -> {:ok, app_root}
      {:error, reason} -> {:error, {:build_app_root_failed, reason}}
    end
  end

  @spec copy_pebble_template(String.t(), String.t(), boolean()) ::
          :ok | {:error, toolchain_error()}
  defp copy_pebble_template(template_root, app_root, _has_phone_companion) do
    mappings = [
      {Path.join(template_root, "wscript"), Path.join(app_root, "wscript")},
      {Path.join(template_root, "src/c/pebble_app_template.c"),
       Path.join(app_root, "src/c/pebble_app_template.c")}
    ]

    Enum.reduce_while(mappings, :ok, fn {source, target}, _acc ->
      case copy_file(source, target) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec write_emulator_build_flags(String.t(), opts()) :: :ok
  defp write_emulator_build_flags(app_root, opts) do
    path = Path.join(app_root, "src/c/elmc_emulator_build_flags.h")
    watchface? = Keyword.get(opts, :target_type) == "watchface"

    watchface_define =
      if watchface?, do: "#define ELMC_WATCHFACE_MODE 1\n", else: ""

    storage_log_defines =
      if Keyword.get(opts, :emulator_storage_logs, false) do
        "#define ELMC_PEBBLE_EMULATOR_STORAGE_LOGS 1\n"
      else
        ""
      end

    probe_defines =
      if Keyword.get(opts, :emulator_agent_probes, false) do
        "#define ELMC_AGENT_PROBES 1\n"
      else
        "#define ELMC_AGENT_PROBES 0\n"
      end

    heap_log_defines =
      if Keyword.get(opts, :emulator_heap_log, false) do
        "#define ELMC_PEBBLE_HEAP_LOG 1\n"
      else
        ""
      end

    debug_log_defines =
      if Keyword.get(opts, :emulator_debug_logs, false) do
        "#define ELMC_PEBBLE_DEBUG_LOGS 1\n"
      else
        ""
      end

    content = """
    /* Generated by elm-pebble IDE prepare_project_build_app. */
    #ifndef ELMC_EMULATOR_BUILD_FLAGS_H
    #define ELMC_EMULATOR_BUILD_FLAGS_H
    #{watchface_define}#{storage_log_defines}#{probe_defines}#{heap_log_defines}#{debug_log_defines}#endif
    """

    File.write!(path, content)
    :ok
  end

  @spec write_package_json(
          String.t(),
          project_slug(),
          String.t(),
          String.t(),
          opts(),
          [pebble_media_entry()],
          WireSchema.key_ids(),
          PebblePreferences.schema() | nil,
          boolean()
        ) ::
          :ok | {:error, toolchain_error()}
  defp write_package_json(
         app_root,
         project_slug,
         target_type,
         project_name,
         opts,
         media_entries,
         app_message_keys,
         preferences_schema,
         has_phone_companion
       ) do
    target_platforms = target_platforms_for_target_type(target_type, opts)
    version = package_version(Keyword.get(opts, :version))

    package =
      %{
        "name" => project_slug,
        "author" => "elm-pebble-ide",
        "version" => version,
        "keywords" => ["pebble-app"],
        "private" => true,
        "dependencies" => %{},
        "pebble" => %{
          "displayName" => truncate_display_name(project_name),
          "uuid" => deterministic_uuid(project_slug),
          "sdkVersion" => "3",
          "targetPlatforms" => target_platforms,
          "watchapp" => %{"watchface" => target_type == "watchface"},
          "resources" => %{"media" => media_entries}
        }
      }
      |> maybe_put_package_description(Keyword.get(opts, :description, ""))
      |> maybe_enable_multijs(has_phone_companion)
      |> maybe_put_message_keys(app_message_keys)
      |> maybe_put_capabilities(Keyword.get(opts, :capabilities, []))
      |> maybe_put_configurable_capability(preferences_schema)

    File.write(Path.join(app_root, "package.json"), Jason.encode!(package, pretty: true))
  end

  defp maybe_put_package_description(package, description) when is_binary(description) do
    case String.trim(description) do
      "" -> package
      trimmed -> Map.put(package, "description", trimmed)
    end
  end

  defp maybe_put_package_description(package, _), do: package

  @spec package_has_phone_companion?(String.t()) :: boolean()
  def package_has_phone_companion?(app_root) do
    package_path = Path.join(app_root, "package.json")

    with {:ok, source} <- File.read(package_path),
         {:ok, package} <- Jason.decode(source) do
      get_in(package, ["pebble", "enableMultiJS"]) == true or
        File.exists?(Path.join(app_root, "src/pkjs/index.js"))
    else
      _ -> false
    end
  end

  @spec maybe_enable_multijs(pebble_package(), boolean()) :: pebble_package()
  defp maybe_enable_multijs(package, enabled?) do
    if enabled? do
      put_in(package, ["pebble", "enableMultiJS"], true)
    else
      package
    end
  end

  @spec maybe_put_message_keys(pebble_package(), WireSchema.key_ids()) :: pebble_package()
  defp maybe_put_message_keys(package, app_message_keys) when app_message_keys == %{}, do: package

  defp maybe_put_message_keys(package, app_message_keys) do
    put_in(package, ["pebble", "messageKeys"], app_message_keys)
  end

  @spec maybe_put_capabilities(pebble_package(), [String.t()] | nil) :: pebble_package()
  defp maybe_put_capabilities(package, capabilities) do
    capabilities = normalize_capabilities(capabilities)

    if capabilities == [] do
      package
    else
      put_in(package, ["pebble", "capabilities"], capabilities)
    end
  end

  @spec maybe_put_configurable_capability(pebble_package(), PebblePreferences.schema() | nil) ::
          pebble_package()
  defp maybe_put_configurable_capability(package, nil), do: package

  defp maybe_put_configurable_capability(package, _preferences_schema) do
    update_in(package, ["pebble"], fn pebble ->
      capabilities =
        pebble
        |> Map.get("capabilities", [])
        |> Kernel.++(["configurable"])
        |> Enum.uniq()

      Map.put(pebble, "capabilities", capabilities)
    end)
  end

  @spec normalize_capabilities([String.t()] | nil) :: [String.t()]
  defp normalize_capabilities(value) when is_list(value) do
    allowed = MapSet.new(["location", "configurable", "health"])

    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&MapSet.member?(allowed, &1))
    |> Enum.uniq()
  end

  defp normalize_capabilities(_), do: []

  @spec stage_project_resources(String.t(), String.t()) ::
          {:ok, [pebble_media_entry()]} | {:error, toolchain_error()}
  defp stage_project_resources(workspace_root, app_root) do
    with {:ok, bitmap_entries} <- stage_bitmap_resources(workspace_root, app_root),
         {:ok, font_entries} <- stage_font_resources(workspace_root, app_root),
         {:ok, vector_entries} <- stage_vector_resources(workspace_root, app_root),
         {:ok, animation_entries} <- stage_animation_resources(workspace_root, app_root),
         :ok <-
           write_resource_id_header(
             app_root,
             bitmap_entries,
             font_entries,
             vector_entries,
             animation_entries
           ) do
      {:ok, bitmap_entries ++ font_entries ++ vector_entries ++ animation_entries}
    end
  end

  @spec write_resource_id_header(
          String.t(),
          [pebble_media_entry()],
          [pebble_media_entry()],
          [pebble_media_entry()],
          [pebble_media_entry()]
        ) ::
          :ok | {:error, toolchain_error()}
  defp write_resource_id_header(
         app_root,
         bitmap_entries,
         font_entries,
         vector_entries,
         animation_entries
       ) do
    header_path = Path.join(app_root, "src/c/generated/resource_ids.h")

    bitmap_cases =
      bitmap_entries
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {entry, index} ->
        "    case #{index}: return RESOURCE_ID_#{Map.fetch!(entry, "name")};"
      end)

    font_cases =
      font_entries
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {entry, index} ->
        "    case #{index}: return RESOURCE_ID_#{Map.fetch!(entry, "name")};"
      end)

    font_height_cases =
      font_entries
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {entry, index} ->
        "    case #{index}: return #{Map.get(entry, "height", 0)};"
      end)

    vector_cases =
      vector_entries
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {entry, index} ->
        "    case #{index}: return RESOURCE_ID_#{Map.fetch!(entry, "name")};"
      end)

    animation_cases =
      animation_entries
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {entry, index} ->
        "    case #{index}: return RESOURCE_ID_#{Map.fetch!(entry, "name")};"
      end)

    source = """
    #ifndef ELM_PEBBLE_RESOURCE_IDS_H
    #define ELM_PEBBLE_RESOURCE_IDS_H

    #include <stdint.h>

    #define ELM_PEBBLE_RESOURCE_ID_MISSING UINT32_MAX

    static inline uint32_t elm_pebble_bitmap_resource_id(int64_t bitmap_id) {
      switch (bitmap_id) {
    #{bitmap_cases}
        default: return ELM_PEBBLE_RESOURCE_ID_MISSING;
      }
    }

    static inline uint32_t elm_pebble_font_resource_id(int64_t font_id) {
      switch (font_id) {
    #{font_cases}
        default: return ELM_PEBBLE_RESOURCE_ID_MISSING;
      }
    }

    static inline int64_t elm_pebble_font_resource_height(int64_t font_id) {
      switch (font_id) {
    #{font_height_cases}
        default: return 0;
      }
    }

    static inline uint32_t elm_pebble_vector_resource_id(int64_t vector_id) {
      switch (vector_id) {
    #{vector_cases}
        default: return ELM_PEBBLE_RESOURCE_ID_MISSING;
      }
    }

    static inline uint32_t elm_pebble_animation_resource_id(int64_t animation_id) {
      switch (animation_id) {
    #{animation_cases}
        default: return ELM_PEBBLE_RESOURCE_ID_MISSING;
      }
    }

    #endif
    """

    with :ok <- File.mkdir_p(Path.dirname(header_path)) do
      File.write(header_path, source)
    end
  end

  defp stage_bitmap_entry_rows(row, assets_root, app_root) do
    ctor = to_string(Map.get(row, "ctor", "Bitmap"))
    normalized = Ide.Resources.BitmapVariants.normalize_row(row)
    package_file = Ide.Resources.BitmapVariants.package_media_file(ctor)
    filenames = Ide.Resources.BitmapVariants.filenames_for_row(normalized)

    Enum.each(filenames, fn filename ->
      source_path = Path.join(assets_root, filename)
      target_variant_path = Path.join([app_root, "resources", "bitmaps", filename])

      if filename != "" and File.exists?(source_path) do
        :ok = File.mkdir_p(Path.dirname(target_variant_path))
        :ok = File.cp(source_path, target_variant_path)
      end
    end)

    if filenames != [] do
      [
        %{
          "type" => "bitmap",
          "name" => "BITMAP_" <> macro_name(ctor),
          "file" => package_file
        }
      ]
    else
      []
    end
  end

  @spec stage_bitmap_resources(String.t(), String.t()) ::
          {:ok, [pebble_media_entry()]} | {:error, toolchain_error()}
  defp stage_bitmap_resources(workspace_root, app_root) do
    manifest_path = Path.join(workspace_root, "watch/resources/bitmaps.json")
    assets_root = Path.join(workspace_root, "watch/resources/bitmaps")

    case File.read(manifest_path) do
      {:ok, json} ->
        with {:ok, decoded} <- Jason.decode(json),
             entries when is_list(entries) <- Map.get(decoded, "entries", []) do
          media_entries =
            entries
            |> Enum.filter(&is_map/1)
            |> Enum.sort_by(&to_string(Map.get(&1, "ctor", "")))
            |> Enum.flat_map(&stage_bitmap_entry_rows(&1, assets_root, app_root))
            |> Enum.filter(fn row -> String.trim(to_string(Map.get(row, "file", ""))) != "" end)

          {:ok, media_entries}
        else
          _ -> {:ok, []}
        end

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec stage_font_resources(String.t(), String.t()) ::
          {:ok, [pebble_media_entry()]} | {:error, toolchain_error()}
  defp stage_font_resources(workspace_root, app_root) do
    manifest_path = Path.join(workspace_root, "watch/resources/fonts.json")
    assets_root = Path.join(workspace_root, "watch/resources/fonts")

    case File.read(manifest_path) do
      {:ok, json} ->
        with {:ok, decoded} <- Jason.decode(json),
             entries when is_list(entries) <- Map.get(decoded, "entries", []) do
          sources_by_id =
            decoded
            |> Map.get("sources", [])
            |> Enum.filter(&is_map/1)
            |> Map.new(fn row ->
              {to_string(Map.get(row, "id", "")), row}
            end)

          media_entries =
            entries
            |> Enum.filter(&is_map/1)
            |> Enum.sort_by(&to_string(Map.get(&1, "ctor", "")))
            |> Enum.map(fn row ->
              ctor = to_string(Map.get(row, "ctor", "Font"))
              source = Map.get(sources_by_id, to_string(Map.get(row, "source_id", "")), row)
              filename = to_string(Map.get(source, "filename", Map.get(row, "filename", "")))
              height = row |> Map.get("height", 0) |> Coercion.positive_integer_or_default(24)
              characters = row |> Map.get("characters", "") |> to_string()
              tracking_adjust = row |> Map.get("tracking_adjust", 0) |> Coercion.integer_or_default(0)
              compatibility = row |> Map.get("compatibility", "2.7") |> to_string()
              target_platforms = Coercion.string_list(Map.get(row, "target_platforms", []))
              source_path = Path.join(assets_root, filename)
              package_rel = Path.join("fonts", filename)
              target_rel = Path.join("resources", package_rel)
              target_path = Path.join(app_root, target_rel)

              if filename != "" and File.exists?(source_path) do
                :ok = File.mkdir_p(Path.dirname(target_path))
                :ok = File.cp(source_path, target_path)
              end

              %{
                "type" => "font",
                "name" => "FONT_" <> macro_name(ctor) <> "_#{height}",
                "file" => package_rel,
                "height" => height
              }
              |> maybe_put_nonempty("characterRegex", characters)
              |> maybe_put_nonzero("trackingAdjust", tracking_adjust)
              |> maybe_put_compatibility(compatibility)
              |> maybe_put_nonempty_list("targetPlatforms", target_platforms)
            end)
            |> Enum.filter(fn row -> String.trim(to_string(Map.get(row, "file", ""))) != "" end)

          {:ok, media_entries}
        else
          _ -> {:ok, []}
        end

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec stage_vector_resources(String.t(), String.t()) ::
          {:ok, [pebble_media_entry()]} | {:error, toolchain_error()}
  defp stage_vector_resources(workspace_root, app_root) do
    manifest_path = Path.join(workspace_root, "watch/resources/vectors.json")
    assets_root = Path.join(workspace_root, "watch/resources/vectors")

    case File.read(manifest_path) do
      {:ok, json} ->
        with {:ok, decoded} <- Jason.decode(json),
             entries when is_list(entries) <- Map.get(decoded, "entries", []) do
          media_entries =
            entries
            |> Enum.filter(&is_map/1)
            |> Enum.flat_map(fn row ->
              ctor = to_string(Map.get(row, "ctor", "Vector"))
              filename = to_string(Map.get(row, "filename", ""))
              source_path = Path.join(assets_root, filename)
              package_rel = Path.join("vectors", filename)
              target_rel = Path.join("resources", package_rel)
              target_path = Path.join(app_root, target_rel)

              if filename != "" and File.exists?(source_path) do
                :ok = File.mkdir_p(Path.dirname(target_path))
                :ok = File.cp(source_path, target_path)

                [
                  %{
                    "type" => "raw",
                    "name" => "VECTOR_" <> macro_name(ctor),
                    "file" => package_rel
                  }
                ]
              else
                []
              end
            end)

          {:ok, media_entries}
        else
          _ -> {:ok, []}
        end

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec stage_animation_resources(String.t(), String.t()) ::
          {:ok, [pebble_media_entry()]} | {:error, toolchain_error()}
  defp stage_animation_resources(workspace_root, app_root) do
    manifest_path = Path.join(workspace_root, "watch/resources/animations.json")
    assets_root = Path.join(workspace_root, "watch/resources/animations")

    case File.read(manifest_path) do
      {:ok, json} ->
        with {:ok, decoded} <- Jason.decode(json),
             entries when is_list(entries) <- Map.get(decoded, "entries", []) do
          media_entries =
            entries
            |> Enum.filter(&is_map/1)
            |> Enum.flat_map(fn row ->
              ctor = to_string(Map.get(row, "ctor", "Animation"))
              filename = to_string(Map.get(row, "filename", ""))
              source_path = Path.join(assets_root, filename)
              package_rel = Path.join("animations", filename)
              target_rel = Path.join("resources", package_rel)
              target_path = Path.join(app_root, target_rel)

              if filename != "" and File.exists?(source_path) do
                :ok = File.mkdir_p(Path.dirname(target_path))
                :ok = stage_animation_file(source_path, target_path)

                [
                  %{
                    "type" => "raw",
                    "name" => "ANIMATION_" <> macro_name(ctor),
                    "file" => package_rel
                  }
                ]
              else
                []
              end
            end)

          {:ok, media_entries}
        else
          _ -> {:ok, []}
        end

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stage_animation_file(source_path, target_path) do
    with {:ok, bytes} <- File.read(source_path) do
      bytes
      |> Ide.Resources.ApngPatch.pebble_stage_bytes()
      |> then(&File.write!(target_path, &1))
    end

    :ok
  end

  @spec macro_name(String.t() | atom()) :: String.t()
  defp macro_name(name) do
    name
    |> to_string()
    |> String.replace(~r/[^A-Za-z0-9]/, "_")
    |> String.upcase()
  end

  @spec maybe_put_nonempty(pebble_package(), String.t(), String.t()) :: pebble_package()
  defp maybe_put_nonempty(map, _key, ""), do: map
  defp maybe_put_nonempty(map, key, value), do: Map.put(map, key, value)

  @spec maybe_put_compatibility(pebble_package(), String.t()) :: pebble_package()
  defp maybe_put_compatibility(map, "latest"), do: map
  defp maybe_put_compatibility(map, ""), do: map
  defp maybe_put_compatibility(map, value), do: Map.put(map, "compatibility", value)

  @spec maybe_put_nonzero(pebble_package(), String.t(), integer()) :: pebble_package()
  defp maybe_put_nonzero(map, _key, 0), do: map
  defp maybe_put_nonzero(map, key, value), do: Map.put(map, key, value)

  @spec maybe_put_nonempty_list(pebble_package(), String.t(), [String.t()]) :: pebble_package()
  defp maybe_put_nonempty_list(map, _key, []), do: map
  defp maybe_put_nonempty_list(map, key, value), do: Map.put(map, key, value)

  @spec target_platforms_for_target_type(String.t(), opts()) :: [String.t()]
  defp target_platforms_for_target_type(_target_type, opts) do
    requested = Keyword.get(opts, :target_platforms)

    case requested do
      targets when is_list(targets) ->
        allowed = MapSet.new(Emulator.supported_emulator_targets())

        normalized =
          targets
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.filter(&MapSet.member?(allowed, &1))
          |> Enum.uniq()

        if normalized == [], do: Emulator.supported_emulator_targets(), else: normalized

      _ ->
        Emulator.supported_emulator_targets()
    end
  end

  @spec copy_file(String.t(), String.t()) :: :ok | {:error, toolchain_error()}
  defp copy_file(source, target) do
    with :ok <- File.mkdir_p(Path.dirname(target)),
         :ok <- File.cp(source, target) do
      :ok
    end
  end

  @spec truncate_display_name(String.t()) :: String.t()
  defp truncate_display_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> case do
      "" -> "elm-pebble"
      value -> String.slice(value, 0, 31)
    end
  end

  @spec deterministic_uuid(project_slug()) :: String.t()
  def deterministic_uuid(seed) do
    bytes =
      :crypto.hash(:sha256, seed)
      |> binary_part(0, 16)
      |> :binary.bin_to_list()

    bytes =
      bytes
      |> List.update_at(6, &((&1 &&& 0x0F) ||| 0x40))
      |> List.update_at(8, &((&1 &&& 0x3F) ||| 0x80))

    hex =
      bytes
      |> :binary.list_to_bin()
      |> Base.encode16(case: :lower)

    "#{String.slice(hex, 0, 8)}-#{String.slice(hex, 8, 4)}-#{String.slice(hex, 12, 4)}-#{String.slice(hex, 16, 4)}-#{String.slice(hex, 20, 12)}"
  end

  defp package_version(version) when is_binary(version) do
    case String.trim(version) do
      "" -> "1.0.0"
      trimmed -> trimmed
    end
  end

  defp package_version(_), do: "1.0.0"
end
