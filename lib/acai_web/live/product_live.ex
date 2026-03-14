defmodule AcaiWeb.ProductLive do
  use AcaiWeb, :live_view

  import Ecto.Query

  alias Acai.Teams
  alias Acai.Specs
  alias Acai.Products
  alias Acai.Implementations

  # product-view.ROUTING.1
  @impl true
  def mount(%{"team_name" => team_name}, _session, socket) do
    team = Teams.get_team_by_name!(team_name)

    # Load all products for the team (for product selector)
    # product-view.PRODUCT_SELECTOR.1
    products = Products.list_products(socket.assigns.current_scope, team)

    socket =
      socket
      |> assign(:team, team)
      |> assign(:products, products)
      |> assign(:current_path, nil)

    {:ok, socket}
  end

  # product-view.ROUTING.2
  # Handle params loads the product data when the URL changes (including from selector)
  @impl true
  def handle_params(params, uri, socket) do
    %{team: team} = socket.assigns
    product_name = params["product_name"]

    # Update current_path for navigation highlighting
    socket = assign(socket, :current_path, URI.parse(uri).path)

    case get_product_by_name_case_insensitive(team, product_name) do
      nil ->
        # product-view.ROUTING.2: Redirect if product not found
        socket =
          socket
          |> put_flash(:error, "Product not found")
          |> push_navigate(to: ~p"/t/#{team.name}")

        {:noreply, socket}

      product ->
        socket = load_product_data(socket, product)
        {:noreply, socket}
    end
  end

  # Load all product data: specs, implementations, and completion matrix
  # product-view.ROUTING.2
  defp load_product_data(socket, product) do
    # Fetch specs and active implementations
    specs = Specs.list_specs_for_product(product)
    implementations = Implementations.list_implementations(product)
    active_implementations = Enum.filter(implementations, & &1.is_active)

    # Group specs by feature_name for row headers
    # product-view.MATRIX.2
    features_by_name =
      specs
      |> Enum.group_by(& &1.feature_name)
      |> Enum.map(fn {feature_name, feature_specs} ->
        first_spec = List.first(feature_specs)

        %{
          name: feature_name,
          description: first_spec.feature_description,
          specs: feature_specs
        }
      end)
      |> Enum.sort_by(& &1.name)

    # product-view.ROUTING.2, product-view.ROUTING.3: Fetch per-spec-impl completion data
    # with inheritance support
    feature_names = Enum.map(features_by_name, & &1.name)

    # Batch resolve specs for all feature/implementation pairs with inheritance
    spec_resolution =
      if feature_names != [] and active_implementations != [] do
        Specs.batch_resolve_specs_for_implementations(feature_names, active_implementations)
      else
        %{}
      end

    # Batch get completion data with inheritance
    feature_impl_completion =
      if feature_names != [] and active_implementations != [] do
        Specs.batch_get_feature_impl_completion(feature_names, active_implementations)
      else
        %{}
      end

    # Build matrix rows: each feature has a cell for each implementation
    # product-view.MATRIX.3, product-view.MATRIX.8
    matrix_rows =
      features_by_name
      |> Enum.map(fn feature ->
        cells =
          active_implementations
          |> Enum.map(fn impl ->
            # product-view.MATRIX.8: Check if feature is in implementation's ancestor tree
            spec_result = Map.get(spec_resolution, {feature.name, impl.id})

            if spec_result == :not_found do
              # Feature not available in this implementation's ancestor tree
              %{
                implementation_id: impl.id,
                implementation_slug: Implementations.implementation_slug(impl),
                has_spec: false,
                completed: 0,
                total: 0,
                percentage: nil
              }
            else
              # Sum completion across all specs for this feature/implementation pair
              {completed, total} =
                feature.specs
                |> Enum.reduce({0, 0}, fn spec, {acc_completed, acc_total} ->
                  spec_total = map_size(spec.requirements)

                  # Get completion from inherited feature_impl_state
                  completion_data =
                    Map.get(feature_impl_completion, {feature.name, impl.id}, %{
                      completed: 0,
                      total: 0
                    })

                  # Filter to only count this spec's ACIDs
                  spec_completed =
                    if completion_data.total > 0 do
                      spec_acids = Map.keys(spec.requirements)

                      Enum.count(spec_acids, fn _acid ->
                        # This is an approximation - we count based on the ratio
                        # In practice, the completion_data is already filtered to the spec
                        true
                      end)
                      # Use the ratio of completed to total from the batch result
                      |> then(fn _ ->
                        # Calculate spec-specific completion from the states
                        {state_row, _} =
                          Acai.Specs.get_feature_impl_state_with_inheritance(
                            feature.name,
                            impl.id
                          )

                        states = if state_row, do: state_row.states, else: %{}

                        Enum.count(Map.keys(spec.requirements), fn spec_acid ->
                          case states[spec_acid] do
                            %{"status" => status} when status in ["completed", "accepted"] ->
                              true

                            _ ->
                              false
                          end
                        end)
                      end)
                    else
                      0
                    end

                  {acc_completed + spec_completed, acc_total + spec_total}
                end)

              percentage = if total > 0, do: round(completed / total * 100), else: 0

              %{
                implementation_id: impl.id,
                implementation_slug: Implementations.implementation_slug(impl),
                has_spec: true,
                completed: completed,
                total: total,
                percentage: percentage
              }
            end
          end)

        %{
          feature_name: feature.name,
          feature_description: feature.description,
          cells: cells
        }
      end)

    # Empty state check: product-view.MATRIX.6
    empty? = features_by_name == [] or active_implementations == []

    socket
    |> assign(:product, product)
    |> assign(:product_name, product.name)
    |> assign(:active_implementations, active_implementations)
    |> assign(:matrix_rows, matrix_rows)
    |> assign(:empty?, empty?)
    |> assign(:no_features?, features_by_name == [])
    |> assign(:no_implementations?, active_implementations == [])
  end

  # Helper to get product by name with case-insensitive matching
  defp get_product_by_name_case_insensitive(team, name) do
    Acai.Repo.one(
      from p in Products.Product,
        where: p.team_id == ^team.id,
        where: fragment("lower(?)", p.name) == ^String.downcase(name),
        limit: 1
    )
  end

  # Handle product selector change
  # product-view.PRODUCT_SELECTOR.2
  @impl true
  def handle_event("select_product", %{"product" => %{"product_id" => product_name}}, socket) do
    %{team: team} = socket.assigns

    # Patch the URL to the new product without full page navigation
    {:noreply, push_patch(socket, to: ~p"/t/#{team.name}/p/#{product_name}")}
  end

  # Calculate cell color based on completion percentage
  # product-view.MATRIX.4
  defp completion_color_class(percentage) when percentage <= 50, do: ""

  defp completion_color_class(percentage) do
    # Map 50-100 -> 0-1, apply ease-in (quadratic)
    t = (percentage - 50) / 50
    eased = t * t

    # Interpolate from base text color to saturated green
    # 50% = no green (text-base-content), 100% = full green
    "color: rgb(34, #{round(100 + eased * 97)}, 34)"
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
        <%!-- product-view.MAIN.1: Page header --%>
        <.content_header
          page_title="Product Overview"
          resource_name={@product_name}
          resource_icon="hero-circle-stack"
          breadcrumb_items={[
            %{label: "Overview", navigate: ~p"/t/#{@team.name}", icon: "hero-home"},
            %{label: @product_name}
          ]}
        />

        <%!-- Product selector dropdown --%>
        <%!-- product-view.PRODUCT_SELECTOR.1 --%>
        <div class="flex items-center gap-4">
          <form phx-change="select_product" id="product-selector-form">
            <.input
              type="select"
              name="product[product_id]"
              value={@product_name}
              options={Enum.map(@products, &{&1.name, &1.name})}
              class="select select-bordered w-64"
            />
          </form>
          <span class="text-sm text-base-content/60">
            {length(@active_implementations)} active implementation{if length(@active_implementations) !=
                                                                         1, do: "s", else: ""}
          </span>
        </div>

        <%!-- Empty state --%>
        <%!-- product-view.MATRIX.6 --%>
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
          <%!-- product-view.MATRIX.1, product-view.MATRIX.2 --%>
          <div class="overflow-x-auto border border-base-300 rounded-lg">
            <table class="table table-zebra w-full">
              <thead>
                <tr class="bg-base-200">
                  <%!-- Feature name column header --%>
                  <th class="sticky left-0 bg-base-200 z-10 min-w-[200px] border-r border-base-300">
                    Feature
                  </th>
                  <%!-- Implementation column headers --%>
                  <%= for impl <- @active_implementations do %>
                    <th class="text-center min-w-[100px] border-l border-base-300 first:border-l-0">
                      <div class="flex flex-col items-center gap-1">
                        <.icon name="hero-server" class="size-4 text-base-content/50" />
                        <span class="text-xs font-medium truncate max-w-[120px]" title={impl.name}>
                          {impl.name}
                        </span>
                      </div>
                    </th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @matrix_rows do %>
                  <tr class="hover:bg-base-200/50">
                    <%!-- Feature name cell (row header) --%>
                    <%!-- product-view.MATRIX.5 --%>
                    <td class="sticky left-0 bg-base-100 z-10 border-r border-base-300 p-0">
                      <.link
                        navigate={"/t/#{@team.name}/f/#{row.feature_name}"}
                        class="block p-4 hover:bg-base-200 transition-colors"
                      >
                        <div class="font-medium text-primary hover:underline">
                          {row.feature_name}
                        </div>
                        <%= if row.feature_description do %>
                          <div class="text-xs text-base-content/60 mt-1 line-clamp-2">
                            {row.feature_description}
                          </div>
                        <% end %>
                      </.link>
                    </td>
                    <%!-- Completion cells --%>
                    <%= for cell <- row.cells do %>
                      <td class="text-center border-l border-base-300 first:border-l-0 p-0">
                        <%!-- product-view.MATRIX.8: Handle n/a for features not in ancestor tree --%>
                        <%= if cell.has_spec do %>
                          <%!-- product-view.MATRIX.7 --%>
                          <.link
                            navigate={"/t/#{@team.name}/i/#{cell.implementation_slug}/f/#{row.feature_name}"}
                            class={[
                              "block py-4 px-2 hover:bg-base-200 transition-colors",
                              cell.percentage == 100 && "bg-success/10"
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
                          <%!-- product-view.MATRIX.8: n/a for unreachable features --%>
                          <div class="block py-4 px-2 text-base-content/30">
                            <span class="text-sm">n/a</span>
                          </div>
                        <% end %>
                      </td>
                    <% end %>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
