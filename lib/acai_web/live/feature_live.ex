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

        # data-model.SPECS.11: Requirements are now JSONB on each spec
        # Count requirements by getting map_size of the requirements JSONB
        spec_requirement_counts =
          Map.new(specs, fn spec -> {spec.id, map_size(spec.requirements)} end)

        # data-model.IMPLS: Implementations now belong to products, not specs
        # Get all active implementations for the product
        implementations = Implementations.list_active_implementations_for_specs(specs)

        # feature-view.PERF.1: Preload product association for each implementation
        implementations = Acai.Repo.preload(implementations, :product)

        # data-model.FEATURE_IMPL_STATES: Get status counts from feature_impl_states JSONB
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
            # feature-view.MAIN.3: Get status counts from feature_impl_states
            impl_counts = Map.get(status_counts_by_impl, impl.id, %{})

            # Calculate status percentages for progress bar
            status_percentages =
              if total_requirements > 0 do
                %{
                  nil => Map.get(impl_counts, nil, 0) / total_requirements * 100,
                  "assigned" => Map.get(impl_counts, "assigned", 0) / total_requirements * 100,
                  "blocked" => Map.get(impl_counts, "blocked", 0) / total_requirements * 100,
                  "completed" => Map.get(impl_counts, "completed", 0) / total_requirements * 100,
                  "accepted" => Map.get(impl_counts, "accepted", 0) / total_requirements * 100,
                  "rejected" => Map.get(impl_counts, "rejected", 0) / total_requirements * 100
                }
              else
                %{
                  nil => 0,
                  "assigned" => 0,
                  "blocked" => 0,
                  "completed" => 0,
                  "accepted" => 0,
                  "rejected" => 0
                }
              end

            # Build the slug for navigation (impl_name+uuid_without_dashes)
            # feature-view.MAIN.4
            slug = Implementations.implementation_slug(impl)

            %{
              id: "impl-#{impl.id}",
              implementation: impl,
              slug: slug,
              product_name: impl.product.name,
              total_requirements: total_requirements,
              status_percentages: status_percentages
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
          # data-model.SPECS.12: Get product name from preloaded association
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

                  <%!-- feature-view.MAIN.3: Product name and requirement count --%>
                  <p class="text-sm text-base-content/60 mt-1">
                    {card.product_name} • {card.total_requirements} requirements
                  </p>

                  <%!-- feature-view.MAIN.3: Segmented progress bar by status --%>
                  <div class="mt-4 pt-3 border-t border-base-200">
                    <%!-- Progress bar with segments for each status --%>
                    <div class="h-2 w-full rounded-full overflow-hidden flex">
                      <%!-- accepted (green) --%>
                      <div
                        :if={card.status_percentages["accepted"] > 0}
                        class="h-full bg-success"
                        style={"width: #{card.status_percentages["accepted"]}%"}
                      />
                      <%!-- completed (blue) --%>
                      <div
                        :if={card.status_percentages["completed"] > 0}
                        class="h-full bg-info"
                        style={"width: #{card.status_percentages["completed"]}%"}
                      />
                      <%!-- assigned (gold) --%>
                      <div
                        :if={card.status_percentages["assigned"] > 0}
                        class="h-full bg-warning"
                        style={"width: #{card.status_percentages["assigned"]}%"}
                      />
                      <%!-- blocked (red) --%>
                      <div
                        :if={card.status_percentages["blocked"] > 0}
                        class="h-full bg-error"
                        style={"width: #{card.status_percentages["blocked"]}%"}
                      />
                      <%!-- rejected (red) --%>
                      <div
                        :if={card.status_percentages["rejected"] > 0}
                        class="h-full bg-error opacity-60"
                        style={"width: #{card.status_percentages["rejected"]}%"}
                      />
                      <%!-- null/no status (gray) --%>
                      <div
                        :if={card.status_percentages[nil] > 0}
                        class="h-full bg-base-300"
                        style={"width: #{card.status_percentages[nil]}%"}
                      />
                      <%!-- Empty state: full gray bar when no statuses at all --%>
                      <div
                        :if={
                          card.status_percentages["accepted"] == 0 &&
                            card.status_percentages["completed"] == 0 &&
                            card.status_percentages["assigned"] == 0 &&
                            card.status_percentages["blocked"] == 0 &&
                            card.status_percentages["rejected"] == 0 &&
                            card.status_percentages[nil] == 0
                        }
                        class="h-full w-full bg-base-300"
                      />
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
