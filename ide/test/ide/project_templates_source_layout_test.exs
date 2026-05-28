defmodule Ide.ProjectTemplatesSourceLayoutTest do
  use ExUnit.Case, async: true

  alias Ide.ProjectTemplates
  alias Ide.ProjectTemplates.SourceValidation

  test "all bundled template Elm sources pass layout, parse, tokenizer, and formatter checks" do
    assert :ok = SourceValidation.validate_all_templates!()
  end

  test "starter template ships watch Elm entrypoint" do
    assert {:ok, root} = ProjectTemplates.template_priv_root("starter")

    assert File.exists?(Path.join(root, "src/Main.elm"))
  end
end
