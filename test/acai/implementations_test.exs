defmodule Acai.ImplementationsTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Implementations

  describe "batch_count_tracked_branches/1" do
    # feature-view.PERFORMANCE.1
    test "returns empty map for empty list" do
      assert Implementations.batch_count_tracked_branches([]) == %{}
    end

    test "returns map of implementation_id => branch count" do
      team = team_fixture()
      spec = spec_fixture(team)
      impl1 = implementation_fixture(spec)
      impl2 = implementation_fixture(spec, %{name: "Staging"})

      tracked_branch_fixture(impl1, %{branch_name: "branch-1"})
      tracked_branch_fixture(impl1, %{repo_uri: "github.com/acai-sh/other", branch_name: "main"})
      tracked_branch_fixture(impl2, %{branch_name: "branch-3"})

      counts = Implementations.batch_count_tracked_branches([impl1, impl2])

      assert Map.get(counts, impl1.id) == 2
      assert Map.get(counts, impl2.id) == 1
    end

    test "returns no entry for implementations with no branches" do
      team = team_fixture()
      spec = spec_fixture(team)
      impl = implementation_fixture(spec)

      counts = Implementations.batch_count_tracked_branches([impl])

      assert Map.get(counts, impl.id) == nil
    end
  end

  describe "batch_count_active_implementations_for_specs/1" do
    # product-view.PERFORMANCE.1
    test "returns empty map for empty list" do
      assert Implementations.batch_count_active_implementations_for_specs([]) == %{}
    end

    test "returns map of spec_id => active implementation count" do
      team = team_fixture()
      spec1 = spec_fixture(team)

      spec2 =
        spec_fixture(team, %{feature_name: "other-feature", path: "features/other/feature.yaml"})

      implementation_fixture(spec1)
      implementation_fixture(spec1, %{name: "Staging"})
      implementation_fixture(spec2)
      implementation_fixture(spec2, %{name: "Archived", is_active: false})

      counts = Implementations.batch_count_active_implementations_for_specs([spec1, spec2])

      assert Map.get(counts, spec1.id) == 2
      assert Map.get(counts, spec2.id) == 1
    end

    test "returns no entry for specs with no active implementations" do
      team = team_fixture()
      spec = spec_fixture(team)

      counts = Implementations.batch_count_active_implementations_for_specs([spec])

      assert Map.get(counts, spec.id) == nil
    end
  end

  describe "batch_get_requirement_status_counts/2" do
    # feature-view.PERFORMANCE.1
    test "returns empty map for empty input" do
      assert Implementations.batch_get_requirement_status_counts(%{}) == %{}
    end

    test "returns map of implementation_id => status counts" do
      team = team_fixture()
      spec = spec_fixture(team)
      req1 = requirement_fixture(spec)
      req2 = requirement_fixture(spec, %{local_id: "2"})
      impl1 = implementation_fixture(spec)
      impl2 = implementation_fixture(spec, %{name: "Staging"})

      requirement_status_fixture(impl1, req1, %{status: "accepted"})
      requirement_status_fixture(impl1, req2, %{status: "completed"})
      requirement_status_fixture(impl2, req1, %{status: "accepted"})
      requirement_status_fixture(impl2, req2, %{status: "accepted"})

      impl_requirements_map = %{
        impl1.id => 2,
        impl2.id => 2
      }

      counts = Implementations.batch_get_requirement_status_counts(impl_requirements_map)

      assert counts[impl1.id] == %{accepted: 1, completed: 1, null: 0}
      assert counts[impl2.id] == %{accepted: 2, completed: 0, null: 0}
    end

    test "handles implementations with no statuses" do
      team = team_fixture()
      spec = spec_fixture(team)
      impl = implementation_fixture(spec)

      impl_requirements_map = %{impl.id => 5}

      counts = Implementations.batch_get_requirement_status_counts(impl_requirements_map)

      assert counts[impl.id] == %{accepted: 0, completed: 0, null: 5}
    end
  end
end
