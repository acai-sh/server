defmodule AcaiWeb.Live.Components.NavLive do
  @moduledoc """
  Sidebar navigation panel for team-scoped views.

  nav.PANEL: A persistent left sidebar rendered on all /t/:team_name/* routes.
  """
  use AcaiWeb, :live_component

  alias Acai.Teams
  alias Acai.Specs

  # nav.AUTH.1
  @impl true
  def update(
        %{current_scope: current_scope, team: team, current_path: current_path} = _assigns,
        socket
      ) do
    # nav.AUTH.2
    teams = Teams.list_teams(current_scope)
    # data-model.PRODUCTS: Products are now first-class entities
    products_data = Specs.list_specs_grouped_by_product(team)

    # nav.PANEL.5: Auto-expand and highlight based on URL
    {active_product, active_feature} = parse_active_from_path(current_path, team)

    # nav.PANEL.4-2: Multiple products can be expanded simultaneously
    # Merge active product into existing expanded set instead of overwriting
    existing_expanded = Map.get(socket.assigns, :expanded_products, MapSet.new())

    expanded_products =
      if active_product do
        MapSet.put(existing_expanded, active_product)
      else
        existing_expanded
      end

    socket =
      socket
      |> assign(:current_scope, current_scope)
      |> assign(:team, team)
      |> assign(:teams, teams)
      |> assign(:products_data, products_data)
      |> assign(:current_path, current_path)
      |> assign(:active_product, active_product)
      |> assign(:active_feature, active_feature)
      |> assign(:expanded_products, expanded_products)

    {:ok, socket}
  end

  # nav.PANEL.5: Parse active product and feature from URL
  defp parse_active_from_path(current_path, team) do
    # Extract path segments after /t/:team_name/
    path_without_team = String.replace_prefix(current_path, "/t/#{team.name}", "")

    cond do
      # nav.PANEL.5-1: /t/:team_name/p/:product_name
      String.starts_with?(path_without_team, "/p/") ->
        product =
          path_without_team |> String.trim_leading("/p/") |> String.split("/") |> List.first()

        {product, nil}

      # nav.PANEL.5-3: /t/:team_name/i/:impl_name-:impl_id/f/:feature_name
      # feature-impl-view.ROUTING.1: Route uses impl_name-impl_id format
      # Check for specific implementation path first (more specific than feature path)
      String.starts_with?(path_without_team, "/i/") and String.contains?(path_without_team, "/f/") ->
        # Parse impl_name-impl_id and feature from /i/:impl_name-:impl_id/f/:feature_name
        # After /i/ comes impl_name-impl_id, after /f/ comes feature_name
        parts = path_without_team |> String.trim_leading("/i/") |> String.split("/f/")
        feature = parts |> Enum.at(1) |> String.split("/") |> List.first()

        # nav.PANEL.5-3: Highlight the feature that owns the implementation
        product = find_product_for_feature(team, feature)
        {product, feature}

      # nav.PANEL.5-2: /t/:team_name/f/:feature_name
      String.starts_with?(path_without_team, "/f/") ->
        feature =
          path_without_team |> String.trim_leading("/f/") |> String.split("/") |> List.first()

        # nav.PANEL.5-4: Find the product that contains this feature
        product = find_product_for_feature(team, feature)
        {product, feature}

      true ->
        {nil, nil}
    end
  end

  defp find_product_for_feature(team, feature_name) when is_binary(feature_name) do
    # data-model.PRODUCTS: Get product name via spec's product association
    spec = Specs.get_spec_by_feature_name(team, feature_name)
    if spec, do: get_product_name_for_spec(spec), else: nil
  end

  defp find_product_for_feature(_team, _feature_name), do: nil

  # data-model.SPECS.12: Specs belong to products
  defp get_product_name_for_spec(spec) do
    # Preload product if not already loaded
    case spec.product do
      %Ecto.Association.NotLoaded{} ->
        Acai.Repo.preload(spec, :product).product.name

      nil ->
        nil

      product ->
        product.name
    end
  end

  # nav.PANEL.4-2: Toggle product expansion
  @impl true
  def handle_event("toggle_product", %{"product" => product}, socket) do
    expanded_products = socket.assigns.expanded_products

    new_expanded =
      if MapSet.member?(expanded_products, product) do
        MapSet.delete(expanded_products, product)
      else
        MapSet.put(expanded_products, product)
      end

    {:noreply, assign(socket, :expanded_products, new_expanded)}
  end

  # nav.PANEL.1-2: Team selection navigates to /t/:team_name
  def handle_event("select_team", %{"team" => team_name}, socket) do
    # nav.ENG.1: Prefer push_navigate over redirect
    {:noreply, push_navigate(socket, to: ~p"/t/#{team_name}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="nav-panel" class="flex flex-col h-full bg-base-100">
      <%!-- nav.HEADER.1: logo moved into the very top left, top of left nav panel above the team dropdown --%>
      <div class="p-4 flex items-center gap-3">
        <.link
          navigate={~p"/teams"}
          class="flex items-center gap-2 hover:opacity-80 transition-opacity"
        >
          <img src={~p"/images/logo.svg"} width="32" />
          <span class="text-lg font-bold">Acai</span>
        </.link>
      </div>

      <%!-- nav.PANEL.1: Team dropdown selector --%>
      <div class="px-3 pb-3 border-b border-base-300">
        <.team_selector teams={@teams} current_team={@team} myself={@myself} />
      </div>

      <%!-- Navigation items --%>
      <nav class="flex-1 overflow-y-auto p-3 space-y-1">
        <%!-- nav.PANEL.2: Home nav item --%>
        <.nav_item
          navigate={~p"/t/#{@team.name}"}
          icon="hero-home"
          label="Home"
          active={is_nil(@active_product) and is_nil(@active_feature)}
        />

        <%!-- nav.PANEL.3: PRODUCTS section header --%>
        <div class="pt-4 pb-2">
          <span class="text-xs font-semibold text-base-content/50 uppercase tracking-wider">
            Products
          </span>
        </div>

        <%= if Enum.empty?(@products_data) do %>
          <div class="px-3 py-4 text-xs text-base-content/50 leading-relaxed">
            No products found. Push a spec using the CLI to get started.
          </div>
        <% else %>
          <%!-- nav.PANEL.3-1: Each product as collapsible item --%>
          <div :for={{product, specs} <- @products_data} class="space-y-1">
            <.product_item
              product={product}
              specs={specs}
              team={@team}
              expanded={MapSet.member?(@expanded_products, product)}
              active_product={@active_product}
              active_feature={@active_feature}
              myself={@myself}
            />
          </div>
        <% end %>
      </nav>

      <%!-- nav.PANEL.6: Bottom navigation links --%>
      <div class="p-3 border-t border-base-300 space-y-1">
        <.nav_item
          navigate={~p"/t/#{@team.name}/settings"}
          icon="hero-cog-6-tooth"
          label="Team Settings"
          active={String.ends_with?(@current_path, "/settings")}
        />
        <.nav_item
          navigate={~p"/t/#{@team.name}/tokens"}
          icon="hero-key"
          label="Tokens"
          active={String.ends_with?(@current_path, "/tokens")}
        />
      </div>
    </div>
    """
  end

  # nav.PANEL.1: Team dropdown selector
  attr :teams, :list, required: true
  attr :current_team, :map, required: true
  attr :myself, :any, required: true

  defp team_selector(assigns) do
    ~H"""
    <div class="relative">
      <%!-- Wrap in form to ensure phx-change works reliably --%>
      <form phx-change="select_team" phx-target={@myself}>
        <select
          id="team-selector"
          name="team"
          class="w-full select select-sm select-bordered pr-8"
        >
          <%!-- nav.PANEL.1-1: List all teams the current user is a member of --%>
          <option :for={team <- @teams} value={team.name} selected={team.id == @current_team.id}>
            {team.name}
          </option>
        </select>
      </form>
      <%!-- nav.PANEL.1-3: Visually indicate currently active team --%>
      <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3">
        <.icon name="hero-chevron-down-micro" class="size-4 text-base-content/50" />
      </div>
    </div>
    """
  end

  # nav.PANEL.2: Nav item component
  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors",
        @active && "bg-base-300 text-primary",
        !@active && "text-base-content/70 hover:bg-base-200 hover:text-base-content"
      ]}
    >
      <.icon name={@icon} class="size-5" />
      <span>{@label}</span>
    </.link>
    """
  end

  # nav.PANEL.3-1: Product item component
  attr :product, :string, required: true
  attr :specs, :list, required: true
  attr :team, :map, required: true
  attr :expanded, :boolean, required: true
  attr :active_product, :string, default: nil
  attr :active_feature, :string, default: nil
  attr :myself, :any, required: true

  defp product_item(assigns) do
    # product-view.MATRIX.2: Deduplicate specs by feature_name for nav display
    # Multiple specs can exist for the same feature across different branches/versions
    distinct_feature_names =
      assigns.specs
      |> Enum.map(& &1.feature_name)
      |> Enum.uniq()
      |> Enum.sort()

    assigns = assign(assigns, :distinct_feature_names, distinct_feature_names)

    ~H"""
    <div>
      <%!-- nav.PANEL.3-2: Product display name --%>
      <div class="flex items-center group">
        <%!-- nav.PANEL.3-3, nav.PANEL.4-3: Product item links to overview --%>
        <.link
          navigate={~p"/t/#{@team.name}/p/#{@product}"}
          class={
            [
              "flex-1 flex items-center gap-2 px-3 py-2 rounded-lg text-xs font-medium transition-colors min-h-10 min-w-0",
              # nav.PANEL.5-4: Active product highlighted with secondary color
              @active_product == @product && "bg-base-300 text-accent",
              @active_product != @product &&
                "text-base-content/70 hover:bg-base-200 hover:text-accent"
            ]
          }
        >
          <.icon name="custom-boxes" class="size-4 flex-shrink-0" />
          <span class="truncate">{@product}</span>
        </.link>

        <%!-- nav.PANEL.4-3: Separate toggle button --%>
        <button
          type="button"
          class={[
            "px-2 py-2 rounded-lg transition-colors text-base-content/40 hover:text-accent hover:bg-base-200 min-h-10",
            @active_product == @product && "bg-base-300 text-accent/60 hover:text-accent"
          ]}
          phx-click="toggle_product"
          phx-value-product={@product}
          phx-target={@myself}
        >
          <.icon
            name={if @expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
            class="size-4"
          />
        </button>
      </div>

      <%!-- nav.PANEL.4-1: Feature names under each product --%>
      <div :if={@expanded} class="mt-1 ml-2 space-y-1">
        <.feature_item
          :for={feature_name <- @distinct_feature_names}
          feature_name={feature_name}
          team={@team}
          active_feature={@active_feature}
        />
      </div>
    </div>
    """
  end

  # nav.PANEL.4-1: Feature item component
  attr :feature_name, :string, required: true
  attr :team, :map, required: true
  attr :active_feature, :string, default: nil

  defp feature_item(assigns) do
    ~H"""
    <.link
      navigate={~p"/t/#{@team.name}/f/#{@feature_name}"}
      class={
        [
          "flex items-center gap-3 px-3 py-1.5 rounded-lg text-xs transition-colors",
          # nav.PANEL.5-2: Active feature highlighted with primary color
          @active_feature == @feature_name && "bg-base-300 text-primary font-medium",
          @active_feature != @feature_name &&
            "text-base-content/60 hover:bg-base-200 hover:text-base-content"
        ]
      }
    >
      <span>{@feature_name}</span>
    </.link>
    """
  end
end
