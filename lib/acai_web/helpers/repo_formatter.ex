defmodule AcaiWeb.Helpers.RepoFormatter do
  @moduledoc """
  Helpers for formatting repository URIs for display.

  Provides consistent repository name display across the implementation view.
  """

  @doc """
  Formats a repository URI for display.

  For known repository host patterns (GitHub and GitLab), returns only the
  repository name (last path segment). For unknown patterns, returns the
  original URI unchanged.

  ## Examples

      iex> format_repo_name("github.com/owner/repo")
      "repo"

      iex> format_repo_name("gitlab.com/group/project")
      "project"

      iex> format_repo_name("bitbucket.org/team/project")
      "bitbucket.org/team/project"

      iex> format_repo_name("custom-git-server.com/repo")
      "custom-git-server.com/repo"
  """
  # feature-impl-view.CARDS.2-2: Repository references show only repo name for known patterns
  # feature-impl-view.CARDS.2-3: Known patterns include GitHub and GitLab URIs
  # feature-impl-view.CARDS.2-4: Unknown patterns display full repo_uri unchanged
  def format_repo_name(uri) when is_binary(uri) do
    # Use exact host matching to avoid incorrectly matching hosts like github.com.au
    # Match github.com/ or gitlab.com/ exactly (case-insensitive)
    cond do
      # feature-impl-view.CARDS.2-3: Recognize GitHub repository URIs
      matches_known_host?(uri, "github.com") ->
        extract_repo_name(uri)

      # feature-impl-view.CARDS.2-3: Recognize GitLab repository URIs
      matches_known_host?(uri, "gitlab.com") ->
        extract_repo_name(uri)

      # feature-impl-view.CARDS.2-4: Unknown patterns - return original unchanged
      true ->
        uri
    end
  end

  def format_repo_name(_), do: ""

  @doc """
  Builds a clickable repository URL from a stored repo URI.
  """
  def repo_http_url(uri) when is_binary(uri) do
    cond do
      String.starts_with?(uri, "https://") -> uri
      String.starts_with?(uri, "http://") -> uri
      true -> "https://#{uri}"
    end
  end

  def repo_http_url(_), do: ""

  # Checks if the URI matches a known host exactly (case-insensitive)
  # e.g., "github.com/owner/repo" matches "github.com"
  # but "github.com.au/owner/repo" does NOT match "github.com"
  defp matches_known_host?(uri, host) when is_binary(uri) and is_binary(host) do
    uri_lower = String.downcase(uri)
    host_lower = String.downcase(host)

    # Must match either:
    # 1. host/... (host followed by slash)
    # 2. host (exact match, no path)
    String.starts_with?(uri_lower, host_lower <> "/") or
      uri_lower == host_lower
  end

  # Extract the last path segment (repository name) from a URI
  # e.g., "github.com/owner/repo" -> "repo"
  defp extract_repo_name(uri) do
    uri
    |> String.split("/")
    |> List.last()
    |> case do
      nil -> uri
      "" -> uri
      name -> name
    end
  end
end
