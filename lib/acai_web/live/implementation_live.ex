defmodule AcaiWeb.ImplementationLive do
  use AcaiWeb, :live_view

  import Ecto.Query

  alias Acai.Teams
  alias Acai.Specs
  alias Acai.Implementations

  @impl true
  def mount(
        %{"team_name" => team_name, "feature_name" => feature_name, "impl_slug" => impl_slug},
        _session,
        socket
      ) do
    team = Teams.get_team_by_name!(team_name)

    # implementation-view.ROUTING.2: Parse slug and look up implementation
    case Implementations.get_implementation_by_slug(impl_slug) do
      nil ->
        # implementation-view.ROUTING.3: Redirect if implementation not found
        socket =
          socket
          |> put_flash(:error, "Implementation not found")
          |> push_navigate(to: ~p"/t/#{team.name}/f/#{feature_name}")

        {:ok, socket}

      implementation ->
        # Verify the implementation belongs to this team
        if implementation.team_id == team.id do
          # data-model.IMPLS: Implementation belongs to product, not spec
          # Find the spec for this feature_name within the same product
          implementation = Acai.Repo.preload(implementation, :product)

          case find_spec_for_feature(team, implementation.product_id, feature_name) do
            nil ->
              # No spec found for this feature in this product
              socket =
                socket
                |> put_flash(:error, "Feature not found in this product")
                |> push_navigate(to: ~p"/t/#{team.name}/f/#{feature_name}")

              {:ok, socket}

            spec ->
              mount_implementation_view(socket, team, spec, implementation, feature_name)
          end
        else
          # Team mismatch - redirect
          socket =
            socket
            |> put_flash(:error, "Implementation not found")
            |> push_navigate(to: ~p"/t/#{team.name}/f/#{feature_name}")

          {:ok, socket}
        end
    end
  end

  # Find a spec by feature_name for a given product
  defp find_spec_for_feature(_team, product_id, feature_name) do
    Acai.Repo.one(
      from s in Acai.Specs.Spec,
        where: s.product_id == ^product_id,
        where: s.feature_name == ^feature_name,
        limit: 1
    )
  end

  defp mount_implementation_view(socket, team, spec, implementation, feature_name) do
    # data-model.SPECS.11: Requirements are JSONB on the spec
    # data-model.SPECS.12: Preload product association for breadcrumb
    # data-model.SPECS.3: Preload branch association for repo info
    spec = Acai.Repo.preload(spec, [:product, :branch])

    # Build requirement rows from the JSONB requirements map
    requirements = build_requirement_rows_from_spec(spec)

    # data-model.FEATURE_IMPL_STATES: Load states from feature_impl_states JSONB
    spec_impl_state = Specs.get_spec_impl_state(spec, implementation)
    states = if spec_impl_state, do: spec_impl_state.states, else: %{}

    # data-model.INHERITANCE.8: Aggregate refs from feature_branch_refs across tracked branches
    # feature-impl-view.MAIN.4: Refs column shows total refs across tracked branches
    # feature-impl-view.INHERITANCE.3: Refs aggregated from tracked branches
    _ref_counts = Implementations.count_refs_for_implementation(feature_name, implementation.id)

    # Load tracked branches with preloaded branch association
    tracked_branches = Implementations.list_tracked_branches(implementation)

    # Get aggregated refs for the drawer (we'll pass this to the drawer component)
    {aggregated_refs, is_inherited} =
      Implementations.get_aggregated_refs_with_inheritance(feature_name, implementation.id)

    # Build requirement rows with status and counts
    requirement_rows =
      requirements
      |> Enum.map(fn req ->
        acid = req.acid
        state_data = Map.get(states, acid, %{"status" => nil})

        # feature-impl-view.DRAWER.4: Get refs for this ACID from aggregated branch refs
        acid_refs = Implementations.get_refs_for_acid(aggregated_refs, acid)

        # Count refs and tests across all branches
        refs_count =
          Enum.reduce(acid_refs, 0, fn {_branch, ref_list}, acc ->
            acc + Enum.count(ref_list, fn ref -> not Map.get(ref, "is_test", false) end)
          end)

        tests_count =
          Enum.reduce(acid_refs, 0, fn {_branch, ref_list}, acc ->
            acc + Enum.count(ref_list, fn ref -> Map.get(ref, "is_test", false) end)
          end)

        %{
          id: acid,
          acid: acid,
          definition: req.definition,
          status: state_data["status"],
          refs_count: refs_count,
          tests_count: tests_count,
          note: req.note,
          is_deprecated: req.is_deprecated,
          replaced_by: req.replaced_by
        }
      end)
      |> Enum.sort_by(& &1.acid)

    socket =
      socket
      |> assign(:team, team)
      |> assign(:spec, spec)
      |> assign(:implementation, implementation)
      |> assign(:feature_name, feature_name)
      |> assign(:requirements, requirement_rows)
      |> assign(:tracked_branches, tracked_branches)
      |> assign(:selected_acid, nil)
      |> assign(:drawer_visible, false)
      |> assign(:sort_by, :acid)
      |> assign(:sort_dir, :asc)
      |> assign(:refs_inherited, is_inherited)
      |> assign(:aggregated_refs, aggregated_refs)
      |> assign(
        :current_path,
        "/t/#{team.name}/i/#{Implementations.implementation_slug(implementation)}/f/#{feature_name}"
      )

    {:ok, socket}
  end

  # data-model.SPECS.11: Build requirement rows from JSONB requirements map
  defp build_requirement_rows_from_spec(spec) do
    spec.requirements
    |> Enum.map(fn {acid, data} ->
      %{
        acid: acid,
        definition: Map.get(data, "definition", ""),
        note: Map.get(data, "note"),
        is_deprecated: Map.get(data, "is_deprecated", false),
        replaced_by: Map.get(data, "replaced_by", [])
      }
    end)
  end

  @impl true
  def handle_event("sort", %{"by" => by}, socket) do
    by_atom = String.to_existing_atom(by)
    current_dir = socket.assigns.sort_dir

    # Toggle direction if clicking same column, otherwise default to asc
    new_dir =
      if socket.assigns.sort_by == by_atom do
        if current_dir == :asc, do: :desc, else: :asc
      else
        :asc
      end

    sorted_requirements = sort_requirements(socket.assigns.requirements, by_atom, new_dir)

    {:noreply,
     socket
     |> assign(:sort_by, by_atom)
     |> assign(:sort_dir, new_dir)
     |> assign(:requirements, sorted_requirements)}
  end

  def handle_event("open_drawer", %{"acid" => acid}, socket) do
    {:noreply,
     socket
     |> assign(:selected_acid, acid)
     |> assign(:drawer_visible, true)}
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply,
     socket
     |> assign(:drawer_visible, false)
     |> assign(:selected_acid, nil)}
  end

  @impl true
  def handle_info("drawer_closed", socket) do
    {:noreply,
     socket
     |> assign(:selected_acid, nil)
     |> assign(:drawer_visible, false)}
  end

  defp sort_requirements(requirements, by, dir) do
    sorted =
      case by do
        :acid -> Enum.sort_by(requirements, & &1.acid)
        :status -> Enum.sort_by(requirements, &(&1.status || ""))
        :definition -> Enum.sort_by(requirements, & &1.definition)
        :refs -> Enum.sort_by(requirements, & &1.refs_count)
        :tests -> Enum.sort_by(requirements, & &1.tests_count)
      end

    if dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      team={@team}
      current_path={@current_path}
    >
      <div class="space-y-6">
        <%!-- implementation-view.MAIN.1: Page header --%>
        <%!-- data-model.PRODUCTS: Product is now a separate entity --%>
        <.content_header
          page_title="Implementation"
          resource_name={@implementation.name}
          resource_icon="hero-code-bracket"
          breadcrumb_items={[
            %{label: "Overview", navigate: ~p"/t/#{@team.name}", icon: "hero-home"},
            %{
              label: @spec.product.name,
              navigate: ~p"/t/#{@team.name}/p/#{@spec.product.name}"
            },
            %{label: @feature_name, navigate: ~p"/t/#{@team.name}/f/#{@feature_name}"},
            %{label: @implementation.name}
          ]}
        />

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- implementation-view.CANONICAL_SPEC.1 --%>
          <.info_card title="Target Spec">
            <div class="flex flex-col gap-2">
              <div class="flex items-center sm:absolute top-4 right-6">
                <.link
                  navigate={~p"/t/#{@team.name}/f/#{@feature_name}"}
                  class="link link-primary flex items-center gap-2 font-medium"
                >
                  <.icon name="hero-cube" class="size-4" />
                  {@feature_name}
                </.link>
              </div>
              <div class="text-sm text-base-content/70">
                <div class="mt-2 flex flex-col gap-1 font-mono text-xs">
                  <div class="flex items-center gap-2">
                    <span class="truncate">{@spec.branch.repo_uri}</span>
                  </div>
                  <div class="flex items-center gap-2">
                    <span class="truncate">{@spec.path}</span>
                  </div>
                </div>
              </div>
            </div>
          </.info_card>

          <%!-- implementation-view.LINKED_BRANCHES: Tracked branches --%>
          <.info_card title="Tracked Branches">
            <.tracked_branches_list branches={@tracked_branches} />
          </.info_card>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- implementation-view.REQ_COVERAGE: Requirements coverage grid --%>
          <.coverage_section title="Requirements Coverage">
            <.req_coverage_grid
              requirements={@requirements}
              on_click="open_drawer"
            />
            <div class="mt-3 pt-3 border-t border-base-200 flex flex-wrap gap-x-3 gap-y-1 text-xs text-base-content/50">
              <span class="flex items-center gap-1">
                <span class="w-2 h-2 rounded-sm bg-success" /> accepted
              </span>
              <span class="flex items-center gap-1">
                <span class="w-2 h-2 rounded-sm bg-info" /> completed
              </span>
              <span class="flex items-center gap-1">
                <span class="w-2 h-2 rounded-sm bg-warning" /> assigned
              </span>
              <span class="flex items-center gap-1">
                <span class="w-2 h-2 rounded-sm bg-error" /> blocked
              </span>
              <span class="flex items-center gap-1">
                <span class="w-2 h-2 rounded-sm bg-error opacity-60" /> rejected
              </span>
            </div>
          </.coverage_section>

          <%!-- implementation-view.TEST_COVERAGE: Test coverage grid --%>
          <.coverage_section title="Test Coverage">
            <.test_coverage_grid
              requirements={@requirements}
              on_click="open_drawer"
            />
            <% reqs_with_tests = Enum.count(@requirements, &(&1.tests_count > 0)) %>
            <% total_reqs = Enum.count(@requirements) %>
            <% coverage_pct =
              if total_reqs > 0, do: round(reqs_with_tests / total_reqs * 100), else: 0 %>
            <div class="mt-3 pt-3 border-t border-base-200 flex items-center justify-between text-sm">
              <span class="text-base-content/50">{coverage_pct}% covered</span>
              <span class="text-base-content/50">{reqs_with_tests} of {total_reqs}</span>
            </div>
          </.coverage_section>
        </div>

        <%!-- implementation-view.REQ_LIST: Requirements table --%>
        <.requirements_table
          requirements={@requirements}
          sort_by={@sort_by}
          sort_dir={@sort_dir}
          on_sort="sort"
          on_row_click="open_drawer"
        />

        <%!-- Requirement details drawer --%>
        <%!-- data-model.SPECS.11: Pass acid instead of requirement_id --%>
        <%!-- feature-impl-view.DRAWER.4: Pass aggregated_refs from tracked branches --%>
        <.live_component
          module={AcaiWeb.Live.Components.RequirementDetailsLive}
          id="requirement-details-drawer"
          acid={@selected_acid}
          spec={@spec}
          implementation={@implementation}
          aggregated_refs={@aggregated_refs}
          visible={@drawer_visible}
        />
      </div>
    </Layouts.app>
    """
  end

  # Coverage section wrapper
  defp coverage_section(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm">
      <div class="card-body">
        <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider mb-3">
          {@title}
        </h3>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # implementation-view.REQ_COVERAGE: Requirements coverage grid
  defp req_coverage_grid(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2">
      <.link
        :for={req <- @requirements}
        phx-click={@on_click}
        phx-value-acid={req.acid}
        class="cursor-pointer"
      >
        <.req_chip requirement={req} />
      </.link>
    </div>
    """
  end

  # implementation-view.REQ_COVERAGE.2: Chip color based on status
  defp req_chip(assigns) do
    ~H"""
    <div
      title={@requirement.acid}
      class={
        [
          "w-6 h-6 rounded-sm cursor-pointer transition-all hover:scale-110",
          # data-model.FEATURE_IMPL_STATES.4-3: Color coding
          # accepted (green), completed (blue), assigned (gold), blocked/rejected (red), null (gray)
          @requirement.status == "accepted" && "bg-success",
          @requirement.status == "completed" && "bg-info",
          @requirement.status == "assigned" && "bg-warning",
          (@requirement.status == "blocked" || @requirement.status == "rejected") && "bg-error",
          (@requirement.status == nil || @requirement.status == "") && "bg-base-300"
        ]
      }
    />
    """
  end

  # implementation-view.TEST_COVERAGE: Test coverage grid
  defp test_coverage_grid(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-1.5">
      <.link
        :for={req <- @requirements}
        phx-click={@on_click}
        phx-value-acid={req.acid}
        class="cursor-pointer"
      >
        <.test_chip requirement={req} />
      </.link>
    </div>
    """
  end

  # implementation-view.TEST_COVERAGE.2: Chip color based on test references
  defp test_chip(assigns) do
    ~H"""
    <div
      title={"#{@requirement.acid} (#{@requirement.tests_count} tests)"}
      class={
        [
          "w-6 h-6 rounded-sm cursor-pointer transition-all hover:scale-110 flex items-center justify-center text-[10px] font-bold text-white",
          # implementation-view.TEST_COVERAGE.2-1: Green if tests exist
          @requirement.tests_count > 0 && "bg-success",
          # implementation-view.TEST_COVERAGE.2-2: Gray if no tests
          @requirement.tests_count == 0 && "bg-base-300"
        ]
      }
    >
      <%= if @requirement.tests_count > 0 do %>
        {@requirement.tests_count}
      <% end %>
    </div>
    """
  end

  # Info card wrapper
  defp info_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm">
      <div class="card-body">
        <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider">
          {@title}
        </h3>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # implementation-view.LINKED_BRANCHES: Tracked branches list
  defp tracked_branches_list(assigns) do
    ~H"""
    <div class="space-y-2">
      <%= if @branches == [] do %>
        <p class="text-sm text-base-content/50">No tracked branches</p>
      <% else %>
        <div :for={tracked_branch <- @branches} class="flex items-center gap-2 text-sm">
          <.icon name="hero-link" class="size-4 text-base-content/50" />
          <span class="text-base-content/80">{tracked_branch.branch.repo_uri}</span>
          <span class="text-base-content/40">/</span>
          <span class="text-primary font-medium">{tracked_branch.branch.branch_name}</span>
        </div>
      <% end %>
    </div>
    """
  end

  # implementation-view.REQ_LIST: Requirements table
  defp requirements_table(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm">
      <div class="card-body p-0">
        <div class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <.sortable_header
                  label="ACID"
                  by="acid"
                  current_by={@sort_by}
                  dir={@sort_dir}
                  on_sort={@on_sort}
                />
                <.sortable_header
                  label="Status"
                  by="status"
                  current_by={@sort_by}
                  dir={@sort_dir}
                  on_sort={@on_sort}
                />
                <.sortable_header
                  label="Definition"
                  by="definition"
                  current_by={@sort_by}
                  dir={@sort_dir}
                  on_sort={@on_sort}
                />
                <.sortable_header
                  label="Refs"
                  by="refs"
                  current_by={@sort_by}
                  dir={@sort_dir}
                  on_sort={@on_sort}
                />
                <.sortable_header
                  label="Tests"
                  by="tests"
                  current_by={@sort_by}
                  dir={@sort_dir}
                  on_sort={@on_sort}
                />
              </tr>
            </thead>
            <tbody>
              <tr
                :for={req <- @requirements}
                class="hover:bg-base-200 cursor-pointer"
                phx-click={@on_row_click}
                phx-value-acid={req.acid}
              >
                <td class="font-mono text-sm">{req.acid}</td>
                <td>
                  <.status_badge status={req.status} />
                </td>
                <td class="max-w-md truncate">{req.definition}</td>
                <td class="text-center">{req.refs_count}</td>
                <td class="text-center">{req.tests_count}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # Sortable table header
  defp sortable_header(assigns) do
    ~H"""
    <th class="cursor-pointer select-none" phx-click={@on_sort} phx-value-by={@by}>
      <div class="flex items-center gap-1">
        <span>{@label}</span>
        <.sort_indicator by={@by} current_by={@current_by} dir={@dir} />
      </div>
    </th>
    """
  end

  # Sort indicator arrow
  defp sort_indicator(assigns) do
    ~H"""
    <%= if @by == @current_by do %>
      <.icon
        name={if @dir == :asc, do: "hero-chevron-up", else: "hero-chevron-down"}
        class="size-4"
      />
    <% end %>
    """
  end

  # Status badge for table
  # data-model.FEATURE_IMPL_STATES.4-3: Color coding
  # null (gray), assigned (gold), blocked (red), completed (blue), accepted (green), rejected (red)
  defp status_badge(assigns) do
    ~H"""
    <%= if @status do %>
      <span class={[
        "badge badge-sm",
        @status == "accepted" && "badge-success",
        @status == "completed" && "badge-info",
        @status == "assigned" && "badge-warning",
        (@status == "blocked" || @status == "rejected") && "badge-error"
      ]}>
        {@status}
      </span>
    <% else %>
      <span class="badge badge-ghost badge-sm text-base-content/50">No status</span>
    <% end %>
    """
  end
end
