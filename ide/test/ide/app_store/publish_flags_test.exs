defmodule Ide.AppStore.PublishFlagsTest do
  use ExUnit.Case, async: true

  alias Ide.AppStore.PublishFlags
  alias Ide.Projects.Project

  test "api_is_published_string/1 and visibility_line/1 cover draft and published" do
    assert PublishFlags.api_is_published_string(:draft) == "false"
    assert PublishFlags.api_is_published_string(:published) == "true"
    assert PublishFlags.visibility_line(:draft) =~ "draft"
    assert PublishFlags.visibility_line(:published) =~ "published"
    assert PublishFlags.from_mcp_args(%{"is_published" => false}) == false
    assert PublishFlags.from_mcp_args(%{"is_published" => true}) == true
  end

  test "resolve_visibility/2 prefers explicit visibility opt" do
    project = %Project{slug: "wf", release_defaults: %{"is_published" => true}}

    assert PublishFlags.resolve_visibility(project, visibility: :draft) == :draft
    assert PublishFlags.resolve_visibility(project, is_published: false) == :draft
    assert PublishFlags.resolve_visibility(project, is_published: true) == :published
  end
end
