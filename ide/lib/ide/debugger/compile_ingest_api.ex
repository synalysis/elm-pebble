defmodule Ide.Debugger.CompileIngestApi do
  @moduledoc false

  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.CompileIngestApply
  alias Ide.Debugger.Types

  @type runtime_state :: Types.RuntimeState.t() | Types.RuntimeState.wire_map()

  @spec ingest_elmc_check(String.t(), Types.compile_ingest_attrs()) :: {:ok, runtime_state()}
  def ingest_elmc_check(project_slug, attrs) when is_binary(project_slug) and is_map(attrs) do
    AgentSession.mutate_ingest(project_slug, &CompileIngestApply.check(&1, attrs, &2))
  end

  @spec ingest_elmc_compile(String.t(), Types.compile_ingest_attrs()) :: {:ok, runtime_state()}
  def ingest_elmc_compile(project_slug, attrs) when is_binary(project_slug) and is_map(attrs) do
    AgentSession.mutate_ingest(project_slug, &CompileIngestApply.compile(&1, attrs, &2))
  end

  @spec ingest_elmc_manifest(String.t(), Types.compile_ingest_attrs()) :: {:ok, runtime_state()}
  def ingest_elmc_manifest(project_slug, attrs) when is_binary(project_slug) and is_map(attrs) do
    AgentSession.mutate_ingest(project_slug, &CompileIngestApply.manifest(&1, attrs, &2))
  end
end
