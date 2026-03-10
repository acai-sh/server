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

        # feature-view.PERF.1: Preload product association for each implementation
        implementations = Acai.Repo.preload(implementations, :product)

        # data-model.SPEC_IMPL_STATES: Get status counts from spec_impl_states JSONB
        # For each implementation, aggregate status counts for only the relevant specs
        status_counts_by_impl =
          Implementations.batch_get_spec_impl_state_counts(implementations, specs)

        # Total requirements across all specs for this feature
        total_requirements =
          specs
          |> Enum.map(fn spec -> Map.get(spec_requirement_counts, spec.id, 0) end)
          |> Enum.sum()

        # Build implementation cards with pre-fetched data
        implementation_cards =
          implementations
          |> Enum.map(fn impl ->
            # feature-view.MAIN.3: Get status counts from spec_impl_states
            impl_counts = Map.get(status_counts_by_impl, impl.id, %{"completed" => 0})

            # Calculate completion percentage
            completed_count = Map.get(impl_counts, "completed", 0)

            completion_percentage =
              if total_requirements > 0 do
                round(completed_count / total_requirements * 100)
              else
                0
              end

            # Build the slug for navigation (impl_name+uuid_without_dashes)
            # feature-view.MAIN.4
            slug = Implementations.implementation_slug(impl)

            %{
              id: "impl-#{impl.id}",
              implementation: impl,
              slug: slug,
              product_name: impl.product.name,
              completion_percentage: completion_percentage
            }
          end)
          |> Enum.sort_by(& &1.implementation.name)

        socket =
          socket
          |> assign(:team, team)
          # feature-view.MAIN.1
          |> assign(:feature_name, actual_feature_name)
          # feature-view.MAIN.1
          |> assign(:feature_description, first_spec.feature_description)
          # data-model.SPECS.14: Get product name from preloaded association
          |> assign(:product_name, first_spec.product.name)
          |> assign(:implementations_empty?, implementation_cards == [])
          # feature-view.MAIN.2
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

        <%!-- feature-view.MAIN.2: Section header --%>
        <h2 class="text-lg font-semibold mb-4">Feature Implementations</h2>

        <%!-- feature-view.MAIN.5 --%>
        <%= if @implementations_empty? do %>
          <%!-- feature-view.MAIN.5: Empty state --%>
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
            <%!-- feature-view.MAIN.2 --%>
            <.link
              :for={{id, card} <- @streams.implementations}
              id={id}
              navigate={"/t/#{@team.name}/i/#{card.slug}/f/#{@feature_name}"}
              class="block group"
            >
              <div class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md hover:border-primary/40 transition-all duration-200 cursor-pointer h-full">
                <div class="card-body">
                  <div class="flex items-start justify-between gap-3">
                    <div class="flex-1 min-w-0">
                      <%!-- feature-view.MAIN.3 --%>
                      <h3 class="font-semibold text-base group-hover:text-primary transition-colors truncate">
                        {card.implementation.name}
                      </h3>
                    </div>
                    <div class="flex-shrink-0">
                      <.icon name="hero-code-bracket" class="size-5 text-base-content/40" />
                    </div>
                  </div>

                  <%!-- feature-view.MAIN.3: Product name --%>
                  <p class="text-sm text-base-content/60 mt-1">
                    {card.product_name}
                  </p>

                  <%!-- feature-view.MAIN.3: Completion percentage --%>
                  <div class="mt-4 pt-3 border-t border-base-200">
                    <div class="flex items-center justify-between">
                      <span class="text-sm text-base-content/50">Completion</span>
                      <span class="text-sm font-semibold text-primary">
                        {card.completion_percentage}%
                      </span>
                    </div>
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
end
