defmodule Ide.Packages do
  @moduledoc """
  Package browsing and installation service with pluggable providers.

  When `:source` is omitted from options, catalog calls try providers in
  `Application.get_env(:ide, Ide.Packages)[:provider_order]` (by default
  official `package.elm-lang.org`, then mirror) until one succeeds.

  The package catalog index (`/search.json` and `/all-packages`) is cached in
  memory with `Last-Modified` / `ETag` validators so unchanged indexes are not
  re-downloaded (HTTP 304).

  Catalog search (default) hides packages whose latest-version dependency tree
  includes browser/DOM packages (`:watch_forbidden_packages` — see config).
  """

  alias Ide.Packages.ElmJsonEditor
  alias Ide.Packages.ElmSourceDocs
  alias Ide.Packages.GenericProvider
  alias Ide.Packages.WatchCompatibility
  alias Ide.Projects

  @blocked_package_families ~w(elm/browser elm/bytes elm/file elm/html elm/http)

  @type provider_key :: atom()
  @type provider_spec :: %{key: provider_key(), module: module(), opts: keyword()}

  @spec search(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def search(query, opts \\ []) do
    page = parse_positive(opts[:page], 1)
    per_page = parse_positive(opts[:per_page], 25)
    runtime = Keyword.take(opts, [:progress])
    platform_target = Keyword.get(opts, :platform_target, :watch)

    with {:ok, provider, packages} <-
           with_provider(opts, &call_provider(&1, :search, [query], runtime)) do
      packages =
        if Keyword.get(opts, :pebble_watch_catalog, true) and platform_target != :phone do
          WatchCompatibility.filter_entries(packages, provider)
        else
          packages
        end
        |> Enum.map(&attach_compatibility(&1, platform_target))

      total = length(packages)
      page_entries = paginate(packages, page, per_page)

      {:ok,
       %{
         source: Atom.to_string(provider.key),
         query: query,
         page: page,
         per_page: per_page,
         total: total,
         packages: page_entries
       }}
    end
  end

  @spec package_details(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def package_details(package, opts \\ []) do
    with {:ok, provider, details} <-
           with_provider(opts, &call_provider(&1, :package_details, [package])) do
      compatibility = compatibility_for_package(package, platform_target: Keyword.get(opts, :platform_target))

      {:ok,
       details
       |> Map.put(:source, Atom.to_string(provider.key))
       |> Map.put(:compatibility, compatibility)}
    end
  end

  @spec compatibility_for_package(String.t(), keyword()) :: map()
  def compatibility_for_package(package, opts \\ []) when is_binary(package) do
    platform_target = Keyword.get(opts, :platform_target, :watch)

    if platform_target != :phone and package in @blocked_package_families do
      %{
        status: "blocked",
        reason_code: "blocked_runtime_family",
        message: "Package #{package} is currently blocked for Pebble runtime compatibility."
      }
    else
      %{
        status: "supported",
        reason_code: "allowed",
        message: "Package #{package} is currently allowed."
      }
    end
  end

  @spec attach_compatibility(term(), atom()) :: term()
  defp attach_compatibility(entry, platform_target) when is_map(entry) do
    name = Map.get(entry, :name) || Map.get(entry, "name")

    if is_binary(name) and name != "" do
      compatibility = compatibility_for_package(name, platform_target: platform_target)

      entry
      |> Map.put(:compatibility, compatibility)
      |> Map.put("compatibility", compatibility)
    else
      entry
    end
  end

  @spec versions(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def versions(package, opts \\ []) do
    with {:ok, provider, versions} <-
           with_provider(opts, &call_provider(&1, :versions, [package])) do
      {:ok, %{source: Atom.to_string(provider.key), package: package, versions: versions}}
    end
  end

  @spec readme(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def readme(package, version \\ "latest", opts \\ []) do
    with {:ok, provider, readme} <-
           with_provider(opts, &call_provider(&1, :readme, [package, version])) do
      {:ok,
       %{
         source: Atom.to_string(provider.key),
         package: package,
         version: version,
         readme: readme
       }}
    end
  end

  @doc """
  Loads API documentation for a single exposed module from the package registry (`docs.json`).
  """
  @spec module_doc_markdown(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def module_doc_markdown(package, version, module_name, opts \\ []) do
    case builtin_module_doc_markdown(package, module_name) do
      {:ok, markdown} ->
        {:ok, markdown}

      _ ->
        version = doc_registry_version(version)
        fetch_opts = Keyword.take(opts, [:source])

        case with_provider(fetch_opts, fn provider ->
               http_opts = merge_catalog_http_opts(provider)
               GenericProvider.module_doc_markdown(package, version, module_name, http_opts)
             end) do
          {:ok, _provider, markdown} -> {:ok, markdown}
          {:error, _} = err -> err
        end
    end
  end

  @spec builtin_module_doc_markdown(term(), term()) :: term()
  defp builtin_module_doc_markdown(package, module_name) do
    with {:ok, source_root} <- builtin_docs_source_root(package),
         {:ok, markdown} <- ElmSourceDocs.module_doc_markdown(source_root, module_name),
         true <- String.trim(markdown) != "" do
      {:ok, markdown}
    else
      _ -> {:error, :builtin_module_docs_not_available}
    end
  end

  @spec builtin_docs_source_root(term()) :: term()
  defp builtin_docs_source_root("elm-pebble/elm-watch"),
    do: {:ok, Ide.InternalPackages.pebble_elm_src_abs()}

  defp builtin_docs_source_root("elm-pebble/companion-core"),
    do: {:ok, Ide.InternalPackages.pebble_companion_core_elm_src_abs()}

  defp builtin_docs_source_root("elm-pebble/companion-preferences"),
    do: {:ok, Ide.InternalPackages.pebble_companion_preferences_elm_src_abs()}

  defp builtin_docs_source_root("elm-pebble/companion-protocol"),
    do: {:ok, Ide.InternalPackages.companion_protocol_elm_src_abs()}

  defp builtin_docs_source_root("elm-pebble/companion-internal"),
    do: {:ok, Ide.InternalPackages.shared_elm_companion_abs()}

  defp builtin_docs_source_root("elm/time"),
    do: {:ok, Ide.InternalPackages.elm_time_elm_src_abs()}

  defp builtin_docs_source_root("elm/random"),
    do: {:ok, Ide.InternalPackages.elm_random_elm_src_abs()}

  defp builtin_docs_source_root(_), do: {:error, :not_builtin_source_backed}

  @spec doc_registry_version(term()) :: term()
  defp doc_registry_version(v) when v in [nil, ""], do: "latest"
  defp doc_registry_version(v), do: to_string(v)

  @spec merge_catalog_http_opts(term()) :: term()
  defp merge_catalog_http_opts(provider) do
    defaults =
      case provider.key do
        :mirror -> [base_url: "https://dark.elm.dmy.fr", cache_ttl_ms: 120_000]
        _ -> [base_url: "https://package.elm-lang.org", cache_ttl_ms: 120_000]
      end

    Keyword.merge(defaults, provider.opts)
  end

  @spec preview_add_to_project(map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def preview_add_to_project(project, package, opts \\ []) when is_map(project) do
    with {:ok, provider, _details} <-
           with_provider(opts, &call_provider(&1, :package_details, [package])),
         editor_opts <- resolver_editor_opts(provider, opts),
         {:ok, preview} <- ElmJsonEditor.preview_add(project, package, editor_opts) do
      {:ok, preview}
    end
  end

  @spec add_to_project(map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def add_to_project(project, package, opts \\ []) when is_map(project) do
    with {:ok, provider, _details} <-
           with_provider(opts, &call_provider(&1, :package_details, [package])),
         editor_opts <- resolver_editor_opts(provider, opts),
         {:ok, result} <- ElmJsonEditor.add_package(project, package, editor_opts) do
      {:ok, result}
    end
  end

  @doc """
  Elm packages the IDE treats as part of the platform: a watch app cannot run without them,
  so they must not be removed from `elm.json`.

  Includes the Pebble bindings packages and core runtime dependencies
  (`elm/core`, `elm/json`, `elm/random`, `elm/time`).
  """
  @spec pebble_builtin_packages() :: [String.t()]
  def pebble_builtin_packages do
    [
      "elm-pebble/elm-watch",
      "elm-pebble/companion-core",
      "elm-pebble/companion-preferences",
      "elm/core",
      "elm/json",
      "elm/random",
      "elm/time"
    ]
  end

  @spec pebble_builtin_package?(String.t()) :: boolean()
  def pebble_builtin_package?(name) when is_binary(name), do: name in pebble_builtin_packages()

  @spec remove_from_project(map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def remove_from_project(project, package, opts \\ []) when is_map(project) do
    if pebble_builtin_package?(package) do
      {:error, :builtin_package_not_removable}
    else
      with {:ok, provider, _details} <-
             with_provider(opts, &call_provider(&1, :package_details, [package])),
           editor_opts <- resolver_editor_opts(provider, opts),
           {:ok, result} <- ElmJsonEditor.remove_package(project, package, editor_opts) do
        {:ok, result}
      end
    end
  end

  @doc """
  Maps exposed module names (e.g. `\"Json.Encode\"`) to package names for documentation links.
  """
  @spec build_doc_module_index(map(), keyword()) :: {:ok, %{optional(String.t()) => String.t()}}
  def build_doc_module_index(project, opts \\ []) when is_map(project) do
    source_root =
      Keyword.get(opts, :source_root) || ElmJsonEditor.candidate_roots(project) |> List.first()

    pkg_opts = Keyword.take(opts, [:source])

    with {:ok, content} <- Projects.read_source_file(project, source_root, "elm.json"),
         {:ok, decoded} <- Jason.decode(content),
         true <- is_map(decoded) do
      deps_section = Map.get(decoded, "dependencies", %{})
      direct = deps_section |> Map.get("direct", %{}) |> Map.keys()
      indirect = deps_section |> Map.get("indirect", %{}) |> Map.keys()
      deps = (direct ++ indirect) |> Enum.uniq()

      index =
        Enum.reduce(deps, %{}, fn pkg, acc ->
          details =
            case package_details(pkg, pkg_opts) do
              {:ok, d} -> d
              _ -> nil
            end

          exposed = exposed_modules_for_package(pkg, pkg_opts, details)

          Enum.reduce(exposed, acc, fn mod, a ->
            if is_binary(mod) and mod != "", do: Map.put(a, mod, pkg), else: a
          end)
        end)

      {:ok, merge_builtin_module_mappings(index, pkg_opts, opts)}
    else
      _ -> {:ok, merge_builtin_module_mappings(%{}, pkg_opts, opts)}
    end
  end

  @doc """
  Packages and versions to populate editor documentation dropdowns (platform packages + elm.json deps).
  """
  @spec list_doc_package_rows(map(), keyword()) :: {:ok, [map()]}
  def list_doc_package_rows(project, opts \\ []) when is_map(project) do
    source_root =
      Keyword.get(opts, :source_root) || ElmJsonEditor.candidate_roots(project) |> List.first()

    pkg_opts = Keyword.take(opts, [:source])
    builtin_pkgs = builtin_doc_packages(opts)

    builtin_rows =
      builtin_pkgs
      |> Enum.sort()
      |> Enum.map(fn pkg ->
        case package_details(pkg, pkg_opts) do
          {:ok, d} ->
            v = d[:latest_version] || List.first(d[:versions] || []) || "latest"
            mods = exposed_modules_for_package(pkg, pkg_opts, d)

            %{
              package: pkg,
              version: to_string(v),
              modules: mods,
              builtin?: true,
              label: doc_catalog_builtin_label(pkg)
            }

          _ ->
            %{
              package: pkg,
              version: "latest",
              modules: exposed_modules_for_package(pkg, pkg_opts, nil),
              builtin?: true,
              label: doc_catalog_builtin_label(pkg)
            }
        end
      end)

    project_rows =
      case Projects.read_source_file(project, source_root, "elm.json") do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, %{"dependencies" => %{"direct" => d, "indirect" => i}}}
            when is_map(d) and is_map(i) ->
              pkgs =
                (Map.keys(d) ++ Map.keys(i))
                |> Enum.uniq()
                |> Enum.reject(&(&1 in builtin_pkgs))
                |> Enum.sort()

              Enum.map(pkgs, fn pkg ->
                ver = (Map.get(d, pkg) || Map.get(i, pkg) || "") |> to_string()

                {mods, label} =
                  case package_details(pkg, pkg_opts) do
                    {:ok, d} ->
                      m = exposed_modules_for_package(pkg, pkg_opts, d)
                      {m, "#{pkg} (#{ver})"}

                    _ ->
                      {exposed_modules_for_package(pkg, pkg_opts, nil), "#{pkg} (#{ver})"}
                  end

                %{package: pkg, version: ver, modules: mods, builtin?: false, label: label}
              end)

            _ ->
              []
          end

        _ ->
          []
      end

    {:ok, builtin_rows ++ project_rows}
  end

  @spec doc_catalog_builtin_label(term()) :: term()
  defp doc_catalog_builtin_label("elm/core"), do: "elm/core (required runtime)"
  defp doc_catalog_builtin_label("elm/json"), do: "elm/json (required program flags runtime)"
  defp doc_catalog_builtin_label("elm/random"), do: "elm/random (required random runtime)"
  defp doc_catalog_builtin_label("elm/time"), do: "elm/time (required time runtime)"

  defp doc_catalog_builtin_label("elm-pebble/elm-watch"),
    do: "elm-pebble/elm-watch (Pebble watch runtime)"

  defp doc_catalog_builtin_label("elm-pebble/companion-core"),
    do: "elm-pebble/companion-core (Pebble companion bridge contracts)"

  defp doc_catalog_builtin_label("elm-pebble/companion-preferences"),
    do: "elm-pebble/companion-preferences (typed companion configuration UI)"

  defp doc_catalog_builtin_label("elm-pebble/companion-protocol"),
    do: "elm-pebble/companion-protocol (typed watch/phone protocol bridge)"

  defp doc_catalog_builtin_label("elm-pebble/companion-internal"),
    do: "elm-pebble/companion-internal (source-backed companion modules)"

  defp doc_catalog_builtin_label(pkg) when is_binary(pkg), do: "#{pkg} (platform)"

  @spec builtin_doc_packages(term()) :: term()
  defp builtin_doc_packages(opts) do
    case opts[:platform_target] do
      :watch ->
        ["elm-pebble/elm-watch", "elm/core", "elm/json", "elm/random", "elm/time"]

      :phone ->
        [
          "elm-pebble/companion-core",
          "elm-pebble/companion-preferences",
          "elm-pebble/companion-protocol",
          "elm-pebble/companion-internal",
          "elm/core",
          "elm/json",
          "elm/random",
          "elm/time"
        ]

      :all ->
        pebble_builtin_packages()

      :none ->
        ["elm/core", "elm/json", "elm/random", "elm/time"]

      _ ->
        if Keyword.get(opts, :include_pebble_platform, true),
          do: ["elm-pebble/elm-watch", "elm/core", "elm/json", "elm/random", "elm/time"],
          else: ["elm/core", "elm/json", "elm/random", "elm/time"]
    end
  end

  @spec merge_builtin_module_mappings(term(), term(), term()) :: term()
  defp merge_builtin_module_mappings(index, pkg_opts, opts) when is_map(index) do
    builtin_pkgs = builtin_doc_packages(opts)

    Enum.reduce(builtin_pkgs, index, fn pkg, acc ->
      details =
        case package_details(pkg, pkg_opts) do
          {:ok, d} -> d
          _ -> nil
        end

      exposed = exposed_modules_for_package(pkg, pkg_opts, details)

      Enum.reduce(exposed, acc, fn mod, a ->
        if is_binary(mod) and mod != "" and not Map.has_key?(a, mod),
          do: Map.put(a, mod, pkg),
          else: a
      end)
    end)
  end

  @spec exposed_modules_for_package(term(), term(), term()) :: term()
  defp exposed_modules_for_package(pkg, _pkg_opts, details) do
    fallback = fallback_builtin_source_modules(pkg)

    from_details =
      details
      |> case do
        nil -> []
        d -> d[:exposed_modules] || []
      end
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.sort()

    (fallback ++ from_details)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec fallback_builtin_source_modules(term()) :: term()
  defp fallback_builtin_source_modules("elm-pebble/elm-watch") do
    case ElmSourceDocs.list_modules(Ide.InternalPackages.pebble_elm_src_abs()) do
      {:ok, modules} -> modules
      _ -> []
    end
  end

  defp fallback_builtin_source_modules("elm-pebble/companion-core") do
    case exposed_modules_from_source_root(
           Ide.InternalPackages.pebble_companion_core_elm_src_abs()
         ) do
      {:ok, modules} -> modules
      _ -> []
    end
  end

  defp fallback_builtin_source_modules("elm-pebble/companion-preferences") do
    case exposed_modules_from_source_root(
           Ide.InternalPackages.pebble_companion_preferences_elm_src_abs()
         ) do
      {:ok, modules} -> modules
      _ -> []
    end
  end

  defp fallback_builtin_source_modules("elm-pebble/companion-protocol") do
    case ElmSourceDocs.list_modules(Ide.InternalPackages.companion_protocol_elm_src_abs()) do
      {:ok, modules} -> modules
      _ -> []
    end
  end

  defp fallback_builtin_source_modules("elm-pebble/companion-internal") do
    case ElmSourceDocs.list_modules(Ide.InternalPackages.shared_elm_companion_abs()) do
      {:ok, modules} -> modules
      _ -> []
    end
  end

  defp fallback_builtin_source_modules("elm/time") do
    case ElmSourceDocs.list_modules(Ide.InternalPackages.elm_time_elm_src_abs()) do
      {:ok, modules} -> modules
      _ -> []
    end
  end

  defp fallback_builtin_source_modules("elm/random") do
    case ElmSourceDocs.list_modules(Ide.InternalPackages.elm_random_elm_src_abs()) do
      {:ok, modules} -> modules
      _ -> []
    end
  end

  defp fallback_builtin_source_modules(_), do: []

  @spec exposed_modules_from_source_root(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  defp exposed_modules_from_source_root(source_root) when is_binary(source_root) do
    elm_json_path =
      source_root
      |> Path.dirname()
      |> Path.join("elm.json")

    with {:ok, content} <- File.read(elm_json_path),
         {:ok, decoded} <- Jason.decode(content),
         modules <- Map.get(decoded, "exposed-modules"),
         {:ok, exposed} <- normalize_exposed_modules(modules) do
      {:ok, exposed}
    end
  end

  @spec normalize_exposed_modules(term()) ::
          {:ok, [String.t()]} | {:error, :invalid_exposed_modules}
  defp normalize_exposed_modules(modules) when is_list(modules) do
    {:ok, modules |> Enum.filter(&is_binary/1) |> Enum.sort()}
  end

  defp normalize_exposed_modules(modules) when is_map(modules) do
    modules
    |> Map.values()
    |> List.flatten()
    |> normalize_exposed_modules()
  end

  defp normalize_exposed_modules(_), do: {:error, :invalid_exposed_modules}

  @spec candidate_elm_json_roots(map()) :: [String.t()]
  def candidate_elm_json_roots(project), do: ElmJsonEditor.candidate_roots(project)

  @doc """
  `elm.json` roots offered for adding/removing packages (watch face + phone companion app).

  Excludes `protocol`.
  """
  @spec package_elm_json_roots(map()) :: [String.t()]
  def package_elm_json_roots(project), do: ElmJsonEditor.roots_for_package_management(project)

  @spec with_provider(term(), term()) :: term()
  defp with_provider(opts, fun) do
    providers = resolve_providers(opts)

    Enum.reduce_while(providers, {:error, :no_provider_available}, fn provider, _acc ->
      case fun.(provider) do
        {:ok, payload} -> {:halt, {:ok, provider, payload}}
        {:error, _reason} = error -> {:cont, error}
      end
    end)
  end

  @spec call_provider(term(), term(), term(), term()) :: term()
  defp call_provider(provider, function_name, args, runtime_opts \\ []) do
    merged_opts = Keyword.merge(provider.opts, runtime_opts)
    full_args = args ++ [merged_opts]
    apply(provider.module, function_name, full_args)
  end

  @spec resolver_editor_opts(term(), term()) :: term()
  defp resolver_editor_opts(provider, opts) do
    source_root = opts[:source_root]
    section = opts[:section]
    scope = opts[:scope]

    [
      source_root: source_root,
      section: section,
      scope: scope,
      versions_fetcher: fn package ->
        call_provider(provider, :versions, [package])
      end,
      release_fetcher: fn package, version ->
        call_provider(provider, :package_release, [package, version])
      end
    ]
  end

  @spec resolve_providers(term()) :: term()
  defp resolve_providers(opts) do
    config = Application.get_env(:ide, __MODULE__, [])
    provider_configs = Keyword.get(config, :providers, default_provider_configs())
    provider_keys = Keyword.keys(provider_configs)
    default_order = Keyword.get(config, :provider_order, provider_keys)

    selected =
      case normalize_source(opts[:source]) do
        nil ->
          Enum.filter(default_order, &Keyword.has_key?(provider_configs, &1))

        source ->
          matched_key =
            Enum.find(provider_keys, fn key ->
              key == source or Atom.to_string(key) == to_string(source)
            end)

          if matched_key do
            [matched_key]
          else
            Enum.filter(default_order, &Keyword.has_key?(provider_configs, &1))
          end
      end

    Enum.map(selected, fn key ->
      cfg = Keyword.get(provider_configs, key, [])

      case Keyword.get(cfg, :module) do
        nil ->
          nil

        module ->
          provider_opts = Keyword.drop(cfg, [:module])
          %{key: key, module: module, opts: provider_opts}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @spec default_provider_configs() :: term()
  defp default_provider_configs do
    [
      official: [module: Ide.Packages.OfficialProvider],
      mirror: [module: Ide.Packages.MirrorProvider]
    ]
  end

  @spec normalize_source(term()) :: term()
  defp normalize_source(nil), do: nil
  defp normalize_source(source) when is_atom(source), do: source

  defp normalize_source(source) when is_binary(source) do
    source
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  @spec paginate(term(), term(), term()) :: term()
  defp paginate(items, page, per_page) do
    offset = (page - 1) * per_page
    items |> Enum.drop(offset) |> Enum.take(per_page)
  end

  @spec parse_positive(term(), term()) :: term()
  defp parse_positive(value, _default) when is_integer(value) and value > 0, do: value

  defp parse_positive(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp parse_positive(_, default), do: default
end
