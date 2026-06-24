defmodule IdeWeb.WorkspaceLive.BuildPage do
  @moduledoc false
  use IdeWeb, :html

  alias IdeWeb.WorkspaceLive.BuildPage.Assigns
  alias Phoenix.LiveView.Rendered

  @type assigns :: Assigns.t()
  @type rendered :: Rendered.t()
  @type flow_status :: :idle | :running | :ok | :error

  @spec render(assigns()) :: rendered()
  def render(assigns) do
    ~H"""
    <section
      :if={@pane == :build}
      class="flex min-h-0 flex-1 flex-col rounded-lg border border-zinc-200 bg-white p-5 shadow-sm"
    >
      <h2 class="text-base font-semibold">Build Pane</h2>
      <.form
        for={%{}}
        as={:build}
        phx-change="set-manifest-strict"
        phx-submit="run-build"
        class="mt-3 flex items-center gap-2"
      >
        <.button type="submit" disabled={@build_status == :running}>
          {if @build_status == :running,
            do: "Building project roots...",
            else: "Build all project roots"}
        </.button>
        <input type="hidden" name="build[manifest_strict]" value="false" />
        <label class="ml-2 inline-flex items-center gap-2 text-xs text-zinc-700">
          <input
            type="checkbox"
            name="build[manifest_strict]"
            value="true"
            checked={@manifest_strict_mode}
          /> strict manifest validation
        </label>
        <span class="text-xs text-zinc-600">Build: {check_status_label(@build_status)}</span>
      </.form>
      <p class="mt-2 text-sm text-zinc-600">
        Runs `elmc check`, `elmc compile`, and `elmc manifest` for each project root, then packages the PBW with the configured target platforms.
      </p>
      <div
        :if={@build_issues != []}
        class="mt-4 rounded border border-rose-200 bg-rose-50 p-3 text-sm text-rose-900"
      >
        <h3 class="font-semibold">Build issues</h3>
        <ul class="mt-2 space-y-2">
          <li :for={issue <- @build_issues}>
            <p class="font-medium">{issue.title}</p>
            <p>{issue.message}</p>
            <p :if={issue[:detail]} class="mt-1 font-mono text-xs text-rose-800">{issue.detail}</p>
          </li>
        </ul>
      </div>
      <pre
        :if={@build_output}
        class="mt-4 min-h-0 flex-1 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
      ><%= @build_output %></pre>
    </section>
    """
  end

  @spec check_status_label(flow_status() | atom()) :: String.t()
  defp check_status_label(:idle), do: "idle"
  defp check_status_label(:running), do: "running"
  defp check_status_label(:ok), do: "ok"
  defp check_status_label(:error), do: "error"
  defp check_status_label(_), do: "unknown"
end
