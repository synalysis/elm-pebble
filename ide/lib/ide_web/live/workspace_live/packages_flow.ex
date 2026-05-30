defmodule IdeWeb.WorkspaceLive.PackagesFlow do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, start_async: 3]

  alias Ide.Packages
  alias Ide.Projects.Types, as: ProjectTypes
  alias IdeWeb.WorkspaceLive.EditorSupport

  @type socket :: Phoenix.LiveView.Socket.t()
  @type lv_noreply :: {:noreply, socket()}
  @type dependency_row :: map()

  @type search_progress ::
          {:phase, atom() | {atom(), non_neg_integer()}}
          | {:bytes, non_neg_integer(), non_neg_integer() | nil}

  @spec search_progress_label(search_progress()) :: String.t()
  def search_progress_label({:phase, :starting}), do: "Preparing search…"
  def search_progress_label({:phase, :connecting}), do: "Connecting to package registry…"
  def search_progress_label({:phase, :download_started}), do: "Downloading package index…"

  def search_progress_label({:phase, {:download_started, total}})
      when is_integer(total) and total > 0 do
    "Downloading package index (#{format_index_bytes(total)} expected)…"
  end

  def search_progress_label({:bytes, received, total})
      when is_integer(received) and received >= 0 do
    got = format_index_bytes(received)

    if is_integer(total) and total > 0 do
      "Downloading index: #{got} / #{format_index_bytes(total)}"
    else
      "Downloading index: #{got}"
    end
  end

  def search_progress_label({:phase, :decoding_json}), do: "Parsing package index…"

  def search_progress_label({:phase, :fallback_all_packages_index}) do
    "Fetching full package list (all-packages, larger download)…"
  end

  def search_progress_label(_), do: "Working…"

  @spec maybe_select_first_package(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def maybe_select_first_package(socket) do
    case socket.assigns.packages_search_results do
      [%{name: package} | _] when is_binary(package) ->
        schedule_inspection(socket, package)

      [%{"name" => package} | _] when is_binary(package) ->
        schedule_inspection(socket, package)

      _ ->
        socket
        |> assign(:packages_inspect_loading, nil)
        |> assign(:packages_selected, nil)
        |> assign(:packages_details, nil)
        |> assign(:packages_versions, [])
        |> assign(:packages_readme, nil)
        |> assign(:packages_preview, nil)
    end
  end

  @spec schedule_inspection(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def schedule_inspection(socket, package) when is_binary(package) do
    socket
    |> assign(:packages_inspect_loading, package)
    |> start_async(:packages_inspect, fn -> fetch_package_inspection(package) end)
  end

  @spec refresh_preview(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refresh_preview(socket) do
    case socket.assigns.packages_selected do
      package when is_binary(package) ->
        opts = [] |> maybe_put_kw(:source_root, socket.assigns.packages_target_root)

        case Packages.preview_add_to_project(socket.assigns.project, package, opts) do
          {:ok, preview} -> assign(socket, :packages_preview, preview)
          {:error, _reason} -> assign(socket, :packages_preview, nil)
        end

      _ ->
        assign(socket, :packages_preview, nil)
    end
  end

  @spec default_packages_target_root(map()) :: String.t()
  def default_packages_target_root(project) do
    roots = Packages.package_elm_json_roots(project)

    cond do
      "watch" in roots -> "watch"
      "phone" in roots -> "phone"
      roots != [] -> List.first(roots)
      true -> "watch"
    end
  end

  @spec sanitize_target_root(map(), String.t() | nil) :: String.t()
  def sanitize_target_root(project, source_root) do
    allowed = Packages.package_elm_json_roots(project)
    root = source_root || default_packages_target_root(project)
    if root in allowed, do: root, else: default_packages_target_root(project)
  end

  @spec fetch_package_inspection(String.t()) ::
          {:ok,
           %{package: String.t(), details: map(), versions: [String.t()], readme: String.t()}}
          | {:error, String.t(), atom() | tuple() | String.t()}
  def fetch_package_inspection(package) when is_binary(package) do
    with {:ok, details} <- Packages.package_details(package, []),
         {:ok, versions_payload} <- Packages.versions(package, []),
         {:ok, readme_payload} <- Packages.readme(package, "latest", []) do
      {:ok,
       %{
         package: package,
         details: details,
         versions: versions_payload.versions,
         readme: readme_payload.readme
       }}
    else
      {:error, reason} -> {:error, package, reason}
    end
  end

  @spec format_index_bytes(non_neg_integer()) :: String.t()
  defp format_index_bytes(n) when is_integer(n) and n >= 1_000_000,
    do: "#{Float.round(n / 1_000_000, 1)} MB"

  defp format_index_bytes(n) when is_integer(n) and n >= 1_000,
    do: "#{Float.round(n / 1_000, 1)} KB"

  defp format_index_bytes(n) when is_integer(n) and n >= 0, do: "#{n} B"

  @spec maybe_put_kw(keyword(), atom(), String.t() | nil) :: keyword()
  defp maybe_put_kw(opts, _key, nil), do: opts
  defp maybe_put_kw(opts, _key, ""), do: opts
  defp maybe_put_kw(opts, key, value), do: Keyword.put(opts, key, value)

  @packages_asyncs [:packages_search, :packages_inspect]

  @spec packages_asyncs() :: [atom()]
  def packages_asyncs, do: @packages_asyncs

  @spec handle_event(String.t(), map(), socket()) :: lv_noreply()
  def handle_event("packages-search", params, socket) do
    search_params = Map.get(params, "packages_search") || %{}
    query = Map.get(search_params, "query", "") |> String.trim()

    if query == "" do
      {:noreply,
       socket
       |> assign(:packages_query, "")
       |> assign(:packages_search_results, [])
       |> assign(:packages_search_total, 0)
       |> assign(:packages_search_busy, false)
       |> assign(:packages_search_progress, nil)
       |> assign(:packages_search_token, nil)
       |> assign(:packages_inspect_loading, nil)
       |> maybe_select_first_package()}
    else
      search_token = make_ref()
      lv = self()

      progress_fn = fn msg ->
        send(lv, {:packages_search_progress, search_token, msg})
      end

      packages_target_root = socket.assigns.packages_target_root

      platform_target =
        case packages_target_root do
          "phone" -> :phone
          _ -> :watch
        end

      {:noreply,
       socket
       |> assign(:packages_search_token, search_token)
       |> assign(:packages_search_busy, true)
       |> assign(
         :packages_search_progress,
         search_progress_label({:phase, :starting})
       )
       |> assign(:packages_query, query)
       |> assign(:packages_search_results, [])
       |> assign(:packages_search_total, 0)
       |> maybe_select_first_package()
       |> start_async(:packages_search, fn ->
         result =
           Packages.search(query,
             per_page: 30,
             progress: progress_fn,
             platform_target: platform_target
           )

         {result, search_token}
       end)}
    end
  end

  def handle_event("packages-select", %{"package" => package}, socket) do
    socket =
      socket
      |> assign(:packages_dep_docs_package, nil)
      |> assign(:packages_dep_docs_version, nil)
      |> assign(:packages_dep_readme, nil)

    {:noreply, schedule_inspection(socket, package)}
  end

  def handle_event(
        "packages-set-target-root",
        %{"packages_target" => %{"source_root" => source_root}},
        socket
      ) do
    source_root = sanitize_target_root(socket.assigns.project, source_root)

    socket =
      socket
      |> assign(:packages_target_root, source_root)
      |> EditorSupport.refresh_editor_dependencies()
      |> refresh_preview()

    {:noreply, socket}
  end

  def handle_event("packages-add", %{"package" => package}, socket) do
    project = socket.assigns.project

    opts = [] |> maybe_put_kw(:source_root, socket.assigns.packages_target_root)

    case Packages.add_to_project(project, package, opts) do
      {:ok, result} ->
        message = "Added #{package} #{result.selected_version} to #{result.source_root}/elm.json"

        {:noreply,
         socket
         |> assign(:project, Map.get(result, :project, project))
         |> assign(:packages_last_add_result, result)
         |> EditorSupport.refresh_tree()
         |> refresh_preview()
         |> put_flash(:info, message)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, package_add_error(reason))}
    end
  end

  def handle_event("packages-remove", %{"package" => package}, socket) do
    project = socket.assigns.project

    opts = [] |> maybe_put_kw(:source_root, socket.assigns.packages_target_root)

    case Packages.remove_from_project(project, package, opts) do
      {:ok, result} ->
        message = "Removed #{package} from #{result.source_root}/elm.json"

        {:noreply,
         socket
         |> assign(:packages_last_add_result, nil)
         |> EditorSupport.refresh_tree()
         |> refresh_preview()
         |> put_flash(:info, message)}

      {:error, :builtin_package_not_removable} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Required packages (e.g. elm/core, elm/json, elm/time, Pebble) cannot be removed."
         )}

      {:error, {:package_in_use, package}} ->
        {:noreply,
         socket
         |> mark_dependency_used(package)
         |> put_flash(
           :error,
           "#{package} is imported by current Elm source files. Remove those imports before removing the package."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not remove package: #{inspect(reason)}")}
    end
  end

  def handle_event("packages-dep-select", %{"package" => package, "version" => version}, socket) do
    readme =
      case Packages.readme(package, version, []) do
        {:ok, payload} ->
          payload.readme

        _ ->
          "(Could not load README for #{package} #{version}.)"
      end

    {:noreply,
     socket
     |> assign(:packages_dep_docs_package, package)
     |> assign(:packages_dep_docs_version, version)
     |> assign(:packages_dep_readme, readme)}
  end

  @spec handle_async(atom(), term(), socket()) :: lv_noreply()
  def handle_async(:packages_search, {:ok, {{:ok, result}, token}}, socket) do
    if socket.assigns.packages_search_token == token do
      {:noreply,
       socket
       |> assign(:packages_search_busy, false)
       |> assign(:packages_search_progress, nil)
       |> assign(:packages_query, result.query)
       |> assign(:packages_search_results, result.packages)
       |> assign(:packages_search_total, result.total)
       |> maybe_select_first_package()}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:packages_search, {:ok, {{:error, reason}, token}}, socket) do
    if socket.assigns.packages_search_token == token do
      {:noreply,
       socket
       |> assign(:packages_search_busy, false)
       |> assign(:packages_search_progress, nil)
       |> put_flash(:error, "Package search failed: #{inspect(reason)}")}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:packages_search, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:packages_search_busy, false)
     |> assign(:packages_search_progress, nil)
     |> put_flash(:error, "Package search interrupted: #{inspect(reason)}")}
  end

  def handle_async(:packages_inspect, {:ok, {:ok, p}}, socket) do
    socket =
      socket
      |> assign(:packages_inspect_loading, nil)
      |> assign(:packages_selected, p.package)
      |> assign(:packages_details, p.details)
      |> assign(:packages_versions, p.versions)
      |> assign(:packages_readme, p.readme)
      |> refresh_preview()

    {:noreply, socket}
  end

  def handle_async(:packages_inspect, {:ok, {:error, package, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:packages_inspect_loading, nil)
     |> assign(:packages_selected, package)
     |> assign(:packages_details, nil)
     |> assign(:packages_versions, [])
     |> assign(:packages_readme, nil)
     |> assign(:packages_preview, nil)
     |> put_flash(:error, "Could not load package details: #{inspect(reason)}")}
  end

  def handle_async(:packages_inspect, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:packages_inspect_loading, nil)
     |> put_flash(:error, "Package inspection interrupted: #{inspect(reason)}")}
  end

  @spec handle_info({:packages_search_progress, reference(), search_progress()}, socket()) ::
          lv_noreply()
  def handle_info({:packages_search_progress, token, msg}, socket) do
    if socket.assigns.packages_search_token == token do
      {:noreply, assign(socket, :packages_search_progress, search_progress_label(msg))}
    else
      {:noreply, socket}
    end
  end

  @spec package_add_error(ProjectTypes.project_error()) :: String.t()
  defp package_add_error({:package_not_supported_for_phone, package}) do
    "Could not add #{package}: this package is not supported for the companion phone elm.json."
  end

  defp package_add_error(reason), do: "Could not add package: #{inspect(reason)}"

  @spec mark_dependency_used(socket(), String.t()) :: socket()
  defp mark_dependency_used(socket, package) when is_binary(package) do
    socket
    |> assign(
      :project_elm_direct,
      mark_dependency_rows_used(socket.assigns[:project_elm_direct], package)
    )
    |> assign(
      :project_elm_indirect,
      mark_dependency_rows_used(socket.assigns[:project_elm_indirect], package)
    )
  end

  @spec mark_dependency_rows_used([dependency_row()], String.t()) :: [dependency_row()]
  defp mark_dependency_rows_used(rows, package) when is_list(rows) and is_binary(package) do
    Enum.map(rows, fn
      %{name: ^package} = row -> Map.put(row, :used?, true)
      %{"name" => ^package} = row -> Map.put(row, :used?, true)
      row -> row
    end)
  end

  defp mark_dependency_rows_used(_rows, _package), do: []
end
