defmodule Elmc.Backend.CCodegen.LayoutSolver do
  @moduledoc false

  alias Elmc.Backend.CCodegen.BindingPlans
  alias Elmc.Backend.CCodegen.Fusion
  alias Elmc.Backend.CCodegen.ListIntRepr
  alias Elmc.Backend.CCodegen.ListRecordRepr
  alias Elmc.Backend.CCodegen.SchemaRegistry
  alias Elmc.Backend.CCodegen.StoragePlan
  alias Elmc.Backend.CCodegen.Types

  @type analysis_result :: %{
          param_plans: %{{String.t(), String.t(), String.t()} => StoragePlan.t()},
          field_plans: %{{String.t(), String.t(), String.t()} => StoragePlan.t()},
          binding_plans: %{{String.t(), String.t(), String.t()} => StoragePlan.t()}
        }

  @spec analyze(Types.function_decl_map(), SchemaRegistry.t() | nil) :: analysis_result()
  def analyze(decl_map, registry \\ nil) when is_map(decl_map) do
    Fusion.reset_caches!()
    registry = registry || Process.get(:elmc_schema_registry)
    ensure_record_alias_shapes()

    int = ListIntRepr.analyze(decl_map)
    float = ListIntRepr.analyze_float(decl_map)
    record = ListRecordRepr.analyze(decl_map, registry)
    bindings = BindingPlans.analyze(decl_map, registry)

    param_plans =
      merge_param_plans([
        legacy_param_map(int.param_repr),
        legacy_param_map(float.param_repr),
        record_param_map(record.param_repr, decl_map, registry)
      ])

    field_plans =
      int.field_repr
      |> legacy_param_map()
      |> Map.merge(legacy_param_map(float.field_repr))

    %{param_plans: param_plans, field_plans: field_plans, binding_plans: bindings}
  end

  defp legacy_param_map(legacy) do
    Map.new(legacy, fn {key, repr} -> {key, StoragePlan.from_legacy_repr(repr)} end)
  end

  defp record_param_map(legacy, decl_map, registry) do
    Map.new(legacy, fn {key, repr} ->
      elem = record_param_elem(key, decl_map, registry)
      {key, StoragePlan.from_record_repr(repr, elem)}
    end)
  end

  defp record_param_elem({mod, fun, arg}, decl_map, registry) do
    case Map.get(decl_map, {mod, fun}) do
      %{type: type, args: args} when is_binary(type) ->
        idx = Enum.find_index(args || [], &(&1 == arg))

        if idx do
          type
          |> Elmc.Backend.CCodegen.TypeParsing.function_arg_types()
          |> Enum.at(idx)
          |> record_elem_type(registry)
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp record_elem_type(type, registry) when is_binary(type) do
    type = Elmc.Backend.CCodegen.Host.normalize_type_name(type)

    with "List " <> elem_type <- type,
         elem_type = Elmc.Backend.CCodegen.Host.normalize_type_name(elem_type),
         {:ok, {mod, record}} <- parse_record_type(elem_type),
         true <- SchemaRegistry.all_native?(registry, mod, record) do
      {mod, record}
    else
      _ -> nil
    end
  end

  defp parse_record_type(type) do
    case String.split(type, ".", parts: 2) do
      [mod, record] -> {:ok, {mod, record}}
      [record] -> {:ok, {"Main", record}}
      _ -> :error
    end
  end

  defp merge_param_plans(maps) do
    Enum.reduce(maps, %{}, fn map, acc ->
      Map.merge(acc, map, fn _key, a, b ->
        StoragePlan.consolidate([a, b])
      end)
    end)
  end

  @spec param_plan(String.t(), String.t(), String.t()) :: StoragePlan.t()
  def param_plan(module, fun, arg_name)
      when is_binary(module) and is_binary(fun) and is_binary(arg_name) do
    case Process.get(:elmc_storage_plans) do
      %{param_plans: plans} ->
        Map.get(plans, {module, fun, arg_name}, StoragePlan.mixed())

      _ ->
        ListIntRepr.param_repr(module, fun, arg_name) |> StoragePlan.from_legacy_repr()
    end
  end

  @spec binding_plan(String.t(), String.t(), String.t()) :: StoragePlan.t() | nil
  def binding_plan(module, fun, name),
    do: BindingPlans.binding_plan(module, fun, name)

  @spec field_plan(String.t(), String.t(), String.t()) :: StoragePlan.t()
  def field_plan(module, record, field)
      when is_binary(module) and is_binary(record) and is_binary(field) do
    case Process.get(:elmc_storage_plans) do
      %{field_plans: plans} ->
        Map.get(plans, {module, record, field}, StoragePlan.mixed())

      _ ->
        StoragePlan.mixed()
    end
  end

  @spec expr_plan(Types.ir_expr(), Types.function_decl_map(), keyword()) :: StoragePlan.t()
  def expr_plan(expr, decl_map, opts \\ []) when is_map(decl_map) do
    storage = Process.get(:elmc_storage_plans, %{param_plans: %{}, field_plans: %{}})

    param_repr =
      storage
      |> Map.get(:param_plans, %{})
      |> Map.new(fn {key, plan} -> {key, StoragePlan.to_legacy_repr(plan)} end)

    repr =
      ListIntRepr.expr_repr(expr, decl_map,
        Keyword.merge(opts, [param_repr: param_repr])
      )

    StoragePlan.from_legacy_repr(repr)
  end

  @spec loop_repr(String.t(), String.t(), String.t()) :: StoragePlan.loop_repr()
  def loop_repr(module, fun, arg_name) do
    module
    |> param_plan(fun, arg_name)
    |> StoragePlan.loop_repr()
  end

  @doc """
  Loop representation for boxed list walks from IR (params, literals, call results).
  """
  @spec list_loop_repr_from_expr(Types.ir_expr(), map()) ::
          :int_list | :float_list | :record_seq | :native_linked | :cons | :dual
  def list_loop_repr_from_expr(expr, env) do
    decl_map = Map.get(env, :__program_decls__, %{})
    module = Map.get(env, :__module__, "Main")
    fun = Map.get(env, :__function_name__, "")

    plan =
      case expr do
        %{op: :var, name: name} when is_binary(name) ->
          param_plan(module, fun, name)

        _ ->
          expr_plan(expr, decl_map)
      end

    codegen_loop_repr(plan)
  end

  @spec codegen_loop_repr(StoragePlan.t()) ::
          :int_list | :float_list | :record_seq | :native_linked | :cons | :dual
  def codegen_loop_repr(plan) do
    case StoragePlan.loop_repr(plan) do
      :compact -> :int_list
      :float_list -> :float_list
      :record_seq -> :record_seq
      :native_linked -> :native_linked
      :cons -> :cons
      :dual -> if StoragePlan.int_list_dual_eligible?(plan), do: :dual, else: :cons
    end
  end

  @spec legacy_param_repr(String.t(), String.t(), String.t()) :: ListIntRepr.repr()
  def legacy_param_repr(module, fun, arg_name) do
    module
    |> param_plan(fun, arg_name)
    |> StoragePlan.to_legacy_repr()
  end

  defp ensure_record_alias_shapes do
    if Process.get(:elmc_record_alias_shapes) == nil do
      shapes =
        Process.get(:elmc_record_field_types, %{})
        |> Enum.map(fn {{mod, record}, fields} ->
          names =
            Enum.map(fields, fn
              {name, _type} when is_binary(name) -> name
              name when is_binary(name) -> name
              _ -> nil
            end)
            |> Enum.reject(&is_nil/1)

          {{mod, record}, names}
        end)
        |> Map.new()

      if map_size(shapes) > 0 do
        Process.put(:elmc_record_alias_shapes, shapes)
      end
    end
  end
end
