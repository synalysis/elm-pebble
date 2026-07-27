defmodule Elmc.Test.RcTrackMatrix do
  @moduledoc false

  @matrix_path Path.expand("../../docs/CODEGEN_COVERAGE_MATRIX.md", __DIR__)
  @special_values_dir Path.expand("../../lib/elmc/backend/c_codegen/special_values", __DIR__)

  @elm_core_prefixes ~w(
    Basics Bitwise List Maybe Result String Char Tuple Dict Set Array Debug Task Process
  )

  @probe_exceptions %{
    "Tuple.pair" => "probePair",
    "List.reverse" => "probeReverseList",
    "Process.spawn" => "probeSpawn",
    "Process.sleep" => "probeSleep",
    "Process.kill" => "probeKill"
  }

  @matrix_probe_exceptions %{
    "Basics" => %{"IsNan" => "Basics.isNaN"},
    "List" => %{"ReverseList" => "List.reverse"},
    "Tuple" => %{"Pair" => "Tuple.pair"},
    "Task" => %{
      "Spawn" => "Process.spawn",
      "Sleep" => "Process.sleep",
      "Kill" => "Process.kill"
    }
  }

  @variant_probes %{
    "List" => ~w(probeConsChain probeAppendChain),
    "Dict" => ~w(probeToListResult probeInsertAlias),
    "Set" => ~w(probeToListResult),
    "Array" => ~w(probeSetAlias probeToListResult),
    "Maybe" => ~w(probeWithDefaultNothing probeMapNothing probeAndThenNothing),
    "Result" => ~w(probeMapErr probeWithDefaultErr probeAndThenErr),
    "String" => ~w(probeSplitList probeToListResult)
  }

  @heap_result_probes %{
    "List" => ~w(probeReverseList),
    "Dict" => ~w(probeToListResult),
    "Set" => ~w(probeToListResult),
    "Array" => ~w(probeToListResult),
    "String" => ~w(probeSplitList probeToListResult)
  }

  @stress_probes [
    {"RcTrackListProbe", "fixtures/rc_track_list_project", "probeAppend"},
    {"RcTrackListProbe", "fixtures/rc_track_list_project", "probeConcatMap"},
    {"RcTrackDictProbe", "fixtures/rc_track_dict_project", "probeInsert"},
    {"RcTrackDictProbe", "fixtures/rc_track_dict_project", "probeUnion"},
    {"RcTrackArrayProbe", "fixtures/rc_track_array_project", "probeSet"},
    {"RcTrackArrayProbe", "fixtures/rc_track_array_project", "probePush"},
    {"RcTrackStringProbe", "fixtures/rc_track_string_project", "probeAppend"},
    {"RcTrackStringProbe", "fixtures/rc_track_string_project", "probeSplit"},
    {"RcTrackTupleProbe", "fixtures/rc_track_tuple_project", "probeMapBoth"},
    {"RcTrackRecordUpdateProbe", "fixtures/rc_track_record_update_project", "probeChainedUpdate"},
    {"RcTrackListProbe", "fixtures/rc_track_list_project", "probeAppendChain"},
    {"RcTrackDictProbe", "fixtures/rc_track_dict_project", "probeInsertAlias"},
    {"RcTrackArrayProbe", "fixtures/rc_track_array_project", "probeSetAlias"},
    {"RcTrackStringProbe", "fixtures/rc_track_string_project", "probeSplitList"},
    {"RcTrackListProbe", "fixtures/rc_track_list_project", "probeConsChain"}
  ]

  @registry %{
    "Basics" => %{
      module: "RcTrackBasicsProbe",
      fixture: "fixtures/rc_track_basics_project",
      probes: ~w(
        probeMax probeMin probeClamp probeModBy probeIdentity probeAlways probeNot
        probeNegate probeAbs probeToFloat probeRound probeFloor probeCeiling probeTruncate
        probeRemainderBy probeXor probeCompare probeSqrt probeSin probeCos probeTan
        probeAsin probeAcos probeAtan probeAtan2 probeDegrees probeRadians probeTurns
        probeLogBase probeIsNan probeIsInfinite probeFromPolar probeToPolar
      )
    },
    "Bitwise" => %{
      module: "RcTrackBitwiseProbe",
      fixture: "fixtures/rc_track_bitwise_project",
      probes: ~w(
        probeAnd probeOr probeXor probeComplement probeShiftLeftBy probeShiftRightBy
        probeShiftRightZfBy
      )
    },
    "List" => %{
      module: "RcTrackListProbe",
      fixture: "fixtures/rc_track_list_project",
      probes:
        ~w(
          probeIsEmpty probeLength probeHead probeTail probeReverse probeMember
          probeMap probeFilter probeFoldl probeFoldr probeAppend probeConcat
          probeConcatMap probeIndexedMap probeFilterMap probeSum probeProduct
          probeMaximum probeMinimum probeAny probeAll probeSort probeSortBy
          probeSortWith probeSingleton probeRange probeRepeat probeTake probeDrop
          probePartition probeUnzip probeIntersperse probeMap2 probeMap3 probeMap4
          probeMap5 probeCons
          probeReverseList probeConsChain probeAppendChain
        )
    },
    "Maybe" => %{
      module: "RcTrackMaybeProbe",
      fixture: "fixtures/rc_track_maybe_project",
      probes:
        ~w(
          probeWithDefault probeMap probeMap2 probeAndThen probeWithDefaultNothing
          probeMapNothing probeAndThenNothing
        )
    },
    "Result" => %{
      module: "RcTrackResultProbe",
      fixture: "fixtures/rc_track_result_project",
      probes:
        ~w(
          probeMap probeMapError probeAndThen probeWithDefault probeToMaybe probeFromMaybe
          probeMapErr probeWithDefaultErr probeAndThenErr
        )
    },
    "String" => %{
      module: "RcTrackStringProbe",
      fixture: "fixtures/rc_track_string_project",
      probes:
        ~w(
          probeAppend probeIsEmpty probeLength probeReverse probeRepeat probeReplace
          probeFromInt probeToInt probeFromFloat probeToFloat probeToUpper probeToLower
          probeTrim probeTrimLeft probeTrimRight probeContains probeStartsWith probeEndsWith
          probeSplit probeJoin probeWords probeLines probeSlice probeLeft probeRight
          probeDropLeft probeDropRight probeCons probeUncons probeToList probeFromList
          probeFromChar probePad probePadLeft probePadRight probeMap probeFilter probeFoldl
          probeFoldr probeAny probeAll probeIndexes probeSplitList probeToListResult
        )
    },
    "Char" => %{
      module: "RcTrackCharProbe",
      fixture: "fixtures/rc_track_char_project",
      probes: ~w(
        probeToCode probeFromCode probeIsUpper probeIsLower probeIsAlpha probeIsAlphaNum
        probeIsDigit probeIsOctDigit probeIsHexDigit probeToUpper probeToLower
      )
    },
    "Tuple" => %{
      module: "RcTrackTupleProbe",
      fixture: "fixtures/rc_track_tuple_project",
      probes: ~w(probeFirst probeSecond probePair probeMapFirst probeMapSecond probeMapBoth)
    },
    "Dict" => %{
      module: "RcTrackDictProbe",
      fixture: "fixtures/rc_track_dict_project",
      probes:
        ~w(
          probeEmpty probeSingleton probeFromList probeInsert probeGet probeMember probeSize
          probeRemove probeIsEmpty probeKeys probeValues probeToList probeMap probeFoldl
          probeFoldr probeFilter probePartition probeUnion probeIntersect probeDiff
          probeMerge probeUpdate probeToListResult probeInsertAlias
        )
    },
    "Set" => %{
      module: "RcTrackSetProbe",
      fixture: "fixtures/rc_track_set_project",
      probes:
        ~w(
          probeEmpty probeSingleton probeFromList probeInsert probeMember probeSize
          probeRemove probeIsEmpty probeToList probeUnion probeIntersect probeDiff
          probeMap probeFoldl probeFoldr probeFilter probePartition probeToListResult
        )
    },
    "Array" => %{
      module: "RcTrackArrayProbe",
      fixture: "fixtures/rc_track_array_project",
      probes:
        ~w(
          probeEmpty probeFromList probeLength probeGet probeSet probePush probeInitialize
          probeRepeat probeIsEmpty probeToList probeToIndexedList probeMap probeIndexedMap
          probeFoldl probeFoldr probeFilter probeAppend probeSlice probeSetAlias
          probeToListResult
        )
    },
    "Debug" => %{
      module: "RcTrackDebugProbe",
      fixture: "fixtures/rc_track_debug_project",
      probes: ~w(probeLog probeTodo probeToString)
    },
    "Task" => %{
      module: "RcTrackTaskProcessProbe",
      fixture: "fixtures/rc_track_task_process_project",
      probes: ~w(probeSucceed probeFail probeSpawn probeSleep probeKill)
    }
  }

  @spec matrix_path() :: String.t()
  def matrix_path, do: @matrix_path

  @spec core_modules() :: [String.t()]
  def core_modules, do: Map.keys(@registry)

  @spec registry() :: Elmc.TestSupport.Types.rc_registry()
  def registry, do: @registry

  @spec registry_entry(String.t()) :: Elmc.TestSupport.Types.rc_registry_entry() | nil
  def registry_entry(module_name), do: Map.get(@registry, module_name)

  @spec stress_probes() :: [{String.t(), String.t(), String.t()}]
  def stress_probes, do: @stress_probes

  @spec variant_probes(String.t()) :: [String.t()]
  def variant_probes(module_name), do: Map.get(@variant_probes, module_name, [])

  @spec heap_result_probes(String.t()) :: [String.t()]
  def heap_result_probes(module_name), do: Map.get(@heap_result_probes, module_name, [])

  @spec int_probes_for(String.t()) :: [String.t()]
  def int_probes_for(module_name) do
    %{probes: probes} = registry_entry(module_name)
    probes -- heap_result_probes(module_name)
  end

  @spec core_module_names() :: [String.t()]
  def core_module_names do
    parsed()
    |> Map.keys()
    |> Enum.sort()
  end

  @spec functions_for(String.t()) :: [String.t()]
  def functions_for(module_name) do
    parsed()
    |> Map.get(module_name, [])
    |> Enum.sort()
  end

  @spec all_core_functions() :: [String.t()]
  def all_core_functions do
    parsed()
    |> Map.values()
    |> List.flatten()
    |> Enum.sort()
  end

  @spec matrix_functions_for(String.t()) :: [String.t()]
  def matrix_functions_for(module_name), do: functions_for(module_name)

  @spec probe_name(String.t()) :: String.t()
  def probe_name(qualified) do
    Map.get(@probe_exceptions, qualified) || default_probe_name(qualified)
  end

  @spec matrix_probe_exceptions(String.t()) :: Elmc.TestSupport.Types.rc_probe_exceptions()
  def matrix_probe_exceptions(module_name) do
    Map.get(@matrix_probe_exceptions, module_name, %{})
  end

  @spec assert_core_ex_alignment!() :: :ok
  def assert_core_ex_alignment! do
    matrix = all_core_functions()
    core_ex = core_ex_functions()

    missing_in_core =
      matrix
      |> Enum.reject(&(&1 in core_ex))
      |> Enum.sort()

    if missing_in_core != [] do
      raise "CODEGEN_COVERAGE_MATRIX documents elm/core functions missing from special_values handlers: #{inspect(missing_in_core)}"
    end

    :ok
  end

  defp parsed do
    parse_matrix_file!()
  end

  defp parse_matrix_file! do
    content = File.read!(@matrix_path)

    content
    |> String.split("### elm/core:")
    |> Enum.drop(1)
    |> Enum.reduce(%{}, fn section, acc ->
      case String.split(section, "\n", parts: 2) do
        [header_line, table_rest] ->
          module_name = header_module_name(header_line)
          table_body = section_table_body(table_rest)
          functions = parse_section_functions(table_body)
          Map.put(acc, module_name, functions)

        [header_line] ->
          module_name = header_module_name(header_line)
          Map.put(acc, module_name, [])
      end
    end)
  end

  defp section_table_body(body) when is_binary(body) do
    case String.split(body, "\n### ", parts: 2) do
      [table, _rest] -> table
      [table] -> table
    end
  end

  defp header_module_name(line) do
    case String.trim(line) do
      "Task & Process" -> "Task"
      name -> name
    end
  end

  defp parse_section_functions(section) do
    section
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^\| `([^`]+)`(?: \(λ\))? \| [^|]+ \| (Real|Stub|Gap) \|/, line) do
        [_, function, "Real"] ->
          [function]

        _ ->
          []
      end
    end)
  end

  defp default_probe_name(qualified) do
    [_prefix, suffix] = String.split(qualified, ".", parts: 2)
    "probe" <> suffix
  end

  defp core_ex_functions do
    dir = @special_values_dir
    root_files = dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".ex"))
    stdlib_files =
      case File.ls(Path.join(dir, "stdlib")) do
        {:ok, files} -> Enum.map(files, &Path.join("stdlib", &1))
        {:error, _} -> []
      end

    (root_files ++ stdlib_files)
    |> Enum.filter(&String.ends_with?(&1, ".ex"))
    |> Enum.flat_map(fn file ->
      path = Path.join(dir, file)
      content = File.read!(path)

      Regex.scan(~r/def special_value_from_target\("([^"]+)"/, content)
      |> Enum.map(fn [_, target] -> target end)
    end)
    |> Enum.filter(fn target ->
      Enum.any?(@elm_core_prefixes, &String.starts_with?(target, &1 <> "."))
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
