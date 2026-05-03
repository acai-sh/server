defmodule AcaiWeb.TeamLive do
  use AcaiWeb, :live_view

  alias Acai.Teams
  alias Acai.Teams.Permissions
  alias Acai.Products

  @impl true
  def mount(%{"team_name" => team_name}, _session, socket) do
    team = Teams.get_team_by_name!(team_name)
    current_user = socket.assigns.current_scope.user

    members = Teams.list_team_members(team)
    # data-model.PRODUCTS: Products are now first-class entities
    products = Products.list_products(socket.assigns.current_scope, team)
    product_names = Enum.map(products, & &1.name) |> Enum.sort()

    current_role =
      Enum.find(members, fn r -> r.user_id == current_user.id end)

    current_role_title = if current_role, do: current_role.title, else: nil

    can_admin? = Permissions.has_permission?(current_role_title, "team:admin")
    global_admin_member? = Teams.member_of_global_admin_team?(socket.assigns.current_scope)
    show_admin_section? = global_admin_member? and team.global_admin

    owner_count =
      Enum.count(members, fn r -> r.title == "owner" end)

    socket =
      socket
      # team-view.MAIN.1
      |> assign(:team, team)
      # data-model.PRODUCTS: Products are now first-class entities
      |> assign(:products, product_names)
      |> assign(:current_role_title, current_role_title)
      |> assign(:current_path, ~p"/t/#{team.name}")
      |> assign(:can_admin?, can_admin?)
      # dashboard.MAIN.1
      # dashboard.MAIN.2
      |> assign(:show_admin_section?, show_admin_section?)
      |> assign(:owner_count, owner_count)
      # team-view.MEMBERS.1
      |> stream(:members, members, dom_id: fn r -> "member-#{r.user_id}" end)
      # team-view.MEMBERS.2
      |> assign(:show_invite_modal, false)
      |> assign(:invite_form, to_form(%{"email" => "", "role" => "developer"}, as: :invite))
      |> assign(:invite_error, nil)
      # team-view.EDIT_ROLE.1
      |> assign(:show_edit_modal, false)
      |> assign(:editing_member, nil)
      |> assign(:edit_form, to_form(%{"role" => "developer"}, as: :edit))
      |> assign(:edit_error, nil)
      # team-view.DELETE_ROLE.1
      |> assign(:show_delete_modal, false)
      |> assign(:deleting_member, nil)
      |> assign(:delete_error, nil)
      # nav.AUTH.1: Pass current_path for navigation
      |> assign(:current_path, "/t/#{team.name}")

    {:ok, socket}
  end

  # --- Invite modal ---

  @impl true
  def handle_event("open_invite_modal", _params, socket) do
    # team-view.MEMBERS.2
    socket =
      socket
      |> assign(:show_invite_modal, true)
      |> assign(:invite_form, to_form(%{"email" => "", "role" => "developer"}, as: :invite))
      |> assign(:invite_error, nil)

    {:noreply, socket}
  end

  def handle_event("close_invite_modal", _params, socket) do
    {:noreply, assign(socket, :show_invite_modal, false)}
  end

  def handle_event("invite_member", %{"invite" => params}, socket) do
    team = socket.assigns.team
    email = params["email"]
    role = params["role"]

    login_url_fn = fn token ->
      url(~p"/users/log-in/#{token}")
    end

    case Teams.invite_member(team, email, role, login_url_fn) do
      {:ok, new_member} ->
        # team-view.INVITE.3-4
        owner_count =
          if new_member.title == "owner",
            do: socket.assigns.owner_count + 1,
            else: socket.assigns.owner_count

        socket =
          socket
          |> stream_insert(:members, new_member, dom_id: fn r -> "member-#{r.user_id}" end)
          |> assign(:owner_count, owner_count)
          |> assign(:show_invite_modal, false)
          |> assign(:invite_form, to_form(%{"email" => "", "role" => "developer"}, as: :invite))
          |> assign(:invite_error, nil)

        {:noreply, socket}

      {:error, :already_member} ->
        # team-view.INVITE.3-1
        {:noreply, assign(socket, :invite_error, "This person is already a member of the team.")}

      {:error, _} ->
        {:noreply, assign(socket, :invite_error, "An error occurred. Please try again.")}
    end
  end

  # --- Edit role modal ---

  def handle_event("open_edit_modal", %{"user_id" => user_id}, socket) do
    # team-view.MEMBERS.3
    members_list = get_members_list(socket)

    editing_member = Enum.find(members_list, fn r -> to_string(r.user_id) == user_id end)

    socket =
      socket
      |> assign(:show_edit_modal, true)
      |> assign(:editing_member, editing_member)
      |> assign(:edit_form, to_form(%{"role" => editing_member.title}, as: :edit))
      |> assign(:edit_error, nil)

    {:noreply, socket}
  end

  def handle_event("close_edit_modal", _params, socket) do
    {:noreply, assign(socket, :show_edit_modal, false)}
  end

  def handle_event("save_role", %{"edit" => %{"role" => new_role}}, socket) do
    # team-view.EDIT_ROLE.3
    editing_member = socket.assigns.editing_member

    case Teams.update_member_role(socket.assigns.current_scope, editing_member, new_role) do
      {:ok, updated_role} ->
        updated_with_user = %{updated_role | user: editing_member.user}

        owner_count = recompute_owner_count(socket, updated_with_user)

        current_user_id = socket.assigns.current_scope.user.id

        current_role_title =
          if updated_with_user.user_id == current_user_id do
            updated_with_user.title
          else
            socket.assigns.current_role_title
          end

        can_admin? = Permissions.has_permission?(current_role_title, "team:admin")

        socket =
          socket
          |> stream_insert(:members, updated_with_user, dom_id: fn r -> "member-#{r.user_id}" end)
          |> assign(:owner_count, owner_count)
          |> assign(:current_role_title, current_role_title)
          |> assign(:can_admin?, can_admin?)
          |> assign(:show_edit_modal, false)
          |> assign(:editing_member, nil)
          |> assign(:edit_error, nil)

        {:noreply, socket}

      {:error, :self_demotion} ->
        {:noreply, assign(socket, :edit_error, "You cannot change your own role.")}

      {:error, :last_owner} ->
        {:noreply, assign(socket, :edit_error, "Cannot change role: this is the last owner.")}

      {:error, _changeset} ->
        {:noreply, assign(socket, :edit_error, "Invalid role selected.")}
    end
  end

  # --- Delete member modal ---

  def handle_event("open_delete_modal", %{"user_id" => user_id}, socket) do
    # team-view.DELETE_ROLE.1
    members_list = get_members_list(socket)
    deleting_member = Enum.find(members_list, fn r -> to_string(r.user_id) == user_id end)

    socket =
      socket
      |> assign(:show_delete_modal, true)
      |> assign(:deleting_member, deleting_member)
      |> assign(:delete_error, nil)

    {:noreply, socket}
  end

  def handle_event("close_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  def handle_event("confirm_delete", _params, socket) do
    team = socket.assigns.team
    deleting_member = socket.assigns.deleting_member

    case Teams.remove_member(team, deleting_member.user_id) do
      {:ok, :removed} ->
        owner_count =
          if deleting_member.title == "owner",
            do: socket.assigns.owner_count - 1,
            else: socket.assigns.owner_count

        socket =
          socket
          |> stream_delete(:members, deleting_member)
          |> assign(:owner_count, owner_count)
          |> assign(:show_delete_modal, false)
          |> assign(:deleting_member, nil)
          |> assign(:delete_error, nil)

        {:noreply, socket}

      {:error, :last_owner} ->
        # team-view.DELETE_ROLE.4
        {:noreply, assign(socket, :delete_error, "Cannot remove the last owner of the team.")}

      {:error, :not_found} ->
        {:noreply, assign(socket, :delete_error, "Member not found.")}
    end
  end

  # --- Private helpers ---

  defp get_members_list(socket) do
    # Pull from the stream's inserts for lookup. We maintain a flat list
    # for modal lookups by fetching fresh from the DB via the team.
    Teams.list_team_members(socket.assigns.team)
  end

  defp recompute_owner_count(socket, updated_role) do
    # Recompute owner count: adjust based on the old and new role of the updated member
    old_title = socket.assigns.editing_member.title
    new_title = updated_role.title

    cond do
      old_title != "owner" && new_title == "owner" -> socket.assigns.owner_count + 1
      old_title == "owner" && new_title != "owner" -> socket.assigns.owner_count - 1
      true -> socket.assigns.owner_count
    end
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
        <%!-- team-view.MAIN.0: Page header --%>
        <.content_header
          page_title="Team Overview"
          resource_name={@team.name}
          resource_icon="hero-user-group"
          resource_icon_color="accent"
          breadcrumb_items={[
            %{label: "Overview", navigate: ~p"/t/#{@team.name}", icon: "hero-home"}
          ]}
        >
          <:actions>
            <%!-- team-view.MAIN.3 --%>
            <.button id="team-settings-btn" navigate={"/t/#{@team.name}/settings"}>
              <.icon name="hero-cog-6-tooth" class="size-4 mr-1" /> Settings
            </.button>
          </:actions>
        </.content_header>

        <%!-- team-view.PRODUCTS.1 --%>
        <div class="space-y-4">
          <div>
            <h2 class="text-base font-semibold">Products</h2>
            <p class="text-sm text-base-content/60">Overview of products owned by this team</p>
          </div>

          <%= if @products == [] do %>
            <div class="text-center py-12 rounded-xl border-2 border-dashed border-base-300">
              <.icon name="hero-folder-open" class="size-12 text-base-content/30 mx-auto mb-4" />
              <p class="text-base-content/60">
                This team does not have any products. Push a spec using the CLI.
              </p>
            </div>
          <% else %>
            <div id="products-list" class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <div :for={product <- @products}>
                <%!-- team-view.PRODUCTS.3 --%>
                <.link navigate={"/t/#{@team.name}/p/#{product}"} class="block group">
                  <div class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md hover:border-accent/40 transition-all duration-200 cursor-pointer h-full">
                    <div class="card-body p-5">
                      <div class="flex items-center gap-3">
                        <div class="rounded-lg bg-accent/10 p-2">
                          <.icon name="custom-boxes" class="size-5 text-accent" />
                        </div>
                        <%!-- team-view.PRODUCTS.2 --%>
                        <h3 class="font-semibold text-base group-hover:text-accent transition-colors">
                          {product}
                        </h3>
                      </div>
                    </div>
                  </div>
                </.link>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- team-view.MEMBERS.1 --%>
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <div>
              <h2 class="text-base font-semibold">Members</h2>
              <p class="text-sm text-base-content/60">People with access to this team</p>
            </div>
            <%!-- team-view.MEMBERS.2 --%>
            <%!-- team-view.MEMBERS.2-1 --%>
            <.button
              id="invite-member-btn"
              phx-click="open_invite_modal"
              variant="primary"
              disabled={not @can_admin?}
            >
              <.icon name="hero-user-plus" class="size-4 mr-1" /> Invite
            </.button>
          </div>

          <div
            id="members-list"
            phx-update="stream"
            class="divide-y divide-base-200 rounded-xl border border-base-300 overflow-hidden"
          >
            <div
              :for={{id, member} <- @streams.members}
              id={id}
              class="flex items-center gap-4 px-4 py-3 bg-base-100 hover:bg-base-200/50 transition-colors"
            >
              <div class="flex-1 min-w-0">
                <p class="font-medium truncate">{member.user.email}</p>
                <p class="text-sm text-base-content/60 capitalize">{member.title}</p>
              </div>
              <div class="flex items-center gap-2">
                <%!-- team-view.MEMBERS.3 --%>
                <%!-- team-view.MEMBERS.3-1 --%>
                <%!-- team-view.MEMBERS.3-2 --%>
                <.button
                  id={"edit-btn-#{member.user_id}"}
                  phx-click="open_edit_modal"
                  phx-value-user_id={member.user_id}
                  disabled={
                    not @can_admin? or
                      (member.user_id == @current_scope.user.id and
                         (member.title != "owner" or @owner_count <= 1))
                  }
                >
                  <.icon name="hero-pencil-square" class="size-4" />
                </.button>
                <.button
                  id={"delete-btn-#{member.user_id}"}
                  phx-click="open_delete_modal"
                  phx-value-user_id={member.user_id}
                  disabled={not @can_admin?}
                >
                  <.icon name="hero-trash" class="size-4" />
                </.button>
              </div>
            </div>
          </div>
        </div>

        <%!-- team-view.MAIN.2 --%>
        <.link navigate={"/t/#{@team.name}/tokens"} class="block group" id="access-tokens-card">
          <div class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md hover:border-primary/40 transition-all duration-200 cursor-pointer">
            <div class="card-body flex-row items-center gap-4">
              <div class="rounded-lg bg-base-300 p-3">
                <.icon name="hero-key" class="size-6 text-primary" />
              </div>
              <div class="flex-1">
                <h3 class="font-semibold text-base group-hover:text-primary transition-colors">
                  Access Tokens
                </h3>
                <p class="text-sm text-base-content/60">Manage API tokens for this team</p>
              </div>
              <.icon
                name="hero-arrow-right"
                class="size-5 text-base-content/40 group-hover:translate-x-1 transition-transform"
              />
            </div>
          </div>
        </.link>

        <%= if @show_admin_section? do %>
          <div id="admin-section" class="space-y-4">
            <div>
              <h2 class="text-base font-semibold">Admin</h2>
              <p class="text-sm text-base-content/60">
                Access internal dashboard tools for monitoring the application
              </p>
            </div>

            <div class="card bg-base-100 border border-base-300 shadow-sm">
              <div class="card-body gap-4 sm:flex-row sm:items-center sm:justify-between">
                <div class="space-y-1">
                  <h3 class="font-semibold text-base">Dashboard</h3>
                  <p class="text-sm text-base-content/60">
                    Review query performance and runtime health from the Phoenix dashboard
                  </p>
                </div>

                <%!-- dashboard.MAIN.1 --%>
                <%!-- dashboard.MAIN.1-1 --%>
                <.button
                  id="admin-dashboard-btn"
                  navigate={~p"/admin/dashboard/home"}
                  variant="primary"
                >
                  <.icon name="hero-chart-bar-square" class="size-4 mr-1" /> Dashboard
                </.button>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- team-view.INVITE.1 / team-view.INVITE.2 / team-view.INVITE.3 --%>
      <%= if @show_invite_modal do %>
        <div
          id="invite-modal-backdrop"
          class="fixed inset-0 z-40 bg-black/50 flex items-center justify-center"
        >
          <div
            id="invite-modal"
            class="relative z-50 w-full max-w-md mx-4 bg-base-100 rounded-2xl shadow-xl p-6 space-y-5"
            phx-click-away="close_invite_modal"
          >
            <div class="flex items-center justify-between">
              <h3 class="text-lg font-semibold">Invite a team member</h3>
              <button
                id="close-invite-modal-btn"
                type="button"
                phx-click="close_invite_modal"
                class="btn btn-ghost btn-sm btn-circle"
                aria-label="Close"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <%= if @invite_error do %>
              <div id="invite-error-msg" class="alert alert-error text-sm">
                <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
                {@invite_error}
              </div>
            <% end %>

            <.form
              for={@invite_form}
              id="invite-form"
              phx-submit="invite_member"
              class="space-y-4"
            >
              <%!-- team-view.INVITE.1 --%>
              <.input
                field={@invite_form[:email]}
                type="email"
                label="Email address"
                placeholder="member@example.com"
                autocomplete="off"
              />
              <%!-- team-view.INVITE.2 --%>
              <.input
                field={@invite_form[:role]}
                type="select"
                label="Role"
                options={[{"Developer", "developer"}, {"Owner", "owner"}, {"Readonly", "readonly"}]}
              />

              <div class="flex gap-3 justify-end pt-1">
                <.button type="button" phx-click="close_invite_modal">
                  Cancel
                </.button>
                <%!-- team-view.INVITE.3 --%>
                <.button type="submit" variant="primary" id="send-invitation-btn">
                  Send Invitation
                </.button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <%!-- team-view.EDIT_ROLE.1 / team-view.EDIT_ROLE.2 --%>
      <%= if @show_edit_modal do %>
        <div
          id="edit-role-modal-backdrop"
          class="fixed inset-0 z-40 bg-black/50 flex items-center justify-center"
          phx-click="close_edit_modal"
        >
          <div
            id="edit-role-modal"
            class="relative z-50 w-full max-w-md mx-4 bg-base-100 rounded-2xl shadow-xl p-6 space-y-5"
            phx-click-away="close_edit_modal"
          >
            <div class="flex items-center justify-between">
              <h3 class="text-lg font-semibold">Edit member role</h3>
              <button
                id="close-edit-modal-btn"
                type="button"
                phx-click="close_edit_modal"
                class="btn btn-ghost btn-sm btn-circle"
                aria-label="Close"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <p class="text-sm text-base-content/60">
              Editing role for
              <span class="font-medium">{@editing_member && @editing_member.user.email}</span>
            </p>

            <%= if @edit_error do %>
              <div id="edit-error-msg" class="alert alert-error text-sm">
                <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
                {@edit_error}
              </div>
            <% end %>

            <.form
              for={@edit_form}
              id="edit-role-form"
              phx-submit="save_role"
              class="space-y-4"
            >
              <%!-- team-view.EDIT_ROLE.2 --%>
              <.input
                field={@edit_form[:role]}
                type="select"
                label="Role"
                options={[{"Developer", "developer"}, {"Owner", "owner"}, {"Readonly", "readonly"}]}
              />

              <div class="flex gap-3 justify-end pt-1">
                <%!-- team-view.EDIT_ROLE.1 --%>
                <.button type="button" phx-click="close_edit_modal" id="cancel-edit-btn">
                  Cancel
                </.button>
                <.button type="submit" variant="primary" id="save-role-btn">
                  Save
                </.button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <%!-- team-view.DELETE_ROLE.1 / team-view.DELETE_ROLE.2 --%>
      <%= if @show_delete_modal do %>
        <div
          id="delete-member-modal-backdrop"
          class="fixed inset-0 z-40 bg-black/50 flex items-center justify-center"
          phx-click="close_delete_modal"
        >
          <div
            id="delete-member-modal"
            class="relative z-50 w-full max-w-md mx-4 bg-base-100 rounded-2xl shadow-xl p-6 space-y-5"
            phx-click-away="close_delete_modal"
          >
            <div class="flex items-center justify-between">
              <h3 class="text-lg font-semibold">Remove team member</h3>
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

            <%!-- team-view.DELETE_ROLE.2 --%>
            <div class="space-y-2">
              <p class="text-sm">
                You are about to remove
                <span class="font-medium">
                  {@deleting_member && @deleting_member.user.email}
                </span>
                from <span class="font-medium">{@team.name}</span>.
              </p>
              <div class="alert alert-warning text-sm">
                <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                <div>
                  <p class="font-semibold">This will:</p>
                  <ul class="list-disc list-inside mt-1 space-y-0.5">
                    <li>Revoke their access to this team</li>
                    <li>Revoke all API access tokens they created for this team</li>
                  </ul>
                </div>
              </div>
            </div>

            <%= if @delete_error do %>
              <div id="delete-error-msg" class="alert alert-error text-sm">
                <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
                {@delete_error}
              </div>
            <% end %>

            <div class="flex gap-3 justify-end pt-1">
              <%!-- team-view.DELETE_ROLE.1 --%>
              <.button type="button" phx-click="close_delete_modal" id="cancel-delete-btn">
                Cancel
              </.button>
              <.button
                type="button"
                phx-click="confirm_delete"
                variant="primary"
                id="confirm-delete-btn"
                class="btn btn-error"
              >
                Delete Member
              </.button>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
