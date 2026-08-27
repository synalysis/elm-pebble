defmodule Elmc.TestSupport.GeneratedCLint do
  @moduledoc """
  Cheap structural checks on generated `elmc_generated.c`.

  Host `cc` typecheck is the ground truth for undeclared identifiers. This lint
  catches the specific class where an Elm bind name is inlined as a C identifier
  in `ELMC_RECORD_GET_INDEX*` (the Just-payload / nested Point bug) before `cc`.
  """

  alias Elmc.Backend.C.Ast.Lint, as: AstLint
  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.GeneratedCTypecheck

  @always_declared MapSet.new(~w(
    owned Rc writer args argc scene_cmd out out0 out1 NULL
  ))

  @spec assert_safe!(String.t(), map()) :: :ok
  def assert_safe!(out_dir, result \\ %{}) when is_binary(out_dir) do
    generated = Path.join(out_dir, "c/elmc_generated.c")
    source = File.read!(generated)
    assert_record_get_bases_bound!(source)
    AstLint.run_source!(source)
    GeneratedCTypecheck.assert_typechecks!(out_dir)
    _ = result
    :ok
  end

  @spec stream_fallbacks([map()] | nil) :: [map()]
  def stream_fallbacks(diagnostics) when is_list(diagnostics) do
    Enum.filter(diagnostics, fn
      %{"code" => "plan_stream_fallback"} -> true
      %{code: "plan_stream_fallback"} -> true
      _ -> false
    end)
  end

  def stream_fallbacks(_), do: []

  @spec assert_record_get_bases_bound!(String.t()) :: :ok
  def assert_record_get_bases_bound!(source) when is_binary(source) do
    source
    |> generated_fn_names()
    |> Enum.each(fn name ->
      body = CCodegenExtract.fn_body(source, name)
      declared = declared_idents(source, name, body)

      body
      |> bare_record_get_bases()
      |> Enum.reject(&MapSet.member?(declared, &1))
      |> case do
        [] ->
          :ok

        bad ->
          raise ExUnit.AssertionError,
            message:
              "#{name} inlines undeclared record base(s) #{inspect(bad)} " <>
                "(Elm bind names must resolve to a C slot, param, or peel)"
      end
    end)

    :ok
  end

  @spec generated_fn_names(String.t()) :: [String.t()]
  defp generated_fn_names(source) do
    ~r/(?:static\s+)?(?:RC|ElmcValue\s*\*+\s*|elmc_int_t|const char\s*\*|void|int|bool)\s+(elmc_fn_[A-Za-z0-9_]+)\s*\(/
    |> Regex.scan(source, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  @spec declared_idents(String.t(), String.t(), String.t()) :: MapSet.t(String.t())
  defp declared_idents(source, name, body) do
    @always_declared
    |> MapSet.union(MapSet.new(fn_param_idents(source, name)))
    |> MapSet.union(MapSet.new(local_idents(body)))
  end

  @spec fn_param_idents(String.t(), String.t()) :: [String.t()]
  defp fn_param_idents(source, name) do
    pattern =
      Regex.compile!(
        "(?:static\\s+)?(?:RC|ElmcValue\\s*\\*+\\s*|elmc_int_t|const char\\s*\\*|void|int|bool)\\s+" <>
          Regex.escape(name) <>
          "\\s*\\(([^;{]*)\\)\\s*\\{"
      )

    case Regex.run(pattern, source, capture: :all_but_first) do
      [params] ->
        params
        |> String.split(",")
        |> Enum.map(&c_ident_from_decl/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  @spec local_idents(String.t()) :: [String.t()]
  defp local_idents(body) do
    ~r/(?:^|\n)\s*(?:const\s+)?(?:ElmcValue\s*\*+|elmc_int_t|bool|int)\s*([A-Za-z_][A-Za-z0-9_]*)/
    |> Regex.scan(body, capture: :all_but_first)
    |> List.flatten()
  end

  @spec c_ident_from_decl(String.t()) :: String.t() | nil
  defp c_ident_from_decl(decl) do
    token =
      decl
      |> String.replace(~r/\/\*.*?\*\//s, "")
      |> String.split(~r/\s+/, trim: true)
      |> Enum.reject(&(&1 in ["const", "static", "volatile"]))
      |> List.last()

    case token do
      name when is_binary(name) ->
        name = String.replace(name, "*", "")

        if name =~ ~r/^[A-Za-z_][A-Za-z0-9_]*$/ do
          name
        else
          nil
        end

      _ ->
        nil
    end
  end

  @spec bare_record_get_bases(String.t()) :: [String.t()]
  def bare_record_get_bases(source) when is_binary(source) do
    source
    |> record_get_first_args()
    |> Enum.filter(&(&1 =~ ~r/^[A-Za-z_][A-Za-z0-9_]*$/))
    |> Enum.uniq()
  end

  @spec record_get_first_args(String.t()) :: [String.t()]
  defp record_get_first_args(source) do
    ~r/ELMC_RECORD_GET_INDEX(?:_INT)?\(/
    |> Regex.scan(source, return: :index)
    |> Enum.map(fn
      [{start, len}] -> first_arg_at(source, start + len)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  @spec first_arg_at(String.t(), non_neg_integer()) :: String.t() | nil
  defp first_arg_at(source, open_after) do
    size = byte_size(source)
    collect_first_arg(source, open_after, size, 0, [])
  end

  defp collect_first_arg(_source, idx, size, _depth, _acc) when idx >= size, do: nil

  defp collect_first_arg(source, idx, size, depth, acc) do
    case :binary.at(source, idx) do
      ?( ->
        collect_first_arg(source, idx + 1, size, depth + 1, [?( | acc])

      ?) when depth > 0 ->
        collect_first_arg(source, idx + 1, size, depth - 1, [?) | acc])

      ?, when depth == 0 ->
        acc
        |> Enum.reverse()
        |> List.to_string()
        |> String.trim()

      byte ->
        collect_first_arg(source, idx + 1, size, depth, [byte | acc])
    end
  end
end
