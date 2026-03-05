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
    products_data = Specs.list_specs_grouped_by_product(team)

    # nav.PANEL.5: Auto-expand and highlight based on URL
    {active_product, active_feature} = parse_active_from_path(current_path, team)

    # nav.PANEL.4-2: Multiple products can be expanded simultaneously
    # Auto-expand the active product if not already expanded
    expanded_products =
      if active_product do
        MapSet.new([active_product])
      else
        MapSet.new()
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

      # nav.PANEL.5-2: /t/:team_name/f/:feature_name
      String.starts_with?(path_without_team, "/f/") ->
        feature =
          path_without_team |> String.trim_leading("/f/") |> String.split("/") |> List.first()

        # nav.PANEL.5-4: Find the product that contains this feature
        product = find_product_for_feature(team, feature)
        {product, feature}

      # nav.PANEL.5-3: /t/:team_name/f/:feature_name/i/:impl_slug
      String.starts_with?(path_without_team, "/f/") and String.contains?(path_without_team, "/i/") ->
        # Parse feature and impl_slug
        parts = path_without_team |> String.trim_leading("/f/") |> String.split("/i/")
        feature = List.first(parts) || nil

        # nav.PANEL.5-3: Highlight the feature that owns the implementation
        product = find_product_for_feature(team, feature)
        {product, feature}

      true ->
        {nil, nil}
    end
  end

  defp find_product_for_feature(team, feature_name) when is_binary(feature_name) do
    spec = Specs.get_spec_by_feature_name(team, feature_name)
    if spec, do: spec.feature_product, else: nil
  end

  defp find_product_for_feature(_team, _feature_name), do: nil

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
    # nav.MOBILE.3: Auto-close on navigation
    {:noreply, push_navigate(socket, to: "/t/#{team_name}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="nav-panel" class="flex flex-col h-full bg-base-100">
      <%!-- nav.HEADER.1: logo moved into the very top left, top of left nav panel above the team dropdown --%>
      <div class="p-4 flex items-center gap-3">
        <.link navigate={~p"/teams"} class="flex items-center gap-2 hover:opacity-80 transition-opacity">
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
          navigate={"/t/#{@team.name}"}
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
      </nav>

      <%!-- nav.PANEL.6: Bottom navigation links --%>
      <div class="p-3 border-t border-base-300 space-y-1">
        <.nav_item
          navigate={"/t/#{@team.name}/settings"}
          icon="hero-cog-6-tooth"
          label="Team Settings"
          active={String.ends_with?(@current_path, "/settings")}
        />
        <.nav_item
          navigate={"/t/#{@team.name}/tokens"}
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
        @active && "bg-primary/10 text-primary",
        !@active && "text-base-content/70 hover:bg-base-200 hover:text-base-content"
      ]}
      phx-click={close_mobile_nav()}
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
    ~H"""
    <div>
      <%!-- nav.PANEL.3-2: Product display name --%>
      <div class="flex items-center group">
        <%!-- nav.PANEL.3-3, nav.PANEL.4-3: Product item links to overview --%>
        <.link
          navigate={~p"/t/#{@team.name}/p/#{@product}"}
          class={
            [
              "flex-1 flex items-center gap-3 px-3 py-2 rounded-l-lg text-sm font-medium transition-colors",
              # nav.PANEL.5-4: Active product highlighted
              @active_product == @product && "bg-primary/10 text-primary",
              @active_product != @product &&
                "text-base-content/70 hover:bg-base-200 hover:text-base-content"
            ]
          }
        >
          <.icon name="hero-cube" class="size-5" />
          <span>{@product}</span>
        </.link>

        <%!-- nav.PANEL.4-3: Separate toggle button --%>
        <button
          type="button"
          class={
            [
              "px-2 py-2 rounded-r-lg transition-colors text-base-content/40 hover:text-base-content hover:bg-base-200",
              @active_product == @product && "bg-primary/10 text-primary/60 hover:text-primary"
            ]
          }
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
      <div :if={@expanded} class="mt-1 ml-4 space-y-1">
        <.feature_item
          :for={spec <- @specs}
          spec={spec}
          team={@team}
          active_feature={@active_feature}
        />
      </div>
    </div>
    """
  end

  # nav.PANEL.4-1: Feature item component
  defp feature_item(assigns) do
    ~H"""
    <.link
      navigate={"/t/#{@team.name}/f/#{@spec.feature_name}"}
      class={
        [
          "flex items-center gap-3 px-3 py-1.5 rounded-lg text-sm transition-colors",
          # nav.PANEL.5-2: Active feature highlighted
          @active_feature == @spec.feature_name && "bg-primary/10 text-primary font-medium",
          @active_feature != @spec.feature_name &&
            "text-base-content/60 hover:bg-base-200 hover:text-base-content"
        ]
      }
      phx-click={close_mobile_nav()}
    >
      <.icon name="hero-document-text" class="size-4" />
      <span>{@spec.feature_name}</span>
    </.link>
    """
  end

  # nav.MOBILE.3: Close mobile panel on navigation
  defp close_mobile_nav do
    JS.toggle_class("hidden", to: "#mobile-nav-backdrop")
    |> JS.toggle_class("translate-x-0", to: "#nav-sidebar")
  end
end
