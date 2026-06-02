defmodule Ide.Debugger.CompileContract do
  @moduledoc """
  Compile-time debugger metadata contract (`debugger_contract.v1`).

  All Elm static analysis for the debugger must be produced here (or below via
  `ElmEx.DebuggerContract`) and attached at **compile ingest** —
  not re-derived in the IDE on hot reload.

  Shell storage:
  - `debugger_contract` — decoded map (preferred)
  - `debugger_contract_b64` — term-encoded artifact from `Ide.Compiler`
  - `elm_introspect` — legacy model/shell key (migrated to `debugger_contract` by `RuntimeArtifacts`; do not write)
  """

  alias ElmEx.DebuggerContract
  alias ElmEx.DebuggerContract.EffectsFromCoreIR
  alias ElmEx.Frontend.Project
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Types

  @contract_version "debugger_contract.v1"

  @type contract :: Types.elm_introspect()
  @type wire_snapshot :: %{optional(String.t()) => map()}

  @entry_candidates ~w(src/Main.elm Main.elm)

  @doc "Version string stored on each contract map."
  @spec version() :: String.t()
  def version, do: @contract_version

  @doc """
  Builds a contract map from in-memory Elm source.

  Prefer `build_for_project_dir/1` during compile; use this for tests and editor helpers.
  """
  @spec analyze_source(String.t(), String.t()) ::
          {:ok, wire_snapshot()} | {:error, Types.parse_error()}
  def analyze_source(source, virtual_path \\ "Main.elm")
      when is_binary(source) and is_binary(virtual_path) do
    case DebuggerContract.analyze_source(source, virtual_path,
           extra_source_roots: package_source_roots()
         ) do
      {:ok, snapshot} ->
        case DebuggerContract.contract_payload(snapshot) do
          %{} = contract -> {:ok, snapshot_from_contract(contract)}
          _ -> {:error, :parse_error}
        end

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Builds a contract from the watch (or phone) entry `Main.elm` under a compiler workspace root.
  """
  @spec build_for_project_dir(String.t()) ::
          {:ok, contract()} | {:error, :entry_not_found | :parse_error}
  def build_for_project_dir(project_dir) when is_binary(project_dir) do
    case build_from_project_dir(project_dir) do
      {:ok, contract} -> {:ok, contract}
      {:error, :entry_not_found} -> {:error, :entry_not_found}
      {:error, _} -> {:error, :parse_error}
    end
  end

  @doc """
  Builds a contract from an already-loaded `ElmEx.Frontend.Project` (same parse as IR lowering).
  """
  @spec build_from_project(Project.t()) ::
          {:ok, contract()} | {:error, :entry_not_found | :parse_error}
  def build_from_project(%Project{} = project) do
    build_from_project(project, nil)
  end

  @spec build_from_project(Project.t(), map() | nil) ::
          {:ok, contract()} | {:error, :entry_not_found | :parse_error}
  def build_from_project(%Project{} = project, core_ir) do
    case DebuggerContract.from_project(project, extra_source_roots: package_source_roots()) do
      {:ok, snapshot} ->
        case DebuggerContract.contract_payload(snapshot) do
          %{} = contract ->
            contract =
              if is_map(core_ir) do
                merge_core_ir_effects(contract, core_ir)
              else
                contract
              end

            {:ok, normalize_contract(contract)}

          _ ->
            {:error, :parse_error}
        end

      {:error, :entry_not_found} ->
        {:error, :entry_not_found}

      {:error, _} ->
        {:error, :parse_error}
    end
  end

  @spec build_from_project_dir(String.t()) ::
          {:ok, contract()} | {:error, :entry_not_found | :parse_error}
  defp build_from_project_dir(project_dir) do
    opts = [extra_source_roots: package_source_roots()]

    case DebuggerContract.from_project_dir(project_dir, opts) do
      {:ok, snapshot} ->
        case DebuggerContract.contract_payload(snapshot) do
          %{} = contract -> {:ok, normalize_contract(contract)}
          _ -> {:error, :parse_error}
        end

      {:error, :entry_not_found} = err ->
        err

      {:error, _} ->
        # Workspace without elm.json (ephemeral) — parse entry file only.
        case find_entry_source(project_dir) do
          {:ok, path, source} ->
            case analyze_source(source, Path.basename(path)) do
              {:ok, %{"debugger_contract" => contract}} -> {:ok, contract}
              {:error, _} -> {:error, :parse_error}
            end

          :error ->
            {:error, :entry_not_found}
        end
    end
  end

  @doc "Artifact fields for compile ingest (encoded contract + metadata)."
  @spec artifact_fields(contract()) :: Types.runtime_artifacts()
  def artifact_fields(%{} = contract) when is_map(contract) do
    %{
      "debugger_contract" => contract,
      "debugger_contract_b64" => encode(contract),
      "debugger_contract_version" => @contract_version
    }
  end

  def artifact_fields(_), do: %{}

  @spec encode(contract()) :: String.t()
  def encode(%{} = contract) when is_map(contract) do
    contract
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  @spec decode(String.t()) :: contract() | nil
  def decode(encoded) when is_binary(encoded) and encoded != "" do
    with {:ok, binary} <- Base.decode64(encoded),
         term when is_map(term) <- :erlang.binary_to_term(binary, [:safe]) do
      normalize_contract(term)
    else
      _ -> nil
    end
  end

  def decode(_), do: nil

  @doc """
  Reads the debugger contract from a surface shell or execution model.

  Prefers `debugger_contract` / `debugger_contract_b64` after `RuntimeArtifacts.normalize_contract_shell/1`.
  """
  @spec from_shell(RuntimeArtifacts.shell() | map()) :: contract() | nil
  def from_shell(shell) when is_map(shell) do
    shell = RuntimeArtifacts.normalize_contract_shell(shell)

    case Map.get(shell, "debugger_contract") || Map.get(shell, :debugger_contract) do
      contract when is_map(contract) ->
        normalize_contract(contract)

      _ ->
        case Map.get(shell, "debugger_contract_b64") || Map.get(shell, :debugger_contract_b64) do
          b64 when is_binary(b64) -> decode(b64)
          _ -> nil
        end
    end
  end

  def from_shell(_), do: nil

  @doc """
  Reads a debugger contract from compile/runtime artifact fields (map from `Ide.Compiler` or ingest).
  """
  @spec from_artifacts(map()) :: contract() | nil
  def from_artifacts(%{} = artifacts) when is_map(artifacts) do
    artifacts
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> from_shell()
  end

  def from_artifacts(_), do: nil

  @doc false
  @spec entrypoint_path?(String.t(), String.t() | nil) :: boolean()
  def entrypoint_path?("watch", rel_path) when is_binary(rel_path) do
    Path.basename(rel_path) == "Main.elm"
  end

  def entrypoint_path?("phone", rel_path) when is_binary(rel_path) do
    Path.basename(rel_path) in ["CompanionApp.elm", "Main.elm"]
  end

  def entrypoint_path?(_source_root, _rel_path), do: false

  @doc """
  Overlays subscription/cmd effect fields extracted from Core IR onto a project-derived contract.
  """
  @spec merge_core_ir_effects(contract(), map()) :: contract()
  def merge_core_ir_effects(%{} = contract, %{} = core_ir)
      when is_map(contract) and is_map(core_ir) do
    entry = default_entry_module_name(core_ir)
    effects = EffectsFromCoreIR.effect_fields(core_ir, entry)

    Enum.reduce(EffectsFromCoreIR.effect_field_keys(), contract, fn key, acc ->
      field = Atom.to_string(key)

      case {Map.get(acc, field), Map.get(effects, field)} do
        {existing, core} when existing in [nil, []] and is_list(core) and core != [] ->
          Map.put(acc, field, core)

        _ ->
          acc
      end
    end)
  end

  def merge_core_ir_effects(contract, _), do: contract

  @spec default_entry_module_name(map()) :: String.t()
  defp default_entry_module_name(core_ir) do
    core_ir
    |> EffectsFromCoreIR.modules_list()
    |> Enum.map(fn mod -> Map.get(mod, "name") || Map.get(mod, :name) end)
    |> Enum.find(&(&1 == "CompanionApp"))
    |> case do
      nil -> "Main"
      name -> name
    end
  end

  @spec snapshot_from_contract(contract()) :: wire_snapshot()
  defp snapshot_from_contract(%{} = contract) do
    %{
      "debugger_contract" => normalize_contract(contract),
      "contract_version" => @contract_version
    }
  end

  @spec normalize_contract(map()) :: contract()
  defp normalize_contract(%{} = contract) do
    contract
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.put("contract_version", Map.get(contract, "contract_version", @contract_version))
  end

  defp normalize_contract(_), do: %{"contract_version" => @contract_version}

  @spec find_entry_source(String.t()) :: {:ok, String.t(), String.t()} | :error
  @doc false
  @spec package_source_roots() :: [String.t()]
  def package_source_roots do
    [
      Ide.InternalPackages.pebble_elm_src_abs(),
      Ide.InternalPackages.pebble_companion_core_elm_src_abs(),
      Ide.InternalPackages.companion_protocol_elm_src_abs(),
      Ide.InternalPackages.elm_time_elm_src_abs(),
      Ide.InternalPackages.elm_random_elm_src_abs(),
      Ide.InternalPackages.shared_elm_abs()
    ]
  end

  defp find_entry_source(project_dir) do
    Enum.reduce_while(@entry_candidates, :error, fn rel, _ ->
      path = Path.join(project_dir, rel)

      if File.regular?(path) do
        {:halt, {:ok, path, File.read!(path)}}
      else
        {:cont, :error}
      end
    end)
  end
end
