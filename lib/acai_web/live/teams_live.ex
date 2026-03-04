defmodule AcaiWeb.TeamsLive do
  use AcaiWeb, :live_view

  alias Acai.Teams
  alias Acai.Teams.Team

  @impl true
  def mount(_params, _session, socket) do
    teams = Teams.list_teams(socket.assigns.current_scope)

    socket =
      socket
      # TEAMS.MAIN.2
      |> stream(:teams, teams)
      |> assign(:teams_empty?, teams == [])
      # TEAMS.CREATE.2
      |> assign(:form, to_form(Teams.change_team(%Team{})))
      # TEAMS.MAIN.1-1
      |> assign(:show_modal, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("open_modal", _params, socket) do
    # TEAMS.MAIN.1-1
    socket =
      socket
      |> assign(:show_modal, true)
      |> assign(:form, to_form(Teams.change_team(%Team{})))

    {:noreply, socket}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :show_modal, false)}
  end

  def handle_event("validate", %{"team" => params}, socket) do
    # TEAMS.ENG.2
    changeset =
      %Team{}
      |> Teams.change_team(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("create_team", %{"team" => params}, socket) do
    case Teams.create_team(socket.assigns.current_scope, params) do
      {:ok, team} ->
        # TEAMS.CREATE.3-1
        {:noreply, push_navigate(socket, to: "/t/#{team.id}")}

      {:error, changeset} ->
        # TEAMS.CREATE.1
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-8">
        <%!-- Page header --%>
        <.header>
          My Teams
          <:subtitle>Manage your teams and create new ones.</:subtitle>
          <:actions>
            <%!-- TEAMS.MAIN.1 --%>
            <.button
              id="open-create-team-modal"
              phx-click="open_modal"
              variant="primary"
            >
              <.icon name="hero-plus" class="size-4 mr-1" /> Create Team
            </.button>
          </:actions>
        </.header>

        <%!-- TEAMS.MAIN.2-1 --%>
        <%= if @teams_empty? do %>
          <div
            id="teams-empty-state"
            class="flex flex-col items-center justify-center rounded-2xl border-2 border-dashed border-base-300 py-20 px-8 text-center gap-4"
          >
            <div class="rounded-full bg-base-200 p-4">
              <.icon name="hero-user-group" class="size-10 text-base-content/40" />
            </div>
            <div>
              <p class="text-lg font-semibold">No teams yet</p>
              <p class="text-sm text-base-content/60 mt-1">
                Create your first team to get started.
              </p>
            </div>
            <.button id="empty-state-create-team" phx-click="open_modal" variant="primary">
              <.icon name="hero-plus" class="size-4 mr-1" /> Create Team
            </.button>
          </div>
        <% end %>

        <%!-- TEAMS.MAIN.2 --%>
        <div
          id="teams-list"
          phx-update="stream"
          class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3"
        >
          <div :for={{id, team} <- @streams.teams} id={id}>
            <%!-- TEAMS.MAIN.2-2 --%>
            <.link navigate={"/t/#{team.id}"} class="block group">
              <div class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md hover:border-primary/40 transition-all duration-200 cursor-pointer">
                <div class="card-body gap-3">
                  <div class="flex items-center gap-3">
                    <div class="rounded-lg bg-primary/10 p-2">
                      <.icon name="hero-user-group" class="size-5 text-primary" />
                    </div>
                    <h2 class="card-title text-base group-hover:text-primary transition-colors">
                      {team.name}
                    </h2>
                  </div>
                  <div class="flex items-center justify-end text-xs text-base-content/50">
                    <.icon
                      name="hero-arrow-right"
                      class="size-4 group-hover:translate-x-1 transition-transform"
                    />
                  </div>
                </div>
              </div>
            </.link>
          </div>
        </div>
      </div>

      <%!-- TEAMS.MAIN.1-1 / TEAMS.CREATE --%>
      <%= if @show_modal do %>
        <div
          id="create-team-modal-backdrop"
          class="fixed inset-0 z-40 bg-black/50 flex items-center justify-center"
          phx-click="close_modal"
        >
          <div
            id="create-team-modal"
            class="relative z-50 w-full max-w-md mx-4 bg-base-100 rounded-2xl shadow-xl p-6 space-y-5"
            phx-click-away="close_modal"
          >
            <div class="flex items-center justify-between">
              <h3 class="text-lg font-semibold">Create a new team</h3>
              <button
                id="close-modal-button"
                type="button"
                phx-click="close_modal"
                class="btn btn-ghost btn-sm btn-circle"
                aria-label="Close"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <.form
              for={@form}
              id="create-team-form"
              phx-change="validate"
              phx-submit="create_team"
              class="space-y-4"
            >
              <%!-- TEAMS.CREATE.2 --%>
              <.input
                field={@form[:name]}
                type="text"
                label="Team name"
                placeholder="e.g. my-team"
                autocomplete="off"
              />
              <p class="text-xs text-base-content/50 -mt-2">
                Lowercase letters, numbers, and hyphens only.
              </p>

              <div class="flex gap-3 justify-end pt-1">
                <.button type="button" phx-click="close_modal">
                  Cancel
                </.button>
                <%!-- TEAMS.CREATE.3 --%>
                <.button type="submit" variant="primary" id="create-team-submit">
                  Create Team
                </.button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
