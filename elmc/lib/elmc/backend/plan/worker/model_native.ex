defmodule Elmc.Backend.Plan.Worker.ModelNative do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{Host, SchemaRegistry, Util}
  alias Elmc.Backend.SizeProfile
  alias ElmEx.IR

  @struct_name "ElmcWorkerModelNative"

  @type field :: %{
          name: String.t(),
          c_name: String.t(),
          type: String.t(),
          c_type: String.t(),
          optional?: boolean()
        }

  @type layout :: %{
          module: String.t(),
          record: String.t(),
          fields: [field()]
        }

  @spec enabled?(map()) :: boolean()
  def enabled?(opts) when is_map(opts) do
    SizeProfile.size?(opts) and Map.get(opts, :native_worker_model, true) == true
  end

  @spec analyze(IR.t(), String.t(), map()) :: layout() | nil
  def analyze(%IR{} = ir, entry_module, opts) when is_map(opts) do
    if enabled?(opts) do
      registry = SchemaRegistry.build(ir)

      case model_record_name(ir, entry_module, registry) do
        nil ->
          nil

        {mod, name} ->
          case SchemaRegistry.record(registry, mod, name) do
            %{fields: fields} when map_size(fields) > 0 ->
              %{
                module: mod,
                record: name,
                fields: fields_to_native(fields)
              }

            _ ->
              nil
          end
      end
    else
      nil
    end
  end

  @spec typedef_c(layout()) :: String.t()
  def typedef_c(%{fields: fields}) do
    members =
      Enum.map_join(fields, "\n", fn field ->
        optional_prefix = if field.optional?, do: "  bool has_#{field.c_name};\n", else: ""
        optional_prefix <> "  #{field.c_type} #{field.c_name};"
      end)

    """
    typedef struct {
    #{members}
    } #{@struct_name};
    """
  end

  @spec sync_helpers_c(layout()) :: String.t()
  def sync_helpers_c(%{fields: fields}) do
    unpack_fields =
      Enum.with_index(fields)
      |> Enum.map_join("\n", fn {field, idx} ->
        case field.type do
          "Bool" ->
            "  native->#{field.c_name} = elmc_record_get_index_bool(record, #{idx}) != 0;"

          "Float" ->
            "  native->#{field.c_name} = (double)elmc_record_get_index_int(record, #{idx});"

          "Maybe Int" ->
            """
              native->has_#{field.c_name} = elmc_record_get_index(record, #{idx}) != elmc_maybe_nothing();
              native->#{field.c_name} = elmc_record_get_index_maybe_int(record, #{idx}, 0);
            """

          _ ->
            "  native->#{field.c_name} = elmc_record_get_index_int(record, #{idx});"
        end
      end)

    pack_fields =
      Enum.map_join(fields, "\n", fn field ->
        idx = field_index(fields, field.name)

        case field.type do
          "Bool" ->
            "  ElmcValue *f#{idx} = elmc_bool(native->#{field.c_name});"

          "Float" ->
            "  ElmcValue *f#{idx} = elmc_new_float_take(native->#{field.c_name});"

          "Maybe Int" ->
            """
              ElmcValue *f#{idx} = NULL;
              if (native->has_#{field.c_name}) {
                ElmcValue *inner = elmc_new_int_take(native->#{field.c_name});
                if (elmc_maybe_just(&f#{idx}, inner) != RC_SUCCESS) {
                  elmc_release(inner);
                  return RC_ERR_OUT_OF_MEMORY;
                }
              } else {
                f#{idx} = elmc_maybe_nothing();
              }
            """

          _ ->
            "  ElmcValue *f#{idx} = elmc_new_int_take(native->#{field.c_name});"
        end
      end)

    field_names =
      fields
      |> Enum.map(fn field -> "\"#{field.name}\"" end)
      |> Enum.join(", ")

    field_refs =
      fields
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {_field, idx} -> "f#{idx}" end)

    """
    static void elmc_worker_model_native_unpack(#{@struct_name} *native, ElmcValue *record) {
      if (!native || !record) return;
    #{unpack_fields}
    }

    static RC elmc_worker_model_native_box(ElmcValue **out, const #{@struct_name} *native) {
      if (!out || !native) return RC_ERR_INVALID_ARG;
    #{pack_fields}
      const char *field_names[] = { #{field_names} };
      ElmcValue *field_values[] = { #{field_refs} };
      return elmc_record_new(out, #{length(fields)}, field_names, field_values);
    }

    static ElmcValue *elmc_worker_model_boxed(const ElmcWorkerState *state) {
      if (!state) return NULL;
      if (state->model) return elmc_retain(state->model);
      ElmcValue *boxed = NULL;
      if (elmc_worker_model_native_box(&boxed, &state->model_native) != RC_SUCCESS) return NULL;
      return boxed;
    }
    """
  end

  defp model_record_name(%IR{} = ir, entry_module, registry) do
    with {:ok, update_decl} <- entry_decl(ir, entry_module, "update"),
         model_type <- model_param_type(update_decl),
         {mod, name} <- parse_record_type(model_type),
         true <- SchemaRegistry.flattenable?(registry, mod, name) do
      {mod, name}
    else
      _ -> nil
    end
  end

  defp model_param_type(%{type: type, args: [_, model | _]}) when is_binary(type) do
    case Host.function_arg_types(type) do
      [_msg, model_type | _] -> model_type
      _ -> model
    end
  end

  defp model_param_type(%{args: [_, model | _]}), do: model
  defp model_param_type(_), do: nil

  defp entry_decl(%IR{} = ir, entry_module, fun_name) do
    ir.modules
    |> Enum.find_value(:error, fn mod ->
      if mod.name == entry_module do
        Enum.find_value(mod.declarations, :error, fn decl ->
          if decl.kind == :function and decl.name == fun_name, do: {:ok, decl}, else: nil
        end)
      else
        nil
      end
    end)
  end

  defp parse_record_type(type) when is_binary(type) do
    type = Host.normalize_type_name(type)

    case String.split(type, ".", parts: 2) do
      [mod, name] -> {mod, name}
      [name] -> {"Main", name}
      _ -> nil
    end
  end

  defp fields_to_native(fields) do
    fields
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {name, type} ->
      type = Host.normalize_type_name(type)
      optional? = type == "Maybe Int"

      %{
        name: name,
        c_name: Util.safe_c_suffix(name),
        type: type,
        c_type: c_type_for(type),
        optional?: optional?
      }
    end)
  end

  defp c_type_for("Bool"), do: "bool"
  defp c_type_for("Float"), do: "double"
  defp c_type_for("Maybe Int"), do: "elmc_int_t"
  defp c_type_for(_), do: "elmc_int_t"

  defp field_index(fields, name) do
    fields
    |> Enum.find_index(&(&1.name == name))
    |> case do
      nil -> 0
      idx -> idx
    end
  end
end
