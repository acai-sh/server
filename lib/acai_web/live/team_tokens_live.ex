defmodule AcaiWeb.TeamTokensLive do
  use AcaiWeb, :live_view

  alias Acai.Teams
  alias Acai.Teams.{AccessToken, Permissions}

  @impl true
  def mount(%{"team_name" => team_name}, _session, socket) do
    team = Teams.get_team_by_name!(team_name)
    current_user = socket.assigns.current_scope.user

    members = Teams.list_team_members(team)

    current_role =
      Enum.find(members, fn r -> r.user_id == current_user.id end)

    current_role_title = if current_role, do: current_role.title, else: nil

    # team-tokens.TATSEC.4
    # team-tokens.TATSEC.5
    can_manage_tokens? = Permissions.has_permission?(current_role_title, "tats:admin")

    # team-tokens.MAIN.1
    tokens = Teams.list_team_tokens(team)
    inactive_tokens = Teams.list_inactive_team_tokens(team)

    timezone_offset =
      if connected?(socket) do
        get_connect_params(socket)["timezone_offset"] || 0
      else
        0
      end

    socket =
      socket
      |> assign(:team, team)
      |> assign(:can_manage_tokens?, can_manage_tokens?)
      |> assign(:tokens_empty?, tokens == [])
      # team-tokens.MAIN.1
      |> stream(:tokens, tokens)
      # team-tokens.INACTIVE.1
      |> stream(:inactive_tokens, inactive_tokens)
      # team-tokens.INACTIVE.3
      |> assign(:inactive_expanded, false)
      # team-tokens.MAIN.3
      |> assign(:show_create_modal, false)
      |> assign(:create_form, to_form(Teams.change_access_token(%AccessToken{}), as: :token))
      # team-tokens.MAIN.4
      |> assign(:created_token, nil)
      # team-tokens.MAIN.5
      |> assign(:show_revoke_modal, false)
      |> assign(:revoking_token, nil)
      |> assign(:timezone_offset, timezone_offset)
      # nav.AUTH.1: Pass current_path for navigation
      |> assign(:current_path, "/t/#{team.name}/tokens")

    {:ok, socket}
  end

  # --- Create token modal ---

  @impl true
  def handle_event("open_create_modal", _params, socket) do
    # team-tokens.TATSEC.4
    if socket.assigns.can_manage_tokens? do
      socket =
        socket
        |> assign(:show_create_modal, true)
        |> assign(:create_form, to_form(Teams.change_access_token(%AccessToken{}), as: :token))
        |> assign(:created_token, nil)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_create_modal", _params, socket) do
    socket =
      socket
      |> assign(:show_create_modal, false)
      |> assign(:created_token, nil)

    {:noreply, socket}
  end

  def handle_event("validate", %{"token" => params}, socket) do
    changeset =
      Teams.change_access_token(%AccessToken{}, params, socket.assigns.timezone_offset)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :create_form, to_form(changeset, as: :token))}
  end

  def handle_event("create_token", %{"token" => params}, socket) do
    # team-tokens.TATSEC.4
    if socket.assigns.can_manage_tokens? do
      case Teams.generate_token(
             socket.assigns.current_scope,
             socket.assigns.team,
             params,
             socket.assigns.timezone_offset
           ) do
        {:ok, token} ->
          is_valid? = Teams.valid_token?(token)

          # team-tokens.MAIN.4
          socket =
            if is_valid? do
              socket
              |> stream_insert(:tokens, token, at: 0)
              |> assign(:tokens_empty?, false)
            else
              socket
              |> stream_insert(:inactive_tokens, token, at: 0)
            end

          socket =
            socket
            |> assign(:created_token, token.raw_token)
            |> assign(
              :create_form,
              to_form(Teams.change_access_token(%AccessToken{}), as: :token)
            )

          {:noreply, socket}

        {:error, changeset} ->
          {:noreply, assign(socket, :create_form, to_form(changeset, as: :token))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("dismiss_token", _params, socket) do
    socket =
      socket
      |> assign(:created_token, nil)
      |> assign(:show_create_modal, false)

    {:noreply, socket}
  end

  # --- Revoke token modal ---

  def handle_event("open_revoke_modal", %{"token_id" => token_id}, socket) do
    # team-tokens.TATSEC.4
    if socket.assigns.can_manage_tokens? do
      token = Teams.get_access_token!(token_id)

      socket =
        socket
        |> assign(:show_revoke_modal, true)
        |> assign(:revoking_token, token)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_revoke_modal", _params, socket) do
    socket =
      socket
      |> assign(:show_revoke_modal, false)
      |> assign(:revoking_token, nil)

    {:noreply, socket}
  end

  def handle_event("confirm_revoke", _params, socket) do
    revoking_token = socket.assigns.revoking_token

    case Teams.revoke_token(revoking_token) do
      {:ok, revoked_token} ->
        revoked_with_user = Acai.Repo.preload(revoked_token, :user)

        socket =
          socket
          |> stream_delete(:tokens, revoking_token)
          |> stream_insert(:inactive_tokens, revoked_with_user, at: 0)
          |> assign(:tokens_empty?, Teams.list_team_tokens(socket.assigns.team) == [])
          |> assign(:show_revoke_modal, false)
          |> assign(:revoking_token, nil)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to revoke token. Please try again.")}
    end
  end

  def handle_event("toggle_inactive", _params, socket) do
    {:noreply, assign(socket, :inactive_expanded, not socket.assigns.inactive_expanded)}
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
        <.header>
          {@team.name} — Access Tokens
          <:subtitle>Manage API access tokens for this team</:subtitle>
          <:actions>
            <%!-- team-tokens.TATSEC.4 --%>
            <.button
              id="create-token-btn"
              phx-click="open_create_modal"
              variant="primary"
              disabled={not @can_manage_tokens?}
            >
              <.icon name="hero-plus" class="size-4 mr-1" /> Create Token
            </.button>
          </:actions>
        </.header>

        <%!-- team-tokens.MAIN.2 --%>
        <div
          id="token-education"
          class="rounded-xl border border-warning/30 bg-warning/10 p-4 text-sm"
        >
          <div class="flex gap-3">
            <.icon name="hero-information-circle" class="size-5 shrink-0 text-warning mt-0.5" />
            <div class="space-y-1">
              <p class="font-semibold text-warning">About Team Access Tokens</p>
              <p class="text-base-content/70">
                Tokens grant full read and write access to all team resources, except they can not be used to manage users or other access tokens.
              </p>
              <p class="text-base-content/70">
                When a user is removed from the team, any tokens they created are revoked.
              </p>
            </div>
          </div>
        </div>

        <%!-- team-tokens.MAIN.1 --%>
        <div class="space-y-4">
          <h2 class="text-base font-semibold">Tokens</h2>

          <div id="tokens-list" phx-update="stream" class="space-y-2">
            <div
              :for={{id, token} <- @streams.tokens}
              id={id}
              class="rounded-xl border border-base-300 bg-base-100 px-4 py-3 flex items-center gap-4"
            >
              <div class="rounded-lg bg-base-300 p-2">
                <.icon name="hero-key" class="size-5 text-primary" />
              </div>
              <div class="flex-1 min-w-0 space-y-0.5">
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="font-semibold truncate">{token.name}</span>
                  <code class="font-mono text-xs bg-base-200 px-1.5 py-0.5 rounded">
                    {token.token_prefix}…
                  </code>
                </div>
                <div class="text-xs text-base-content/50 flex flex-wrap gap-x-3 gap-y-0.5">
                  <span>
                    Created by {token.user && token.user.email}
                  </span>
                  <span>
                    {Calendar.strftime(token.inserted_at, "%b %d, %Y")}
                  </span>
                  <%= if not is_nil(token.expires_at) do %>
                    <span>Expires {Calendar.strftime(token.expires_at, "%b %d, %Y")}</span>
                  <% end %>
                  <%= if not is_nil(token.last_used_at) do %>
                    <span>Last used {Calendar.strftime(token.last_used_at, "%b %d, %Y")}</span>
                  <% end %>
                </div>
              </div>
              <%!-- team-tokens.MAIN.5 --%>
              <%!-- team-tokens.TATSEC.4 --%>
              <.button
                id={"revoke-btn-#{token.id}"}
                phx-click="open_revoke_modal"
                phx-value-token_id={token.id}
                disabled={not @can_manage_tokens?}
                class="btn btn-sm btn-ghost text-error hover:bg-error/10"
              >
                <.icon name="hero-x-circle" class="size-4" />
              </.button>
            </div>
          </div>
          <%= if @tokens_empty? do %>
            <div id="tokens-empty-state" class="text-sm text-base-content/50 py-4 text-center">
              No tokens yet. Create one to get started.
            </div>
          <% end %>
        </div>

        <%!-- team-tokens.INACTIVE.1 / INACTIVE.3 --%>
        <div id="inactive-tokens-section" class="border-t border-base-300 pt-6">
          <button
            id="toggle-inactive-btn"
            type="button"
            phx-click="toggle_inactive"
            class="flex items-center gap-2 text-sm font-semibold text-base-content/50 hover:text-base-content"
          >
            <.icon
              name={if @inactive_expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
              class="size-4"
            /> Inactive Tokens
          </button>

          <div id="inactive-tokens-container" class={if not @inactive_expanded, do: "hidden"}>
            <div id="inactive-tokens-list" phx-update="stream" class="mt-4 space-y-2">
              <div
                id="inactive-tokens-empty-state"
                class="hidden only:block text-xs text-base-content/30 py-2 italic"
              >
                No inactive tokens.
              </div>
              <div
                :for={{id, token} <- @streams.inactive_tokens}
                id={id}
                class="rounded-xl border border-base-300 bg-base-50/50 px-4 py-3 flex items-center gap-4 opacity-70"
              >
                <div class="rounded-lg bg-base-300 p-2">
                  <.icon name="hero-key" class="size-5 text-base-content/40" />
                </div>
                <div class="flex-1 min-w-0 space-y-0.5">
                  <div class="flex items-center gap-2 flex-wrap">
                    <span class="font-semibold truncate text-base-content/60">{token.name}</span>
                    <code class="font-mono text-xs bg-base-200/50 px-1.5 py-0.5 rounded text-base-content/50">
                      {token.token_prefix}…
                    </code>
                    <%!-- team-tokens.INACTIVE.2 --%>
                    <%= if not is_nil(token.revoked_at) do %>
                      <span class="inline-flex items-center gap-1 text-[10px] font-bold uppercase tracking-wider text-base-content/40 bg-base-300 px-2 py-0.5 rounded-full">
                        Revoked
                      </span>
                    <% else %>
                      <span class="inline-flex items-center gap-1 text-[10px] font-bold uppercase tracking-wider text-warning/70 bg-warning/10 px-2 py-0.5 rounded-full">
                        Expired
                      </span>
                    <% end %>
                  </div>
                  <div class="text-[11px] text-base-content/40 flex flex-wrap gap-x-3 gap-y-0.5">
                    <span>
                      Created by {token.user && token.user.email}
                    </span>
                    <%!-- team-tokens.INACTIVE.2 --%>
                    <%= if not is_nil(token.revoked_at) do %>
                      <span>
                        Revoked on {Calendar.strftime(token.revoked_at, "%b %d, %Y")}
                      </span>
                    <% else %>
                      <span>
                        Expired on {Calendar.strftime(token.expires_at, "%b %d, %Y")}
                      </span>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- team-tokens.USAGE.1 --%>
        <div id="usage-section" class="space-y-4">
          <h2 class="text-base font-semibold">Usage</h2>
          <div class="rounded-xl border border-base-300 bg-base-100 p-8 text-center space-y-2">
            <.icon name="hero-chart-bar" class="size-8 text-base-content/20 mx-auto" />
            <p class="font-medium text-base-content/50">Coming soon</p>
            <p class="text-sm text-base-content/40">
              Token usage analytics will be available in a future release.
            </p>
          </div>
        </div>
      </div>

      <%!-- team-tokens.MAIN.3 / team-tokens.MAIN.4 --%>
      <%= if @show_create_modal do %>
        <div
          id="create-token-modal-backdrop"
          class="fixed inset-0 z-40 bg-black/50 flex items-center justify-center"
        >
          <div
            id="create-token-modal"
            class="relative z-50 w-full max-w-lg mx-4 bg-base-100 rounded-2xl shadow-xl p-6 space-y-5"
            phx-click-away="close_create_modal"
          >
            <div class="flex items-center justify-between">
              <h3 class="text-lg font-semibold">
                {if @created_token, do: "Token Created", else: "Create Access Token"}
              </h3>
              <button
                id="close-create-modal-btn"
                type="button"
                phx-click="close_create_modal"
                class="btn btn-ghost btn-sm btn-circle"
                aria-label="Close"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <%= if @created_token do %>
              <%!-- team-tokens.MAIN.4 --%>
              <div id="token-reveal" class="space-y-4">
                <div class="rounded-lg border border-warning/40 bg-warning/10 p-3 flex gap-2 text-sm text-warning-content">
                  <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-warning mt-0.5" />
                  <p>
                    Make sure to copy your token now.
                    <strong>You won't be able to see it again.</strong>
                  </p>
                </div>
                <%!-- team-tokens.MAIN.4-1 --%>
                <div class="relative">
                  <pre
                    id="raw-token-display"
                    class="font-mono text-sm bg-base-200 rounded-lg px-4 py-3 break-all select-all overflow-x-auto"
                    phx-hook=".CopyToken"
                    data-token={@created_token}
                  >{@created_token}</pre>
                  <button
                    id="copy-token-btn"
                    type="button"
                    class="absolute top-2 right-2 btn btn-xs btn-ghost flex items-center gap-1.5"
                    aria-label="Copy token"
                  >
                    <span
                      id="copy-status"
                      class="hidden text-[10px] font-bold uppercase tracking-wider text-success"
                    >
                      Copied!
                    </span>
                    <span id="copy-icon-container">
                      <.icon name="hero-clipboard" class="size-4" />
                    </span>
                  </button>
                </div>
                <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToken">
                  export default {
                    mounted() {
                      const btn = this.el.parentElement.querySelector("#copy-token-btn");
                      const status = this.el.parentElement.querySelector("#copy-status");
                      const iconContainer = this.el.parentElement.querySelector("#copy-icon-container");

                      if (btn && status && iconContainer) {
                        btn.addEventListener("click", () => {
                          const token = this.el.dataset.token;
                          navigator.clipboard.writeText(token).then(() => {
                            // team-tokens.MAIN.4-1
                            status.classList.remove("hidden");
                            const originalIcon = iconContainer.innerHTML;
                            iconContainer.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" class="size-4 text-success" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" /></svg>';

                            setTimeout(() => {
                              status.classList.add("hidden");
                              iconContainer.innerHTML = originalIcon;
                            }, 2000);
                          });
                        });
                      }
                    }
                  }
                </script>
                <div class="flex justify-end">
                  <.button id="dismiss-token-btn" phx-click="dismiss_token" variant="primary">
                    Done
                  </.button>
                </div>
              </div>
            <% else %>
              <%!-- team-tokens.MAIN.3 --%>
              <%!-- team-tokens.MAIN.3-1 --%>
              <.form
                for={@create_form}
                id="create-token-form"
                phx-change="validate"
                phx-submit="create_token"
                class="space-y-4"
              >
                <.input
                  field={@create_form[:name]}
                  type="text"
                  label="Token name"
                  placeholder="e.g. Agentic CLI V1"
                  autocomplete="off"
                />
                <.input
                  field={@create_form[:expires_at_local]}
                  type="datetime-local"
                  label="Expiration (optional)"
                />
                <p class="text-xs text-base-content/50 -mt-2">
                  Leave blank for a non-expiring token.
                </p>
                <div class="flex gap-3 justify-end pt-1">
                  <.button type="button" phx-click="close_create_modal" id="cancel-create-btn">
                    Cancel
                  </.button>
                  <.button type="submit" variant="primary" id="submit-create-token-btn">
                    Create Token
                  </.button>
                </div>
              </.form>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- team-tokens.MAIN.5-1 --%>
      <%= if @show_revoke_modal do %>
        <div
          id="revoke-token-modal-backdrop"
          class="fixed inset-0 z-40 bg-black/50 flex items-center justify-center"
        >
          <div
            id="revoke-token-modal"
            class="relative z-50 w-full max-w-md mx-4 bg-base-100 rounded-2xl shadow-xl p-6 space-y-5"
            phx-click-away="close_revoke_modal"
          >
            <div class="flex items-center justify-between">
              <h3 class="text-lg font-semibold">Revoke Token</h3>
              <button
                id="close-revoke-modal-btn"
                type="button"
                phx-click="close_revoke_modal"
                class="btn btn-ghost btn-sm btn-circle"
                aria-label="Close"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <div class="space-y-2">
              <p class="text-sm">
                Are you sure you want to revoke this token?
                <%= if @revoking_token do %>
                  <span class="font-medium">{@revoking_token.name}</span>
                <% end %>
              </p>
              <div class="alert alert-warning text-sm">
                <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                <p>
                  This action is immediate and cannot be undone. Any API clients using this token will lose access instantly.
                </p>
              </div>
            </div>

            <div class="flex gap-3 justify-end pt-1">
              <.button type="button" phx-click="close_revoke_modal" id="cancel-revoke-btn">
                Cancel
              </.button>
              <.button
                id="confirm-revoke-btn"
                type="button"
                phx-click="confirm_revoke"
                class="btn btn-error"
              >
                <.icon name="hero-x-circle" class="size-4 mr-1" /> Revoke Token
              </.button>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
