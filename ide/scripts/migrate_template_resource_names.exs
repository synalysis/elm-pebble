# Migrates project template resource manifests, asset filenames, and Elm references
# to BitmapStatic*, BitmapAnimated*, VectorStatic*, VectorAnimated* naming.
#
# Run from ide/: mix run scripts/migrate_template_resource_names.exs

defmodule Ide.Scripts.MigrateTemplateResourceNames do
  alias Ide.Resources.CtorNaming

  @templates_root Path.expand("../priv/project_templates", __DIR__)

  def run! do
    replacements =
      @templates_root
      |> Path.join("**/bitmaps.json")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.reduce(%{}, &migrate_bitmap_manifest/2)

    replacements =
      @templates_root
      |> Path.join("**/vectors.json")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.reduce(replacements, &migrate_vector_manifest/2)

    replacements =
      @templates_root
      |> Path.join("**/animations.json")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.reduce(replacements, &migrate_animation_manifest/2)

    elm_files =
      @templates_root
      |> Path.join("**/*.{elm,exs,py,md}")
      |> Path.wildcard()
      |> Enum.sort()

    Enum.each(elm_files, fn path ->
      source = File.read!(path)

      updated =
        replacements
        |> Enum.sort_by(fn {old, _new} -> String.length(old) end, :desc)
        |> Enum.reduce(source, fn {old, new}, acc ->
          acc
          |> String.replace("Resources.#{old}", "Resources.#{new}")
          |> String.replace("UiResources.#{old}", "UiResources.#{new}")
        end)

      if updated != source do
        File.write!(path, updated)
        IO.puts("Updated #{Path.relative_to(path, @templates_root)}")
      end
    end)

    IO.puts("Migration complete (#{map_size(replacements)} ctor renames).")
  end

  defp migrate_bitmap_manifest(path, replacements) do
    assets_dir = Path.join(Path.dirname(path), "bitmaps")
    {:ok, manifest} = path |> File.read!() |> Jason.decode()
    {entries, reps} = migrate_entries(manifest["entries"] || [], :bitmap_static, assets_dir, replacements)
    write_manifest(path, Map.put(manifest, "entries", entries))
    reps
  end

  defp migrate_vector_manifest(path, replacements) do
    assets_dir = Path.join(Path.dirname(path), "vectors")
    {:ok, manifest} = path |> File.read!() |> Jason.decode()
    {entries, reps} = migrate_vector_entries(manifest["entries"] || [], assets_dir, replacements)
    write_manifest(path, Map.put(manifest, "entries", entries))
    reps
  end

  defp migrate_animation_manifest(path, replacements) do
    assets_dir = Path.join(Path.dirname(path), "animations")
    {:ok, manifest} = path |> File.read!() |> Jason.decode()
    {entries, reps} = migrate_entries(manifest["entries"] || [], :bitmap_animated, assets_dir, replacements)
    write_manifest(path, Map.put(manifest, "entries", entries))
    reps
  end

  defp migrate_vector_entries(entries, assets_dir, replacements) do
    Enum.map_reduce(entries, replacements, fn row, reps ->
      kind = CtorNaming.vector_kind_from_row(row)
      migrate_row(row, kind, assets_dir, reps)
    end)
  end

  defp migrate_entries(entries, kind, assets_dir, replacements) do
    Enum.map_reduce(entries, replacements, fn row, reps ->
      migrate_row(row, kind, assets_dir, reps)
    end)
  end

  defp migrate_row(row, kind, assets_dir, replacements) do
    old_ctor = Map.get(row, "ctor", "")
    ensured = CtorNaming.ensure_row!(row, kind)
    new_ctor = Map.get(ensured, "ctor", "")

    row =
      if old_ctor != new_ctor and File.exists?(assets_dir) do
        rename_row_assets(assets_dir, row, old_ctor, new_ctor)
        ensured
      else
        ensured
      end

    row =
      row
      |> Map.put("id", resource_id(kind, new_ctor))
      |> Map.update("filename", nil, fn
        filename when is_binary(filename) and filename != "" ->
          String.replace_prefix(filename, old_ctor, new_ctor)

        other ->
          other
      end)
      |> rewrite_variant_filenames(old_ctor, new_ctor)

    reps =
      if old_ctor != "" and new_ctor != "" do
        Map.put(replacements, old_ctor, new_ctor)
      else
        replacements
      end

    {row, reps}
  end

  defp rename_row_assets(assets_dir, row, old_ctor, new_ctor) do
    filenames =
      case Map.get(row, "variants") do
        %{} = variants ->
          variants
          |> Map.values()
          |> Enum.map(&Map.get(&1, "filename", ""))
          |> Enum.filter(&(&1 != ""))

        _ ->
          []
      end

    legacy =
      case Map.get(row, "filename") do
        f when is_binary(f) and f != "" -> [f]
        _ -> []
      end

    Enum.uniq(legacy ++ filenames)
    |> Enum.each(fn filename ->
      old_path = Path.join(assets_dir, filename)

      if File.exists?(old_path) do
        new_filename = String.replace_prefix(filename, old_ctor, new_ctor)
        File.rename!(old_path, Path.join(assets_dir, new_filename))
      end
    end)
  end

  defp rewrite_variant_filenames(row, old_ctor, new_ctor) do
    case Map.get(row, "variants") do
      %{} = variants ->
        updated =
          Map.new(variants, fn {mode, variant} ->
            filename = Map.get(variant, "filename", "")

            new_filename =
              if filename != "" do
                String.replace_prefix(filename, old_ctor, new_ctor)
              else
                filename
              end

            {mode, Map.put(variant, "filename", new_filename)}
          end)

        Map.put(row, "variants", updated)

      _ ->
        row
    end
  end

  defp resource_id(kind, ctor) do
    prefix =
      case kind do
        :bitmap_static -> "bitmap_"
        :bitmap_animated -> "animation_"
        :vector_static -> "vector_"
        :vector_animated -> "vector_"
      end

    prefix <> String.downcase(ctor)
  end

  defp write_manifest(path, manifest) do
    File.write!(path, Jason.encode!(manifest, pretty: true) <> "\n")
    IO.puts("Wrote #{Path.relative_to(path, @templates_root)}")
  end
end

Ide.Scripts.MigrateTemplateResourceNames.run!()
