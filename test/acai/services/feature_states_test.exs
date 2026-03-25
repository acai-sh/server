defmodule Acai.Services.FeatureStatesTest do
  @moduledoc """
  Tests for feature-states writes.

  ACIDs:
  - feature-states.REQUEST.1-6
  - feature-states.WRITE.1-7
  - feature-states.RESPONSE.3-4
  - feature-states.VALIDATION.1-3
  - feature-states.ABUSE.2-4
  """

  use Acai.DataCase, async: false

  import Acai.DataModelFixtures

  alias Acai.Services.FeatureStates
  alias Acai.Specs

  setup do
    original = Application.get_env(:acai, :api_operations)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:acai, :api_operations)
      else
        Application.put_env(:acai, :api_operations, original)
      end
    end)

    :ok
  end

  defp feature_setup(opts \\ []) do
    feature_name = Keyword.get(opts, :feature_name, "feature-states-test")
    team = team_fixture()
    product = product_fixture(team, %{name: "feature-states-product"})

    branch =
      branch_fixture(team, %{repo_uri: "github.com/acai/feature-states", branch_name: "main"})

    parent_impl = implementation_fixture(product, %{name: "Parent"})

    child_impl =
      implementation_fixture(product, %{name: "Child", parent_implementation_id: parent_impl.id})

    tracked_branch_fixture(parent_impl, %{branch: branch})

    spec =
      spec_fixture(product, %{
        feature_name: feature_name,
        branch: branch,
        requirements: %{
          "#{feature_name}.REQ.1" => %{requirement: "One"},
          "#{feature_name}.REQ.2" => %{requirement: "Two"}
        }
      })

    %{
      team: team,
      product: product,
      branch: branch,
      parent_impl: parent_impl,
      child_impl: child_impl,
      spec: spec,
      feature_name: feature_name
    }
  end

  test "first write snapshots the parent row and patches incoming states" do
    ctx = feature_setup()

    {:ok, _parent_state} =
      Specs.create_feature_impl_state(ctx.feature_name, ctx.parent_impl, %{
        states: %{
          "#{ctx.feature_name}.REQ.1" => %{"status" => "assigned"},
          "#{ctx.feature_name}.REQ.2" => %{"status" => "completed", "comment" => "baseline"}
        }
      })

    assert {:ok, result} =
             FeatureStates.execute(ctx.team, %{
               "product_name" => ctx.product.name,
               "feature_name" => ctx.feature_name,
               "implementation_name" => ctx.child_impl.name,
               "states" => %{
                 "#{ctx.feature_name}.REQ.2" => %{"status" => "blocked"}
               }
             })

    assert result.states_written == 1
    assert result.warnings == []

    child_state = Specs.get_feature_impl_state(ctx.feature_name, ctx.child_impl)
    assert child_state.states["#{ctx.feature_name}.REQ.1"]["status"] == "assigned"
    assert child_state.states["#{ctx.feature_name}.REQ.2"]["status"] == "blocked"
    assert child_state.states["#{ctx.feature_name}.REQ.2"]["comment"] == nil
  end

  test "subsequent writes replace touched local acids and preserve untouched local acids" do
    ctx = feature_setup()

    assert {:ok, initial} =
             FeatureStates.execute(ctx.team, %{
               "product_name" => ctx.product.name,
               "feature_name" => ctx.feature_name,
               "implementation_name" => ctx.child_impl.name,
               "states" => %{
                 "#{ctx.feature_name}.REQ.1" => %{"status" => "assigned"},
                 "#{ctx.feature_name}.REQ.2" => %{"status" => "completed", "comment" => "keep"}
               }
             })

    assert initial.states_written == 2

    assert {:ok, updated} =
             FeatureStates.execute(ctx.team, %{
               "product_name" => ctx.product.name,
               "feature_name" => ctx.feature_name,
               "implementation_name" => ctx.child_impl.name,
               "states" => %{
                 "#{ctx.feature_name}.REQ.2" => %{"status" => "blocked"}
               }
             })

    assert updated.states_written == 1

    child_state = Specs.get_feature_impl_state(ctx.feature_name, ctx.child_impl)
    assert child_state.states["#{ctx.feature_name}.REQ.1"]["status"] == "assigned"
    assert child_state.states["#{ctx.feature_name}.REQ.2"]["status"] == "blocked"
    assert child_state.states["#{ctx.feature_name}.REQ.2"]["comment"] == nil
  end

  test "rejects non-string identifiers" do
    ctx = feature_setup()

    for {field, value} <- [
          {"product_name", 123},
          {"feature_name", true},
          {"implementation_name", :child}
        ] do
      attrs = %{
        "product_name" => ctx.product.name,
        "feature_name" => ctx.feature_name,
        "implementation_name" => ctx.child_impl.name,
        "states" => %{"#{ctx.feature_name}.REQ.1" => %{"status" => "completed"}}
      }

      attrs = Map.put(attrs, field, value)

      assert {:error, {reason, _meta}} = FeatureStates.execute(ctx.team, attrs)
      assert reason =~ "must be a string"
    end
  end

  test "stores explicit null status locally" do
    ctx = feature_setup()

    assert {:ok, result} =
             FeatureStates.execute(ctx.team, %{
               "product_name" => ctx.product.name,
               "feature_name" => ctx.feature_name,
               "implementation_name" => ctx.child_impl.name,
               "states" => %{
                 "#{ctx.feature_name}.REQ.1" => %{"status" => nil, "comment" => "pending"}
               }
             })

    assert result.states_written == 1

    child_state = Specs.get_feature_impl_state(ctx.feature_name, ctx.child_impl)
    assert Map.has_key?(child_state.states, "#{ctx.feature_name}.REQ.1")
    assert child_state.states["#{ctx.feature_name}.REQ.1"]["status"] == nil
    assert child_state.states["#{ctx.feature_name}.REQ.1"]["comment"] == "pending"
  end

  test "returns a warning for dangling but prefix-matching acids" do
    ctx = feature_setup()

    assert {:ok, result} =
             FeatureStates.execute(ctx.team, %{
               "product_name" => ctx.product.name,
               "feature_name" => ctx.feature_name,
               "implementation_name" => ctx.child_impl.name,
               "states" => %{
                 "#{ctx.feature_name}.REQ.99" => %{"status" => "accepted"}
               }
             })

    assert result.states_written == 1
    assert Enum.any?(result.warnings, &String.contains?(&1, "REQ.99"))

    child_state = Specs.get_feature_impl_state(ctx.feature_name, ctx.child_impl)
    assert Map.has_key?(child_state.states, "#{ctx.feature_name}.REQ.99")
  end

  test "rejects ACIDs outside the requested feature prefix" do
    ctx = feature_setup()

    assert {:error, reason} =
             FeatureStates.execute(ctx.team, %{
               "product_name" => ctx.product.name,
               "feature_name" => ctx.feature_name,
               "implementation_name" => ctx.child_impl.name,
               "states" => %{
                 "other-feature.REQ.1" => %{"status" => "completed"}
               }
             })

    assert reason =~ "All state ACIDs must start"
  end

  test "rejects invalid status values" do
    ctx = feature_setup()

    assert {:error, reason} =
             FeatureStates.execute(ctx.team, %{
               "product_name" => ctx.product.name,
               "feature_name" => ctx.feature_name,
               "implementation_name" => ctx.child_impl.name,
               "states" => %{
                 "#{ctx.feature_name}.REQ.1" => %{"status" => "bogus"}
               }
             })

    assert reason == "Invalid state status value"
  end

  test "rejects comments that exceed the configured semantic cap" do
    Application.put_env(:acai, :api_operations, %{
      default: %{
        request_size_cap: 2_000_000,
        semantic_caps: %{},
        rate_limit: %{requests: 60, window_seconds: 60}
      },
      feature_states: %{
        semantic_caps: %{max_states: 500, max_comment_length: 4}
      }
    })

    ctx = feature_setup()

    assert {:error, {reason, meta}} =
             FeatureStates.execute(ctx.team, %{
               "product_name" => ctx.product.name,
               "feature_name" => ctx.feature_name,
               "implementation_name" => ctx.child_impl.name,
               "states" => %{
                 "#{ctx.feature_name}.REQ.1" => %{"status" => "completed", "comment" => "toolong"}
               }
             })

    assert reason =~ "configured maximum length"
    assert meta[:max_comment_length] == 4
  end

  test "rejects requests that exceed the configured ACID cap" do
    Application.put_env(:acai, :api_operations, %{
      default: %{
        request_size_cap: 2_000_000,
        semantic_caps: %{},
        rate_limit: %{requests: 60, window_seconds: 60}
      },
      feature_states: %{
        semantic_caps: %{max_states: 1, max_comment_length: 2_000}
      }
    })

    ctx = feature_setup()

    assert {:error, {reason, meta}} =
             FeatureStates.execute(ctx.team, %{
               "product_name" => ctx.product.name,
               "feature_name" => ctx.feature_name,
               "implementation_name" => ctx.child_impl.name,
               "states" => %{
                 "#{ctx.feature_name}.REQ.1" => %{"status" => "completed"},
                 "#{ctx.feature_name}.REQ.2" => %{"status" => "blocked"}
               }
             })

    assert reason =~ "maximum number of ACIDs"
    assert meta[:states_count] == 2
    assert meta[:max_states] == 1
  end
end
