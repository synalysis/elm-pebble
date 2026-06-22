defmodule Ide.Debugger.RuntimeInitApply do
  @moduledoc false

  alias Ide.Debugger.DebuggerContractSnapshot
  alias Ide.Debugger.InitSurfaceEffects
  alias Ide.Debugger.Surface
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.Types

  @type ctx :: %{
          required(:snapshot_apply) => DebuggerContractSnapshot.apply_ctx(),
          required(:init_surface_effects) => InitSurfaceEffects.ctx()
        }

  @spec ensure_applied(Types.runtime_state(), Types.surface_target(), ctx()) ::
          Types.runtime_state()
  def ensure_applied(state, target, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    if needs_init?(state, target) do
      state
      |> apply_init_snapshot(target, ctx.snapshot_apply)
      |> InitSurfaceEffects.apply_all(target, ctx.init_surface_effects)
    else
      state
    end
  end

  def ensure_applied(state, _target, _ctx), do: state

  @spec needs_init?(Types.runtime_state(), Types.surface_target()) :: boolean()
  defp needs_init?(state, target) when is_map(state) and target in [:watch, :companion, :phone] do
    canonical = canonical_init_target(target)

    SurfaceCompileArtifacts.surface_has_versioned_runtime_artifacts?(state, canonical) and
      not init_executed?(state, canonical)
  end

  defp needs_init?(_state, _target), do: false

  @spec init_executed?(Types.runtime_state(), Types.surface_target()) :: boolean()
  defp init_executed?(state, target) when is_map(state) do
    canonical = canonical_init_target(target)

    state
    |> Surface.from_state(canonical)
    |> Surface.app_model()
    |> Map.get("runtime_execution_mode") == "runtime_executed"
  end

  @spec canonical_init_target(Types.surface_target()) :: Types.surface_target()
  defp canonical_init_target(target), do: SurfaceTargets.normalize(target)

  @spec apply_init_snapshot(
          Types.runtime_state(),
          Types.surface_target(),
          DebuggerContractSnapshot.apply_ctx()
        ) :: Types.runtime_state()
  defp apply_init_snapshot(state, target, snapshot_ctx)
       when is_map(state) and is_map(snapshot_ctx) do
    target = canonical_init_target(target)
    surface = Surface.from_state(state, target)
    ei = Surface.introspect(surface)

    if is_map(ei) and map_size(ei) > 0 do
      model = Surface.app_model(surface)
      source = Map.get(model, "last_source") || ""
      rel_path = Map.get(model, "last_path") || default_rel_path(target)

      DebuggerContractSnapshot.apply(state, ei, target, source, rel_path, snapshot_ctx)
    else
      state
    end
  end

  defp apply_init_snapshot(state, _target, _snapshot_ctx), do: state

  @spec default_rel_path(Types.surface_target()) :: String.t()
  defp default_rel_path(:watch), do: "src/Main.elm"
  defp default_rel_path(:companion), do: "src/CompanionApp.elm"
end
