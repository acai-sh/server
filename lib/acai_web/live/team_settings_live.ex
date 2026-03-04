defmodule AcaiWeb.TeamSettingsLive do
  use AcaiWeb, :live_view

  alias Acai.Teams
  alias Acai.Teams.Permissions

  @impl true
  def mount(%{"team_id" => team_id}, _session, socket) do
    team = Teams.get_team!(team_id)
    current_user = socket.assigns.current_scope.user

    members = Teams.list_team_members(team)

    current_role =
      Enum.find(members, fn r -> r.user_id == current_user.id end)

    current_role_title = if current_role, do: current_role.title, else: nil

    # TEAM_SETTINGS.AUTH.1
    # TEAM_SETTINGS.AUTH.2
    if Permissions.has_permission?(current_role_title, "team:admin") do
      socket =
        socket
        # TEAM_SETTINGS.MAIN.1
        |> assign(:team, team)
        # TEAM_SETTINGS.MAIN.2
        |> assign(:show_rename_modal, false)
        |> assign(:rename_form, to_form(Teams.change_team(team)))
        # TEAM_SETTINGS.MAIN.3
        |> assign(:show_delete_modal, false)
        # TEAM_SETTINGS.DELETE.2
        |> assign(:confirm_name, "")

      {:ok, socket}
    else
      {:ok, push_navigate(socket, to: "/t/#{team_id}")}
    end
  end

  # --- Rename modal ---

  @impl true
  def handle_event("open_rename_modal", _params, socket) do
    # TEAM_SETTINGS.MAIN.2
    socket =
      socket
      |> assign(:show_rename_modal, true)
      |> assign(:rename_form, to_form(Teams.change_team(socket.assigns.team)))

    {:noreply, socket}
  end

  def handle_event("close_rename_modal", _params, socket) do
    {:noreply, assign(socket, :show_rename_modal, false)}
  end

  def handle_event("rename_team", %{"team" => params}, socket) do
    # TEAM_SETTINGS.RENAME.3
    case Teams.update_team(socket.assigns.team, params) do
      {:ok, updated_team} ->
        # TEAM_SETTINGS.RENAME.3-2
        socket =
          socket
          |> assign(:team, updated_team)
          |> assign(:show_rename_modal, false)
          |> assign(:rename_form, to_form(Teams.change_team(updated_team)))

        {:noreply, socket}

      {:error, changeset} ->
        # TEAM_SETTINGS.RENAME.3-1
        {:noreply, assign(socket, :rename_form, to_form(changeset))}
    end
  end

  # --- Delete modal ---

  def handle_event("open_delete_modal", _params, socket) do
    # TEAM_SETTINGS.MAIN.3
    socket =
      socket
      |> assign(:show_delete_modal, true)
      |> assign(:confirm_name, "")

    {:noreply, socket}
  end

  def handle_event("close_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  def handle_event("update_confirm_name", %{"confirm_name" => name}, socket) do
    # TEAM_SETTINGS.DELETE.3
    {:noreply, assign(socket, :confirm_name, name)}
  end

  def handle_event("confirm_delete", _params, socket) do
    team = socket.assigns.team

    if socket.assigns.confirm_name == team.name do
      # TEAM_SETTINGS.DELETE.5
      case Teams.delete_team(team) do
        {:ok, _} ->
          {:noreply, push_navigate(socket, to: "/teams")}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-8 max-w-2xl mx-auto">
        <%!-- TEAM_SETTINGS.MAIN.1 --%>
        <.header>
          {@team.name}
          <:subtitle>Team settings</:subtitle>
        </.header>

        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body space-y-6">
            <%!-- Rename section --%>
            <div class="flex items-center justify-between gap-4">
              <div>
                <h3 class="font-semibold">Team Name</h3>
                <p class="text-sm text-base-content/60">
                  Change the name of your team.
                </p>
              </div>
              <%!-- TEAM_SETTINGS.MAIN.2 --%>
              <.button id="rename-team-btn" phx-click="open_rename_modal">
                <.icon name="hero-pencil-square" class="size-4 mr-1" /> Rename Team
              </.button>
            </div>

            <div class="divider my-0"></div>

            <%!-- Delete section --%>
            <div class="flex items-center justify-between gap-4">
              <div>
                <h3 class="font-semibold text-error">Delete Team</h3>
                <p class="text-sm text-base-content/60">
                  Permanently delete this team and all its data.
                </p>
              </div>
              <%!-- TEAM_SETTINGS.MAIN.3 --%>
              <.button
                id="delete-team-btn"
                phx-click="open_delete_modal"
                class="btn btn-error btn-sm"
              >
                <.icon name="hero-trash" class="size-4 mr-1" /> Delete Team
              </.button>
            </div>
          </div>
        </div>
      </div>

      <%!-- TEAM_SETTINGS.RENAME --%>
      <%= if @show_rename_modal do %>
        <div
          id="rename-modal-backdrop"
          class="fixed inset-0 z-40 bg-black/50 flex items-center justify-center"
          phx-click="close_rename_modal"
        >
          <div
            id="rename-modal"
            class="relative z-50 w-full max-w-md mx-4 bg-base-100 rounded-2xl shadow-xl p-6 space-y-5"
            phx-click-away="close_rename_modal"
          >
            <div class="flex items-center justify-between">
              <h3 class="text-lg font-semibold">Rename Team</h3>
              <button
                id="close-rename-modal-btn"
                type="button"
                phx-click="close_rename_modal"
                class="btn btn-ghost btn-sm btn-circle"
                aria-label="Close"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <.form
              for={@rename_form}
              id="rename-team-form"
              phx-submit="rename_team"
              class="space-y-4"
            >
              <%!-- TEAM_SETTINGS.RENAME.1 --%>
              <.input
                field={@rename_form[:name]}
                type="text"
                label="Team name"
                autocomplete="off"
              />
              <p class="text-xs text-base-content/50 -mt-2">
                Lowercase letters, numbers, and hyphens only.
              </p>

              <%!-- TEAM_SETTINGS.RENAME.2 --%>
              <div class="flex gap-3 justify-end pt-1">
                <.button type="button" phx-click="close_rename_modal" id="cancel-rename-btn">
                  Cancel
                </.button>
                <.button type="submit" variant="primary" id="save-rename-btn">
                  Save
                </.button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <%!-- TEAM_SETTINGS.DELETE --%>
      <%= if @show_delete_modal do %>
        <div
          id="delete-modal-backdrop"
          class="fixed inset-0 z-40 bg-black/50 flex items-center justify-center"
          phx-click="close_delete_modal"
        >
          <div
            id="delete-modal"
            class="relative z-50 w-full max-w-md mx-4 bg-base-100 rounded-2xl shadow-xl p-6 space-y-5"
            phx-click-away="close_delete_modal"
          >
            <div class="flex items-center justify-between">
              <h3 class="text-lg font-semibold text-error">Delete Team</h3>
              <button
                id="close-delete-modal-btn"
                type="button"
                phx-click="close_delete_modal"
                class="btn btn-ghost btn-sm btn-circle"
                aria-label="Close"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <%!-- TEAM_SETTINGS.DELETE.1 --%>
            <div class="alert alert-error text-sm">
              <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
              <div>
                <p class="font-semibold">This action is permanent and cannot be undone.</p>
                <p class="mt-1">
                  Deleting this team will cascade-delete all associated data, including:
                </p>
                <ul class="list-disc list-inside mt-1 space-y-0.5">
                  <li>Implementations</li>
                  <li>Specs and requirements</li>
                  <li>Members</li>
                  <li>Access tokens</li>
                </ul>
              </div>
            </div>

            <%!-- TEAM_SETTINGS.DELETE.2 --%>
            <div class="space-y-2">
              <p class="text-sm">
                To confirm, type <span class="font-mono font-semibold">{@team.name}</span> below:
              </p>
              <form phx-change="update_confirm_name">
                <input
                  id="confirm-team-name-input"
                  type="text"
                  name="confirm_name"
                  value={@confirm_name}
                  placeholder={@team.name}
                  autocomplete="off"
                  class="input input-bordered w-full"
                />
              </form>
            </div>

            <div class="flex gap-3 justify-end pt-1">
              <%!-- TEAM_SETTINGS.DELETE.4 --%>
              <.button type="button" phx-click="close_delete_modal" id="cancel-delete-btn">
                Cancel
              </.button>
              <%!-- TEAM_SETTINGS.DELETE.3 --%>
              <.button
                id="confirm-delete-team-btn"
                phx-click="confirm_delete"
                class="btn btn-error"
                disabled={@confirm_name != @team.name}
              >
                <.icon name="hero-trash" class="size-4 mr-1" /> Delete Team
              </.button>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
