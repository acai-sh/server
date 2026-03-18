defmodule AcaiWeb.FeatureLive do
  use AcaiWeb, :live_view

  alias Acai.Teams
  alias Acai.Specs
  alias Acai.Implementations

  @impl true
  def mount(%{"team_name" => team_name, "feature_name" => feature_name}, _session, socket) do
    team = Teams.get_team_by_name!(team_name)

    # feature-view.ENG.1: Single consolidated query loads all feature page data
    case Specs.load_feature_page_data(team, feature_name) do
      {:error, :feature_not_found} ->
        # feature-view.ROUTING.2: Redirect if feature not found
        socket =
          socket
          |> put_flash(:error, "Feature not found")
          |> push_navigate(to: ~p"/t/#{team.name}")

        {:ok, socket}

      {:ok, feature_data} ->
        socket = build_feature_page_assigns(socket, team, feature_data)
        {:ok, socket}
    end
  end

  # Build all assigns for the feature page from consolidated data
  # feature-view.ENG.1: All data comes from single load_feature_page_data/2 call
  # Pass reset: true when called from reload_feature_data to ensure stream reset
  defp build_feature_page_assigns(socket, team, feature_data, opts \\ []) do
    reset_stream? = Keyword.get(opts, :reset, false)

    # Build implementation cards with pre-fetched data
    implementation_cards =
      feature_data.implementations
      |> Enum.map(fn impl ->
        # feature-view.MAIN.3: Get status counts from feature_impl_states
        impl_counts = Map.get(feature_data.status_counts_by_impl, impl.id, %{})

        total_reqs = feature_data.total_requirements

        # Calculate status percentages for progress bar
        status_percentages =
          if total_reqs > 0 do
            %{
              nil => Map.get(impl_counts, nil, 0) / total_reqs * 100,
              "assigned" => Map.get(impl_counts, "assigned", 0) / total_reqs * 100,
              "blocked" => Map.get(impl_counts, "blocked", 0) / total_reqs * 100,
              "completed" => Map.get(impl_counts, "completed", 0) / total_reqs * 100,
              "accepted" => Map.get(impl_counts, "accepted", 0) / total_reqs * 100,
              "rejected" => Map.get(impl_counts, "rejected", 0) / total_reqs * 100
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

        # Build the slug for navigation (impl_name-uuid_without_dashes)
        # feature-view.MAIN.4
        # feature-impl-view.ROUTING.1: Route uses impl_name-impl_id format
        slug = Implementations.implementation_slug(impl)

        %{
          id: "impl-#{impl.id}",
          implementation: impl,
          slug: slug,
          product_name: impl.product.name,
          total_requirements: total_reqs,
          status_percentages: status_percentages
        }
      end)
      |> Enum.sort_by(& &1.implementation.name)

    socket
    |> assign(:team, team)
    # feature-view.MAIN.1
    |> assign(:feature_name, feature_data.feature_name)
    # feature-view.MAIN.1
    |> assign(:feature_description, feature_data.feature_description)
    # data-model.SPECS.12: Get product name from preloaded association
    |> assign(:product_name, feature_data.product.name)
    |> assign(:product, feature_data.product)
    |> assign(:implementations_empty?, implementation_cards == [])
    # feature-view.MAIN.2
    # Reset stream when switching features to remove stale cards from DOM
    |> stream(:implementations, implementation_cards, reset: reset_stream?)
    # feature-view.MAIN.1: Available features for dropdown
    |> assign(:available_features, feature_data.available_features)
    # nav.AUTH.1: Pass current_path for navigation
    |> assign(:current_path, "/t/#{team.name}/f/#{feature_data.feature_name}")
  end

  # Handle params for URL changes (patch navigation)
  # feature-view.MAIN.1: Reload page data when URL is patched via dropdown changes
  @impl true
  def handle_params(%{"team_name" => team_name, "feature_name" => feature_name}, uri, socket) do
    # Update current_path for navigation highlighting
    socket = assign(socket, :current_path, URI.parse(uri).path)

    # Only reload data if feature has actually changed (not on initial mount)
    current_feature = socket.assigns[:feature_name]

    should_reload = is_nil(current_feature) || current_feature != feature_name

    if should_reload do
      reload_feature_data(socket, team_name, feature_name)
    else
      {:noreply, socket}
    end
  end

  # Reload feature data after URL patch (shared logic with mount)
  # feature-view.ENG.1: Uses single consolidated query path
  defp reload_feature_data(socket, team_name, feature_name) do
    team = Teams.get_team_by_name!(team_name)

    case Specs.load_feature_page_data(team, feature_name) do
      {:error, :feature_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Feature not found")
         |> push_navigate(to: ~p"/t/#{team.name}")}

      {:ok, feature_data} ->
        # Pass reset: true to clear stale stream entries when switching features
        socket = build_feature_page_assigns(socket, team, feature_data, reset: true)
        {:noreply, socket}
    end
  end

  # feature-view.MAIN.1: Handle feature dropdown change with patch navigation
  @impl true
  def handle_event("select_feature", %{"feature_name" => new_feature_name}, socket) do
    %{team: team} = socket.assigns

    # Patch to the new URL without full page reload
    {:noreply, push_patch(socket, to: ~p"/t/#{team.name}/f/#{new_feature_name}")}
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
        <%!-- feature-view.MAIN.1: Page header with breadcrumb --%>
        <nav class="flex items-center gap-2 text-sm text-base-content/70">
          <.link navigate={~p"/t/#{@team.name}"} class="hover:text-primary flex items-center gap-1">
            <.icon name="hero-home" class="size-4" />
          </.link>
          <span class="text-base-content/40">/</span>
          <.link navigate={~p"/t/#{@team.name}/p/#{@product_name}"} class="hover:text-primary">
            {@product_name}
          </.link>
          <span class="text-base-content/40">/</span>
          <span class="text-base-content font-medium">{@feature_name}</span>
        </nav>

        <%!-- feature-view.MAIN.2: Page title with dropdown --%>
        <div class="flex flex-col sm:flex-row sm:items-center gap-3">
          <span class="text-2xl font-bold">Overview of the</span>

          <%!-- Feature dropdown with popover API --%>
          <div class="flex-shrink-0">
            <button
              class="btn btn-outline btn-xl flex items-center gap-2 justify-start font-bold lg:text-2xl px-2 border-primary border-dashed"
              popovertarget="feature-popover"
              style="anchor-name:--anchor-feature"
            >
              <.icon name="hero-cube" class="size-4 text-primary" />
              <span class="truncate">{@feature_name}</span>
              <.icon name="hero-chevron-down" class="size-4 ml-auto text-base-content/50" />
            </button>
            <ul
              class="dropdown menu w-52 rounded-box bg-base-100 shadow-sm"
              popover
              id="feature-popover"
              style="position-anchor:--anchor-feature"
            >
              <li :for={{name, _value} <- @available_features}>
                <a
                  href="#"
                  phx-click="select_feature"
                  phx-value-feature_name={name}
                  class={[
                    "flex items-center gap-2",
                    name == @feature_name && "active"
                  ]}
                >
                  <.icon name="hero-cube" class="size-4 text-primary" />
                  <span class="truncate">{name}</span>
                  <%= if name == @feature_name do %>
                    <.icon name="hero-check" class="size-4 ml-auto text-success" />
                  <% end %>
                </a>
              </li>
            </ul>
          </div>

          <span class="text-2xl font-bold">feature</span>
        </div>

        <%!-- feature-view.MAIN.1: Feature description --%>
        <%= if @feature_description do %>
          <p class="text-base-content/70 text-lg">{@feature_description}</p>
        <% end %>

        <%!-- feature-view.MAIN.3: Section header --%>
        <h2 class="text-lg font-semibold mb-4">Implementations of this feature</h2>

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
