defmodule AcaiWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use AcaiWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :team, :map,
    default: nil,
    doc: "the current team for team-scoped routes"

  attr :current_path, :string,
    default: nil,
    doc: "the current request path"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%!-- nav.AUTH.1: Check if in team-scoped route --%>
    <%= if @team do %>
      <.team_layout
        flash={@flash}
        current_scope={@current_scope}
        team={@team}
        current_path={@current_path}
      >
        {render_slot(@inner_block)}
      </.team_layout>
    <% else %>
      <.default_layout flash={@flash} current_scope={@current_scope}>
        {render_slot(@inner_block)}
      </.default_layout>
    <% end %>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Default layout for non-team routes.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def default_layout(assigns) do
    ~H"""
    <div class="flex flex-col min-h-screen">
      <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300 bg-base-100 min-h-16">
        <div class="flex-1">
          <a href="/" class="flex items-center gap-2 hover:opacity-80 transition-opacity">
            <img src={~p"/images/logo.svg"} width="32" />
            <span class="text-lg font-bold">Acai</span>
          </a>
        </div>
        <div class="flex-none flex items-center gap-4">
          <.theme_toggle />

          <%= if @current_scope do %>
            <div class="flex items-center gap-3 ml-2">
              <span class="text-sm text-base-content/70 hidden sm:inline">
                {@current_scope.user.email}
              </span>

              <div class="dropdown dropdown-end">
                <label
                  tabindex="0"
                  class="btn btn-ghost btn-circle avatar border-none hover:bg-base-300"
                >
                  <div class="w-10 rounded-full bg-base-300 flex items-center justify-center">
                    <.icon name="hero-user" class="size-5 text-primary" />
                  </div>
                </label>
                <ul
                  tabindex="0"
                  class="dropdown-content z-50 menu p-2 shadow-lg bg-base-100 rounded-box w-52 border border-base-300 mt-2"
                >
                  <li>
                    <.link href={~p"/users/settings"} class="flex items-center gap-2">
                      <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
                    </.link>
                  </li>
                  <li class="menu-title px-4 py-2">
                    <span class="text-xs text-base-content/50 truncate">
                      {@current_scope.user.email}
                    </span>
                  </li>
                  <div class="divider my-0"></div>
                  <li>
                    <.link
                      href={~p"/users/log-out"}
                      method="delete"
                      class="flex items-center gap-2 text-error"
                    >
                      <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Log out
                    </.link>
                  </li>
                </ul>
              </div>
            </div>
          <% else %>
            <ul class="menu menu-horizontal px-1 gap-2">
              <li><.link href={~p"/users/log-in"} class="btn btn-ghost btn-sm">Log in</.link></li>
              <li>
                <.link href={~p"/users/register"} class="btn btn-primary btn-sm">Register</.link>
              </li>
            </ul>
          <% end %>
        </div>
      </header>

      <main class="flex-grow px-4 py-12 sm:px-6 lg:px-8 bg-base-200">
        <div class="mx-auto max-w-4xl space-y-4">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>
    """
  end

  @doc """
  Team layout with navigation sidebar and header.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :team, :map, required: true
  attr :current_path, :string, required: true
  slot :inner_block, required: true

  def team_layout(assigns) do
    ~H"""
    <div class="flex h-screen">
      <%!-- nav.MOBILE.2: Mobile panel overlay --%>
      <div
        id="mobile-nav-backdrop"
        class="lg:hidden hidden fixed inset-0 z-40 bg-black/50"
        phx-click={
          JS.toggle_class("hidden", to: "#mobile-nav-backdrop")
          |> JS.toggle_class("translate-x-0", to: "#nav-sidebar")
        }
      />

      <%!-- Sidebar --%>
      <aside
        id="nav-sidebar"
        class={
          [
            "fixed lg:static inset-y-0 left-0 z-50 w-64 bg-base-100 border-r border-base-300 flex flex-col",
            "transform transition-transform duration-300 ease-in-out",
            # nav.MOBILE.2: Hidden by default on mobile
            "lg:translate-x-0 -translate-x-full"
          ]
        }
      >
        <.live_component
          module={AcaiWeb.Live.Components.NavLive}
          id="nav-component"
          current_scope={@current_scope}
          team={@team}
          current_path={@current_path}
        />
      </aside>

      <%!-- Main content area --%>
      <div class="flex-1 flex flex-col min-w-0">
        <%!-- nav.HEADER: Top header bar --%>
        <.nav_header current_scope={@current_scope} team={@team} />

        <%!-- Main content --%>
        <main class="flex-1 overflow-y-auto p-4 sm:p-6 lg:p-8 bg-base-200">
          <div class="mx-auto max-w-6xl space-y-4">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>
    """
  end

  @doc """
  Navigation header for team-scoped routes.
  """
  attr :current_scope, :map, required: true
  attr :team, :map, required: true

  def nav_header(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300 bg-base-100 min-h-16">
      <%!-- nav.MOBILE.1: Hamburger button for small screens --%>
      <div class="flex-none lg:hidden">
        <button
          id="mobile-nav-toggle"
          type="button"
          class="btn btn-ghost btn-sm btn-square"
          phx-click={
            JS.toggle_class("hidden", to: "#mobile-nav-backdrop")
            |> JS.toggle_class("translate-x-0", to: "#nav-sidebar")
          }
          aria-label="Toggle navigation"
        >
          <.icon name="hero-bars-3" class="size-5" />
        </button>
      </div>

      <div class="flex-1">
        <%!-- Empty space since logo moved to sidebar --%>
      </div>

      <%!-- nav.HEADER.5: Theme toggle and User info --%>
      <div class="flex-none flex items-center gap-4">
        <.theme_toggle />

        <div class="flex items-center gap-3">
          <div class="dropdown dropdown-end">
            <label
              tabindex="0"
              class="btn btn-ghost btn-circle avatar border-none hover:bg-base-300 flex"
            >
              <div class="avatar avatar-placeholder">
                <div class="bg-primary text-neutral-content w-8 rounded-full">
                  <.icon name="hero-user" class="size-5" />
                </div>
              </div>
            </label>
            <ul
              tabindex="0"
              class="dropdown-content z-50 menu p-2 shadow-lg bg-base-100 rounded-box w-52 border border-base-300 mt-2"
            >
              <li class="menu-title px-4 py-2">
                <span class="text-xs text-base-content/50 truncate">{@current_scope.user.email}</span>
              </li>
              <%!-- nav.HEADER.3: Link to User Settings --%>
              <li>
                <.link href={~p"/users/settings"} class="flex items-center gap-2">
                  <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
                </.link>
              </li>

              <%!-- nav.HEADER.4: Log Out button --%>
              <div class="divider my-0"></div>
              <li>
                <.link
                  href={~p"/users/log-out"}
                  method="delete"
                  class="flex items-center gap-2 text-error"
                >
                  <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Log out
                </.link>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </header>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
