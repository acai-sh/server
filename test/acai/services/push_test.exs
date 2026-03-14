defmodule Acai.Services.PushTest do
  @moduledoc """
  Tests for the Push service.

  ACIDs from push.feature.yaml:
  - push.INSERT_SPEC.1 - Inserts a new spec record
  - push.UPDATE_SPEC.1 - Updates existing spec
  - push.REFS.1-6 - Ref writing behavior
  - push.STATES.1-4 - State writing behavior
  - push.NEW_IMPLS.1-5 - New implementation creation
  - push.LINK_IMPLS.1-3 - Linking to existing implementations
  - push.EXISTING_IMPLS.1-4 - Existing implementation handling
  - push.PARENTS.1-3 - Parent implementation handling
  - push.IDEMPOTENCY.1-4 - Idempotency guarantees
  """

  use Acai.DataCase, async: true

  import Acai.DataModelFixtures
  alias Acai.AccountsFixtures
  alias Acai.Services.Push
  alias Acai.Teams
  alias Acai.Repo
  alias Acai.Implementations.{Branch, Implementation, TrackedBranch}
  alias Acai.Specs.{Spec, FeatureImplState, FeatureBranchRef}
  alias Acai.Products.Product

  @valid_push_params %{
    repo_uri: "github.com/test-org/test-repo",
    branch_name: "main",
    commit_hash: "abc123def456",
    specs: [
      %{
        feature: %{
          name: "test-feature",
          product: "test-product",
          description: "A test feature",
          version: "1.0.0"
        },
        requirements: %{
          "test-feature.REQ.1" => %{
            requirement: "Must do something"
          }
        },
        meta: %{
          path: "features/test.feature.yaml",
          last_seen_commit: "abc123def456"
        }
      }
    ]
  }

  describe "execute/2" do
    setup do
      user = AccountsFixtures.user_fixture()
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      {:ok, token} =
        Teams.generate_token(
          %{user: user},
          team,
          %{name: "Test Token"}
        )

      %{team: team, user: user, token: token}
    end

    # push.INSERT_SPEC.1
    test "inserts a new spec record when first time feature_name is pushed", %{
      token: token
    } do
      {:ok, result} = Push.execute(token, @valid_push_params)

      assert result.specs_created == 1
      assert result.specs_updated == 0

      # Verify spec was created in DB
      branch =
        Repo.one(
          from b in Branch,
            where: b.repo_uri == "github.com/test-org/test-repo" and b.branch_name == "main"
        )

      spec = Repo.one(from s in Spec, where: s.branch_id == ^branch.id)
      assert spec.feature_name == "test-feature"
    end

    # push.UPDATE_SPEC.1, push.UPDATE_SPEC.2, push.UPDATE_SPEC.3
    test "updates existing spec when same feature_name is pushed again", %{
      token: token
    } do
      # First push
      {:ok, _} = Push.execute(token, @valid_push_params)

      # Second push with updated requirements
      updated_params =
        put_in(@valid_push_params, [:specs, Access.at(0), :requirements], %{
          "test-feature.REQ.1" => %{requirement: "Updated requirement"},
          "test-feature.REQ.2" => %{requirement: "New requirement"}
        })

      {:ok, result} = Push.execute(token, updated_params)

      # Should be an update, not create
      assert result.specs_created == 0
      assert result.specs_updated == 1

      # Verify spec was updated
      branch =
        Repo.one(
          from b in Branch,
            where: b.repo_uri == "github.com/test-org/test-repo" and b.branch_name == "main"
        )

      spec = Repo.one(from s in Spec, where: s.branch_id == ^branch.id)

      # push.UPDATE_SPEC.3 - Requirements completely overwritten
      assert map_size(spec.requirements) == 2

      assert get_in(spec.requirements, ["test-feature.REQ.1", "requirement"]) ==
               "Updated requirement"
    end

    # push.IDEMPOTENCY.1
    test "pushing same spec content multiple times is a no-op after the first", %{
      token: token
    } do
      # First push
      {:ok, result1} = Push.execute(token, @valid_push_params)
      assert result1.specs_created == 1

      # Second push with identical content
      {:ok, result2} = Push.execute(token, @valid_push_params)
      assert result2.specs_created == 0
      assert result2.specs_updated == 1
    end

    # push.NEW_IMPLS.1, push.NEW_IMPLS.1-1
    test "creates new implementation when branch is not tracked", %{token: token} do
      {:ok, result} = Push.execute(token, @valid_push_params)

      assert result.implementation_name == "main"
      assert result.implementation_id != nil
      assert result.product_name == "test-product"

      # Verify implementation in DB
      impl = Repo.get(Implementation, result.implementation_id)
      assert impl.name == "main"
      assert impl.is_active == true
    end

    # push.NEW_IMPLS.3
    test "creates new product when product name is new to the team", %{token: token} do
      {:ok, _} = Push.execute(token, @valid_push_params)

      team_id = token.team_id

      product =
        Repo.one(from p in Product, where: p.team_id == ^team_id and p.name == "test-product")

      assert product
    end

    # push.NEW_IMPLS.4
    test "rejects multi-product push", %{token: token} do
      multi_product_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "abc123",
        specs: [
          %{
            feature: %{name: "feature-1", product: "product-a"},
            requirements: %{"feature-1.REQ.1" => %{requirement: "Do something"}},
            meta: %{path: "f1.yaml", last_seen_commit: "abc"}
          },
          %{
            feature: %{name: "feature-2", product: "product-b"},
            requirements: %{"feature-2.REQ.1" => %{requirement: "Do something else"}},
            meta: %{path: "f2.yaml", last_seen_commit: "abc"}
          }
        ]
      }

      assert {:error, reason} = Push.execute(token, multi_product_params)
      assert reason =~ "multiple products"
    end

    # push.NEW_IMPLS.5
    test "rejects when auto-generated implementation name collides", %{
      token: token,
      team: team
    } do
      product = product_fixture(team, %{name: "test-product"})

      # Create an implementation with the same name as the branch
      implementation_fixture(product, %{name: "main"})

      assert {:error, reason} = Push.execute(token, @valid_push_params)
      assert reason =~ "already exists"
    end

    # push.LINK_IMPLS.1, push.LINK_IMPLS.2
    test "links to existing implementation when target_impl_name matches", %{
      token: token,
      team: team
    } do
      product = product_fixture(team, %{name: "test-product"})
      existing_impl = implementation_fixture(product, %{name: "my-impl"})

      params_with_target =
        Map.put(@valid_push_params, :target_impl_name, "my-impl")

      {:ok, result} = Push.execute(token, params_with_target)

      assert result.implementation_name == "my-impl"
      assert result.implementation_id == existing_impl.id
    end

    # push.LINK_IMPLS.3
    test "rejects link when implementation already tracks branch in same repo", %{
      token: token,
      team: team
    } do
      product = product_fixture(team, %{name: "test-product"})
      existing_impl = implementation_fixture(product, %{name: "my-impl"})

      # Create a branch and track it
      branch =
        branch_fixture(team, %{
          repo_uri: "github.com/test-org/test-repo",
          branch_name: "other-branch"
        })

      {:ok, _} =
        TrackedBranch.changeset(%TrackedBranch{}, %{
          implementation_id: existing_impl.id,
          branch_id: branch.id,
          repo_uri: "github.com/test-org/test-repo"
        })
        |> Repo.insert()

      # Try to link to this implementation from a different branch in same repo
      params_with_target =
        Map.put(@valid_push_params, :target_impl_name, "my-impl")

      assert {:error, reason} = Push.execute(token, params_with_target)
      assert reason =~ "already tracks a branch in this repository"
    end

    # push.EXISTING_IMPLS.2
    test "rejects when multiple implementations track branch without target_impl_name", %{
      token: token,
      team: team
    } do
      product = product_fixture(team, %{name: "test-product"})

      # First push to create initial implementation
      {:ok, _} = Push.execute(token, @valid_push_params)

      # Create a second implementation
      impl2 = implementation_fixture(product, %{name: "second-impl"})

      # Get the branch
      branch =
        Repo.one(
          from b in Branch,
            where: b.repo_uri == "github.com/test-org/test-repo" and b.branch_name == "main"
        )

      # Track the same branch from the second implementation
      {:ok, _} =
        TrackedBranch.changeset(%TrackedBranch{}, %{
          implementation_id: impl2.id,
          branch_id: branch.id,
          repo_uri: "github.com/test-org/test-repo"
        })
        |> Repo.insert()

      # Try push without specifying target
      assert {:error, reason} = Push.execute(token, @valid_push_params)
      assert reason =~ "multiple implementations"
    end

    # push.PARENTS.1, push.PARENTS.3
    test "creates implementation with parent when parent_impl_name provided", %{
      token: token,
      team: team
    } do
      product = product_fixture(team, %{name: "test-product"})
      parent_impl = implementation_fixture(product, %{name: "parent-impl"})

      params_with_parent =
        Map.put(@valid_push_params, :parent_impl_name, "parent-impl")

      {:ok, result} = Push.execute(token, params_with_parent)

      impl = Repo.get(Implementation, result.implementation_id)
      assert impl.parent_implementation_id == parent_impl.id
    end

    # push.PARENTS.3
    test "rejects when parent_impl_name doesn't exist", %{token: token} do
      params_with_parent =
        Map.put(@valid_push_params, :parent_impl_name, "nonexistent-parent")

      assert {:error, reason} = Push.execute(token, params_with_parent)
      assert reason =~ "not found"
    end

    # push.NEW_IMPLS.2
    test "rejects states push when branch not tracked and no specs", %{
      token: token
    } do
      states_params = %{
        repo_uri: "github.com/new-repo/test",
        branch_name: "feature",
        commit_hash: "abc123",
        states: %{
          data: %{
            "feature.REQ.1" => %{status: "completed"}
          }
        }
      }

      assert {:error, reason} = Push.execute(token, states_params)
      assert reason =~ "Cannot push states"
    end

    # push.WRITE_STATES.2 - State snapshot from parent
    test "snapshots states from parent on first state write", %{
      token: token,
      team: team
    } do
      product = product_fixture(team, %{name: "test-product"})

      # Create parent implementation with states
      parent_impl = implementation_fixture(product, %{name: "parent-impl"})

      # First push specs to parent impl to create the feature
      parent_push = @valid_push_params
      {:ok, _} = Push.execute(token, parent_push)

      # Add states to parent implementation
      {:ok, _} =
        FeatureImplState.changeset(%FeatureImplState{}, %{
          implementation_id: parent_impl.id,
          feature_name: "test-feature",
          states: %{
            "test-feature.REQ.1" => %{
              status: "completed",
              comment: "Parent state"
            }
          }
        })
        |> Repo.insert()

      # Now create child implementation with parent
      child_params =
        @valid_push_params
        |> Map.put(:branch_name, "child-branch")
        |> Map.put(:repo_uri, "github.com/test-org/child-repo")
        |> Map.put(:target_impl_name, nil)
        |> Map.put(:parent_impl_name, "parent-impl")

      # Push specs first to create child impl
      {:ok, _} = Push.execute(token, child_params)

      # Now push states - should snapshot from parent
      child_states_params = %{
        repo_uri: "github.com/test-org/child-repo",
        branch_name: "child-branch",
        commit_hash: "def789",
        states: %{
          data: %{
            "test-feature.REQ.2" => %{status: "in_progress"}
          }
        }
      }

      {:ok, _} = Push.execute(token, child_states_params)

      # Verify child has both parent's state and new state
      child_impl =
        Repo.one(from i in Implementation, where: i.name == "child-branch")

      child_state =
        Repo.one(
          from fis in FeatureImplState,
            where:
              fis.implementation_id == ^child_impl.id and
                fis.feature_name == "test-feature"
        )

      # Should have both parent's REQ.1 and child's REQ.2
      assert get_in(child_state.states, ["test-feature.REQ.1", "status"]) == "completed"
      assert get_in(child_state.states, ["test-feature.REQ.2", "status"]) == "in_progress"
    end

    # push.AUTH.2-5 - Scope checking
    test "rejects when token missing specs:write scope", %{team: team, user: user} do
      {:ok, limited_token} =
        Teams.generate_token(
          %{user: user},
          team,
          %{name: "Limited", scopes: ["refs:write"]}
        )

      assert {:error, reason} = Push.execute(limited_token, @valid_push_params)
      assert reason =~ "specs:write"
    end

    # push.AUTH.6, push.AUTH.7 - Team scoping
    test "resources are scoped to token's team", %{token: token, team: team} do
      {:ok, _} = Push.execute(token, @valid_push_params)

      # Verify branch belongs to the team
      branch =
        Repo.one(
          from b in Branch,
            where: b.repo_uri == "github.com/test-org/test-repo"
        )

      assert branch.team_id == team.id
    end
  end

  describe "refs handling" do
    setup do
      user = AccountsFixtures.user_fixture()
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      {:ok, token} =
        Teams.generate_token(
          %{user: user},
          team,
          %{name: "Test Token"}
        )

      # First push specs to create implementation
      {:ok, _} = Push.execute(token, @valid_push_params)

      %{team: team, user: user, token: token}
    end

    # push.REFS.3, push.WRITE_REFS.1, push.WRITE_REFS.2, push.WRITE_REFS.3, push.WRITE_REFS.4
    test "writes refs to feature_branch_refs", %{token: token} do
      refs_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "newcommit123",
        references: %{
          data: %{
            "test-feature.REQ.1" => [
              %{path: "lib/my_app.ex:42", is_test: false}
            ]
          }
        }
      }

      {:ok, _} = Push.execute(token, refs_params)

      # Verify refs were written
      branch =
        Repo.one(
          from b in Branch,
            where: b.repo_uri == "github.com/test-org/test-repo"
        )

      ref =
        Repo.one(
          from fbr in FeatureBranchRef,
            where: fbr.branch_id == ^branch.id and fbr.feature_name == "test-feature"
        )

      assert ref
      assert ref.refs["test-feature.REQ.1"] != nil
      assert ref.commit == "newcommit123"
    end

    # push.REFS.5 - Merge behavior
    test "merges refs when override is false", %{token: token} do
      # First refs push
      refs_params1 = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "commit1",
        references: %{
          override: false,
          data: %{
            "test-feature.REQ.1" => [
              %{path: "lib/file1.ex:10", is_test: false}
            ]
          }
        }
      }

      {:ok, _} = Push.execute(token, refs_params1)

      # Second refs push with different ACID
      refs_params2 = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "commit2",
        references: %{
          override: false,
          data: %{
            "test-feature.REQ.2" => [
              %{path: "lib/file2.ex:20", is_test: false}
            ]
          }
        }
      }

      {:ok, _} = Push.execute(token, refs_params2)

      # Verify both refs exist
      branch =
        Repo.one(
          from b in Branch,
            where: b.repo_uri == "github.com/test-org/test-repo"
        )

      ref =
        Repo.one(
          from fbr in FeatureBranchRef,
            where: fbr.branch_id == ^branch.id and fbr.feature_name == "test-feature"
        )

      assert map_size(ref.refs) == 2
      assert ref.refs["test-feature.REQ.1"] != nil
      assert ref.refs["test-feature.REQ.2"] != nil
    end

    # push.REFS.6 - Override behavior
    test "replaces all refs when override is true", %{token: token} do
      # First refs push
      refs_params1 = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "commit1",
        references: %{
          override: false,
          data: %{
            "test-feature.REQ.1" => [
              %{path: "lib/file1.ex:10", is_test: false}
            ]
          }
        }
      }

      {:ok, _} = Push.execute(token, refs_params1)

      # Second refs push with override
      refs_params2 = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "commit2",
        references: %{
          override: true,
          data: %{
            "test-feature.REQ.2" => [
              %{path: "lib/file2.ex:20", is_test: false}
            ]
          }
        }
      }

      {:ok, _} = Push.execute(token, refs_params2)

      # Verify only the new ref exists
      branch =
        Repo.one(
          from b in Branch,
            where: b.repo_uri == "github.com/test-org/test-repo"
        )

      ref =
        Repo.one(
          from fbr in FeatureBranchRef,
            where: fbr.branch_id == ^branch.id and fbr.feature_name == "test-feature"
        )

      assert map_size(ref.refs) == 1
      assert ref.refs["test-feature.REQ.1"] == nil
      assert ref.refs["test-feature.REQ.2"] != nil
    end

    # push.REFS.4 - Refs can be pushed independently
    test "allows refs-only push to untracked branch", %{token: token, team: _team} do
      refs_only_params = %{
        repo_uri: "github.com/test-org/new-repo",
        branch_name: "new-branch",
        commit_hash: "abc123",
        references: %{
          data: %{
            "some-feature.REQ.1" => [
              %{path: "lib/test.ex:42", is_test: false}
            ]
          }
        }
      }

      # push.WRITE_REFS.3 - Refs written even if branch not tracked
      {:ok, result} = Push.execute(token, refs_only_params)

      # No implementation since no specs
      assert result.implementation_id == nil

      # But branch and refs should exist
      branch =
        Repo.one(
          from b in Branch,
            where: b.repo_uri == "github.com/test-org/new-repo"
        )

      assert branch

      ref =
        Repo.one(
          from fbr in FeatureBranchRef,
            where: fbr.branch_id == ^branch.id and fbr.feature_name == "some-feature"
        )

      assert ref
    end
  end

  describe "states handling" do
    setup do
      user = AccountsFixtures.user_fixture()
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      {:ok, token} =
        Teams.generate_token(
          %{user: user},
          team,
          %{name: "Test Token"}
        )

      # First push specs to create implementation
      {:ok, _} = Push.execute(token, @valid_push_params)

      %{team: team, user: user, token: token}
    end

    # push.WRITE_STATES.1
    test "writes states to feature_impl_states", %{token: token} do
      states_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "abc123",
        states: %{
          data: %{
            "test-feature.REQ.1" => %{
              status: "completed",
              comment: "Done!"
            }
          }
        }
      }

      {:ok, _} = Push.execute(token, states_params)

      impl = Repo.one(from i in Implementation, where: i.name == "main")

      state =
        Repo.one(
          from fis in FeatureImplState,
            where: fis.implementation_id == ^impl.id and fis.feature_name == "test-feature"
        )

      assert state
      assert get_in(state.states, ["test-feature.REQ.1", "status"]) == "completed"
      assert get_in(state.states, ["test-feature.REQ.1", "comment"]) == "Done!"
    end

    # push.WRITE_STATES.3 - Merge behavior for states
    test "merges states on subsequent pushes", %{token: token} do
      # First states push
      states_params1 = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "commit1",
        states: %{
          data: %{
            "test-feature.REQ.1" => %{status: "completed"}
          }
        }
      }

      {:ok, _} = Push.execute(token, states_params1)

      # Second states push with different ACID
      states_params2 = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "commit2",
        states: %{
          data: %{
            "test-feature.REQ.2" => %{status: "in_progress"}
          }
        }
      }

      {:ok, _} = Push.execute(token, states_params2)

      impl = Repo.one(from i in Implementation, where: i.name == "main")

      state =
        Repo.one(
          from fis in FeatureImplState,
            where: fis.implementation_id == ^impl.id and fis.feature_name == "test-feature"
        )

      assert map_size(state.states) == 2
      assert get_in(state.states, ["test-feature.REQ.1", "status"]) == "completed"
      assert get_in(state.states, ["test-feature.REQ.2", "status"]) == "in_progress"
    end

    # push.STATES.1 - Override behavior
    test "replaces all states when override is true", %{token: token} do
      # First states push
      states_params1 = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "commit1",
        states: %{
          data: %{
            "test-feature.REQ.1" => %{status: "completed"}
          }
        }
      }

      {:ok, _} = Push.execute(token, states_params1)

      # Second states push with override
      states_params2 = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "commit2",
        states: %{
          override: true,
          data: %{
            "test-feature.REQ.2" => %{status: "in_progress"}
          }
        }
      }

      {:ok, _} = Push.execute(token, states_params2)

      impl = Repo.one(from i in Implementation, where: i.name == "main")

      state =
        Repo.one(
          from fis in FeatureImplState,
            where: fis.implementation_id == ^impl.id and fis.feature_name == "test-feature"
        )

      assert map_size(state.states) == 1
      assert get_in(state.states, ["test-feature.REQ.1"]) == nil
      assert get_in(state.states, ["test-feature.REQ.2", "status"]) == "in_progress"
    end
  end
end
