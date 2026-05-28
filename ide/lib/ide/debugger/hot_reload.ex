defmodule Ide.Debugger.HotReload do
  @moduledoc false

  alias Ide.Debugger.ElmIntrospectSnapshot
  alias Ide.Debugger.Types

  @type ctx :: %{
          required(:compute_revision) => (String.t() | nil, String.t() -> String.t()),
          required(:prepare_running_state) => (Types.runtime_state() -> Types.runtime_state()),
          required(:put_reload_fields) =>
            (Types.runtime_state(), Types.surface_target(), String.t() | nil, String.t(), String.t() ->
               Types.runtime_state()),
          required(:put_placeholder_views) =>
            (Types.runtime_state(), String.t(), String.t(), String.t() -> Types.runtime_state()),
          required(:merge_introspect) =>
            (Types.runtime_state() -> {Types.runtime_state(), Types.elm_introspect() | nil}),
          required(:append_reload_events) =>
            (Types.runtime_state(), String.t(), String.t() | nil, String.t(), String.t(), String.t() ->
               Types.runtime_state())
        }

  @spec apply(
          Types.runtime_state(),
          String.t() | nil,
          String.t(),
          String.t(),
          String.t(),
          ctx()
        ) :: Types.runtime_state()
  def apply(state, rel_path, source, reason, source_root, ctx)
      when is_map(state) and is_binary(source) and is_binary(reason) and is_binary(source_root) and
             is_map(ctx) do
    revision = ctx.compute_revision.(rel_path, source)
    path = rel_path || "unknown"
    target = ElmIntrospectSnapshot.target_key(source_root)

    state
    |> ctx.prepare_running_state.()
    |> revision_messages(revision, source_root)
    |> ctx.put_reload_fields.(target, rel_path, source, source_root)
    |> ctx.put_placeholder_views.(path, revision, source_root)
    |> then(fn st ->
      {next_state, intro_payload} = ctx.merge_introspect.(st)
      ctx.append_reload_events.(next_state, reason, rel_path, revision, source_root, intro_payload)
    end)
  end

  @spec put_source_fields(
          Types.runtime_state(),
          Types.surface_target(),
          String.t() | nil,
          String.t(),
          String.t()
        ) :: Types.runtime_state()
  def put_source_fields(state, target, rel_path, source, source_root)
      when target in [:watch, :companion, :phone] do
    state
    |> put_in([target, :model, "last_path"], rel_path)
    |> put_in([target, :model, "last_source"], source)
    |> put_in([target, :model, "source_root"], source_root)
  end

  def put_source_fields(state, _target, _rel_path, _source, _source_root), do: state

  @spec reload_pulse(Types.surface_target(), String.t()) :: String.t()
  def reload_pulse(:watch, "phone"), do: "PhoneSync"
  def reload_pulse(:companion, "phone"), do: "PhoneSync"
  def reload_pulse(:phone, "phone"), do: "PhoneHotReload"
  def reload_pulse(:watch, "protocol"), do: "ProtocolSync"
  def reload_pulse(:companion, "protocol"), do: "ProtocolHotReload"
  def reload_pulse(:phone, "protocol"), do: "ProtocolSync"
  def reload_pulse(_target, _source_root), do: "HotReload"

  @spec revision_messages(Types.runtime_state(), String.t(), String.t()) :: Types.runtime_state()
  def revision_messages(state, revision, source_root) when is_map(state) do
    state
    |> put_in([:watch, :last_message], reload_pulse(:watch, source_root))
    |> put_in([:watch, :model, "revision"], revision)
    |> put_in([:companion, :last_message], reload_pulse(:companion, source_root))
    |> put_in([:companion, :model, "revision"], revision)
    |> put_in([:phone, :last_message], reload_pulse(:phone, source_root))
    |> put_in([:phone, :model, "revision"], revision)
  end
end
