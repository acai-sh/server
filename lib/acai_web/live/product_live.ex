defmodule AcaiWeb.ProductLive do
  use AcaiWeb, :live_view

  alias Acai.Products
  alias Acai.Implementations

  @impl true
  def mount(%{"team_name" => team_name}, _session, socket) do
    # Use non-raising lookup for consistent error handling
    case Products.get_team_by_name(team_name) do
      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Team not found")
         |> push_navigate(to: ~p"/")}

      {:ok, team} ->
        # Load all products for the team (for product selector)
        products = Products.list_products(socket.assigns.current_scope, team)

        socket =
          socket
          |> assign(:team, team)
          |> assign(:products, products)
          |> assign(:current_path, nil)
          |> assign(:product, nil)
          |> assign(:product_name, nil)
          |> assign(:active_implementations, [])
          |> assign(:empty?, true)
          |> assign(:no_features?, true)
          |> assign(:no_implementations?, true)
          |> stream(:matrix_rows, [])

        {:ok, socket}
    end
  end

  # Handle params loads the product data when the URL changes (including from selector)
  @impl true
  def handle_params(params, uri, socket) do
    %{team: team, products: products} = socket.assigns
    product_name = params["product_name"]

    # Update current_path for navigation highlighting
    socket = assign(socket, :current_path, URI.parse(uri).path)

    # Capture direction param for RTL/LTR ordering
    socket = assign(socket, :direction_param, params["dir"])

    # Use already-loaded products list to avoid extra query
    case Products.get_product_from_list(products, team, product_name) do
      {:error, :not_found} ->
        socket =
          socket
          |> put_flash(:error, "Product not found")
          |> push_navigate(to: ~p"/t/#{team.name}")

        {:noreply, socket}

      {:ok, product} ->
        socket = load_product_data(socket, product)
        {:noreply, socket}
    end
  end

  # Load all product data using the consolidated context loader
  # and stream matrix rows instead of large assign
  defp load_product_data(socket, product) do
    direction = get_direction(socket)

    # Single context call fetches all page data
    page_data = Products.load_product_page(product, direction: direction)

    # Build matrix rows for streaming (minimal payload per cell)
    matrix_rows = build_matrix_rows(page_data, socket.assigns.team)

    socket
    |> assign(:product, page_data.product)
    |> assign(:product_name, page_data.product.name)
    |> assign(:active_implementations, page_data.active_implementations)
    |> assign(:empty?, page_data.empty?)
    |> assign(:no_features?, page_data.no_features?)
    |> assign(:no_implementations?, page_data.no_implementations?)
    |> stream(:matrix_rows, matrix_rows, reset: true)
  end

  # Build matrix rows with minimal per-cell payload
  # Each cell only needs: impl_id, percentage, completed/total, available flag
  # The implementation metadata is kept once in @active_implementations
  defp build_matrix_rows(page_data, team) do
    %{
      features_by_name: features_by_name,
      active_implementations: active_implementations,
      spec_impl_completion: spec_impl_completion,
      feature_availability: feature_availability
    } = page_data

    features_by_name
    |> Enum.map(fn feature ->
      cells =
        active_implementations
        |> Enum.map(fn impl ->
          available = Map.get(feature_availability, {feature.name, impl.id}, false)

          # Sum completion across all specs for this feature/implementation pair
          {completed, total} =
            feature.specs
            |> Enum.reduce({0, 0}, fn spec, {acc_completed, acc_total} ->
              spec_total = map_size(spec.requirements)

              spec_completed =
                case Map.get(spec_impl_completion, {spec.id, impl.id}) do
                  nil -> 0
                  data -> data.completed
                end

              {acc_completed + spec_completed, acc_total + spec_total}
            end)

          percentage = if total > 0, do: round(completed / total * 100), else: 0

          # Minimal cell payload - implementation_slug is needed for URL generation
          %{
            implementation_id: impl.id,
            implementation_slug: Implementations.implementation_slug(impl),
            completed: completed,
            total: total,
            percentage: percentage,
            available: available
          }
        end)

      # Each row has a unique DOM id for streaming
      %{
        id: "feature-row-#{slugify(feature.name)}",
        feature_name: feature.name,
        feature_description: feature.description,
        team_name: team.name,
        cells: cells
      }
    end)
  end

  # product-view.MATRIX.4: Cell text color uses ease-in gradient (0-50% uncolored, 100% saturated green)
  defp completion_color_class(percentage) when percentage <= 50, do: ""

  defp completion_color_class(percentage) do
    t = (percentage - 50) / 50
    eased = t * t
    "color: rgb(34, #{round(100 + eased * 97)}, 34)"
  end

  # Get text direction from URL params or session, default to LTR
  defp get_direction(socket) do
    case socket.assigns[:direction_param] do
      "rtl" -> :rtl
      "ltr" -> :ltr
      _ -> :ltr
    end
  end

  # URL-safe slug for feature names (for DOM IDs)
  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  # product-view.PRODUCT_SELECTOR.2: Changing selection patches URL via handle_params
  @impl true
  def handle_event("select_product", %{"product_name" => new_product_name}, socket) do
    %{team: team} = socket.assigns

    dir_param = socket.assigns[:direction_param]

    path =
      if dir_param do
        ~p"/t/#{team.name}/p/#{new_product_name}?dir=#{dir_param}"
      else
        ~p"/t/#{team.name}/p/#{new_product_name}"
      end

    {:noreply, push_patch(socket, to: path)}
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
        <%!-- Page header with breadcrumb --%>
        <nav class="flex items-center gap-2 text-sm text-base-content/70">
          <.link navigate={~p"/t/#{@team.name}"} class="hover:text-primary flex items-center gap-1">
            <.icon name="hero-home" class="size-4" />
          </.link>
          <span class="text-base-content/40">/</span>
          <span class="text-base-content font-medium">{@product_name}</span>
        </nav>

        <%!-- Page title with product selector --%>
        <div class="flex flex-col sm:flex-row sm:items-center gap-3">
          <span class="text-2xl font-bold">Overview of the</span>

          <%!-- product-view.PRODUCT_SELECTOR.1: Dropdown lists all products in the current team --%>
          <div class="flex-shrink-0" id="product-selector-container">
            <button
              id="product-selector-trigger"
              class="btn btn-outline btn-xl flex items-center gap-2 justify-start font-bold lg:text-2xl px-2 border-accent border-dashed"
              popovertarget="product-popover"
              style="anchor-name:--anchor-product"
            >
              <.icon name="custom-boxes" class="size-4 text-accent" />
              <span class="truncate">{@product_name}</span>
              <.icon name="hero-chevron-down" class="size-4 ml-auto text-base-content/50" />
            </button>
            <ul
              class="dropdown menu w-52 rounded-box bg-base-100 shadow-sm"
              popover
              id="product-popover"
              style="position-anchor:--anchor-product"
            >
              <li :for={product <- @products}>
                <a
                  href="#"
                  phx-click="select_product"
                  phx-value-product_name={product.name}
                  class={[
                    "flex items-center gap-2",
                    product.name == @product_name && "active"
                  ]}
                >
                  <.icon name="custom-boxes" class="size-4 text-accent" />
                  <span class="truncate">{product.name}</span>
                  <%= if product.name == @product_name do %>
                    <.icon name="hero-check" class="size-4 ml-auto text-success" />
                  <% end %>
                </a>
              </li>
            </ul>
          </div>

          <span class="text-2xl font-bold">product</span>
        </div>

        <%!-- product-view.MATRIX.6: Empty state shown if product has no features or implementations --%>
        <%= if @empty? do %>
          <div class="text-center py-16 bg-base-200/50 rounded-lg border border-base-300">
            <.icon name="hero-table-cells" class="size-16 text-base-content/20 mx-auto mb-4" />
            <%= if @no_features? do %>
              <h3 class="text-lg font-medium mb-2">No features found</h3>
              <p class="text-base-content/60 max-w-md mx-auto">
                This product doesn't have any feature specs yet. Add specs to see the completion matrix.
              </p>
            <% else %>
              <h3 class="text-lg font-medium mb-2">No active implementations</h3>
              <p class="text-base-content/60 max-w-md mx-auto">
                This product doesn't have any active implementations. Activate or add implementations to track completion.
              </p>
            <% end %>
          </div>
        <% else %>
          <%!-- Feature × Implementation Matrix --%>
          <div class="overflow-x-auto">
            <table class="table w-full border-r-1 border-base-300 border-b-1 rounded-b-lg overflow-hidden">
              <thead>
                <%!-- Label row for implementation columns --%>
                <tr class="bg-base-100">
                  <th class="sticky left-0 bg-base-100 z-10 lg:min-w-[200px] bg-base-200 border-0">
                    <span class="sr-only">Feature</span>
                  </th>
                  <th
                    colspan={length(@active_implementations)}
                    class="text-center py-2 text-sm font-medium text-secondary border-base-300 rounded-t-lg border-1 border-r-0"
                  >
                    Implementation (% accepted)
                  </th>
                </tr>
                <tr class="bg-base-100">
                  <%!-- Feature name column header --%>
                  <th class="sticky left-0 bg-base-100 z-10 lg:min-w-[200px] lg:py-2 text-sm font-medium text-primary rounded-tl-lg border-t-1 border-l-1 border-base-300">
                    Feature
                  </th>
                  <%!-- Implementation column headers --%>
                  <%= for impl <- @active_implementations do %>
                    <th class="text-center lg:min-w-[100px] border-l border-base-300 first:border-l-0">
                      <div class="flex flex-col items-center gap-1">
                        <.icon name="hero-tag" class="size-4 text-secondary" />
                        <span
                          class="text-xs font-medium text-secondary truncate max-w-[120px]"
                          title={impl.name}
                        >
                          {impl.name}
                        </span>
                      </div>
                    </th>
                  <% end %>
                </tr>
              </thead>
              <tbody id="matrix-rows" phx-update="stream">
                <tr
                  :for={{id, row} <- @streams.matrix_rows}
                  id={id}
                  class="bg-base-100 hover:bg-base-200/50"
                >
                  <%!-- product-view.MATRIX.5: Clicking a row navigates to the feature view --%>
                  <td class="sticky left-0 bg-base-100 z-10 p-0 border-l-1 border-base-300">
                    <.link
                      navigate={"/t/#{row.team_name}/f/#{row.feature_name}"}
                      class="block p-2 lg:p-4 hover:bg-base-200 transition-colors"
                    >
                      <div class="flex items-center gap-2">
                        <.icon
                          name="hero-cube"
                          class="size-3 lg:size-4 text-primary flex-shrink-0"
                        />
                        <div class="font-medium text-primary hover:underline text-xs lg:text-base">
                          {row.feature_name}
                        </div>
                      </div>
                      <%= if row.feature_description do %>
                        <div class="text-base-content/70 mt-1 line-clamp-2 text-xs">
                          {row.feature_description}
                        </div>
                      <% end %>
                    </.link>
                  </td>
                  <%!-- Completion cells --%>
                  <%= for {cell, idx} <- Enum.with_index(row.cells) do %>
                    <td class="bg-base-100 text-center border-l border-base-300 first:border-l-0 p-0">
                      <%!-- product-view.MATRIX.7: Clicking a cell navigates to that feature-impl --%>
                      <%= if cell.available do %>
                        <.link
                          navigate={"/t/#{row.team_name}/i/#{cell.implementation_slug}/f/#{row.feature_name}"}
                          class={[
                            "block py-4 lg:px-2 hover:bg-base-200 transition-colors",
                            cell.percentage == 100 && "bg-success/3"
                          ]}
                        >
                          <span
                            class="font-semibold text-sm"
                            style={completion_color_class(cell.percentage)}
                          >
                            {cell.percentage}%
                          </span>
                          <%= if cell.total > 0 do %>
                            <div class="text-xs text-base-content/40 mt-1">
                              {cell.completed}/{cell.total}
                            </div>
                          <% end %>
                        </.link>
                      <% else %>
                        <div class="block py-4 lg:px-2 text-base-content/30">
                          <span class="text-sm">n/a</span>
                        </div>
                      <% end %>
                    </td>
                  <% end %>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
