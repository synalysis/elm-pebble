defmodule Ide.StoreListingUrlsTest do
  use ExUnit.Case, async: true

  alias Ide.StoreListingUrls

  test "default website and source repo URLs" do
    assert StoreListingUrls.default_website_url() == "https://elm-pebble.dev"
    assert StoreListingUrls.default_source_repo_url() == "https://github.com/synalysis/elm-pebble"
  end

  test "website_url uses stored value or elm-pebble.dev default" do
    assert StoreListingUrls.website_url(%{release_defaults: %{}}) ==
             "https://elm-pebble.dev"

    assert StoreListingUrls.website_url(%{
             release_defaults: %{"website_url" => "https://example.test"}
           }) == "https://example.test"
  end

  test "source_url uses public GitHub repo when configured" do
    project = %{
      release_defaults: %{},
      github: %{
        "owner" => "my-org",
        "repo" => "my-watchface",
        "branch" => "main",
        "visibility" => "public"
      }
    }

    assert StoreListingUrls.source_url(project) == "https://github.com/my-org/my-watchface"
    assert StoreListingUrls.public_github_repo_url(project) == "https://github.com/my-org/my-watchface"
  end

  test "source_url falls back to synalysis repo when GitHub is private or unset" do
    private = %{
      release_defaults: %{},
      github: %{"owner" => "my-org", "repo" => "secret", "visibility" => "private"}
    }

    assert StoreListingUrls.source_url(private) == "https://github.com/synalysis/elm-pebble"
    assert StoreListingUrls.source_url(%{release_defaults: %{}, github: %{}}) ==
             "https://github.com/synalysis/elm-pebble"
  end

  test "source_url uses explicit release_defaults override" do
    assert StoreListingUrls.source_url(%{
             release_defaults: %{"source_url" => "https://github.com/custom/repo"}
           }) == "https://github.com/custom/repo"
  end
end
