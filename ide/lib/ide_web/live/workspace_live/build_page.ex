defmodule IdeWeb.WorkspaceLive.BuildPage do
  @moduledoc false
  use IdeWeb, :html

  @spec render(term()) :: term()
  def render(assigns) do
    ~H"""
    <section :if={@pane == :build} class="rounded-lg border border-zinc-200 bg-white p-5 shadow-sm">
      <h2 class="text-base font-semibold">Build Pane</h2>
      <div class="mt-3 flex items-center gap-2">
        <.button phx-click="run-build" disabled={@build_status == :running}>
          {if @build_status == :running,
            do: "Building project roots...",
            else: "Build all project roots"}
        </.button>
        <label class="ml-2 inline-flex items-center gap-2 text-xs text-zinc-700">
          <input
            type="checkbox"
            checked={@manifest_strict_mode}
            phx-click="set-manifest-strict"
            phx-value-value={if @manifest_strict_mode, do: "false", else: "true"}
          /> strict manifest validation
        </label>
        <span class="text-xs text-zinc-600">Build: {check_status_label(@build_status)}</span>
      </div>
      <p class="mt-2 text-sm text-zinc-600">
        Runs the full build pipeline for each project root with `elm.json` (workspace/watch/protocol/phone): `elmc check`, `elmc compile`, then `elmc manifest`.
      </p>
      <pre
        :if={@build_output}
        class="mt-4 max-h-96 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
      ><%= @build_output %></pre>
      <div class="mt-6 rounded border border-zinc-200 bg-zinc-50 p-3">
        <h3 class="text-sm font-semibold">Next step: Publish</h3>
        <p class="mt-2 text-sm text-zinc-600">
          Build only handles compile/package checks. Use the Publish tab for release readiness, screenshot coverage, and publish bundle exports.
        </p>
        <.link
          patch={~p"/projects/#{@project.slug}/publish"}
          class="mt-3 inline-flex rounded bg-zinc-900 px-3 py-2 text-xs font-medium text-white hover:bg-zinc-800"
        >
          Open Publish
        </.link>
      </div>
    </section>
    """
  end

  @spec check_status_label(term()) :: term()
  defp check_status_label(:idle), do: "idle"
  defp check_status_label(:running), do: "running"
  defp check_status_label(:ok), do: "ok"
  defp check_status_label(:error), do: "error"
  defp check_status_label(_), do: "unknown"
end
