defmodule Ide.Projects.BootstrapErrorTest do
  use ExUnit.Case, async: true

  alias Ide.Paths
  alias Ide.Projects.BootstrapError

  test "describe missing template asset mentions path and priv layout" do
    path = "/opt/ide/lib/ide/priv/project_templates/starter_watch/src"

    message =
      BootstrapError.describe({:missing_template_asset, path}, %{
        template: "starter",
        workspace: "/var/lib/ide/workspace_projects/demo"
      })

    assert message =~ path
    assert message =~ to_string(Paths.priv_dir())
    assert message =~ "project_templates"
  end

  test "describe enoent includes priv layout guidance" do
    message =
      BootstrapError.describe(:enoent, %{
        workspace: "/tmp/demo",
        template: "starter"
      })

    assert message =~ "not found"
    assert message =~ "priv"
  end

  test "describe unknown template" do
    assert BootstrapError.describe({:unknown_template, "nope"}, %{}) =~ "nope"
  end
end
