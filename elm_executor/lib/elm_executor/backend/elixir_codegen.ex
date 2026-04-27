defmodule ElmExecutor.Backend.ElixirCodegen do
  @moduledoc """
  Emits Elixir modules from normalized ElmEx CoreIR.

  The generated code is intentionally deterministic and preserves an execution
  contract that can be loaded by both IDE and generic host runtimes.
  """

  alias ElmEx.CoreIR

  @spec write_project(CoreIR.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def write_project(%CoreIR{} = core_ir, out_dir, opts) when is_binary(out_dir) and is_list(opts) do
    entry_module = Keyword.get(opts, :entry_module, "Main")
    mode = Keyword.get(opts, :mode, :library)
    module_name = generated_module_name(entry_module, core_ir)
    file_path = Path.join([out_dir, "elixir", Macro.underscore(module_name) <> ".ex"])

    File.mkdir_p!(Path.dirname(file_path))
    File.write!(file_path, render_module(module_name, core_ir, entry_module, mode))
    write_runtime_support(out_dir)
    write_manifest(out_dir, module_name, entry_module, mode, core_ir)
  end

  @spec generated_module_name(term(), term()) :: term()
  defp generated_module_name(entry_module, %CoreIR{} = core_ir) when is_binary(entry_module) do
    suffix = String.slice(core_ir.deterministic_sha256, 0, 8)
    "ElmExecutor.Generated." <> String.replace(entry_module, ".", "_") <> "_" <> suffix
  end

  @spec render_module(term(), term(), term(), term()) :: term()
  defp render_module(module_name, %CoreIR{} = core_ir, entry_module, mode) do
    encoded_core_ir = Base.encode64(:erlang.term_to_binary(core_ir))

    """
    defmodule #{module_name} do
      @moduledoc false

      @encoded_core_ir "#{encoded_core_ir}"
      @entry_module "#{entry_module}"
      @mode #{inspect(mode)}

      @spec compiler_metadata() :: term()
      def compiler_metadata do
        %{
          engine: "elm_executor_runtime_v1",
          compiler: "elm_executor",
          contract: "elm_executor.runtime_executor.v1",
          entry_module: @entry_module,
          mode: @mode
        }
      end

      @spec core_ir() :: term()
      def core_ir do
        @encoded_core_ir
        |> Base.decode64!()
        |> :erlang.binary_to_term()
      end

      @spec debugger_execute(term()) :: term()
      def debugger_execute(request) when is_map(request) do
        ElmExecutor.Runtime.Executor.execute(request, core_ir(), compiler_metadata())
      end
    end
    """
  end

  @spec write_runtime_support(term()) :: term()
  defp write_runtime_support(out_dir) do
    runtime_dir = Path.join([out_dir, "elixir"])
    File.mkdir_p!(runtime_dir)

    support_file = Path.join(runtime_dir, "elm_executor_bootstrap.ex")

    File.write!(
      support_file,
      """
      defmodule ElmExecutor.Generated.RuntimeBootstrap do
        @moduledoc false

        @spec contract() :: term()
        def contract, do: "elm_executor.runtime_executor.v1"
      end
      """
    )

    :ok
  end

  @spec write_manifest(term(), term(), term(), term(), term()) :: term()
  defp write_manifest(out_dir, module_name, entry_module, mode, %CoreIR{} = core_ir) do
    manifest = %{
      "compiler" => "elm_executor",
      "contract" => "elm_executor.runtime_executor.v1",
      "engine" => "elm_executor_runtime_v1",
      "entry_module" => entry_module,
      "generated_module" => module_name,
      "mode" => to_string(mode),
      "core_ir_version" => core_ir.version,
      "core_ir_sha256" => core_ir.deterministic_sha256
    }

    manifest_path = Path.join([out_dir, "elixir", "elm_executor_manifest.json"])
    File.write!(manifest_path, Jason.encode!(manifest, pretty: true))
    :ok
  end
end
