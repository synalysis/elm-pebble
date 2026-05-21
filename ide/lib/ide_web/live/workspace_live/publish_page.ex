defmodule IdeWeb.WorkspaceLive.PublishPage do
  @moduledoc false
  use IdeWeb, :html

  alias Phoenix.LiveView.Rendered

  @type assigns :: map()
  @type rendered :: Rendered.t()
  @type flow_status :: :idle | :running | :ok | :error
  @type publish_summary :: %{
          required(:status) => :idle | :ready | :blocked,
          required(:blockers) => non_neg_integer(),
          required(:warnings) => non_neg_integer(),
          required(:passed) => non_neg_integer()
        }
  @type publish_check :: %{required(:status) => :ok | :error | atom(), optional(atom()) => term()}

  @spec render(assigns()) :: rendered()
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
        id="publish-form"
        phx-change="update-publish-form"
        phx-submit={if app_store_publish_enabled?(@auth_mode), do: "submit-publish-release"}
        phx-debounce="300"
        class="mt-4 rounded border border-zinc-200 p-3"
      >
        <h3 class="text-sm font-semibold">Release Summary</h3>
        <p class="mt-1 text-xs text-zinc-600">
          {release_summary_help(@auth_mode)}
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
            <span class="mt-1 block text-zinc-500">
              Sent to the store as release notes. Submitting includes the text above even if the field still has focus.
            </span>
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
        <div :if={@auth_mode == :public_custom} class="mt-4">
          <.link
            :if={@project}
            href={~p"/projects/#{@project.slug}/publish/pbw"}
            class="inline-flex rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white hover:bg-zinc-800"
          >
            Download PBW
          </.link>
          <p class="mt-2 text-xs text-zinc-600">
            Upload the downloaded `.pbw` to your app store or sideload it. Automated Rebble App Store submit is not available in this deployment.
          </p>
        </div>
      </div>

      <div :if={app_store_publish_enabled?(@auth_mode)} class="mt-4 rounded border border-zinc-200 p-3">
        <h3 class="text-sm font-semibold">Store Submission</h3>
        <p class="mt-1 text-xs text-zinc-600">
          Submit directly to the Rebble App Store from the prepared app workspace.
        </p>

        <div
          :if={app_store_login_needed?(@current_user, @firebase_id_token, @firebase_id_token_exp)}
          class="mt-3 rounded border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900"
        >
          <p class="font-semibold">
            {app_store_login_title(@firebase_id_token, @firebase_id_token_exp)}
          </p>
          <p class="mt-1">
            Log in here to refresh App Store access without leaving this page. Your changelog and
            submit options stay in place.
          </p>
          <div class="mt-2 flex flex-wrap gap-2">
            <button
              type="button"
              class="firebase-login rounded bg-blue-600 px-3 py-1.5 font-semibold text-white"
              data-provider="google"
              data-live-auth="true"
            >
              Log in with Google
            </button>
            <button
              type="button"
              class="firebase-login rounded bg-zinc-800 px-3 py-1.5 font-semibold text-white"
              data-provider="github"
              data-live-auth="true"
            >
              Log in with GitHub
            </button>
            <button
              type="button"
              class="firebase-login rounded bg-white px-3 py-1.5 font-semibold text-zinc-900 ring-1 ring-amber-300"
              data-provider="apple"
              data-live-auth="true"
            >
              Log in with Apple
            </button>
          </div>
          <p id="firebase-login-status" class="mt-2"></p>
        </div>

        <div
          :if={IdeWeb.WorkspaceLive.PublishFlow.offers_ai_store_graphics?(@project, @store_assets)}
          class="mt-3 rounded border border-blue-200 bg-blue-50 p-3 text-xs text-zinc-700"
        >
          <input type="hidden" form="publish-form" name="publish_submit[generate_store_graphics]" value="false" />
          <label class="flex items-start gap-2">
            <input
              type="checkbox"
              form="publish-form"
              name="publish_submit[generate_store_graphics]"
              value="true"
              checked={@publish_submit_options["generate_store_graphics"] == true}
              class="mt-0.5"
            />
            <span>
              <span class="block font-medium text-zinc-900">Generate App Store icons with AI on first publish</span>
              <span class="mt-1 block text-zinc-600">
                Uses your App Store description from Project Settings. Only applies when creating a new listing without uploaded icons.
              </span>
            </span>
          </label>
        </div>

        <div class="mt-3 space-y-2">
          <input type="hidden" form="publish-form" name="publish_submit[is_published]" value="false" />
          <label class="inline-flex items-center gap-2 text-xs text-zinc-700">
            <input
              type="checkbox"
              form="publish-form"
              name="publish_submit[is_published]"
              value="true"
              checked={@publish_submit_options["is_published"] == true}
            /> Make release visible immediately (unchecked uploads a draft; the store keeps showing the previous public version)
          </label>

          <input type="hidden" form="publish-form" name="publish_submit[all_platforms]" value="false" />
          <label class="inline-flex items-center gap-2 text-xs text-zinc-700">
            <input
              type="checkbox"
              form="publish-form"
              name="publish_submit[all_platforms]"
              value="true"
              checked={@publish_submit_options["all_platforms"] == true}
            /> Capture static screenshots for all platforms during publish
          </label>
          <p class="text-xs text-zinc-500">
            All saved screenshots per platform are uploaded on submit; the store screenshot set is replaced (not appended).
          </p>
        </div>

        <div class="mt-3 flex flex-wrap items-center gap-2">
          <button
            type="submit"
            form="publish-form"
            class="rounded bg-zinc-900 px-3 py-1.5 text-sm font-semibold text-white hover:bg-zinc-800 disabled:opacity-50"
            disabled={@publish_submit_status == :running}
          >
            {if @publish_submit_status == :running,
              do: "Submitting to App Store...",
              else: "Submit to App Store"}
          </button>
          <span class="text-xs text-zinc-600">Status: {status_label(@publish_submit_status)}</span>
        </div>
        <pre
          :if={@publish_submit_output}
          class="mt-3 max-h-64 overflow-auto rounded bg-zinc-900 p-3 text-xs text-zinc-100"
        ><%= @publish_submit_output %></pre>
      </div>

      <div
        :if={@debug_mode}
        class="mt-4 rounded border border-zinc-200 p-3 text-xs text-zinc-700"
      >
        <h3 class="text-sm font-semibold">Flow Metrics</h3>
        <p class="mt-1">Last run duration: {@publish_metrics.last_duration_ms || "n/a"} ms</p>
        <p>Last run finished: {@publish_metrics.last_finished_at || "n/a"}</p>
        <p>In-IDE completion rate: {@publish_metrics.in_ide_completion_rate || "0.00"}%</p>
      </div>
    </section>
    """
  end

  @spec failed_checks([publish_check()]) :: [publish_check()]
  defp failed_checks(checks), do: Enum.filter(checks, &(&1.status != :ok))

  @spec quick_fix_label(String.t()) :: String.t()
  defp quick_fix_label("appinfo_fields"), do: "Open metadata editor"
  defp quick_fix_label("appinfo_exists"), do: "Open metadata editor"
  defp quick_fix_label("screenshot_coverage"), do: "Capture missing screenshots"
  defp quick_fix_label("watchapp_mode"), do: "Fix app type"
  defp quick_fix_label("artifact_exists"), do: "Generate PBW"
  defp quick_fix_label(_), do: "View details"

  @spec readiness_text(publish_summary()) :: String.t()
  defp readiness_text(%{status: :ready} = summary),
    do: "Ready to ship. #{summary.passed} checks passed."

  defp readiness_text(%{status: :blocked} = summary),
    do: "#{summary.blockers} blocker(s) remain before publish."

  defp readiness_text(_), do: "Run Prepare Release to compute readiness."

  @spec readiness_class(:ready | :blocked | atom()) :: String.t()
  defp readiness_class(:ready), do: "mt-2 text-sm font-medium text-emerald-700"
  defp readiness_class(:blocked), do: "mt-2 text-sm font-medium text-rose-700"
  defp readiness_class(_), do: "mt-2 text-sm font-medium text-zinc-700"

  @spec status_label(flow_status() | atom()) :: String.t()
  defp status_label(:idle), do: "idle"
  defp status_label(:running), do: "running"
  defp status_label(:ok), do: "ok"
  defp status_label(:error), do: "error"
  defp status_label(_), do: "unknown"

  defp app_store_publish_enabled?(:public_pebble), do: true
  defp app_store_publish_enabled?(_), do: false

  defp release_summary_help(:public_pebble),
    do:
      "Changelog is sent to the App Store as release notes. Version and tags are edited in Project Settings."

  defp release_summary_help(:public_custom),
    do: "Changelog is saved in the project for your release notes export. Version and tags are edited in Project Settings."

  defp release_summary_help(_),
    do:
      "Changelog is sent to the App Store as release notes when publishing. Version and tags are edited in Project Settings."

  defp app_store_login_needed?(current_user, firebase_id_token, firebase_id_token_exp) do
    is_nil(current_user) or is_nil(firebase_id_token) or
      Ide.Auth.token_expired?(firebase_id_token_exp)
  end

  defp app_store_login_title(firebase_id_token, firebase_id_token_exp) do
    if is_binary(firebase_id_token) and Ide.Auth.token_expired?(firebase_id_token_exp) do
      "App Store login expired"
    else
      "App Store login required for publishing"
    end
  end
end
