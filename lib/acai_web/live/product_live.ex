defmodule AcaiWeb.ProductLive do
  use AcaiWeb, :live_view

  import Ecto.Query

  alias Acai.Teams
  alias Acai.Specs
  alias Acai.Products
  alias Acai.Implementations

  @impl true
  def mount(%{"team_name" => team_name, "product_name" => product_name}, _session, socket) do
    team = Teams.get_team_by_name!(team_name)

    # product-view.ROUTING.1: Case-insensitive product name matching
    # data-model.PRODUCTS: Use Products context to get product by name
    case get_product_by_name_case_insensitive(team, product_name) do
      nil ->
        # product-view.ROUTING.2: Redirect if product not found
        socket =
          socket
          |> put_flash(:error, "Product not found")
          |> push_navigate(to: ~p"/t/#{team.name}")

        {:ok, socket}

      product ->
        # data-model.SPECS.14: Get specs for this product
        specs = Specs.list_specs_for_product(product)

        # data-model.IMPLS: Implementations now belong to products, not specs
        implementations = Implementations.list_implementations(product)
        active_impl_count = Enum.count(implementations, & &1.is_active)

        # Group specs by feature_name to get distinct features
        # Each feature_name can have multiple specs (different versions/branches)
        # We show one card per distinct feature_name
        features =
          specs
          |> Enum.group_by(& &1.feature_name)
          |> Enum.map(fn {feature_name, feature_specs} ->
            # Get the first spec for display info (they share the same feature_name)
            first_spec = List.first(feature_specs)

            # data-model.IMPLS.2: All implementations belong to the product
            # and span all features within that product
            %{
              id: "features-#{feature_name}",
              feature_name: feature_name,
              feature_description: first_spec.feature_description,
              implementation_count: active_impl_count
            }
          end)
          |> Enum.sort_by(& &1.feature_name)

        socket =
          socket
          |> assign(:team, team)
          # product-view.MAIN.1
          |> assign(:product_name, product.name)
          |> assign(:features_empty?, features == [])
          # product-view.MAIN.2
          |> stream(:features, features)
          # nav.AUTH.1: Pass current_path for navigation
          |> assign(:current_path, "/t/#{team.name}/p/#{product_name}")

        {:ok, socket}
    end
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

        <%!-- product-view.MAIN.3: Section header --%>
        <h2 class="text-lg font-semibold">Features:</h2>

        <%!-- product-view.MAIN.4 --%>
        <%= if @features_empty? do %>
          <%!-- product-view.MAIN.2-1: Empty state --%>
          <div class="text-center py-12">
            <.icon name="hero-folder-open" class="size-12 text-base-content/30 mx-auto mb-4" />
            <p class="text-base-content/60">No features found for this product</p>
          </div>
        <% else %>
          <div
            id="features-grid"
            phx-update="stream"
            class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
          >
            <%!-- product-view.FEATURE_CARD --%>
            <.link
              :for={{id, feature} <- @streams.features}
              id={id}
              navigate={"/t/#{@team.name}/f/#{feature.feature_name}"}
              class="block group"
            >
              <div class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md hover:border-primary/40 transition-all duration-200 cursor-pointer h-full">
                <div class="card-body">
                  <div class="flex items-start justify-between gap-3">
                    <div class="flex-1 min-w-0">
                      <%!-- product-view.FEATURE_CARD.1 --%>
                      <h3 class="font-semibold text-base group-hover:text-primary transition-colors truncate">
                        {feature.feature_name}
                      </h3>
                      <%!-- product-view.FEATURE_CARD.2 --%>
                      <p
                        :if={feature.feature_description}
                        class="text-sm text-base-content/60 mt-1 line-clamp-2"
                      >
                        {feature.feature_description}
                      </p>
                    </div>
                    <div class="flex-shrink-0">
                      <.icon name="hero-cube" class="size-5 text-base-content/40" />
                    </div>
                  </div>
                  <%!-- product-view.FEATURE_CARD.3 --%>
                  <div class="flex items-center gap-2 mt-3 pt-3 border-t border-base-200">
                    <.icon name="hero-code-bracket" class="size-4 text-base-content/50" />
                    <span class="text-sm text-base-content/60">
                      {feature.implementation_count} implementation{if feature.implementation_count !=
                                                                         1, do: "s", else: ""}
                    </span>
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
