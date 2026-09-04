defmodule ElmEx.Typesys.GeneratedResources do
  @moduledoc """
  Typesys-only `Pebble.Ui.Resources` overlay from resource manifests.

  Real projects get this module from the IDE resource store. Templates and
  check paths that only have `resources/*.json` still need the generated
  constructors (`BitmapStaticPikachuBack`, …) so typesys matches compile.
  The overlay is not written to disk and is stripped after check so codegen
  does not compile the stub.
  """

  alias ElmEx.Frontend.{GeneratedParser, Project}
  alias ElmEx.Typesys.Type

  @sentinels ~w(NoStaticBitmap NoAnimatedBitmap NoStaticVector NoAnimatedVector DefaultFont)
  @resources "Pebble.Ui.Resources"

  @spec attach(Project.t()) ::
          {Project.t(), MapSet.t(String.t()), [ElmEx.Frontend.Module.t()]}
  def attach(%Project{} = project) do
    extras =
      []
      |> maybe_resources(project)

    names = MapSet.new(extras, & &1.name)

    {kept, replaced} =
      Enum.split_with(project.modules, fn mod -> not MapSet.member?(names, mod.name) end)

    {%{project | modules: kept ++ extras}, names, replaced}
  end

  @spec strip([ElmEx.Frontend.Module.t()], MapSet.t(String.t()), [ElmEx.Frontend.Module.t()]) ::
          [ElmEx.Frontend.Module.t()]
  def strip(modules, names, originals \\ [])

  def strip(modules, names, originals) when is_list(modules) do
    Enum.reject(modules, &MapSet.member?(names, &1.name)) ++ originals
  end

  @doc """
  Install generated resource constructors into the typesys env.

  Template sandboxes often keep the official `Pebble.Ui.Resources` stub on an
  absolute package path. Overlay replacement can miss that tree; these names
  still have to resolve (`Resources.VectorStaticTangramBird`).
  """
  @spec install_env(map(), Project.t()) :: map()
  def install_env(env, %Project{} = project) when is_map(env) do
    case manifest_ctors(project) do
      nil ->
        env

      {vectors, fonts, bitmaps, animations} ->
        {static_vectors, animated_vectors} =
          Enum.split_with(vectors, &(not String.starts_with?(&1, "VectorAnimated")))

        {static_bitmaps, animated_from_bitmaps} =
          Enum.split_with(bitmaps, &(not String.starts_with?(&1, "BitmapAnimated")))

        animated_bitmaps = Enum.uniq(animated_from_bitmaps ++ animations)
        modules = resources_module_names(project)

        env
        |> put_union_ctors(modules, "StaticVector", ["NoStaticVector" | static_vectors])
        |> put_union_ctors(modules, "AnimatedVector", ["NoAnimatedVector" | animated_vectors])
        |> put_union_ctors(modules, "StaticBitmap", ["NoStaticBitmap" | static_bitmaps])
        |> put_union_ctors(modules, "AnimatedBitmap", ["NoAnimatedBitmap" | animated_bitmaps])
        |> put_union_ctors(modules, "Font", ["DefaultFont" | fonts])
    end
  end

  def install_env(env, _), do: env

  defp manifest_ctors(project) do
    root = resources_root(project) || Path.join(to_string(project.project_dir), "resources")
    vectors = ctors_from(Path.join(root, "vectors.json"), "VectorStatic", "VectorAnimated")
    fonts = ctors_from(Path.join(root, "fonts.json"), nil, nil)
    bitmaps = ctors_from(Path.join(root, "bitmaps.json"), "BitmapStatic", "BitmapAnimated")
    animations = ctors_from(Path.join(root, "animations.json"), "BitmapAnimated", "BitmapAnimated")

    if vectors == [] and fonts == [] and bitmaps == [] and animations == [] do
      nil
    else
      {vectors, fonts, bitmaps, animations}
    end
  end

  # Collision mangling keeps every on-disk `Pebble.Ui.Resources` under a
  # `Pkg.*.Pebble.Ui.Resources` name and rewrites app imports to that target.
  # Generated ctors must be visible on those names, not only the canonical one.
  defp resources_module_names(%Project{modules: modules}) do
    from_mods =
      modules
      |> Enum.map(& &1.name)
      |> Enum.filter(&(is_binary(&1) and String.ends_with?(&1, "Pebble.Ui.Resources")))

    Enum.uniq([@resources | from_mods])
  end

  defp put_union_ctors(env, modules, union_short, ctors) do
    Enum.reduce(modules, env, fn module_name, env ->
      scheme = {:forall, [], Type.named(@resources <> "." <> union_short)}

      Enum.reduce(Enum.uniq(ctors), env, fn ctor, env ->
        qualified = "#{module_name}.#{ctor}"
        info = %{name: ctor, union: "#{@resources}.#{union_short}", arity: 0, scheme: scheme}

        env
        |> Map.update!(:values, &Map.put(&1, qualified, scheme))
        |> Map.update!(:constructors, &Map.put(&1, qualified, info))
      end)
    end)
  end

  defp maybe_resources(extras, project) do
    case parse_overlay(project) do
      {:ok, mod} -> extras ++ [mod]
      :skip -> extras
    end
  end

  defp parse_overlay(project) do
    root = resources_root(project) || Path.join(to_string(project.project_dir), "resources")
    vectors = ctors_from(Path.join(root, "vectors.json"), "VectorStatic", "VectorAnimated")
    fonts = ctors_from(Path.join(root, "fonts.json"), nil, nil)
    bitmaps = ctors_from(Path.join(root, "bitmaps.json"), "BitmapStatic", "BitmapAnimated")
    animations = ctors_from(Path.join(root, "animations.json"), "BitmapAnimated", "BitmapAnimated")

    if vectors == [] and fonts == [] and bitmaps == [] and animations == [] do
      :skip
    else
      rel = "src/Pebble/Ui/Resources.elm"
      path = Path.join(project.project_dir, rel)
      source = source(vectors, fonts, bitmaps, animations)

      case GeneratedParser.parse_source(path, source) do
        {:ok, mod} -> {:ok, %{mod | path: path}}
        _ -> :skip
      end
    end
  end

  defp resources_root(%Project{} = project) do
    Enum.find(resources_candidates(project), &manifest_root?/1)
  end

  defp resources_candidates(%Project{project_dir: dir, elm_json: json}) when is_binary(dir) do
    from_src =
      json
      |> Map.get("source-directories", ["src"])
      |> List.wrap()
      |> Enum.filter(&is_binary/1)
      |> Enum.map(fn src ->
        abs =
          if Path.type(src) == :absolute do
            Path.expand(src)
          else
            Path.expand(Path.join(dir, src))
          end

        Path.expand(Path.join(abs, "../resources"))
      end)

    Enum.uniq([Path.join(dir, "resources") | from_src])
  end

  defp resources_candidates(_), do: []

  defp manifest_root?(root) when is_binary(root) do
    Enum.any?(
      ~w(vectors.json fonts.json bitmaps.json animations.json),
      &File.exists?(Path.join(root, &1))
    )
  end

  defp ctors_from(path, static_prefix, animated_prefix) do
    path
    |> read_ctors()
    |> prefix_ctors(static_prefix, animated_prefix)
  end

  defp read_ctors(path) do
    with true <- File.exists?(path),
         {:ok, data} <- File.read(path),
         {:ok, decoded} <- Jason.decode(data) do
      decoded
      |> Map.get("entries", [])
      |> Enum.map(& &1["ctor"])
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.uniq()
    else
      _ -> []
    end
  end

  defp prefix_ctors(ctors, nil, nil), do: ctors

  defp prefix_ctors(ctors, static_prefix, animated_prefix) do
    Enum.map(ctors, fn ctor ->
      cond do
        String.starts_with?(ctor, static_prefix) -> ctor
        String.starts_with?(ctor, animated_prefix) -> ctor
        ctor in @sentinels -> ctor
        true -> static_prefix <> ctor
      end
    end)
  end

  @spec source([String.t()], [String.t()], [String.t()], [String.t()]) :: String.t()
  def source(vectors, fonts, bitmaps, animations) do
    {static_vectors, animated_vectors} =
      Enum.split_with(vectors, &(not String.starts_with?(&1, "VectorAnimated")))

    {static_bitmaps, animated_from_bitmaps} =
      Enum.split_with(bitmaps, &(not String.starts_with?(&1, "BitmapAnimated")))

    animated_bitmaps = Enum.uniq(animated_from_bitmaps ++ animations)

    static_vectors = ["NoStaticVector" | static_vectors] |> Enum.uniq()
    animated_vectors = ["NoAnimatedVector" | animated_vectors] |> Enum.uniq()
    static_bitmaps = ["NoStaticBitmap" | static_bitmaps] |> Enum.uniq()
    animated_bitmaps = ["NoAnimatedBitmap" | animated_bitmaps] |> Enum.uniq()
    fonts = ["DefaultFont" | fonts] |> Enum.uniq()

    """
    module Pebble.Ui.Resources exposing
        ( AnimatedBitmap(..)
        , AnimatedBitmapInfo
        , AnimatedVector(..)
        , AnimatedVectorInfo
        , Font(..)
        , FontInfo
        , StaticBitmap(..)
        , StaticBitmapInfo
        , StaticVector(..)
        , StaticVectorInfo
        , allAnimatedBitmaps
        , allAnimatedVectors
        , allFonts
        , allStaticBitmaps
        , allStaticVectors
        , animatedBitmapInfo
        , animatedVectorInfo
        , fontInfo
        , staticBitmapInfo
        , staticVectorInfo
        )


    #{union_decl("StaticBitmap", static_bitmaps)}

    type alias StaticBitmapInfo =
        { staticBitmap : StaticBitmap
        , name : String
        , width : Int
        , height : Int
        }


    allStaticBitmaps : List StaticBitmap
    allStaticBitmaps =
        #{list_lit(static_bitmaps)}


    staticBitmapInfo : StaticBitmap -> StaticBitmapInfo
    staticBitmapInfo staticBitmap =
        { staticBitmap = staticBitmap, name = "", width = 0, height = 0 }


    #{union_decl("AnimatedBitmap", animated_bitmaps)}

    type alias AnimatedBitmapInfo =
        { animatedBitmap : AnimatedBitmap
        , name : String
        , width : Int
        , height : Int
        , frameCount : Int
        , durationMs : Int
        }


    allAnimatedBitmaps : List AnimatedBitmap
    allAnimatedBitmaps =
        #{list_lit(animated_bitmaps)}


    animatedBitmapInfo : AnimatedBitmap -> AnimatedBitmapInfo
    animatedBitmapInfo animatedBitmap =
        { animatedBitmap = animatedBitmap, name = "", width = 0, height = 0, frameCount = 0, durationMs = 0 }


    #{union_decl("Font", fonts)}

    type alias FontInfo =
        { font : Font
        , name : String
        , height : Int
        }


    allFonts : List Font
    allFonts =
        #{list_lit(fonts)}


    fontInfo : Font -> FontInfo
    fontInfo font =
        { font = font, name = "", height = 0 }


    #{union_decl("StaticVector", static_vectors)}

    type alias StaticVectorInfo =
        { staticVector : StaticVector
        , name : String
        }


    allStaticVectors : List StaticVector
    allStaticVectors =
        #{list_lit(static_vectors)}


    staticVectorInfo : StaticVector -> StaticVectorInfo
    staticVectorInfo staticVector =
        { staticVector = staticVector, name = "" }


    #{union_decl("AnimatedVector", animated_vectors)}

    type alias AnimatedVectorInfo =
        { animatedVector : AnimatedVector
        , name : String
        }


    allAnimatedVectors : List AnimatedVector
    allAnimatedVectors =
        #{list_lit(animated_vectors)}


    animatedVectorInfo : AnimatedVector -> AnimatedVectorInfo
    animatedVectorInfo animatedVector =
        { animatedVector = animatedVector, name = "" }
    """
  end

  defp union_decl(name, ctors) do
    [first | rest] = ctors
    rest_src = Enum.map_join(rest, "\n", fn ctor -> "    | #{ctor}" end)

    """
    type #{name}
        = #{first}
    #{rest_src}
    """
    |> String.trim_trailing()
  end

  defp list_lit(ctors) do
    "[ " <> Enum.join(ctors, ", ") <> " ]"
  end
end
