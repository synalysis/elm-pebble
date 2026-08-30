defmodule Elmc.Backend.CCodegen.DirectRender.PlanStreamEmit do
  @moduledoc """
  Plan SSA scene-stream body emission for DirectRender `*_commands_append` helpers.
  """
  alias Elmc.Backend.C.Lower.Frame
  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.CCodegen.Types, as: Types
  alias Elmc.Backend.Plan.Stream
  alias Elmc.Backend.Plan.Verify

  @spec try_emit_body(
          Types.function_declaration(),
          String.t(),
          Types.function_decl_map()
        ) :: {:ok, String.t()} | {:error, :ineligible | {:stream_failed, term()}}
  def try_emit_body(decl, module_name, decl_map) do
    prev_decls = Process.get(:elmc_program_decls)
    Process.put(:elmc_program_decls, decl_map)

    try do
      cond do
        Stream.eligible_expr?(Map.get(decl, :expr), decl_map, module_name) and
            Stream.pipeline_expr?(Map.get(decl, :expr), decl_map, module_name) ->
          with {:ok, plan} <- Stream.lower_function(decl, module_name, decl_map),
               :ok <- Verify.run(plan),
               {:ok, body} <- emit_plan_core(plan) do
            {:ok, body}
          else
            :unsupported -> {:error, {:stream_failed, :unsupported}}
            :error -> {:error, {:stream_failed, :emit_error}}
            {:error, reason} -> {:error, {:stream_failed, reason}}
            other -> {:error, {:stream_failed, other}}
          end

        true ->
          {:error, :ineligible}
      end
    rescue
      error ->
        if Stream.eligible_expr?(Map.get(decl, :expr), decl_map, module_name) and
             Stream.pipeline_expr?(Map.get(decl, :expr), decl_map, module_name) do
          {:error, {:stream_failed, {:exception, Exception.message(error)}}}
        else
          {:error, :ineligible}
        end
    after
      if prev_decls == nil do
        Process.delete(:elmc_program_decls)
      else
        Process.put(:elmc_program_decls, prev_decls)
      end
    end
  end

  defp emit_plan_core(plan) do
    prev_writer = Process.get(:elmc_direct_scene_writer)

    try do
      Process.put(:elmc_direct_scene_writer, true)
      {core, slots} = CLowerFunction.emit_core_with_slots(plan)
      slot_count = map_size(slots) |> then(fn n -> if n == 0, do: 0, else: Enum.max(Map.values(slots)) + 1 end)

      owned_decl =
        if slot_count > 0 do
          Frame.owned_declaration(plan, slots) <> "\n"
        else
          ""
        end

      epilogue =
        if slot_count > 0 do
          indices = Enum.to_list(0..(slot_count - 1))
          "\n" <> Frame.epilogue_release(indices, slot_count)
        else
          ""
        end

      {:ok, String.trim_trailing(owned_decl <> core <> epilogue) <> "\n"}
    rescue
      _ -> :error
    after
      if prev_writer == nil do
        Process.delete(:elmc_direct_scene_writer)
      else
        Process.put(:elmc_direct_scene_writer, prev_writer)
      end
    end
  end
end
