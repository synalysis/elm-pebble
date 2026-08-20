defmodule Ide.StoreListingUrlsTest do
  use ExUnit.Case, async: false

  alias Ide.StoreListingUrls

  test "default website and source repo URLs" do
    assert StoreListingUrls.default_website_url() == "https://elm-pebble.dev"
    assert StoreListingUrls.default_source_repo_url() == "https://github.com/synalysis/elm-pebble"
  end

  test "app_page_url builds the public Rebble listing from store_app_id" do
    assert StoreListingUrls.app_page_url("abc-123") == "https://apps.rePebble.com/abc-123"

    assert StoreListingUrls.app_page_url(%{store_app_id: "abc-123"}) ==
             "https://apps.rePebble.com/abc-123"

    assert StoreListingUrls.app_page_url(%{"store_app_id" => "abc-123"}) ==
             "https://apps.rePebble.com/abc-123"

    assert StoreListingUrls.app_page_url(%{store_app_id: nil}) == nil
    assert StoreListingUrls.app_page_url("") == nil
    assert StoreListingUrls.app_page_url(nil) == nil
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

    assert StoreListingUrls.public_github_repo_url(project) ==
             "https://github.com/my-org/my-watchface"
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

  test "source_url_placeholder uses the GitHub repo only when it exists" do
    project = %{
      release_defaults: %{},
      github: %{
        "owner" => "my-org",
        "repo" => "my-watchface",
        "visibility" => "public"
      }
    }

    assert StoreListingUrls.source_url_placeholder(project, :exists) ==
             "https://github.com/my-org/my-watchface"

    assert StoreListingUrls.source_url_placeholder(project, :not_found) ==
             "https://github.com/synalysis/elm-pebble"

    assert StoreListingUrls.source_url_placeholder(project, :checking) ==
             "https://github.com/synalysis/elm-pebble"

    assert StoreListingUrls.form_source_url(project) == ""
  end

  test "github_repo_url falls back to the connected GitHub login" do
    credentials_path =
      Path.join(
        System.tmp_dir!(),
        "ide_store_listing_urls_#{System.unique_integer([:positive])}.json"
      )

    original_github = Application.get_env(:ide, Ide.GitHub, [])

    File.write!(
      credentials_path,
      Jason.encode!(%{"access_token" => "test-token", "user_login" => "pebbledev"})
    )

    Application.put_env(
      :ide,
      Ide.GitHub,
      Keyword.put(original_github, :credentials_path, credentials_path)
    )

    on_exit(fn ->
      Application.put_env(:ide, Ide.GitHub, original_github)
      File.rm(credentials_path)
    end)

    project = %{
      release_defaults: %{},
      github: %{"owner" => "", "repo" => "classic-motivate", "visibility" => "public"}
    }

    assert StoreListingUrls.github_repo_url(project) ==
             "https://github.com/pebbledev/classic-motivate"

    assert StoreListingUrls.source_url_placeholder(project, :exists) ==
             "https://github.com/pebbledev/classic-motivate"
  end
end
