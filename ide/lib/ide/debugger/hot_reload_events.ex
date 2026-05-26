defmodule Ide.Debugger.HotReloadEvents do
  @moduledoc false

  alias Ide.Debugger.Types

  @type host :: %{
          required(:append_event) => (map(), String.t(), map() -> map()),
          required(:maybe_append_elm_introspect) => (map(), map() | nil -> map()),
          required(:maybe_append_runtime_exec) => (map(), String.t() -> map()),
          required(:maybe_append_phone_view_render) => (map(), String.t() -> map())
        }

  @spec append(
          map(),
          String.t(),
          String.t() | nil,
          String.t(),
          String.t(),
          map() | nil,
          host()
        ) :: map()
  def append(state, reason, rel_path, revision, source_root, intro_payload, host)
      when is_map(state) and is_binary(reason) and is_binary(revision) and is_binary(source_root) and
             is_map(host) do
    state
    |> host.append_event.(
      "debugger.reload",
      Types.HotReloadEventPayload.from_reload(reason, rel_path, revision, source_root)
    )
    |> host.maybe_append_elm_introspect.(intro_payload)
    |> host.maybe_append_runtime_exec.(source_root)
    |> host.append_event.(
      "debugger.protocol_tx",
      Types.ProtocolTxRxPayload.from_reload(revision, source_root)
    )
    |> host.append_event.(
      "debugger.protocol_rx",
      Types.ProtocolTxRxPayload.from_reload(revision, source_root)
    )
    |> host.append_event.(
      "debugger.view_render",
      Types.ViewRenderEventPayload.from_render("watch", "simulated-root")
    )
    |> host.append_event.(
      "debugger.view_render",
      Types.ViewRenderEventPayload.from_render("companion", "companion-root")
    )
    |> host.maybe_append_phone_view_render.(source_root)
  end
end
