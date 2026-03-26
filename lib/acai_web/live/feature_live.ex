defmodule AcaiWeb.FeatureLive do
  use AcaiWeb, :live_view

  alias Acai.Teams
  alias Acai.Specs
  alias Acai.Implementations

  @impl true
  def mount(%{"team_name" => team_name}, _session, socket) do
    # mount/3: Only do cheap initialization
    # feature-view.ENG.1: Full data loading happens in handle_params/3
    team = Teams.get_team_by_name!(team_name)

    socket =
      socket
      |> assign(:team, team)
      |> assign(:page_title, "Feature")
      # These will be populated by handle_params/3
      |> assign(:feature_name, nil)
      |> assign(:feature_description, nil)
      |> assign(:product_name, nil)
      |> assign(:implementations_empty?, true)
      |> assign(:available_features, [])
      |> assign(:current_path, nil)
      |> stream(:implementations, [])

    {:ok, socket}
  end

  # Maximum display depth for hierarchy visualization
  # feature-view.HIERARCHY.3: Hierarchy supports nesting up to a maximum depth of 4
  @max_hierarchy_depth 4

  # Build all assigns for the feature page from consolidated data
  # feature-view.ENG.1: All data comes from single load_feature_page_data/2 call
  # Pass reset: true when called from handle_params to ensure stream reset
  defp build_feature_page_assigns(socket, feature_data, opts) do
    reset_stream? = Keyword.get(opts, :reset, false)

    # Build a map of spec_id => requirement_count for quick lookup
    spec_req_counts =
      Map.new(feature_data.specs, fn spec ->
        {spec.id, map_size(spec.requirements)}
      end)

    # Build implementation cards with pre-fetched data
    # feature-view.HIERARCHY.1, feature-view.HIERARCHY.2
    # feature-view.ENG.1: Use precomputed canonical_specs_by_impl instead of N+1 resolve_canonical_spec/2
    implementation_cards =
      feature_data.implementations
      |> Enum.map(fn impl ->
        # feature-view.MAIN.3: Get status counts from feature_impl_states
        impl_counts = Map.get(feature_data.status_counts_by_impl, impl.id, %{})

        # feature-view.MAIN.3: Get requirement count from the canonical spec (using precomputed data)
        canonical_spec_info = Map.get(feature_data.canonical_specs_by_impl, impl.id, %{})
        canonical_spec_id = canonical_spec_info[:spec_id]

        total_reqs =
          if canonical_spec_id do
            Map.get(spec_req_counts, canonical_spec_id, 0)
          else
            0
          end

        # Calculate status percentages for progress bar
        status_percentages = calculate_status_percentages(impl_counts, total_reqs)

        # Build the slug for navigation (impl_name-uuid_without_dashes)
        # feature-view.MAIN.4
        # feature-impl-view.ROUTING.1: Route uses impl_name-impl_id format
        slug = Implementations.implementation_slug(impl)

        # feature-view.ENG.1: Lean view-model with only fields needed for rendering
        %{
          id: "impl-#{impl.id}",
          name: impl.name,
          inserted_at: impl.inserted_at,
          slug: slug,
          parent_implementation_id: impl.parent_implementation_id,
          total_requirements: total_reqs,
          status_percentages: status_percentages
        }
      end)
      # feature-view.HIERARCHY.1, feature-view.HIERARCHY.2: Order by inheritance depth
      |> order_cards_by_hierarchy()

    team = socket.assigns.team

    socket
    # feature-view.MAIN.1
    |> assign(:feature_name, feature_data.feature_name)
    # feature-view.MAIN.1
    |> assign(:feature_description, feature_data.feature_description)
    # data-model.SPECS.12: Get product name from preloaded association
    |> assign(:product_name, feature_data.product.name)
    |> assign(:implementations_empty?, implementation_cards == [])
    # Reset stream when switching features to remove stale cards from DOM
    |> stream(:implementations, implementation_cards, reset: reset_stream?)
    # feature-view.MAIN.1: Available features for dropdown
    |> assign(:available_features, feature_data.available_features)
    # nav.AUTH.1: Pass current_path for navigation
    |> assign(:current_path, "/t/#{team.name}/f/#{feature_data.feature_name}")
  end

  # Calculate status percentages from counts
  defp calculate_status_percentages(impl_counts, total_reqs) do
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
  end

  # feature-view.HIERARCHY.1, feature-view.HIERARCHY.2, feature-view.HIERARCHY.3, feature-view.HIERARCHY.4
  # Orders implementation cards by inheritance tree structure.
  # - Parents appear before their children (depth-first order)
  # - Siblings are sorted alphabetically by name
  # - Cards with parents not in the set are treated as roots
  # - Display depth is capped at @max_hierarchy_depth (4 levels)
  # - Each card gets connector metadata for L-shape connector rendering
  defp order_cards_by_hierarchy(cards) do
    # Build set of card IDs for root detection
    card_ids =
      MapSet.new(cards, fn card ->
        # Extract UUID from "impl-{uuid}" format
        String.replace_prefix(card.id, "impl-", "")
      end)

    # Build parent_id -> children map
    children_by_parent =
      cards
      |> Enum.group_by(fn card -> card.parent_implementation_id end)

    # Identify root nodes: either no parent OR parent not in the filtered card set
    # This ensures cards whose parents are not in the filtered set are still shown
    roots =
      cards
      |> Enum.filter(fn card ->
        card.parent_implementation_id == nil ||
          not MapSet.member?(card_ids, card.parent_implementation_id)
      end)
      |> Enum.sort_by(fn card -> card.name end)

    # Perform depth-first traversal with depth tracking
    # feature-view.HIERARCHY.3: Cap display depth at max_hierarchy_depth
    # Pass active_levels as MapSet to track which ancestor depths still have siblings below
    Enum.flat_map(roots, fn root ->
      build_hierarchy_order(
        root,
        children_by_parent,
        1,
        @max_hierarchy_depth,
        false,
        MapSet.new()
      )
    end)
  end

  # feature-view.HIERARCHY.1, feature-view.HIERARCHY.2, feature-view.HIERARCHY.3, feature-view.HIERARCHY.4
  # Recursively builds hierarchy order for a card and its descendants.
  # current_depth: actual depth in tree (for traversal)
  # display_depth: capped depth for UI display (1-4, flattened at 4)
  # is_last_child: whether this card is the last sibling at its level
  # active_levels: MapSet of ancestor depth levels with continuing vertical lines
  defp build_hierarchy_order(
         card,
         children_by_parent,
         current_depth,
         max_depth,
         is_last_child,
         active_levels
       ) do
    # feature-view.HIERARCHY.3, feature-view.HIERARCHY.4: Cap display depth
    display_depth = min(current_depth, max_depth)

    # Add display depth and connector metadata to the card for UI rendering
    card_with_depth =
      card
      |> Map.put(:display_depth, display_depth)
      |> Map.put(:is_last_child, is_last_child)
      |> Map.put(:connector_levels, active_levels)

    # Extract UUID from id for looking up children
    card_uuid = String.replace_prefix(card.id, "impl-", "")

    # Get children and sort alphabetically
    children = Map.get(children_by_parent, card_uuid, [])
    sorted_children = Enum.sort_by(children, fn child -> child.name end)
    last_index = length(sorted_children) - 1

    # For children, update active_levels: add current display_depth if this card has
    # more siblings after it (i.e. it's not the last child), remove it if it is
    child_active_levels =
      if is_last_child do
        MapSet.delete(active_levels, display_depth - 1)
      else
        active_levels
      end

    # Recursively process children with incremented depth
    descendants =
      sorted_children
      |> Enum.with_index()
      |> Enum.flat_map(fn {child, idx} ->
        child_is_last = idx == last_index
        # Add current depth to active levels for children (vertical line continues from parent)
        # Remove it for the last child (the L terminates)
        levels_for_child =
          if child_is_last do
            child_active_levels
          else
            MapSet.put(child_active_levels, display_depth)
          end

        build_hierarchy_order(
          child,
          children_by_parent,
          current_depth + 1,
          max_depth,
          child_is_last,
          levels_for_child
        )
      end)

    [card_with_depth | descendants]
  end

  # Handle params for URL changes (patch navigation)
  # feature-view.MAIN.1: Centralized param-driven data loading
  # feature-view.ENG.1: Single path for all data loading (mount + handle_params)
  @impl true
  def handle_params(%{"team_name" => team_name, "feature_name" => feature_name}, uri, socket) do
    # Update current_path for navigation highlighting
    socket = assign(socket, :current_path, URI.parse(uri).path)

    # Get the team - reuse if already assigned and team hasn't changed
    team =
      if socket.assigns.team && socket.assigns.team.name == team_name do
        socket.assigns.team
      else
        Teams.get_team_by_name!(team_name)
      end

    socket = assign(socket, :team, team)

    # Only reload data if feature has actually changed
    current_feature = socket.assigns[:feature_name]
    should_reload = is_nil(current_feature) || current_feature != feature_name

    if should_reload do
      load_feature_data(socket, team, feature_name)
    else
      {:noreply, socket}
    end
  end

  # Load feature data - single consolidated path for all data loading
  # feature-view.ENG.1: Uses single consolidated query path
  defp load_feature_data(socket, team, feature_name) do
    case Specs.load_feature_page_data(team, feature_name) do
      {:error, :feature_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Feature not found")
         |> push_navigate(to: ~p"/t/#{team.name}")}

      {:ok, feature_data} ->
        # Pass reset: true to clear stale stream entries when switching features
        socket = build_feature_page_assigns(socket, feature_data, reset: true)
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
      <div class="space-y-6 lg:space-y-8">
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
          <p class="text-base-content/70 text-lg -mt-4">{@feature_description}</p>
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
          <%!-- feature-view.HIERARCHY.1, feature-view.HIERARCHY.2: Hierarchy-friendly layout --%>
          <div
            id="implementations-grid"
            class="-mt-4"
            phx-update="stream"
          >
            <%!-- feature-view.MAIN.2 --%>
            <div
              :for={{id, card} <- @streams.implementations}
              id={id}
              class="flex items-stretch"
              data-depth={card.display_depth}
            >
              <%!-- Connector columns: one per ancestor depth level --%>
              <%= for level <- 1..(card.display_depth - 1)//1 do %>
                <div class={
                  [
                    "connector-col",
                    # The column at this card's immediate parent depth draws the turn
                    level == card.display_depth - 1 && card.is_last_child && "connector-l",
                    level == card.display_depth - 1 && !card.is_last_child && "connector-t",
                    # Ancestor columns: passthrough if more siblings below, empty otherwise
                    level != card.display_depth - 1 && MapSet.member?(card.connector_levels, level) &&
                      "connector-passthrough",
                    level != card.display_depth - 1 && !MapSet.member?(card.connector_levels, level) &&
                      "connector-empty"
                  ]
                }>
                </div>
              <% end %>

              <%!-- The card itself --%>
              <.link
                navigate={"/t/#{@team.name}/i/#{card.slug}/f/#{@feature_name}"}
                class="block group flex-1 min-w-0 mt-4"
              >
                <div class={[
                  "card bg-base-100 border border-base-300 shadow-sm hover:shadow-md hover:border-secondary/40 transition-all duration-200 cursor-pointer",
                  "flex items-stretch overflow-hidden h-full max-w-2xl"
                ]}>
                  <div class={[
                    "w-1 flex-shrink-0",
                    card.display_depth == 1 && "bg-primary",
                    card.display_depth == 2 && "bg-secondary",
                    card.display_depth == 3 && "bg-accent",
                    card.display_depth >= 4 && "bg-neutral"
                  ]}>
                  </div>

                  <div class="card-body py-4 px-4 flex-1 min-w-0">
                    <div class="flex items-start justify-between gap-3">
                      <div class="flex-1 min-w-0">
                        <%!-- feature-view.MAIN.3 --%>
                        <div class="flex items-center gap-2">
                          <.icon
                            name="hero-tag"
                            class="size-4 text-secondary flex-shrink-0"
                          />
                          <h3 class="font-semibold text-base group-hover:text-secondary transition-colors truncate">
                            {card.name}
                          </h3>
                        </div>
                        <p class="text-xs text-base-content/50 mt-1">
                          Created {Calendar.strftime(card.inserted_at, "%b %d, %Y")}
                        </p>
                      </div>

                      <%!-- feature-view.MAIN.3: Requirement count --%>
                      <span class="badge badge-sm badge-ghost">
                        {card.total_requirements} requirements
                      </span>
                    </div>

                    <%!-- feature-view.MAIN.3: Segmented progress bar by status --%>
                    <div class="pt-3 border-t border-base-200">
                      <div class="h-2 w-full rounded-full overflow-hidden flex">
                        <div
                          :if={card.status_percentages["accepted"] > 0}
                          class="h-full bg-success"
                          style={"width: #{card.status_percentages["accepted"]}%"}
                        />
                        <div
                          :if={card.status_percentages["completed"] > 0}
                          class="h-full bg-info"
                          style={"width: #{card.status_percentages["completed"]}%"}
                        />
                        <div
                          :if={card.status_percentages["assigned"] > 0}
                          class="h-full bg-warning"
                          style={"width: #{card.status_percentages["assigned"]}%"}
                        />
                        <div
                          :if={card.status_percentages["blocked"] > 0}
                          class="h-full bg-error"
                          style={"width: #{card.status_percentages["blocked"]}%"}
                        />
                        <div
                          :if={card.status_percentages["rejected"] > 0}
                          class="h-full bg-error opacity-60"
                          style={"width: #{card.status_percentages["rejected"]}%"}
                        />
                        <div
                          :if={card.status_percentages[nil] > 0}
                          class="h-full bg-base-300"
                          style={"width: #{card.status_percentages[nil]}%"}
                        />
                        <div class="h-full flex-1 bg-base-200" />
                      </div>
                    </div>
                  </div>
                </div>
              </.link>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
