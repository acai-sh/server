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
          # Get the spec for this implementation
          spec = Specs.get_spec!(implementation.spec_id)

          # Verify the spec belongs to this feature
          if spec.feature_name == feature_name do
            mount_implementation_view(socket, team, spec, implementation, feature_name)
          else
            # Feature name mismatch - redirect to correct feature
            socket =
              socket
              |> put_flash(:error, "Implementation not found in this feature")
              |> push_navigate(to: ~p"/t/#{team.name}/f/#{feature_name}")

            {:ok, socket}
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

  defp mount_implementation_view(socket, team, spec, implementation, feature_name) do
    # Load requirements for the spec
    requirements = Specs.list_requirements(spec)

    # Load requirement statuses for this implementation
    statuses = Implementations.list_requirement_statuses(implementation)
    status_by_req_id = Map.new(statuses, &{&1.requirement_id, &1})

    # Load tracked branches
    tracked_branches = Implementations.list_tracked_branches(implementation)

    # Load code reference counts per requirement
    ref_counts = get_code_reference_counts(requirements, tracked_branches)

    # Build requirement rows with status and counts
    requirement_rows =
      requirements
      |> Enum.map(fn req ->
        status = Map.get(status_by_req_id, req.id)
        counts = Map.get(ref_counts, req.id, %{refs: 0, tests: 0})

        %{
          id: req.id,
          acid: req.acid,
          definition: req.definition,
          status: status && status.status,
          refs_count: counts.refs,
          tests_count: counts.tests
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
      |> assign(:selected_requirement_id, nil)
      |> assign(:drawer_visible, false)
      |> assign(:sort_by, :acid)
      |> assign(:sort_dir, :asc)
      |> assign(
        :current_path,
        "/t/#{team.name}/f/#{feature_name}/i/#{Implementations.implementation_slug(implementation)}"
      )

    {:ok, socket}
  end

  # Get code reference counts per requirement
  defp get_code_reference_counts(requirements, tracked_branches) do
    if tracked_branches == [] do
      Map.new(requirements, fn req -> {req.id, %{refs: 0, tests: 0}} end)
    else
      branch_ids = Enum.map(tracked_branches, & &1.id)

      # Query code references grouped by requirement_id and is_test
      alias Acai.Specs.CodeReference

      counts =
        Acai.Repo.all(
          from ref in CodeReference,
            where: ref.requirement_id in ^Enum.map(requirements, & &1.id),
            where: ref.branch_id in ^branch_ids,
            group_by: [ref.requirement_id, ref.is_test],
            select: {ref.requirement_id, ref.is_test, count()}
        )

      # Build a map of requirement_id => %{refs: count, tests: count}
      Enum.reduce(counts, Map.new(requirements, fn req -> {req.id, %{refs: 0, tests: 0}} end), fn
        {req_id, true, count}, acc ->
          update_in(acc, [req_id, :tests], fn _ -> count end)

        {req_id, false, count}, acc ->
          update_in(acc, [req_id, :refs], fn _ -> count end)
      end)
    end
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

  def handle_event("open_drawer", %{"requirement_id" => req_id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_requirement_id, req_id)
     |> assign(:drawer_visible, true)}
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply,
     socket
     |> assign(:drawer_visible, false)
     |> assign(:selected_requirement_id, nil)}
  end

  @impl true
  def handle_info("drawer_closed", socket) do
    {:noreply,
     socket
     |> assign(:selected_requirement_id, nil)
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
        <.content_header
          page_title="Implementation"
          resource_name={@implementation.name}
          resource_icon="hero-code-bracket"
          breadcrumb_items={[
            %{label: "Overview", navigate: ~p"/t/#{@team.name}", icon: "hero-home"},
            %{
              label: @spec.feature_product,
              navigate: ~p"/t/#{@team.name}/p/#{@spec.feature_product}"
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
                    <span class="truncate">{@spec.repo_uri}</span>
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
          </.coverage_section>

          <%!-- implementation-view.TEST_COVERAGE: Test coverage grid --%>
          <.coverage_section title="Test Coverage">
            <.test_coverage_grid
              requirements={@requirements}
              on_click="open_drawer"
            />
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
        <.live_component
          module={AcaiWeb.Live.Components.RequirementDetailsLive}
          id="requirement-details-drawer"
          requirement_id={@selected_requirement_id}
          implementation={@implementation}
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
        phx-value-requirement_id={req.id}
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
          # implementation-view.REQ_COVERAGE.2-1: Green for accepted
          @requirement.status == "accepted" && "bg-success",
          # implementation-view.REQ_COVERAGE.2-2: Blue for completed
          @requirement.status == "completed" && "bg-info",
          # implementation-view.REQ_COVERAGE.2-3: Gray for null/no status
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
        phx-value-requirement_id={req.id}
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
        <div :for={branch <- @branches} class="flex items-center gap-2 text-sm">
          <.icon name="hero-link" class="size-4 text-base-content/50" />
          <span class="text-base-content/80">{branch.repo_uri}</span>
          <span class="text-base-content/40">/</span>
          <span class="text-primary font-medium">{branch.branch_name}</span>
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
                phx-value-requirement_id={req.id}
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
  defp status_badge(assigns) do
    ~H"""
    <%= if @status do %>
      <span class={[
        "badge badge-sm",
        @status == "accepted" && "badge-success",
        @status == "completed" && "badge-info",
        @status == "pending" && "badge-warning",
        @status == "blocked" && "badge-error"
      ]}>
        {@status}
      </span>
    <% else %>
      <span class="badge badge-ghost badge-sm text-base-content/50">—</span>
    <% end %>
    """
  end
end
