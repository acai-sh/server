defmodule Acai.Specs.FeaturePageQueryCountTest do
  @moduledoc """
  Query-count performance tests for the feature page consolidated loader.

  These tests verify that the batched loader has bounded query growth
  regardless of implementation count or ancestor depth.

  ACID:
  - feature-view.ENG.1: Single query fetches all specs, implementations, and state counts
  """

  use Acai.DataCase, async: false

  import Acai.DataModelFixtures
  require Logger

  alias Acai.Specs

  @moduletag :performance

  describe "feature page query growth" do
    # feature-view.ENG.1: Query count should stay nearly flat as implementation count grows
    test "query count stays bounded as implementation count grows", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create one implementation
      impl_1 = create_implementation_with_feature(team, product, "perf-feature", 1)

      # Preload setup data OUTSIDE the measurement to isolate loader queries
      _ = Acai.Repo.preload(impl_1, :product)

      {_, small_stats} =
        measure_feature_page_queries(team, "perf-feature")

      # Create many more implementations
      additional_impls =
        for i <- 2..10 do
          create_implementation_with_feature(team, product, "perf-feature", i)
        end

      # Preload all implementations OUTSIDE the measurement
      _ = Enum.map([impl_1 | additional_impls], &Acai.Repo.preload(&1, :product))

      {_, large_stats} =
        measure_feature_page_queries(team, "perf-feature")

      # Query growth should be nearly flat (constant, not O(N))
      # With setup moved outside, loader queries should stay bounded
      assert_flat_growth(small_stats, large_stats, 3)

      print_growth("implementations", small_stats, large_stats)
    end

    # feature-view.ENG.1: Query count should stay bounded with deep ancestry chains
    test "query count stays bounded as ancestor depth grows", %{} do
      # Use different teams to avoid branch name collisions
      shallow_team = team_fixture(%{name: "shallow-team"})
      deep_team = team_fixture(%{name: "deep-team"})

      # Create SHALLOW inheritance chain (depth 1 - just root with spec)
      shallow_product = product_fixture(shallow_team, %{name: "shallow-product"})

      _shallow_impls =
        create_inheritance_chain(shallow_team, shallow_product, "shallow-feature", 1)

      # Measure shallow chain
      {_, shallow_stats} =
        measure_feature_page_queries(shallow_team, "shallow-feature")

      # Create DEEP inheritance chain (depth 5)
      deep_product = product_fixture(deep_team, %{name: "deep-product"})
      _deep_impls = create_inheritance_chain(deep_team, deep_product, "deep-feature", 5)

      # Measure deep chain
      {_, deep_stats} =
        measure_feature_page_queries(deep_team, "deep-feature")

      # Query growth should be nearly flat regardless of ancestry depth
      # The batched loader uses the same number of queries for 1-level vs 5-level chains
      assert_flat_growth(shallow_stats, deep_stats, 2)

      print_growth("ancestor depth (1 vs 5)", shallow_stats, deep_stats)
    end

    # feature-view.ENG.1: Single query path should be used
    test "cold feature page load uses bounded number of queries", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create multiple implementations
      impls =
        for i <- 1..5 do
          create_implementation_with_feature(team, product, "cold-feature", i)
        end

      # Preload setup data OUTSIDE the measurement
      _ = Enum.map(impls, &Acai.Repo.preload(&1, :product))

      {result, stats} = measure_feature_page_queries(team, "cold-feature")

      assert {:ok, data} = result
      assert data.feature_name == "cold-feature"
      assert length(data.implementations) == 5

      # Query budget should be bounded regardless of implementation count
      # With setup moved outside, the loader uses approximately 12-14 queries:
      # - 2 for get_specs_by_feature_name (get name + get specs)
      # - 1 for list_features_for_product
      # - 1 for list active implementations
      # - 3 for batch_check_feature_availability (impls, tracked_branches, specs)
      # - 1 for preload products on implementations
      # - 1 for batch_get_feature_impl_state_counts
      # - 3 for batch_resolve_canonical_specs (impls, tracked_branches, specs)
      assert stats.total <= 14

      print_stats("cold feature page load", stats)
    end
  end

  # Helper to measure queries for the consolidated loader
  # feature-view.ENG.1: Measures Specs.load_feature_page_data/2 in isolation
  defp measure_feature_page_queries(team, feature_name) do
    original_log_level = Logger.level()
    storage_key = {:feature_page_query_count_result, make_ref()}

    try do
      Logger.configure(level: :debug)

      log_output =
        ExUnit.CaptureLog.capture_log(fn ->
          # ONLY measure the consolidated loader - all setup/preload happens outside
          Process.put(storage_key, Specs.load_feature_page_data(team, feature_name))
        end)

      {Process.get(storage_key), analyze_queries(log_output)}
    after
      Process.delete(storage_key)
      Logger.configure(level: original_log_level)
    end
  end

  # Parse SQL log output to count queries by type
  defp analyze_queries(log_output) do
    query_blocks =
      log_output
      |> String.split("[debug] QUERY")
      |> Enum.drop(1)

    stats =
      Enum.reduce(query_blocks, %{select: 0, insert: 0, update: 0, delete: 0}, fn block, acc ->
        lines = String.split(block, "\n")

        sql_line =
          Enum.find(lines, fn line ->
            String.match?(line, ~r/^\s*(SELECT|INSERT|UPDATE|DELETE)/i)
          end) || ""

        cond do
          String.match?(sql_line, ~r/^\s*SELECT/i) ->
            Map.update!(acc, :select, &(&1 + 1))

          String.match?(sql_line, ~r/^\s*INSERT/i) ->
            Map.update!(acc, :insert, &(&1 + 1))

          String.match?(sql_line, ~r/^\s*UPDATE/i) ->
            Map.update!(acc, :update, &(&1 + 1))

          String.match?(sql_line, ~r/^\s*DELETE/i) ->
            Map.update!(acc, :delete, &(&1 + 1))

          true ->
            acc
        end
      end)

    total = stats.select + stats.insert + stats.update + stats.delete

    Map.merge(stats, %{total: total, raw_blocks: length(query_blocks)})
  end

  # Assert that query growth stays within acceptable bounds
  # feature-view.ENG.1: Query growth should be nearly flat (constant, not O(N))
  # With setup moved outside the measurement, we can enforce tighter bounds
  defp assert_flat_growth(smaller, larger, max_delta) do
    # The key assertion: growth should be constant regardless of data size
    # If we 10x the implementations, queries should stay nearly the same
    base = max(smaller.total, 1)
    growth_ratio = larger.total / base

    # Tight ratio bound - loader should have nearly constant query count
    assert growth_ratio <= 1.5,
           "expected query growth ratio <= 1.5, got #{growth_ratio} (#{smaller.total} -> #{larger.total}). " <>
             "The consolidated loader should have bounded query growth."

    # Small absolute delta - loader queries shouldn't grow with data size
    assert larger.total <= smaller.total + max_delta,
           "expected query growth to stay within +#{max_delta}, got #{smaller.total} -> #{larger.total}. " <>
             "The consolidated loader should be O(1) in queries."
  end

  # Create an implementation with a tracked branch and spec for a feature
  defp create_implementation_with_feature(_team, product, feature_name, index) do
    impl =
      implementation_fixture(product, %{
        name: "impl-#{index}",
        is_active: true
      })

    # Create tracked branch
    tracked =
      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo-#{index}", branch_name: "main")

    branch = Acai.Repo.preload(tracked, :branch).branch

    # Create spec for the feature on this branch
    spec_fixture(product, %{
      feature_name: feature_name,
      feature_description: "Description for #{feature_name}",
      branch: branch,
      repo_uri: "github.com/org/repo-#{index}",
      requirements: %{
        "#{feature_name}.COMP.1" => %{
          "requirement" => "Requirement 1",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "#{feature_name}.COMP.2" => %{
          "requirement" => "Requirement 2",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }
    })

    impl
  end

  # Create a chain of implementations with inheritance
  defp create_inheritance_chain(_team, product, feature_name, depth) do
    # suppress unused warning
    _ = feature_name

    # Create root with spec
    root =
      implementation_fixture(product, %{
        name: "root",
        is_active: true
      })

    root_tracked =
      tracked_branch_fixture(root, repo_uri: "github.com/org/root", branch_name: "main")

    root_branch = Acai.Repo.preload(root_tracked, :branch).branch

    spec_fixture(product, %{
      feature_name: feature_name,
      feature_description: "Inherited feature",
      branch: root_branch,
      repo_uri: "github.com/org/root",
      requirements: %{
        "#{feature_name}.COMP.1" => %{
          "requirement" => "Req 1",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }
    })

    # Create descendants (only if depth > 1)
    impls =
      if depth > 1 do
        {descendants, _} =
          Enum.reduce(1..(depth - 1)//1, {[root], root.id}, fn i, {acc, parent_id} ->
            child =
              implementation_fixture(product, %{
                name: "child-#{i}",
                is_active: true,
                parent_implementation_id: parent_id
              })

            {[child | acc], child.id}
          end)

        Enum.reverse(descendants)
      else
        [root]
      end

    impls
  end

  # Print query statistics for debugging (hidden behind DEBUG_QUERY_COUNTS env var)
  defp print_stats(label, stats) do
    if System.get_env("DEBUG_QUERY_COUNTS") do
      IO.puts("\n===== FEATURE PAGE QUERY COUNT: #{label} =====")
      IO.puts("Total queries: #{stats.total}")
      IO.puts("  - SELECT: #{stats.select}")
      IO.puts("  - INSERT: #{stats.insert}")
      IO.puts("  - UPDATE: #{stats.update}")
      IO.puts("  - DELETE: #{stats.delete}")
      IO.puts("==============================================\n")
    end
  end

  # Print growth comparison between two test runs (hidden behind DEBUG_QUERY_COUNTS env var)
  defp print_growth(label, smaller, larger) do
    if System.get_env("DEBUG_QUERY_COUNTS") do
      IO.puts("\n===== FEATURE PAGE QUERY GROWTH: #{label} =====")

      IO.puts(
        "Small payload total: #{smaller.total} (SELECT #{smaller.select}, INSERT #{smaller.insert})"
      )

      IO.puts(
        "Large payload total: #{larger.total} (SELECT #{larger.select}, INSERT #{larger.insert})"
      )

      IO.puts("Growth delta: #{larger.total - smaller.total}")
      IO.puts("===============================================\n")
    end
  end
end
