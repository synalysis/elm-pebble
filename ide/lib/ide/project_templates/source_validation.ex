defmodule Ide.ProjectTemplates.SourceValidation do
  @moduledoc """
  Validates bundled project template Elm sources before MCP or corpus runs.

  Every `.elm` file under `priv/project_templates/<template>/` must:

  - use Elm `let`/`in` layout (`in` on its own line)
  - parse through the generated frontend parser
  - produce no compiler-mode tokenizer parser diagnostics
  - already match IDE formatter output (`Formatter.format/1` must not change the file)
  """

  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.LetLayout
  alias Ide.Formatter
  alias Ide.ProjectTemplates
  alias Ide.Tokenizer

  @type issue :: %{
          required(:template) => String.t(),
          required(:file) => String.t(),
          required(:check) => atom(),
          required(:detail) => String.t()
        }

  @doc """
  Validates all bundled template Elm sources. Raises on the first template with issues.
  """
  @spec validate_all_templates!() :: :ok
  def validate_all_templates! do
    Enum.each(ProjectTemplates.template_keys(), fn template_key ->
      case validate_template(template_key) do
        :ok ->
          :ok

        {:error, issues} ->
          raise ArgumentError, format_issues(template_key, issues)
      end
    end)

    :ok
  end

  @doc """
  Validates every `.elm` file shipped for `template_key`.
  """
  @spec validate_template(String.t()) :: :ok | {:error, [issue()]}
  def validate_template(template_key) when is_binary(template_key) do
    case ProjectTemplates.template_priv_root(template_key) do
      {:ok, root} ->
        issues =
          root
          |> list_elm_sources()
          |> Enum.flat_map(fn path -> validate_elm_file(template_key, root, path) end)

        if issues == [], do: :ok, else: {:error, issues}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Human-readable summary for test failures and MCP health output.
  """
  @spec format_issues(String.t(), [issue()]) :: String.t()
  def format_issues(template_key, issues) when is_binary(template_key) and is_list(issues) do
    lines =
      Enum.map(issues, fn %{file: file, check: check, detail: detail} ->
        "  #{file} [#{check}] #{detail}"
      end)

    "template #{template_key} source validation failed:\n" <> Enum.join(lines, "\n")
  end

  @spec list_elm_sources(String.t()) :: [String.t()]
  defp list_elm_sources(root) when is_binary(root) do
    root
    |> Path.join("**/*.elm")
    |> Path.wildcard()
    |> Enum.sort()
  end

  @spec validate_elm_file(String.t(), String.t(), String.t()) :: [issue()]
  defp validate_elm_file(template_key, root, path)
       when is_binary(template_key) and is_binary(root) and is_binary(path) do
    source = File.read!(path)
    rel = Path.relative_to(path, root)

    let_layout_issue(template_key, rel, source)
    |> List.wrap()
    |> Kernel.++(List.wrap(parse_issue(template_key, rel, path)))
    |> Kernel.++(tokenizer_issues(template_key, rel, source))
    |> Kernel.++(List.wrap(formatter_issue(template_key, rel, source)))
  end

  @spec let_layout_issue(String.t(), String.t(), String.t()) :: issue() | nil
  defp let_layout_issue(template_key, rel, source) do
    case LetLayout.validate(source) do
      :ok ->
        nil

      {:error, {:inline_let_in, line}} ->
        %{
          template: template_key,
          file: rel,
          check: :let_layout,
          detail: "let and in must be on separate lines (line #{line})"
        }
    end
  end

  @spec parse_issue(String.t(), String.t(), String.t()) :: issue() | nil
  defp parse_issue(template_key, rel, path) do
    case GeneratedParser.parse_file(path) do
      {:ok, _module} ->
        nil

      {:error, reason} ->
        %{
          template: template_key,
          file: rel,
          check: :parse,
          detail: "generated parser: #{inspect(reason, limit: 4)}"
        }
    end
  end

  @spec tokenizer_issues(String.t(), String.t(), String.t()) :: [issue()]
  defp tokenizer_issues(template_key, rel, source) do
    source
    |> Tokenizer.tokenize(mode: :compiler)
    |> Map.get(:diagnostics, [])
    |> Enum.filter(&(Map.get(&1, :severity) in ["error", "warning"]))
    |> Enum.map(fn diag ->
      %{
        template: template_key,
        file: rel,
        check: :tokenizer,
        detail:
          "#{diag.source || "tokenizer"} line #{diag.line}: #{String.trim(diag.message || "")}"
      }
    end)
  end

  @spec formatter_issue(String.t(), String.t(), String.t()) :: issue() | nil
  defp formatter_issue(template_key, rel, source) do
    case Formatter.format(source) do
      {:ok, %{changed?: false}} ->
        nil

      {:ok, %{changed?: true}} ->
        %{
          template: template_key,
          file: rel,
          check: :formatter,
          detail: "file is not formatter-clean; run the IDE formatter and commit the result"
        }

      {:error, reason} ->
        %{
          template: template_key,
          file: rel,
          check: :formatter,
          detail: "formatter failed: #{inspect(reason, limit: 4)}"
        }
    end
  end
end
