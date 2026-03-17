defmodule AcaiWeb.Helpers.RepoFormatterTest do
  use ExUnit.Case, async: true

  alias AcaiWeb.Helpers.RepoFormatter

  describe "format_repo_name/1" do
    # feature-impl-view.CARDS.2-2
    # feature-impl-view.CARDS.2-3
    test "extracts repo name from GitHub URIs" do
      assert RepoFormatter.format_repo_name("github.com/owner/repo") == "repo"
      assert RepoFormatter.format_repo_name("github.com/user/my-project") == "my-project"
      assert RepoFormatter.format_repo_name("github.com/org/deep/nested/repo") == "repo"
    end

    # feature-impl-view.CARDS.2-2
    # feature-impl-view.CARDS.2-3
    test "extracts repo name from GitLab URIs" do
      assert RepoFormatter.format_repo_name("gitlab.com/group/project") == "project"
      assert RepoFormatter.format_repo_name("gitlab.com/user/repo") == "repo"
      assert RepoFormatter.format_repo_name("gitlab.com/org/subgroup/project") == "project"
    end

    # feature-impl-view.CARDS.2-3
    test "handles case-insensitive host matching" do
      assert RepoFormatter.format_repo_name("GITHUB.COM/owner/repo") == "repo"
      assert RepoFormatter.format_repo_name("GitLab.com/group/project") == "project"
      assert RepoFormatter.format_repo_name("github.com/Owner/Repo") == "Repo"
    end

    # feature-impl-view.CARDS.2-4
    test "returns full URI unchanged for unknown patterns" do
      assert RepoFormatter.format_repo_name("bitbucket.org/team/project") ==
               "bitbucket.org/team/project"

      assert RepoFormatter.format_repo_name("custom-git.example.com/repo") ==
               "custom-git.example.com/repo"

      assert RepoFormatter.format_repo_name("my-server.local/path/to/repo") ==
               "my-server.local/path/to/repo"
    end

    # feature-impl-view.CARDS.2-4
    # Regression test: hosts that share a prefix with known hosts should NOT be reformatted
    test "returns full URI unchanged for hosts that share prefix with known hosts" do
      # github.com.au should NOT match github.com
      assert RepoFormatter.format_repo_name("github.com.au/team/repo") ==
               "github.com.au/team/repo"

      # github.com.au with different casing
      assert RepoFormatter.format_repo_name("GITHUB.COM.AU/team/repo") ==
               "GITHUB.COM.AU/team/repo"

      # gitlab.com.internal should NOT match gitlab.com
      assert RepoFormatter.format_repo_name("gitlab.com.internal/group/project") ==
               "gitlab.com.internal/group/project"

      # my-github.com should NOT match github.com
      assert RepoFormatter.format_repo_name("my-github.com/owner/repo") ==
               "my-github.com/owner/repo"

      # github.computer/... should NOT match github.com
      assert RepoFormatter.format_repo_name("github.computer/something") ==
               "github.computer/something"
    end

    # feature-impl-view.CARDS.2-4
    test "returns full URI for URIs without path segments" do
      assert RepoFormatter.format_repo_name("example.com") == "example.com"
      assert RepoFormatter.format_repo_name("not-a-repo-uri") == "not-a-repo-uri"
    end

    test "handles nil input" do
      assert RepoFormatter.format_repo_name(nil) == ""
    end

    test "handles empty string" do
      assert RepoFormatter.format_repo_name("") == ""
    end

    test "handles URIs ending with slash" do
      # Edge case: URI ending with slash has empty last segment
      # When last segment is empty, returns original URI
      assert RepoFormatter.format_repo_name("github.com/owner/repo/") == "github.com/owner/repo/"
    end
  end
end
