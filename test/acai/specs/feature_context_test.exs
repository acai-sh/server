defmodule Acai.Specs.FeatureContextTest do
  @moduledoc false

  use Acai.DataCase, async: true

  import Acai.DataModelFixtures
  import Ecto.Query

  alias Acai.Repo
  alias Acai.Implementations
  alias Acai.Specs
  alias Acai.Specs.Spec

  defp set_spec_updated_at(%Spec{} = spec, updated_at) do
    Repo.update_all(from(s in Spec, where: s.id == ^spec.id), set: [updated_at: updated_at])
  end

  describe "resolve_canonical_spec/3" do
    # feature-context.RESOLUTION.2, feature-context.RESOLUTION.8
    test "prefers the newest spec and breaks ties by branch name" do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      branch_alpha =
        branch_fixture(team, %{repo_uri: "github.com/acai/api-alpha", branch_name: "alpha"})

      branch_beta =
        branch_fixture(team, %{repo_uri: "github.com/acai/api-beta", branch_name: "beta"})

      tracked_branch_fixture(impl, %{branch: branch_alpha})
      tracked_branch_fixture(impl, %{branch: branch_beta})

      feature_name = "tie-break-feature"
      spec_alpha = spec_fixture(product, %{feature_name: feature_name, branch: branch_alpha})
      spec_beta = spec_fixture(product, %{feature_name: feature_name, branch: branch_beta})

      older = DateTime.from_naive!(~N[2026-03-25 00:00:00], "Etc/UTC")
      newer = DateTime.from_naive!(~N[2026-03-25 01:00:00], "Etc/UTC")

      set_spec_updated_at(spec_alpha, older)
      set_spec_updated_at(spec_beta, newer)

      {resolved, source} = Specs.resolve_canonical_spec(feature_name, impl.id)

      assert resolved.id == spec_beta.id
      assert source.source_branch.branch_name == "beta"

      set_spec_updated_at(spec_alpha, newer)
      set_spec_updated_at(spec_beta, newer)

      {resolved, source} = Specs.resolve_canonical_spec(feature_name, impl.id)

      assert resolved.id == spec_alpha.id
      assert source.source_branch.branch_name == "alpha"
    end
  end

  describe "get_feature_context/5" do
    # feature-context.RESOLUTION.3, feature-context.RESPONSE.13, feature-context.RESPONSE.2
    test "falls back to the nearest ancestor spec and ignores foreign-product specs" do
      team = team_fixture()
      product = product_fixture(team, %{name: "local-product"})
      other_product = product_fixture(team, %{name: "other-product"})

      parent = implementation_fixture(product, %{name: "parent"})

      child =
        implementation_fixture(product, %{name: "child", parent_implementation_id: parent.id})

      parent_branch =
        branch_fixture(team, %{repo_uri: "github.com/acai/api", branch_name: "parent-branch"})

      child_branch =
        branch_fixture(team, %{repo_uri: "github.com/acai/api", branch_name: "child-branch"})

      tracked_branch_fixture(parent, %{branch: parent_branch})
      tracked_branch_fixture(child, %{branch: child_branch})

      feature_name = "shared-feature"
      _parent_spec = spec_fixture(product, %{feature_name: feature_name, branch: parent_branch})

      _foreign_spec =
        spec_fixture(other_product, %{feature_name: feature_name, branch: child_branch})

      {:ok, context} = Specs.get_feature_context(team, product.name, feature_name, child.name)

      assert context.implementation_name == child.name
      assert context.spec_source.source_type == "inherited"
      assert context.spec_source.implementation_name == parent.name
      assert context.spec_source.branch_names == [parent_branch.branch_name]
    end

    # feature-context.RESOLUTION.6, feature-context.RESOLUTION.4
    test "stops state inheritance when a local empty row exists" do
      team = team_fixture(%{name: "empty-state-team-#{System.unique_integer([:positive])}"})
      product = product_fixture(team)
      parent = implementation_fixture(product, %{name: "parent"})

      child =
        implementation_fixture(product, %{name: "child", parent_implementation_id: parent.id})

      parent_branch =
        branch_fixture(team, %{repo_uri: "github.com/acai/api", branch_name: "main"})

      tracked_branch_fixture(parent, %{branch: parent_branch})

      feature_name = "state-inheritance-feature"

      spec =
        spec_fixture(product, %{
          feature_name: feature_name,
          branch: parent_branch,
          requirements: %{"#{feature_name}.REQ.1" => %{requirement: "Do the thing"}}
        })

      {:ok, parent_state} =
        Specs.create_feature_impl_state(feature_name, parent, %{
          states: %{
            "#{feature_name}.REQ.1" => %{"status" => "completed", "comment" => "done"}
          }
        })

      {:ok, child_state} =
        Specs.create_feature_impl_state(feature_name, child, %{states: %{}})

      assert {resolved_state, source_impl_id} =
               Specs.get_feature_impl_state_with_inheritance(feature_name, child.id)

      assert resolved_state.id == child_state.id
      assert source_impl_id == nil

      {:ok, context} = Specs.get_feature_context(team, product.name, feature_name, child.name)

      [acid] = context.acids
      assert acid.acid == "#{feature_name}.REQ.1"
      assert acid.state.status == nil
      assert context.states_source.source_type == "local"
      assert context.states_source.implementation_name == child.name
      assert parent_state.id != child_state.id
      assert spec.feature_name == feature_name
    end

    # feature-context.RESOLUTION.7, feature-context.REQUEST.7-1, feature-context.RESPONSE.4
    test "filters returned ACIDs by repeated statuses including null" do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      branch = branch_fixture(team, %{repo_uri: "github.com/acai/api", branch_name: "main"})
      tracked_branch_fixture(impl, %{branch: branch})

      feature_name = "status-filter-feature"

      spec =
        spec_fixture(product, %{
          feature_name: feature_name,
          branch: branch,
          requirements: %{
            "#{feature_name}.REQ.1" => %{requirement: "Done"},
            "#{feature_name}.REQ.2" => %{requirement: "Unset"},
            "#{feature_name}.REQ.3" => %{requirement: "Blocked"}
          }
        })

      {:ok, _} =
        Specs.create_feature_impl_state(feature_name, impl, %{
          states: %{
            "#{feature_name}.REQ.1" => %{"status" => "completed"},
            "#{feature_name}.REQ.2" => %{"status" => nil},
            "#{feature_name}.REQ.3" => %{"status" => "blocked"}
          }
        })

      {:ok, context} =
        Specs.get_feature_context(team, product.name, feature_name, impl.name,
          statuses: [nil, "completed"]
        )

      assert Enum.map(context.acids, & &1.acid) == [
               "#{feature_name}.REQ.1",
               "#{feature_name}.REQ.2"
             ]

      assert context.summary.total_acids == 2
      assert context.summary.status_counts == %{"completed" => 1, "null" => 1}
      assert context.acids |> Enum.any?(&(&1.state.status == nil))
      assert context.acids |> Enum.any?(&(&1.state.status == "completed"))
      assert context.acids |> Enum.all?(&(&1.state.status in [nil, "completed"]))
      assert spec.feature_name == feature_name
    end

    # feature-context.RESOLUTION.5
    test "falls back to parent refs when no local refs exist" do
      team = team_fixture()
      product = product_fixture(team)
      parent = implementation_fixture(product, %{name: "parent"})

      child =
        implementation_fixture(product, %{name: "child", parent_implementation_id: parent.id})

      parent_branch =
        branch_fixture(team, %{repo_uri: "github.com/acai/api", branch_name: "main"})

      child_branch =
        branch_fixture(team, %{repo_uri: "github.com/acai/api", branch_name: "feature"})

      tracked_branch_fixture(parent, %{branch: parent_branch})
      tracked_branch_fixture(child, %{branch: child_branch})

      feature_name = "refs-feature"

      _spec =
        spec_fixture(product, %{
          feature_name: feature_name,
          branch: parent_branch,
          requirements: %{"#{feature_name}.REQ.1" => %{requirement: "Track me"}}
        })

      feature_branch_ref_fixture(parent_branch, feature_name, %{
        refs: %{
          "#{feature_name}.REQ.1" => [
            %{"path" => "lib/acai/example.ex:1", "is_test" => false}
          ]
        }
      })

      {:ok, context} =
        Specs.get_feature_context(team, product.name, feature_name, child.name,
          include_refs: true
        )

      [acid] = context.acids
      assert context.refs_source.source_type == "inherited"
      assert context.refs_source.implementation_name == parent.name
      assert context.refs_source.branch_names == [parent_branch.branch_name]
      assert acid.refs_count == 1
      assert acid.test_refs_count == 0

      assert [
               %{
                 path: "lib/acai/example.ex:1",
                 branch_name: "main",
                 repo_uri: "github.com/acai/api",
                 is_test: false
               }
             ] = acid.refs
    end
  end

  describe "get_implementation_by_team_and_product_name/3" do
    # implementations.FILTERS.1
    test "finds an implementation only within the requested team and product" do
      team = team_fixture()
      product = product_fixture(team, %{name: "api-product"})
      other_product = product_fixture(team, %{name: "other-product"})

      impl = implementation_fixture(product, %{name: "Production"})
      _other_impl = implementation_fixture(other_product, %{name: "Production"})

      assert {:ok, found} =
               Implementations.get_implementation_by_team_and_product_name(
                 team,
                 product,
                 "production"
               )

      assert found.id == impl.id

      assert {:error, :not_found} =
               Implementations.get_implementation_by_team_and_product_name(
                 team,
                 other_product,
                 "missing"
               )
    end
  end
end
