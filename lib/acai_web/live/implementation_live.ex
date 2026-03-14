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

    case Implementations.get_implementation_by_slug(impl_slug) do
      nil ->
        socket =
          socket
          |> put_flash(:error, "Implementation not found")
          |> push_navigate(to: ~p"/t/#{team.name}/f/#{feature_name}")

        {:ok, socket}

      implementation ->
        if implementation.team_id == team.id do
          implementation = Acai.Repo.preload(implementation, :product)

          # feature-impl-view.INHERITANCE.1: Use inheritance-aware spec lookup
          case find_spec_for_feature(feature_name, implementation.id) do
            {nil, nil} ->
              socket =
                socket
                |> put_flash(:error, "Feature not found in this product")
                |> push_navigate(to: ~p"/t/#{team.name}/f/#{feature_name}")

              {:ok, socket}

            {spec, spec_source_impl_id} ->
              mount_implementation_view(
                socket,
                team,
                spec,
                spec_source_impl_id,
                implementation,
                feature_name
              )
          end
        else
          socket =
            socket
            |> put_flash(:error, "Implementation not found")
            |> push_navigate(to: ~p"/t/#{team.name}/f/#{feature_name}")

          {:ok, socket}
        end
    end
  end

  defp find_spec_for_feature(feature_name, implementation_id) do
    Specs.get_spec_for_feature_with_inheritance(feature_name, implementation_id)
  end

  defp mount_implementation_view(
         socket,
         team,
         spec,
         spec_source_impl_id,
         implementation,
         feature_name
       ) do
    spec = Acai.Repo.preload(spec, [:product, :branch])

    requirements = build_requirement_rows_from_spec(spec)

    # feature-impl-view.INHERITANCE.2: Load states with inheritance
    {state_row, state_source_impl_id} =
      Specs.get_feature_impl_state_with_inheritance(feature_name, implementation.id)

    states = if state_row, do: state_row.states, else: %{}

    # Load tracked branches with preloaded branch association
    tracked_branches = Implementations.list_tracked_branches(implementation)

    # Get aggregated refs for the drawer (branch-scoped refs with inheritance)
    {aggregated_refs, refs_inherited} =
      Implementations.get_aggregated_refs_with_inheritance(feature_name, implementation.id)

    # feature-impl-view.MAIN.6: Get inheritance summary
    # Determine if refs came from parent (refs_inherited is true if from parent)
    # We need to find the source impl_id for refs if inherited
    refs_source_impl_id =
      if refs_inherited do
        # Walk parent chain to find first implementation with refs
        chain = Implementations.get_parent_chain(implementation.id)

        Enum.reduce_while(chain, nil, fn impl_id, _acc ->
          impl = Acai.Repo.get(Acai.Implementations.Implementation, impl_id)

          if impl do
            branch_ids = Implementations.get_tracked_branch_ids(impl)
            refs = Implementations.aggregate_feature_branch_refs(branch_ids, feature_name)

            if refs != [] do
              {:halt, impl_id}
            else
              {:cont, nil}
            end
          else
            {:cont, nil}
          end
        end)
      else
        implementation.id
      end

    inheritance_summary = %{
      spec: %{
        inherited?: spec_source_impl_id != nil and spec_source_impl_id != implementation.id,
        source_impl_id: spec_source_impl_id
      },
      states: %{
        inherited?: state_source_impl_id != nil and state_source_impl_id != implementation.id,
        source_impl_id: state_source_impl_id
      },
      refs: %{
        inherited?: refs_inherited,
        source_impl_id: refs_source_impl_id
      }
    }

    # Load source implementation names for inherited resources
    source_impl_ids =
      [spec_source_impl_id, state_source_impl_id, refs_source_impl_id]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    source_impls =
      source_impl_ids
      |> Enum.map(&{&1, Acai.Repo.get(Acai.Implementations.Implementation, &1)})
      |> Map.new()

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
      |> assign(:aggregated_refs, aggregated_refs)
      |> assign(:inheritance_summary, inheritance_summary)
      |> assign(:source_impls, source_impls)
      |> assign(
        :current_path,
        "/t/#{team.name}/i/#{Implementations.implementation_slug(implementation)}/f/#{feature_name}"
      )

    {:ok, socket}
  end

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
              <%!-- feature-impl-view.MAIN.6: Inheritance badges --%>
              <.inheritance_badges
                inheritance_summary={@inheritance_summary}
                source_impls={@source_impls}
                current_impl_id={@implementation.id}
              />
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
        <%!-- data-model.SPECS.13: Pass acid instead of requirement_id --%>
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

  defp req_chip(assigns) do
    ~H"""
    <div
      title={@requirement.acid}
      class={[
        "w-6 h-6 rounded-sm cursor-pointer transition-all hover:scale-110",
        @requirement.status == "accepted" && "bg-success",
        @requirement.status == "completed" && "bg-info",
        @requirement.status == "assigned" && "bg-warning",
        (@requirement.status == "blocked" || @requirement.status == "rejected") && "bg-error",
        (@requirement.status == nil || @requirement.status == "") && "bg-base-300"
      ]}
    />
    """
  end

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

  defp test_chip(assigns) do
    ~H"""
    <div
      title={"#{@requirement.acid} (#{@requirement.tests_count} tests)"}
      class={[
        "w-6 h-6 rounded-sm cursor-pointer transition-all hover:scale-110 flex items-center justify-center text-[10px] font-bold text-white",
        @requirement.tests_count > 0 && "bg-success",
        @requirement.tests_count == 0 && "bg-base-300"
      ]}
    >
      <%= if @requirement.tests_count > 0 do %>
        {@requirement.tests_count}
      <% end %>
    </div>
    """
  end

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

  defp inheritance_badges(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2 mt-3 pt-3 border-t border-base-200">
      <.inheritance_badge
        type="Spec"
        inherited?={@inheritance_summary.spec.inherited?}
        source_impl_id={@inheritance_summary.spec.source_impl_id}
        source_impls={@source_impls}
        icon="hero-document-text"
      />
      <.inheritance_badge
        type="States"
        inherited?={@inheritance_summary.states.inherited?}
        source_impl_id={@inheritance_summary.states.source_impl_id}
        source_impls={@source_impls}
        icon="hero-check-circle"
      />
      <.inheritance_badge
        type="Refs"
        inherited?={@inheritance_summary.refs.inherited?}
        source_impl_id={@inheritance_summary.refs.source_impl_id}
        source_impls={@source_impls}
        icon="hero-link"
      />
    </div>
    """
  end

  defp inheritance_badge(assigns) do
    source_impl_name =
      if assigns.inherited? && assigns.source_impl_id do
        case Map.get(assigns.source_impls, assigns.source_impl_id) do
          nil -> "parent"
          impl -> impl.name
        end
      else
        nil
      end

    assigns = assign(assigns, :source_impl_name, source_impl_name)

    ~H"""
    <span
      class={[
        "badge badge-sm gap-1",
        @inherited? && "badge-warning",
        not @inherited? && "badge-ghost"
      ]}
      title={
        if @inherited? do
          "Inherited from #{@source_impl_name}"
        else
          "Local"
        end
      }
    >
      <.icon name={@icon} class="size-3" />
      {@type}
      <%= if @inherited? do %>
        <.icon name="hero-arrow-up-right" class="size-3" />
      <% end %>
    </span>
    """
  end
end
