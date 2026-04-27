defmodule IdeWeb.WorkspaceLive.PackagesFlow do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]

  alias Ide.Packages

  @spec search_progress_label(term()) :: String.t()
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
          | {:error, String.t(), term()}
  def fetch_package_inspection(package) when is_binary(package) do
    with {:ok, details} <- Packages.package_details(package, []),
         {:ok, versions_payload} <- Packages.versions(package, []),
         {:ok, readme_payload} <- Packages.readme(package, "latest", []) do
      {:ok,
       %{
         package: package,
         details: details,
         versions: versions_payload.versions,
         readme: readme_payload.readme || ""
       }}
    else
      {:error, reason} -> {:error, package, reason}
    end
  end

  @spec format_index_bytes(term()) :: term()
  defp format_index_bytes(n) when is_integer(n) and n >= 1_000_000,
    do: "#{Float.round(n / 1_000_000, 1)} MB"

  defp format_index_bytes(n) when is_integer(n) and n >= 1_000,
    do: "#{Float.round(n / 1_000, 1)} KB"

  defp format_index_bytes(n) when is_integer(n) and n >= 0, do: "#{n} B"

  @spec maybe_put_kw(term(), term(), term()) :: term()
  defp maybe_put_kw(opts, _key, nil), do: opts
  defp maybe_put_kw(opts, _key, ""), do: opts
  defp maybe_put_kw(opts, key, value), do: Keyword.put(opts, key, value)
end
