defmodule IdeWeb.WorkspaceLive.PublishPage do
  @moduledoc false
  use IdeWeb, :html

  @spec render(term()) :: term()
  def render(assigns) do
    ~H"""
    <section
      :if={@pane == :publish}
      class="min-h-0 flex-1 overflow-auto rounded-lg border border-zinc-200 bg-white p-5 shadow-sm"
    >
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 class="text-base font-semibold">Publish</h2>
          <p class="mt-1 text-sm text-zinc-600">
            Prepare a complete release package without leaving the IDE.
          </p>
        </div>
        <.button phx-click="prepare-release" disabled={@prepare_release_status == :running}>
          {if @prepare_release_status == :running, do: "Preparing release...", else: "Prepare Release"}
        </.button>
      </div>

      <div class="mt-4 rounded border border-zinc-200 bg-zinc-50 p-3">
        <h3 class="text-sm font-semibold">Readiness</h3>
        <p class={readiness_class(@publish_summary.status)}>
          {readiness_text(@publish_summary)}
        </p>
        <div class="mt-2 flex flex-wrap gap-2 text-xs">
          <span class="rounded bg-rose-100 px-2 py-1 text-rose-800">
            Blockers: {@publish_summary.blockers}
          </span>
          <span class="rounded bg-amber-100 px-2 py-1 text-amber-900">
            Warnings: {@publish_summary.warnings}
          </span>
          <span class="rounded bg-emerald-100 px-2 py-1 text-emerald-800">
            Checks passed: {@publish_summary.passed}
          </span>
        </div>
      </div>

      <.form
        for={@release_summary_form}
        id="release-summary-form"
        phx-change="update-release-summary"
        class="mt-4 rounded border border-zinc-200 p-3"
      >
        <h3 class="text-sm font-semibold">Release Summary</h3>
        <p class="mt-1 text-xs text-zinc-600">
          Used when generating release notes and handoff metadata. Version and tags are edited in Project Settings.
        </p>
        <p class="mt-2 text-xs text-zinc-600">
          Version: <span class="font-mono">{@release_summary_form["version_label"].value}</span>
          · Tags: <span class="font-mono">{@release_summary_form["tags"].value}</span>
        </p>
        <div class="mt-3 grid gap-3 md:grid-cols-2">
          <label class="text-xs">
            <span class="mb-1 block font-medium text-zinc-700">Release channel</span>
            <select
              name={@release_summary_form["release_channel"].name}
              class="w-full rounded border border-zinc-300 px-2 py-1.5"
            >
              <option
                value="stable"
                selected={@release_summary_form["release_channel"].value == "stable"}
              >
                Stable
              </option>
              <option value="beta" selected={@release_summary_form["release_channel"].value == "beta"}>
                Beta
              </option>
              <option
                value="internal"
                selected={@release_summary_form["release_channel"].value == "internal"}
              >
                Internal
              </option>
            </select>
          </label>
          <label class="text-xs md:col-span-2">
            <span class="mb-1 block font-medium text-zinc-700">Changelog</span>
            <textarea
              name={@release_summary_form["changelog"].name}
              class="min-h-20 w-full rounded border border-zinc-300 px-2 py-1.5"
              placeholder="- Added ...&#10;- Fixed ..."
            ><%= @release_summary_form["changelog"].value %></textarea>
          </label>
        </div>
      </.form>

      <div class="mt-4 rounded border border-zinc-200 p-3">
        <h3 class="text-sm font-semibold">Blockers & Quick Fixes</h3>
        <p class="mt-1 text-xs text-zinc-600">
          Resolve failed checks directly from here, then run Prepare Release again.
        </p>
        <ul class="mt-3 space-y-2 text-xs">
          <li
            :for={check <- failed_checks(@publish_checks)}
            class="rounded border border-rose-200 bg-rose-50 px-2 py-2"
          >
            <div class="flex flex-wrap items-center justify-between gap-2">
              <div>
                <p class="font-medium text-rose-900">{check.label}</p>
                <p class="text-rose-800">{check.message}</p>
              </div>
              <button
                type="button"
                phx-click="resolve-publish-check"
                phx-value-check-id={check.id}
                class="rounded bg-rose-700 px-2 py-1 text-white hover:bg-rose-600"
              >
                {quick_fix_label(check.id)}
              </button>
            </div>
          </li>
        </ul>
        <p :if={failed_checks(@publish_checks) == []} class="mt-2 text-xs text-emerald-700">
          No blockers detected.
        </p>
      </div>

      <div class="mt-4 rounded border border-zinc-200 p-3">
        <h3 class="text-sm font-semibold">Warnings</h3>
        <ul class="mt-2 space-y-2 text-xs">
          <li
            :for={warning <- @publish_warnings}
            class="rounded border border-amber-200 bg-amber-50 px-2 py-2"
          >
            <p class="font-medium text-amber-900">{warning.label}</p>
            <p class="text-amber-800">{warning.message}</p>
          </li>
        </ul>
        <p :if={@publish_warnings == []} class="mt-2 text-xs text-emerald-700">No warnings.</p>
      </div>

      <div class="mt-4 rounded border border-zinc-200 p-3">
        <h3 class="text-sm font-semibold">Type-Specific Guidance</h3>
        <p class="mt-1 text-xs text-zinc-600">{@publish_type_guidance.headline}</p>
        <ul class="mt-2 list-disc pl-5 text-xs text-zinc-700">
          <li :for={item <- @publish_type_guidance.items}>{item}</li>
        </ul>
      </div>

      <div class="mt-4 rounded border border-zinc-200 p-3">
        <h3 class="text-sm font-semibold">Artifacts & Exports</h3>
        <p :if={@publish_artifact_path} class="mt-2 text-xs font-mono text-zinc-700">
          PBW: {@publish_artifact_path}
        </p>
        <p :if={@manifest_export_path} class="mt-1 text-xs font-mono text-zinc-700">
          Manifest: {@manifest_export_path}
        </p>
        <p :if={@release_notes_path} class="mt-1 text-xs font-mono text-zinc-700">
          Release notes: {@release_notes_path}
        </p>
        <ul class="mt-3 space-y-1 text-xs">
          <li
            :for={item <- @publish_readiness}
            class="rounded border border-zinc-200 bg-zinc-50 px-2 py-1"
          >
            <span class={if item.status == :ok, do: "text-emerald-700", else: "text-amber-700"}>
              {if item.status == :ok, do: "OK", else: "MISSING"}
            </span>
            <span class="ml-2 font-mono">{item.target}</span>
            <span class="ml-2 text-zinc-600">{item.count} screenshot(s)</span>
          </li>
        </ul>
        <pre
          :if={@prepare_release_output}
          class="mt-3 max-h-64 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
        ><%= @prepare_release_output %></pre>
      </div>

      <div class="mt-4 rounded border border-zinc-200 p-3">
        <h3 class="text-sm font-semibold">Store Submission</h3>
        <p class="mt-1 text-xs text-zinc-600">
          Submit directly using `pebble publish` from the prepared app workspace.
        </p>

        <.form
          for={%{}}
          id="publish-submit-form"
          phx-change="update-publish-submit-options"
          class="mt-3 space-y-2"
        >
          <input type="hidden" name="publish_submit[is_published]" value="false" />
          <label class="inline-flex items-center gap-2 text-xs text-zinc-700">
            <input
              type="checkbox"
              name="publish_submit[is_published]"
              value="true"
              checked={@publish_submit_options["is_published"] == true}
            /> Make release visible immediately
          </label>

          <input type="hidden" name="publish_submit[all_platforms]" value="false" />
          <label class="inline-flex items-center gap-2 text-xs text-zinc-700">
            <input
              type="checkbox"
              name="publish_submit[all_platforms]"
              value="true"
              checked={@publish_submit_options["all_platforms"] == true}
            /> Capture static screenshots for all platforms during publish
          </label>
        </.form>

        <div class="mt-3 flex flex-wrap items-center gap-2">
          <.button phx-click="submit-publish-release" disabled={@publish_submit_status == :running}>
            {if @publish_submit_status == :running,
              do: "Submitting to App Store...",
              else: "Submit to App Store"}
          </.button>
          <span class="text-xs text-zinc-600">Status: {status_label(@publish_submit_status)}</span>
        </div>
        <pre
          :if={@publish_submit_output}
          class="mt-3 max-h-64 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
        ><%= @publish_submit_output %></pre>
      </div>

      <div class="mt-4 rounded border border-zinc-200 p-3 text-xs text-zinc-700">
        <h3 class="text-sm font-semibold">Flow Metrics</h3>
        <p class="mt-1">Last run duration: {@publish_metrics.last_duration_ms || "n/a"} ms</p>
        <p>Last run finished: {@publish_metrics.last_finished_at || "n/a"}</p>
        <p>In-IDE completion rate: {@publish_metrics.in_ide_completion_rate || "0.00"}%</p>
      </div>
    </section>
    """
  end

  @spec failed_checks(term()) :: term()
  defp failed_checks(checks), do: Enum.filter(checks, &(&1.status != :ok))

  @spec quick_fix_label(term()) :: term()
  defp quick_fix_label("appinfo_fields"), do: "Open metadata editor"
  defp quick_fix_label("appinfo_exists"), do: "Open metadata editor"
  defp quick_fix_label("screenshot_coverage"), do: "Capture missing screenshots"
  defp quick_fix_label("watchapp_mode"), do: "Fix app type"
  defp quick_fix_label("artifact_exists"), do: "Generate PBW"
  defp quick_fix_label(_), do: "View details"

  @spec readiness_text(term()) :: term()
  defp readiness_text(%{status: :ready} = summary),
    do: "Ready to ship. #{summary.passed} checks passed."

  defp readiness_text(%{status: :blocked} = summary),
    do: "#{summary.blockers} blocker(s) remain before publish."

  defp readiness_text(_), do: "Run Prepare Release to compute readiness."

  @spec readiness_class(term()) :: term()
  defp readiness_class(:ready), do: "mt-2 text-sm font-medium text-emerald-700"
  defp readiness_class(:blocked), do: "mt-2 text-sm font-medium text-rose-700"
  defp readiness_class(_), do: "mt-2 text-sm font-medium text-zinc-700"

  @spec status_label(term()) :: term()
  defp status_label(:idle), do: "idle"
  defp status_label(:running), do: "running"
  defp status_label(:ok), do: "ok"
  defp status_label(:error), do: "error"
  defp status_label(_), do: "unknown"
end
