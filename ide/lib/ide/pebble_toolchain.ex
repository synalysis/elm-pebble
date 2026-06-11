defmodule Ide.PebbleToolchain do
  @moduledoc """
  Boundary for Pebble SDK and emulator command execution.
  """

  alias Ide.PebbleToolchain.{Build, Command, Companion, Emulator, Package, Types}

  @type project_slug :: Types.project_slug()
  @type opts :: Types.opts()
  @type wire_input :: Types.wire_input()
  @type command_result :: Types.command_result()
  @type package_result :: Types.package_result()
  @type pebble_opts :: Types.pebble_opts()
  @type toolchain_error :: Types.toolchain_error()
  @type pebble_package :: Types.pebble_package()
  @type pebble_media_entry :: Types.pebble_media_entry()
  @type elmc_compile_opts :: Types.elmc_compile_opts()
  @type elmc_compile_result :: Types.elmc_compile_result()
  @type emulator_control_params :: Types.emulator_control_params()
  @type core_ir_expr :: Types.core_ir_expr()

  @callback build(project_slug(), opts()) :: {:ok, command_result()} | {:error, toolchain_error()}
  @callback package(project_slug(), opts()) ::
              {:ok, package_result()} | {:error, toolchain_error()}
  @callback publish(project_slug(), opts()) ::
              {:ok, command_result()} | {:error, toolchain_error()}
  @callback run_emulator(project_slug(), opts()) ::
              {:ok, command_result()} | {:error, toolchain_error()}
  @callback stop_emulator(project_slug(), opts()) ::
              {:ok, command_result()} | {:error, toolchain_error()}
  @callback run_emulator_control(project_slug(), String.t(), emulator_control_params()) ::
              {:ok, command_result()} | {:error, toolchain_error()}
  @callback run_screenshot(project_slug(), String.t(), String.t()) ::
              {:ok, command_result()} | {:error, toolchain_error()}

  defdelegate build(project_slug, opts), to: Build
  defdelegate package(project_slug, opts), to: Package
  defdelegate publish(project_slug, opts), to: Package
  defdelegate run_emulator(project_slug, opts), to: Emulator
  defdelegate stop_emulator(project_slug, opts \\ []), to: Emulator
  defdelegate emulator_logs_snapshot(emulator_target, cwd, seconds), to: Emulator
  defdelegate run_emulator_control(project_slug, emulator_target, params), to: Emulator
  defdelegate run_screenshot(project_slug, output_path, emulator_target), to: Emulator
  defdelegate supported_emulator_targets(), to: Emulator
  defdelegate template_app_root_path(), to: Package
  defdelegate infer_package_target_type(project_root, fallback), to: Package
  defdelegate companion_index_js_for_preferences(preferences_schema), to: Companion
  defdelegate deterministic_app_uuid(slug), to: Package
  defdelegate elm_bin(), to: Command
end
