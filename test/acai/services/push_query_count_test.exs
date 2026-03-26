defmodule Acai.Services.PushQueryCountTest do
  @moduledoc """
  Query-count performance tests for push operations.

  These tests focus on query-growth behavior rather than absolute latency.
  """

  use Acai.DataCase, async: false

  import Acai.DataModelFixtures
  require Logger

  alias Acai.AccountsFixtures
  alias Acai.Services.Push
  alias Acai.Teams

  @moduletag :performance

  @product_name "perf-test-product"
  @growth_feature_count 25

  describe "query growth" do
    setup do
      user = AccountsFixtures.user_fixture()
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      {:ok, token} =
        Teams.generate_token(
          %{user: user},
          team,
          %{name: "Performance Test Token"}
        )

      %{team: team, user: user, token: token}
    end

    # push.TX.1, push.INSERT_SPEC.1, push.WRITE_REFS.1
    test "cold complete push path stays in a tight constant query band", %{token: token} do
      feature_names = ["cold-feature-1"]

      {result, stats} =
        measure_push_queries(token, complete_push_params("cold", feature_names, "cold-commit-1"))

      assert {:ok, push_result} = result
      assert push_result.specs_created == 1
      assert stats.total <= 13

      print_stats("cold complete push", stats)
    end

    # push.INSERT_SPEC.1, push.UPDATE_SPEC.1, push.IDEMPOTENCY.1
    test "spec query count stays nearly flat as spec count grows", %{token: token} do
      {_, one_stats} =
        measure_push_queries(
          token,
          specs_only_params("spec-one", build_feature_names("spec-one", 1), "spec-one-commit")
        )

      {_, many_stats} =
        measure_push_queries(
          token,
          specs_only_params(
            "spec-many",
            build_feature_names("spec-many", @growth_feature_count),
            "spec-many-commit"
          )
        )

      assert one_stats.total <= 11
      assert many_stats.total <= 10
      assert_flat_growth(one_stats, many_stats, 1)

      print_growth("specs", one_stats, many_stats)
    end

    # push.WRITE_REFS.1, push.WRITE_REFS.3, push.REFS.5, push.REFS.6
    test "refs query count stays nearly flat as touched feature count grows", %{token: token} do
      {_, one_stats} =
        measure_push_queries(
          token,
          refs_only_params("refs-one", build_feature_names("refs-one", 1), "refs-one-commit")
        )

      {_, many_stats} =
        measure_push_queries(
          token,
          refs_only_params(
            "refs-many",
            build_feature_names("refs-many", @growth_feature_count),
            "refs-many-commit"
          )
        )

      assert one_stats.total <= 5
      assert many_stats.total <= 5
      assert_flat_growth(one_stats, many_stats, 0)

      print_growth("refs", one_stats, many_stats)
    end

    # push.TX.1, push.UPDATE_SPEC.1, push.WRITE_REFS.2
    test "warm update path is cheaper than cold create path", %{token: token} do
      cold_feature_names = ["warm-compare-feature"]

      {_, cold_stats} =
        measure_push_queries(
          token,
          complete_push_params("warm-cold", cold_feature_names, "warm-cold-commit-1")
        )

      warm_context = setup_warm_update_context(token, "warm-hot", cold_feature_names)

      {result, warm_stats} =
        measure_push_queries(
          token,
          complete_update_params(
            warm_context,
            "warm-hot-commit-2"
          )
        )

      assert {:ok, push_result} = result
      assert push_result.specs_updated == 1
      assert cold_stats.total <= 13
      assert warm_stats.total <= 9
      assert warm_stats.total < cold_stats.total

      print_comparison("cold vs warm", cold_stats, warm_stats)
    end
  end

  defp measure_push_queries(token, params) do
    original_log_level = Logger.level()
    storage_key = {:push_query_count_result, make_ref()}

    try do
      Logger.configure(level: :debug)

      log_output =
        ExUnit.CaptureLog.capture_log(fn ->
          Process.put(storage_key, Push.execute(token, params))
        end)

      {Process.get(storage_key), analyze_queries(log_output)}
    after
      Process.delete(storage_key)
      Logger.configure(level: original_log_level)
    end
  end

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

  defp assert_flat_growth(smaller, larger, max_delta) do
    assert larger.total <= smaller.total + max_delta,
           "expected query growth to stay within #{max_delta}, got #{smaller.total} -> #{larger.total}"

    assert larger.select <= smaller.select + max_delta,
           "expected SELECT growth to stay within #{max_delta}, got #{smaller.select} -> #{larger.select}"
  end

  defp complete_push_params(tag, feature_names, commit_hash) do
    %{
      repo_uri: "github.com/test-org/#{tag}-repo",
      branch_name: "#{tag}-branch",
      commit_hash: commit_hash,
      specs: build_specs(feature_names, @product_name, commit_hash),
      references: %{data: build_refs(feature_names, 1)}
    }
  end

  defp specs_only_params(tag, feature_names, commit_hash) do
    %{
      repo_uri: "github.com/test-org/#{tag}-repo",
      branch_name: "#{tag}-branch",
      commit_hash: commit_hash,
      specs: build_specs(feature_names, @product_name, commit_hash)
    }
  end

  defp refs_only_params(tag, feature_names, commit_hash) do
    %{
      repo_uri: "github.com/test-org/#{tag}-repo",
      branch_name: "#{tag}-branch",
      commit_hash: commit_hash,
      references: %{data: build_refs(feature_names, 1)}
    }
  end

  defp setup_warm_update_context(token, tag, feature_names) do
    initial_params = complete_push_params(tag, feature_names, "#{tag}-commit-1")

    {:ok, _} = Push.execute(token, initial_params)

    %{
      repo_uri: initial_params.repo_uri,
      branch_name: initial_params.branch_name,
      product_name: @product_name,
      feature_names: feature_names
    }
  end

  defp complete_update_params(context, commit_hash) do
    [feature_name] = context.feature_names

    %{
      repo_uri: context.repo_uri,
      branch_name: context.branch_name,
      commit_hash: commit_hash,
      specs: [updated_spec(feature_name, context.product_name, commit_hash)],
      references: %{data: build_refs([feature_name], 2)}
    }
  end

  defp build_feature_names(prefix, count) do
    Enum.map(1..count, fn index -> "#{prefix}-feature-#{index}" end)
  end

  defp build_specs(feature_names, product_name, commit_hash) do
    Enum.map(feature_names, &base_spec(&1, product_name, commit_hash))
  end

  defp base_spec(feature_name, product_name, commit_hash) do
    %{
      feature: %{
        name: feature_name,
        product: product_name,
        description: "Description for #{feature_name}",
        version: "1.0.0"
      },
      requirements: %{
        acid(feature_name, 1) => %{requirement: "Requirement 1 for #{feature_name}"}
      },
      meta: %{
        path: "features/#{feature_name}.feature.yaml",
        last_seen_commit: commit_hash
      }
    }
  end

  defp updated_spec(feature_name, product_name, commit_hash) do
    %{
      feature: %{
        name: feature_name,
        product: product_name,
        description: "Updated description for #{feature_name}",
        version: "1.1.0"
      },
      requirements: %{
        acid(feature_name, 1) => %{requirement: "Requirement 1 for #{feature_name}"},
        acid(feature_name, 2) => %{requirement: "Requirement 2 for #{feature_name}"}
      },
      meta: %{
        path: "features/#{feature_name}.feature.yaml",
        last_seen_commit: commit_hash
      }
    }
  end

  defp build_refs(feature_names, acid_index) do
    Map.new(feature_names, fn feature_name ->
      {acid(feature_name, acid_index),
       [%{path: "lib/#{feature_name}.ex:#{acid_index}", is_test: false}]}
    end)
  end

  defp acid(feature_name, requirement_index) do
    "#{feature_name}.REQ.#{requirement_index}"
  end

  defp print_stats(label, stats) do
    if System.get_env("VERBOSE_TESTS") do
      IO.puts("\n===== PUSH QUERY STATS: #{label} =====")
      IO.puts("Total queries: #{stats.total}")
      IO.puts("  - SELECT: #{stats.select}")
      IO.puts("  - INSERT: #{stats.insert}")
      IO.puts("  - UPDATE: #{stats.update}")
      IO.puts("  - DELETE: #{stats.delete}")
      IO.puts("===========================================\n")
    end
  end

  defp print_growth(label, smaller, larger) do
    if System.get_env("VERBOSE_TESTS") do
      IO.puts("\n===== PUSH QUERY GROWTH TEST: #{label} =====")

      IO.puts(
        "Small payload total: #{smaller.total} (SELECT #{smaller.select}, INSERT #{smaller.insert})"
      )

      IO.puts(
        "Large payload total: #{larger.total} (SELECT #{larger.select}, INSERT #{larger.insert})"
      )

      IO.puts("Growth delta: #{larger.total - smaller.total}")
      IO.puts("============================================\n")
    end
  end

  defp print_comparison(label, colder, warmer) do
    if System.get_env("VERBOSE_TESTS") do
      IO.puts("\n===== PUSH QUERY COMPARISON: #{label} =====")

      IO.puts(
        "Cold path total: #{colder.total} (SELECT #{colder.select}, INSERT #{colder.insert})"
      )

      IO.puts(
        "Warm path total: #{warmer.total} (SELECT #{warmer.select}, INSERT #{warmer.insert})"
      )

      IO.puts("Savings: #{colder.total - warmer.total}")
      IO.puts("===========================================\n")
    end
  end
end
