defmodule Acai.Services.PushTest do
  @moduledoc """
  Tests for the Push service.

  ACIDs from push.feature.yaml:
  - push.INSERT_SPEC.1 - Inserts a new spec record
  - push.UPDATE_SPEC.1 - Updates existing spec
  - push.REFS.1-6 - Ref writing behavior
  - push.STATES.1-4 - State writing behavior
  - push.REQUEST.9-10 - Updated request contract and duplicate feature guard
  - push.VALIDATION.6-9 - Product/refs-only validation matrix
  - push.ABUSE.2-5 - Semantic caps and rejection logging
  - push.AUTH.4 - Refs-only implementation scope enforcement
  - push.NEW_IMPLS.1-5 - New implementation creation
  - push.LINK_IMPLS.1-5 - Linking to existing implementations
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

    # push.INSERT_SPEC.1 - Batch optimization: multi-spec push with all new specs
    test "batch insert: handles multiple new specs in a single push", %{token: token} do
      multi_spec_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "abc123",
        specs: [
          %{
            feature: %{
              name: "feature-one",
              product: "test-product",
              description: "First feature",
              version: "1.0.0"
            },
            requirements: %{
              "feature-one.REQ.1" => %{requirement: "First requirement"}
            },
            meta: %{
              path: "features/one.feature.yaml",
              last_seen_commit: "abc123"
            }
          },
          %{
            feature: %{
              name: "feature-two",
              product: "test-product",
              description: "Second feature",
              version: "1.0.0"
            },
            requirements: %{
              "feature-two.REQ.1" => %{requirement: "Second requirement"}
            },
            meta: %{
              path: "features/two.feature.yaml",
              last_seen_commit: "abc123"
            }
          },
          %{
            feature: %{
              name: "feature-three",
              product: "test-product",
              description: "Third feature",
              version: "1.0.0"
            },
            requirements: %{
              "feature-three.REQ.1" => %{requirement: "Third requirement"}
            },
            meta: %{
              path: "features/three.feature.yaml",
              last_seen_commit: "abc123"
            }
          }
        ]
      }

      {:ok, result} = Push.execute(token, multi_spec_params)

      # All specs should be created
      assert result.specs_created == 3
      assert result.specs_updated == 0

      # Verify all specs exist in DB
      branch =
        Repo.one(
          from b in Branch,
            where: b.repo_uri == "github.com/test-org/test-repo" and b.branch_name == "main"
        )

      specs = Repo.all(from s in Spec, where: s.branch_id == ^branch.id)
      feature_names = Enum.map(specs, & &1.feature_name) |> Enum.sort()
      assert feature_names == ["feature-one", "feature-three", "feature-two"]
    end

    # push.UPDATE_SPEC.1, push.UPDATE_SPEC.2, push.IDEMPOTENCY.1
    # Batch optimization: multi-spec push with mix of new and existing specs
    test "batch update: updates existing specs without creating duplicates", %{token: token} do
      # First push - create initial specs
      initial_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "abc123",
        specs: [
          %{
            feature: %{
              name: "feature-alpha",
              product: "test-product",
              description: "Alpha feature",
              version: "1.0.0"
            },
            requirements: %{
              "feature-alpha.REQ.1" => %{requirement: "Original alpha req"}
            },
            meta: %{
              path: "features/alpha.feature.yaml",
              last_seen_commit: "abc123"
            }
          },
          %{
            feature: %{
              name: "feature-beta",
              product: "test-product",
              description: "Beta feature",
              version: "1.0.0"
            },
            requirements: %{
              "feature-beta.REQ.1" => %{requirement: "Original beta req"}
            },
            meta: %{
              path: "features/beta.feature.yaml",
              last_seen_commit: "abc123"
            }
          }
        ]
      }

      {:ok, result1} = Push.execute(token, initial_params)
      assert result1.specs_created == 2
      assert result1.specs_updated == 0

      # Second push - update one, add one new
      updated_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "def456",
        specs: [
          %{
            feature: %{
              name: "feature-alpha",
              product: "test-product",
              description: "Alpha feature updated",
              version: "1.1.0"
            },
            requirements: %{
              "feature-alpha.REQ.1" => %{requirement: "Updated alpha req"},
              "feature-alpha.REQ.2" => %{requirement: "New alpha req"}
            },
            meta: %{
              path: "features/alpha.feature.yaml",
              last_seen_commit: "def456"
            }
          },
          %{
            feature: %{
              name: "feature-gamma",
              product: "test-product",
              description: "Gamma feature",
              version: "1.0.0"
            },
            requirements: %{
              "feature-gamma.REQ.1" => %{requirement: "Gamma req"}
            },
            meta: %{
              path: "features/gamma.feature.yaml",
              last_seen_commit: "def456"
            }
          }
        ]
      }

      {:ok, result2} = Push.execute(token, updated_params)

      # Should update alpha and create gamma
      assert result2.specs_created == 1
      assert result2.specs_updated == 1

      # Verify final state - only 3 specs total (no duplicates)
      branch =
        Repo.one(
          from b in Branch,
            where: b.repo_uri == "github.com/test-org/test-repo" and b.branch_name == "main"
        )

      specs = Repo.all(from s in Spec, where: s.branch_id == ^branch.id)
      assert length(specs) == 3

      # Verify alpha was updated
      alpha = Enum.find(specs, &(&1.feature_name == "feature-alpha"))
      assert alpha.feature_description == "Alpha feature updated"
      assert alpha.feature_version == "1.1.0"
      assert map_size(alpha.requirements) == 2
    end

    # push.PERMANENCE.1 - Refs and states survive spec updates
    test "preserves refs and states when spec is updated", %{token: token} do
      # First push - create spec
      {:ok, result1} = Push.execute(token, @valid_push_params)

      # Push refs for the feature
      refs_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "refcommit",
        references: %{
          data: %{
            "test-feature.REQ.1" => [
              %{path: "lib/my_app.ex:42", is_test: false}
            ]
          }
        }
      }

      {:ok, _} = Push.execute(token, refs_params)

      # Push states for the feature
      states_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "statecommit",
        states: %{
          data: %{
            "test-feature.REQ.1" => %{status: "completed", comment: "Done!"}
          }
        }
      }

      {:ok, _} = Push.execute(token, states_params)

      # Verify refs and states exist
      branch =
        Repo.one(
          from b in Branch,
            where: b.repo_uri == "github.com/test-org/test-repo" and b.branch_name == "main"
        )

      ref =
        Repo.one(
          from fbr in FeatureBranchRef,
            where: fbr.branch_id == ^branch.id and fbr.feature_name == "test-feature"
        )

      assert ref
      assert ref.refs["test-feature.REQ.1"] != nil

      impl = Repo.get(Implementation, result1.implementation_id)

      state =
        Repo.one(
          from fis in FeatureImplState,
            where: fis.implementation_id == ^impl.id and fis.feature_name == "test-feature"
        )

      assert state
      assert get_in(state.states, ["test-feature.REQ.1", "status"]) == "completed"

      # Update the spec
      updated_params =
        put_in(@valid_push_params, [:specs, Access.at(0), :requirements], %{
          "test-feature.REQ.1" => %{requirement: "Updated requirement"},
          "test-feature.REQ.2" => %{requirement: "New requirement"}
        })

      {:ok, _} = Push.execute(token, updated_params)

      # Verify refs and states still exist after spec update
      ref_after =
        Repo.one(
          from fbr in FeatureBranchRef,
            where: fbr.branch_id == ^branch.id and fbr.feature_name == "test-feature"
        )

      assert ref_after
      assert ref_after.refs["test-feature.REQ.1"] != nil

      state_after =
        Repo.one(
          from fis in FeatureImplState,
            where: fis.implementation_id == ^impl.id and fis.feature_name == "test-feature"
        )

      assert state_after
      assert get_in(state_after.states, ["test-feature.REQ.1", "status"]) == "completed"
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

      # Second push with identical content - should be a no-op
      {:ok, result2} = Push.execute(token, @valid_push_params)
      assert result2.specs_created == 0
      assert result2.specs_updated == 0
    end

    # push.IDEMPOTENCY.1 - Multi-spec idempotency
    test "multi-spec identical re-push results in zero updates", %{token: token} do
      multi_spec_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "abc123",
        specs: [
          %{
            feature: %{
              name: "feature-one",
              product: "test-product",
              description: "First feature",
              version: "1.0.0"
            },
            requirements: %{
              "feature-one.REQ.1" => %{requirement: "First requirement"}
            },
            meta: %{
              path: "features/one.feature.yaml",
              last_seen_commit: "abc123"
            }
          },
          %{
            feature: %{
              name: "feature-two",
              product: "test-product",
              description: "Second feature",
              version: "1.0.0"
            },
            requirements: %{
              "feature-two.REQ.1" => %{requirement: "Second requirement"}
            },
            meta: %{
              path: "features/two.feature.yaml",
              last_seen_commit: "abc123"
            }
          }
        ]
      }

      # First push - creates 2 specs
      {:ok, result1} = Push.execute(token, multi_spec_params)
      assert result1.specs_created == 2
      assert result1.specs_updated == 0

      # Identical re-push - should be no-op
      {:ok, result2} = Push.execute(token, multi_spec_params)
      assert result2.specs_created == 0
      assert result2.specs_updated == 0
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

    # push.NEW_IMPLS.1, push.NEW_IMPLS.1-1
    test "creates a new implementation when target_impl_name does not exist", %{token: token} do
      params_with_target = Map.put(@valid_push_params, :target_impl_name, "new-impl")

      {:ok, result} = Push.execute(token, params_with_target)

      assert result.implementation_name == "new-impl"
      assert result.product_name == "test-product"

      impl = Repo.get(Implementation, result.implementation_id)
      assert impl.name == "new-impl"
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

    # push.REQUEST.10
    test "rejects duplicate feature names within one push", %{token: token} do
      duplicate_feature_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "abc123def456",
        specs: [
          %{
            feature: %{name: "dup-feature", product: "test-product"},
            requirements: %{"dup-feature.REQ.1" => %{requirement: "First"}},
            meta: %{path: "dup-1.yaml", last_seen_commit: "abc123"}
          },
          %{
            feature: %{name: "dup-feature", product: "test-product"},
            requirements: %{"dup-feature.REQ.2" => %{requirement: "Second"}},
            meta: %{path: "dup-2.yaml", last_seen_commit: "abc123"}
          }
        ]
      }

      assert {:error, reason} = Push.execute(token, duplicate_feature_params)
      assert reason =~ "duplicate feature.name"
    end

    # push.VALIDATION.6
    test "rejects product_name when it does not match pushed specs", %{token: token} do
      mismatch_params = Map.put(@valid_push_params, :product_name, "other-product")

      assert {:error, reason} = Push.execute(token, mismatch_params)
      assert reason =~ "product_name"
    end

    # push.ABUSE.2-1, push.ABUSE.2-2
    test "rejects pushes that exceed configured semantic caps", %{token: token} do
      original = Application.get_env(:acai, :api_operations)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:acai, :api_operations)
        else
          Application.put_env(:acai, :api_operations, original)
        end
      end)

      Application.put_env(:acai, :api_operations, %{
        default: %{semantic_caps: %{max_specs: 100, max_references: 100}},
        push: %{semantic_caps: %{max_specs: 0, max_references: 0}}
      })

      assert {:error, reason} = Push.execute(token, @valid_push_params)
      assert reason =~ "too many specs"
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

    # push.IDEMPOTENCY.5, push.IDEMPOTENCY.5-1
    test "rejects changing parent on an existing tracked implementation", %{
      token: token,
      team: team
    } do
      product = product_fixture(team, %{name: "test-product"})
      parent_impl = implementation_fixture(product, %{name: "parent-impl"})
      other_parent = implementation_fixture(product, %{name: "other-parent"})

      params_with_parent = Map.put(@valid_push_params, :parent_impl_name, "parent-impl")

      {:ok, _} = Push.execute(token, params_with_parent)

      {:ok, _} = Push.execute(token, params_with_parent)

      changed_parent_params = Map.put(@valid_push_params, :parent_impl_name, "other-parent")

      assert {:error, reason} = Push.execute(token, changed_parent_params)
      assert reason =~ "Parent implementation cannot be changed"

      impl = Repo.one(from i in Implementation, where: i.name == "main")
      assert impl.parent_implementation_id == parent_impl.id
      assert Repo.get(Implementation, other_parent.id)
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

      assert {:error, {:forbidden, reason}} = Push.execute(limited_token, @valid_push_params)
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

    # push.REQUEST.4, push.REQUEST.5, push.REQUEST.6, push.REQUEST.7, push.REQUEST.8
    # Regression test: String-key params should work identically to atom-key params
    test "accepts string-key params and normalizes them correctly", %{token: token} do
      string_key_params = %{
        "repo_uri" => "github.com/test-org/string-key-repo",
        "branch_name" => "string-branch",
        "commit_hash" => "stringcommit123",
        "specs" => [
          %{
            "feature" => %{
              "name" => "string-feature",
              "product" => "string-product",
              "description" => "A test feature with string keys",
              "version" => "1.0.0"
            },
            "requirements" => %{
              "string-feature.REQ.1" => %{
                "requirement" => "Must work with string keys"
              }
            },
            "meta" => %{
              "path" => "features/string.feature.yaml",
              "last_seen_commit" => "stringcommit123"
            }
          }
        ]
      }

      {:ok, result} = Push.execute(token, string_key_params)

      # Verify push succeeded with string keys
      assert result.specs_created == 1
      assert result.specs_updated == 0
      assert result.product_name == "string-product"
      assert result.implementation_name == "string-branch"

      # Verify spec was created in DB
      branch =
        Repo.one(
          from b in Branch,
            where: b.repo_uri == "github.com/test-org/string-key-repo"
        )

      spec = Repo.one(from s in Spec, where: s.branch_id == ^branch.id)
      assert spec.feature_name == "string-feature"
    end

    # push.NEW_IMPLS.6, push.NEW_IMPLS.6-1, push.NEW_IMPLS.6-2
    test "creates a child implementation when both target and parent are provided", %{
      token: token,
      team: team
    } do
      product = product_fixture(team, %{name: "test-product"})
      parent_impl = implementation_fixture(product, %{name: "parent-for-link"})

      params = %{
        repo_uri: "github.com/test-org/target-parent-repo",
        branch_name: "target-parent-branch",
        commit_hash: "tparent123",
        target_impl_name: "child-target-impl",
        parent_impl_name: "parent-for-link",
        specs: [
          %{
            feature: %{
              name: "target-parent-feature",
              product: "test-product",
              description: "Feature with both target and parent"
            },
            requirements: %{"target-parent-feature.REQ.1" => %{requirement: "Test req"}},
            meta: %{path: "features/tp.yaml", last_seen_commit: "tparent123"}
          }
        ]
      }

      {:ok, result} = Push.execute(token, params)

      assert result.implementation_name == "child-target-impl"
      assert result.implementation_id != parent_impl.id
      assert result.specs_created == 1

      impl = Repo.get(Implementation, result.implementation_id)
      assert impl.parent_implementation_id == parent_impl.id
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

    # push.LINK_IMPLS.5, push.VALIDATION.9
    test "rejects refs-only push with product_name and target_impl_name when target is missing",
         %{token: token} do
      refs_only_params = %{
        repo_uri: "github.com/test-org/new-repo",
        branch_name: "new-branch",
        commit_hash: "abc123",
        product_name: "test-product",
        target_impl_name: "missing-impl",
        references: %{
          data: %{
            "some-feature.REQ.1" => [
              %{path: "lib/test.ex:42", is_test: false}
            ]
          }
        }
      }

      assert {:error, reason} = Push.execute(token, refs_only_params)
      assert reason =~ "existing implementation"

      assert Repo.one(
               from i in Implementation,
                 where: i.team_id == ^token.team_id and i.name == "missing-impl"
             ) == nil
    end

    # push.NEW_IMPLS.6, push.NEW_IMPLS.6-1, push.NEW_IMPLS.6-2
    test "creates a child implementation from refs-only inputs on an untracked branch", %{
      token: token,
      team: team
    } do
      product = product_fixture(team, %{name: "child-product"})
      parent_impl = implementation_fixture(product, %{name: "parent-impl"})

      refs_only_child_params = %{
        repo_uri: "github.com/test-org/child-repo",
        branch_name: "child-branch",
        commit_hash: "abc123",
        product_name: "child-product",
        target_impl_name: "child-impl",
        parent_impl_name: "parent-impl",
        references: %{
          data: %{
            "child-feature.REQ.1" => [%{path: "lib/test.ex:42", is_test: false}]
          }
        }
      }

      {:ok, result} = Push.execute(token, refs_only_child_params)

      assert result.implementation_name == "child-impl"
      assert result.product_name == "child-product"

      impl = Repo.get(Implementation, result.implementation_id)
      assert impl.parent_implementation_id == parent_impl.id
    end

    # push.AUTH.4
    test "rejects refs-only implementation creation without impls:write", %{
      team: team,
      user: user
    } do
      product = product_fixture(team, %{name: "child-product"})
      _parent_impl = implementation_fixture(product, %{name: "parent-impl"})

      {:ok, limited_token} =
        Teams.generate_token(
          %{user: user},
          team,
          %{name: "Refs Only", scopes: ["refs:write"]}
        )

      refs_only_child_params = %{
        repo_uri: "github.com/test-org/child-repo",
        branch_name: "child-branch",
        commit_hash: "abc123",
        product_name: "child-product",
        target_impl_name: "child-impl",
        parent_impl_name: "parent-impl",
        references: %{
          data: %{
            "child-feature.REQ.1" => [%{path: "lib/test.ex:42", is_test: false}]
          }
        }
      }

      assert {:error, {:forbidden, reason}} = Push.execute(limited_token, refs_only_child_params)
      assert reason =~ "impls:write"
    end

    # push.VALIDATION.7, push.VALIDATION.8, push.VALIDATION.9
    test "rejects partial refs-only implementation inputs on an untracked branch", %{
      token: token
    } do
      partial_params = %{
        repo_uri: "github.com/test-org/new-repo",
        branch_name: "new-branch",
        commit_hash: "abc123",
        references: %{
          data: %{"feature.REQ.1" => [%{path: "lib/test.ex:42", is_test: false}]}
        },
        product_name: "test-product"
      }

      assert {:error, reason} = Push.execute(token, partial_params)
      assert reason =~ "rule set"
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

  describe "batch refs optimization" do
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

    # push.WRITE_REFS.1 - Batch refs with multiple features in one payload
    test "batch write: writes refs for multiple features in single push", %{token: token} do
      # Push refs for multiple features without pushing specs first
      # push.WRITE_REFS.3 - Refs can be written even without implementation
      multi_feature_refs = %{
        repo_uri: "github.com/test-org/batch-repo",
        branch_name: "main",
        commit_hash: "batchcommit1",
        references: %{
          data: %{
            "feature-alpha.REQ.1" => [%{path: "lib/alpha.ex:10", is_test: false}],
            "feature-beta.REQ.1" => [%{path: "lib/beta.ex:20", is_test: false}],
            "feature-gamma.REQ.1" => [%{path: "lib/gamma.ex:30", is_test: false}]
          }
        }
      }

      {:ok, result} = Push.execute(token, multi_feature_refs)

      # No implementation since no specs
      assert result.implementation_id == nil

      # Verify branch exists
      branch =
        Repo.one(
          from b in Branch,
            where: b.repo_uri == "github.com/test-org/batch-repo"
        )

      assert branch

      # Verify all three feature buckets were created
      refs =
        Repo.all(
          from fbr in FeatureBranchRef,
            where: fbr.branch_id == ^branch.id
        )

      assert length(refs) == 3

      feature_names = Enum.map(refs, & &1.feature_name) |> Enum.sort()
      assert feature_names == ["feature-alpha", "feature-beta", "feature-gamma"]

      # Verify each ref has the correct data
      alpha_ref = Enum.find(refs, &(&1.feature_name == "feature-alpha"))
      assert alpha_ref.refs["feature-alpha.REQ.1"] != nil
      assert alpha_ref.commit == "batchcommit1"
    end

    # push.REFS.5, push.IDEMPOTENCY.4 - Batch merge without duplicate bucket creation
    test "batch merge: merges refs into existing rows without creating duplicates", %{
      token: token
    } do
      # First push - create initial refs
      initial_refs = %{
        repo_uri: "github.com/test-org/merge-repo",
        branch_name: "main",
        commit_hash: "commit1",
        references: %{
          override: false,
          data: %{
            "merge-feature.REQ.1" => [%{path: "lib/original.ex:10", is_test: false}]
          }
        }
      }

      {:ok, _} = Push.execute(token, initial_refs)

      branch =
        Repo.one(
          from b in Branch,
            where: b.repo_uri == "github.com/test-org/merge-repo"
        )

      # Verify initial state
      initial_row =
        Repo.one(
          from fbr in FeatureBranchRef,
            where: fbr.branch_id == ^branch.id and fbr.feature_name == "merge-feature"
        )

      initial_id = initial_row.id
      assert initial_row.refs["merge-feature.REQ.1"] != nil

      # Second push - add new refs (merge mode)
      merge_refs = %{
        repo_uri: "github.com/test-org/merge-repo",
        branch_name: "main",
        commit_hash: "commit2",
        references: %{
          override: false,
          data: %{
            "merge-feature.REQ.2" => [%{path: "lib/added.ex:20", is_test: false}]
          }
        }
      }

      {:ok, _} = Push.execute(token, merge_refs)

      # Verify same row was updated (no duplicate created)
      final_rows =
        Repo.all(
          from fbr in FeatureBranchRef,
            where: fbr.branch_id == ^branch.id and fbr.feature_name == "merge-feature"
        )

      assert length(final_rows) == 1
      final_row = hd(final_rows)
      assert final_row.id == initial_id

      # Verify both refs are present (merged)
      assert final_row.refs["merge-feature.REQ.1"] != nil
      assert final_row.refs["merge-feature.REQ.2"] != nil
      assert final_row.commit == "commit2"
    end
  end

  describe "batch states optimization" do
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

    # push.WRITE_STATES.1 - Batch states with multiple features in one payload
    test "batch write: writes states for multiple features in single push", %{token: token} do
      # First push specs for multiple features (in addition to test-feature from setup)
      multi_spec_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "speccommit",
        specs: [
          %{
            feature: %{
              name: "multi-feature-one",
              product: "test-product",
              description: "First feature",
              version: "1.0.0"
            },
            requirements: %{"multi-feature-one.REQ.1" => %{requirement: "First req"}},
            meta: %{path: "features/one.yaml", last_seen_commit: "speccommit"}
          },
          %{
            feature: %{
              name: "multi-feature-two",
              product: "test-product",
              description: "Second feature",
              version: "1.0.0"
            },
            requirements: %{"multi-feature-two.REQ.1" => %{requirement: "Second req"}},
            meta: %{path: "features/two.yaml", last_seen_commit: "speccommit"}
          }
        ]
      }

      {:ok, _} = Push.execute(token, multi_spec_params)

      impl = Repo.one(from i in Implementation, where: i.name == "main")

      # Now push states for both features
      multi_feature_states = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "statecommit",
        states: %{
          data: %{
            "multi-feature-one.REQ.1" => %{status: "completed"},
            "multi-feature-two.REQ.1" => %{status: "in_progress"}
          }
        }
      }

      {:ok, _} = Push.execute(token, multi_feature_states)

      # Verify both feature state buckets were created (2 new ones)
      states =
        Repo.all(
          from fis in FeatureImplState,
            where: fis.implementation_id == ^impl.id
        )

      # Should have 2 state rows (for multi-feature-one and multi-feature-two)
      # test-feature has no state row yet since we didn't push states for it
      assert length(states) == 2

      one_state = Enum.find(states, &(&1.feature_name == "multi-feature-one"))
      two_state = Enum.find(states, &(&1.feature_name == "multi-feature-two"))

      assert one_state
      assert get_in(one_state.states, ["multi-feature-one.REQ.1", "status"]) == "completed"

      assert two_state
      assert get_in(two_state.states, ["multi-feature-two.REQ.1", "status"]) == "in_progress"
    end

    # push.WRITE_STATES.2 - Batch parent inheritance for multiple features
    test "batch inheritance: snapshots parent states for multiple features on first write", %{
      token: token,
      team: team
    } do
      # Use existing test-product from setup
      product =
        Repo.one(from p in Product, where: p.team_id == ^team.id and p.name == "test-product")

      # Create parent implementation with existing states for multiple features
      _parent_impl = implementation_fixture(product, %{name: "parent-batch-impl"})

      # Push specs to parent implementation for two features
      parent_specs = %{
        repo_uri: "github.com/test-org/parent-repo",
        branch_name: "parent-branch",
        commit_hash: "parentcommit",
        specs: [
          %{
            feature: %{
              name: "inherit-feature-a",
              product: "test-product",
              description: "Feature A"
            },
            requirements: %{"inherit-feature-a.REQ.1" => %{requirement: "Req A"}},
            meta: %{path: "a.yaml", last_seen_commit: "parentcommit"}
          },
          %{
            feature: %{
              name: "inherit-feature-b",
              product: "test-product",
              description: "Feature B"
            },
            requirements: %{"inherit-feature-b.REQ.1" => %{requirement: "Req B"}},
            meta: %{path: "b.yaml", last_seen_commit: "parentcommit"}
          }
        ]
      }

      {:ok, _} = Push.execute(token, parent_specs)

      # Manually add states to parent for both features
      parent_impl_record =
        Repo.one(from i in Implementation, where: i.name == "parent-batch-impl")

      {:ok, _} =
        FeatureImplState.changeset(%FeatureImplState{}, %{
          implementation_id: parent_impl_record.id,
          feature_name: "inherit-feature-a",
          states: %{"inherit-feature-a.REQ.1" => %{status: "completed", comment: "Parent A"}}
        })
        |> Repo.insert()

      {:ok, _} =
        FeatureImplState.changeset(%FeatureImplState{}, %{
          implementation_id: parent_impl_record.id,
          feature_name: "inherit-feature-b",
          states: %{"inherit-feature-b.REQ.1" => %{status: "accepted", comment: "Parent B"}}
        })
        |> Repo.insert()

      # Create child implementation with parent
      child_specs = %{
        repo_uri: "github.com/test-org/child-repo",
        branch_name: "child-branch",
        commit_hash: "childcommit",
        specs: [
          %{
            feature: %{
              name: "inherit-feature-a",
              product: "test-product",
              description: "Feature A"
            },
            requirements: %{"inherit-feature-a.REQ.1" => %{requirement: "Req A"}},
            meta: %{path: "a.yaml", last_seen_commit: "childcommit"}
          },
          %{
            feature: %{
              name: "inherit-feature-b",
              product: "test-product",
              description: "Feature B"
            },
            requirements: %{"inherit-feature-b.REQ.1" => %{requirement: "Req B"}},
            meta: %{path: "b.yaml", last_seen_commit: "childcommit"}
          }
        ]
      }

      # Push specs to create child impl with parent
      child_params =
        child_specs
        |> Map.put(:target_impl_name, nil)
        |> Map.put(:parent_impl_name, "parent-batch-impl")

      {:ok, _} = Push.execute(token, child_params)

      # Now push states to child - should inherit from parent for both features
      child_states = %{
        repo_uri: "github.com/test-org/child-repo",
        branch_name: "child-branch",
        commit_hash: "childstatecommit",
        states: %{
          data: %{
            # Only add new states, no updates to existing
            "inherit-feature-a.REQ.2" => %{status: "in_progress"},
            "inherit-feature-b.REQ.2" => %{status: "pending"}
          }
        }
      }

      {:ok, _} = Push.execute(token, child_states)

      # Verify child has inherited parent states for both features
      child_impl = Repo.one(from i in Implementation, where: i.name == "child-branch")

      child_states_records =
        Repo.all(
          from fis in FeatureImplState,
            where: fis.implementation_id == ^child_impl.id
        )

      assert length(child_states_records) == 2

      # Feature A should have both inherited and new state
      state_a = Enum.find(child_states_records, &(&1.feature_name == "inherit-feature-a"))
      assert get_in(state_a.states, ["inherit-feature-a.REQ.1", "status"]) == "completed"
      assert get_in(state_a.states, ["inherit-feature-a.REQ.1", "comment"]) == "Parent A"
      assert get_in(state_a.states, ["inherit-feature-a.REQ.2", "status"]) == "in_progress"

      # Feature B should have both inherited and new state
      state_b = Enum.find(child_states_records, &(&1.feature_name == "inherit-feature-b"))
      assert get_in(state_b.states, ["inherit-feature-b.REQ.1", "status"]) == "accepted"
      assert get_in(state_b.states, ["inherit-feature-b.REQ.1", "comment"]) == "Parent B"
      assert get_in(state_b.states, ["inherit-feature-b.REQ.2", "status"]) == "pending"
    end
  end
end
