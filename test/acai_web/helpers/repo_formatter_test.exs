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

  describe "source_file_url/4" do
    # feature-impl-view.DRAWER.5
    test "feature-impl-view.DRAWER.5: builds a /blob/ link with a line anchor for GitHub repos" do
      assert RepoFormatter.source_file_url(
               "github.com/acai-sh/server",
               "main",
               "lib/foo.ex",
               "42"
             ) == "https://github.com/acai-sh/server/blob/main/lib/foo.ex#L42"
    end

    # feature-impl-view.DRAWER.5
    test "feature-impl-view.DRAWER.5: omits the line anchor when the ref has no line number" do
      assert RepoFormatter.source_file_url("github.com/acai-sh/server", "main", "lib/foo.ex") ==
               "https://github.com/acai-sh/server/blob/main/lib/foo.ex"
    end

    # feature-impl-view.DRAWER.5
    test "feature-impl-view.DRAWER.5: keeps the /blob/ shape for hosts other than Codeberg" do
      assert RepoFormatter.source_file_url("gitlab.com/group/project", "main", "lib/foo.ex", "42") ==
               "https://gitlab.com/group/project/blob/main/lib/foo.ex#L42"

      assert RepoFormatter.source_file_url("bitbucket.org/team/repo", "main", "lib/foo.ex", "42") ==
               "https://bitbucket.org/team/repo/blob/main/lib/foo.ex#L42"
    end

    # feature-impl-view.DRAWER.5-1
    test "feature-impl-view.DRAWER.5-1: builds a /src/branch/ link for Codeberg repos" do
      assert RepoFormatter.source_file_url(
               "codeberg.org/tarcisio/conan-flake",
               "main",
               "nix/modules/configuration/outputs.nix",
               "106"
             ) ==
               "https://codeberg.org/tarcisio/conan-flake/src/branch/main/nix/modules/configuration/outputs.nix#L106"
    end

    # feature-impl-view.DRAWER.5-1
    test "feature-impl-view.DRAWER.5-1: does not double the scheme when the repo_uri has one" do
      assert RepoFormatter.source_file_url(
               "https://codeberg.org/tarcisio/conan-flake",
               "main",
               "nix/x.nix",
               "106"
             ) == "https://codeberg.org/tarcisio/conan-flake/src/branch/main/nix/x.nix#L106"
    end

    # feature-impl-view.DRAWER.5-1
    test "feature-impl-view.DRAWER.5-1: omits the line anchor for Codeberg refs without a line" do
      assert RepoFormatter.source_file_url("codeberg.org/owner/repo", "feat/a-b", "lib/foo.ex") ==
               "https://codeberg.org/owner/repo/src/branch/feat/a-b/lib/foo.ex"
    end

    # feature-impl-view.DRAWER.5-1
    test "feature-impl-view.DRAWER.5-1: matches the Codeberg host case-insensitively" do
      assert RepoFormatter.source_file_url("CODEBERG.ORG/Owner/Repo", "main", "lib/foo.ex", "42") ==
               "https://CODEBERG.ORG/Owner/Repo/src/branch/main/lib/foo.ex#L42"
    end

    # feature-impl-view.DRAWER.5-1
    # Regression test: hosts that share a prefix with codeberg.org must NOT use /src/branch/
    test "feature-impl-view.DRAWER.5-1: does not use /src/branch/ for Codeberg lookalike hosts" do
      assert RepoFormatter.source_file_url(
               "codeberg.org.au/owner/repo",
               "main",
               "lib/foo.ex",
               "42"
             ) ==
               "https://codeberg.org.au/owner/repo/blob/main/lib/foo.ex#L42"

      assert RepoFormatter.source_file_url(
               "my-codeberg.org/owner/repo",
               "main",
               "lib/foo.ex",
               "42"
             ) ==
               "https://my-codeberg.org/owner/repo/blob/main/lib/foo.ex#L42"

      assert RepoFormatter.source_file_url(
               "codeberg.organic/owner/repo",
               "main",
               "lib/foo.ex",
               "42"
             ) ==
               "https://codeberg.organic/owner/repo/blob/main/lib/foo.ex#L42"
    end

    test "feature-impl-view.DRAWER.5: handles nil repo_uri" do
      assert RepoFormatter.source_file_url(nil, "main", "lib/foo.ex", "42") == ""
    end
  end
end
