defmodule AcaiWeb.FeatureLive do
  use AcaiWeb, :live_view

  alias Acai.Teams
  alias Acai.Specs
  alias Acai.Implementations

  @impl true
  def mount(%{"team_name" => team_name, "feature_name" => feature_name}, _session, socket) do
    team = Teams.get_team_by_name!(team_name)

    # feature-view.ROUTING.1: Case-insensitive feature name matching
    case Specs.get_specs_by_feature_name(team, feature_name) do
      nil ->
        # feature-view.ROUTING.2: Redirect if feature not found
        socket =
          socket
          |> put_flash(:error, "Feature not found")
          |> push_navigate(to: ~p"/t/#{team.name}")

        {:ok, socket}

      {actual_feature_name, specs} ->
        # Get the first spec for display info (they share the same feature_name)
        first_spec = List.first(specs) |> Acai.Repo.preload(:product)

        # data-model.SPECS.13: Requirements are now JSONB on each spec
        # Count requirements by getting map_size of the requirements JSONB
        spec_requirement_counts =
          Map.new(specs, fn spec -> {spec.id, map_size(spec.requirements)} end)

        # data-model.IMPLS: Implementations now belong to products, not specs
        # Get all active implementations for the product
        implementations = Implementations.list_active_implementations_for_specs(specs)

        # feature-view.PERFORMANCE.1: Batch count tracked branches (query 4)
        tracked_branch_counts = Implementations.batch_count_tracked_branches(implementations)

        # data-model.SPEC_IMPL_STATES: Get status counts from spec_impl_states JSONB
        # For each implementation, aggregate status counts across all specs
        status_counts_by_impl =
          Implementations.batch_get_spec_impl_state_counts(implementations)

        # Build implementation cards with pre-fetched data
        implementation_cards =
          implementations
          |> Enum.map(fn impl ->
            # feature-view.IMPL_CARD.2: Count tracked branches (from batch)
            tracked_branch_count = Map.get(tracked_branch_counts, impl.id, 0)

            # feature-view.IMPL_CARD.3: Total requirements across all specs for this feature
            total_requirements =
              specs
              |> Enum.map(fn spec -> Map.get(spec_requirement_counts, spec.id, 0) end)
              |> Enum.sum()

            # feature-view.IMPL_CARD.4: Get status counts from spec_impl_states
            impl_counts = Map.get(status_counts_by_impl, impl.id, %{"completed" => 0})

            # Build status counts for progress bar
            completed_count = Map.get(impl_counts, "completed", 0)
            in_progress_count = Map.get(impl_counts, "in_progress", 0)
            # Null count is everything that's not completed or in_progress
            null_count = max(0, total_requirements - completed_count - in_progress_count)

            status_counts = %{
              completed: completed_count,
              in_progress: in_progress_count,
              null: null_count
            }

            # Build the slug for navigation (impl_name+uuid_without_dashes)
            # feature-view.MAIN.4
            slug = Implementations.implementation_slug(impl)

            %{
              id: "impl-#{impl.id}",
              implementation: impl,
              slug: slug,
              tracked_branch_count: tracked_branch_count,
              total_requirements: total_requirements,
              status_counts: status_counts
            }
          end)
          |> Enum.sort_by(& &1.implementation.name)

        socket =
          socket
          |> assign(:team, team)
          # feature-view.MAIN.1
          |> assign(:feature_name, actual_feature_name)
          # feature-view.MAIN.2
          |> assign(:feature_description, first_spec.feature_description)
          # data-model.SPECS.14: Get product name from preloaded association
          |> assign(:product_name, first_spec.product.name)
          |> assign(:implementations_empty?, implementation_cards == [])
          # feature-view.MAIN.3
          |> stream(:implementations, implementation_cards)
          # nav.AUTH.1: Pass current_path for navigation
          |> assign(:current_path, "/t/#{team.name}/f/#{feature_name}")

        {:ok, socket}
    end
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
      <div class="space-y-8">
        <%!-- feature-view.MAIN.1: Page header --%>
        <.content_header
          page_title="Feature Overview"
          resource_name={@feature_name}
          resource_icon="hero-cube"
          resource_description={@feature_description}
          breadcrumb_items={[
            %{label: "Overview", navigate: ~p"/t/#{@team.name}", icon: "hero-home"},
            %{label: @product_name, navigate: ~p"/t/#{@team.name}/p/#{@product_name}"},
            %{label: @feature_name}
          ]}
        />

        <%!-- feature-view.MAIN.3: Section header --%>
        <h2 class="text-lg font-semibold mb-4">Feature Implementations</h2>

        <%!-- feature-view.MAIN.4 --%>
        <%= if @implementations_empty? do %>
          <%!-- feature-view.MAIN.4-1: Empty state --%>
          <div class="text-center py-12 rounded-xl border-2 border-dashed border-base-300">
            <.icon name="hero-code-bracket" class="size-12 text-base-content/30 mx-auto mb-4" />
            <p class="text-base-content/60">No implementations found for this feature</p>
          </div>
        <% else %>
          <div
            id="implementations-grid"
            phx-update="stream"
            class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
          >
            <%!-- feature-view.IMPL_CARD --%>
            <.link
              :for={{id, card} <- @streams.implementations}
              id={id}
              navigate={"/t/#{@team.name}/f/#{@feature_name}/i/#{card.slug}"}
              class="block group"
            >
              <div class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md hover:border-primary/40 transition-all duration-200 cursor-pointer h-full">
                <div class="card-body">
                  <div class="flex items-start justify-between gap-3">
                    <div class="flex-1 min-w-0">
                      <%!-- feature-view.IMPL_CARD.1 --%>
                      <h3 class="font-semibold text-base group-hover:text-primary transition-colors truncate">
                        {card.implementation.name}
                      </h3>
                    </div>
                    <div class="flex-shrink-0">
                      <.icon name="hero-code-bracket" class="size-5 text-base-content/40" />
                    </div>
                  </div>

                  <div class="flex items-center gap-4 mt-3 pt-3 border-t border-base-200">
                    <%!-- feature-view.IMPL_CARD.2 --%>
                    <div class="flex items-center gap-1.5">
                      <.icon name="hero-git-branch" class="size-4 text-base-content/50" />
                      <span class="text-sm text-base-content/60">
                        {card.tracked_branch_count} branch{if card.tracked_branch_count != 1,
                          do: "es",
                          else: ""}
                      </span>
                    </div>

                    <%!-- feature-view.IMPL_CARD.3 --%>
                    <div class="flex items-center gap-1.5">
                      <.icon name="hero-list-bullet" class="size-4 text-base-content/50" />
                      <span class="text-sm text-base-content/60">
                        {card.total_requirements} requirement{if card.total_requirements != 1,
                          do: "s",
                          else: ""}
                      </span>
                    </div>
                  </div>

                  <%!-- feature-view.IMPL_CARD.4: Progress bar --%>
                  <div class="mt-3">
                    <.progress_bar counts={card.status_counts} total={card.total_requirements} />
                  </div>
                </div>
              </div>
            </.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # feature-view.IMPL_CARD.4: Progress bar component
  defp progress_bar(assigns) do
    %{counts: %{completed: completed, in_progress: in_progress, null: null}, total: total} =
      assigns

    # Calculate percentages (avoid division by zero)
    {completed_pct, in_progress_pct, null_pct} =
      if total > 0 do
        {
          round(completed / total * 100),
          round(in_progress / total * 100),
          round(null / total * 100)
        }
      else
        {0, 0, 0}
      end

    assigns =
      assigns
      |> assign(:completed, completed)
      |> assign(:in_progress, in_progress)
      |> assign(:completed_pct, completed_pct)
      |> assign(:in_progress_pct, in_progress_pct)
      |> assign(:null_pct, null_pct)

    ~H"""
    <div class="flex items-center gap-2">
      <div class="flex-1 h-2 bg-base-200 rounded-full overflow-hidden flex">
        <%!-- feature-view.IMPL_CARD.4-1: Green for completed --%>
        <div
          :if={@completed_pct > 0}
          class="bg-success h-full"
          style={"width: #{@completed_pct}%"}
          title={"#{@completed_pct}% completed"}
        />
        <%!-- feature-view.IMPL_CARD.4-2: Blue for in_progress --%>
        <div
          :if={@in_progress_pct > 0}
          class="bg-info h-full"
          style={"width: #{@in_progress_pct}%"}
          title={"#{@in_progress_pct}% in progress"}
        />
        <%!-- feature-view.IMPL_CARD.4-3: Gray for null/no status --%>
        <div
          :if={@null_pct > 0}
          class="bg-base-300 h-full"
          style={"width: #{@null_pct}%"}
          title={"#{@null_pct}% not started"}
        />
      </div>
      <span class="text-xs text-base-content/50">
        {@completed + @in_progress}/{@total}
      </span>
    </div>
    """
  end
end
