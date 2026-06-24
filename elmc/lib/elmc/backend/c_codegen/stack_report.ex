defmodule Elmc.Backend.CCodegen.StackReport do
  @moduledoc false

  alias Elmc.Backend.CCodegen.LinkedBinaryReport
  alias Elmc.Backend.CCodegen.StackEstimate
  alias Elmc.Backend.CCodegen.Types.LinkedBinary, as: LinkedBinaryTypes

  @spec enrich_file(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def enrich_file(stack_report_path, app_root, opts \\ []) when is_binary(stack_report_path) do
    with {:ok, contents} <- File.read(stack_report_path),
         {:ok, report} <- Jason.decode(contents),
         {:ok, linked} <- LinkedBinaryReport.from_app_build(app_root, opts) do
      report
      |> StackEstimate.put_linked_binary(linked)
      |> Jason.encode!(pretty: true)
      |> then(&File.write(stack_report_path, &1))
    else
      {:error, :map_not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec enrich_from_pebble_build(String.t(), keyword()) :: :ok | {:error, term()}
  def enrich_from_pebble_build(app_root, opts \\ []) when is_binary(app_root) do
    stack_report_path = Path.join(app_root, "src/c/elmc/elmc_stack_report.json")

    if File.regular?(stack_report_path) do
      enrich_file(stack_report_path, app_root, opts)
    else
      :ok
    end
  end

  @spec flash_detail(LinkedBinaryTypes.wire_map()) :: String.t() | nil
  def flash_detail(%{"available" => true} = linked) do
    text =
      case Map.get(linked, "elf_size") do
        %{"text" => bytes} when is_integer(bytes) -> bytes
        _ -> nil
      end

    elmc_bytes = Map.get(linked, "elmc_text_bytes")

    cond do
      is_integer(text) and is_integer(elmc_bytes) ->
        "flash text=#{text} B, elmc symbols≈#{elmc_bytes} B"

      is_integer(text) ->
        "flash text=#{text} B"

      is_integer(elmc_bytes) ->
        "elmc symbols≈#{elmc_bytes} B"

      true ->
        nil
    end
  end

  def flash_detail(_), do: nil

  @spec read_linked_binary(String.t()) :: LinkedBinaryTypes.wire_map() | nil
  def read_linked_binary(stack_report_path) when is_binary(stack_report_path) do
    with {:ok, contents} <- File.read(stack_report_path),
         {:ok, %{"code_size_indicators" => %{"linked_binary" => linked}}} <- Jason.decode(contents),
         true <- is_map(linked) do
      linked
    else
      _ -> nil
    end
  end

  def read_linked_binary(_), do: nil
end
