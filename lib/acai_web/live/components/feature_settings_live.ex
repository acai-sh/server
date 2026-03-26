defmodule AcaiWeb.Live.Components.FeatureSettingsLive do
  @moduledoc """
  Side drawer component for feature settings.
  """
  use AcaiWeb, :live_component

  alias Acai.Specs

  @impl true
  def update(assigns, socket) do
    id = Map.get(assigns, :id) || Map.get(assigns, "id")
    feature_name = Map.get(assigns, :feature_name) || Map.get(assigns, "feature_name")
    implementation = Map.get(assigns, :implementation) || Map.get(assigns, "implementation")
    product = Map.get(assigns, :product) || Map.get(assigns, "product")
    team = Map.get(assigns, :team) || Map.get(assigns, "team")
    visible = Map.get(assigns, :visible, false)
    spec = Map.get(assigns, :spec) || Map.get(assigns, "spec")

    spec_inherited =
      Map.get(assigns, :spec_inherited) || Map.get(assigns, "spec_inherited", false)

    tracked_branches =
      Map.get(assigns, :tracked_branches) || Map.get(assigns, "tracked_branches", [])

    states_inherited =
      Map.get(assigns, :states_inherited) || Map.get(assigns, "states_inherited", false)

    refs_inherited =
      Map.get(assigns, :refs_inherited) || Map.get(assigns, "refs_inherited", false)

    # Get branch IDs for checking local refs
    branch_ids = Enum.map(tracked_branches, & &1.branch_id)

    # Check if local states/refs exist
    has_local_states = Specs.local_feature_impl_state_exists?(feature_name, implementation)
    has_local_refs = Specs.local_feature_branch_refs_exist?(branch_ids, feature_name)

    socket =
      socket
      |> assign(:id, id)
      |> assign(:feature_name, feature_name)
      |> assign(:implementation, implementation)
      |> assign(:product, product)
      |> assign(:team, team)
      |> assign(:visible, visible)
      |> assign(:spec, spec)
      |> assign(:spec_inherited, spec_inherited)
      |> assign(:tracked_branches, tracked_branches)
      |> assign(:branch_ids, branch_ids)
      |> assign(:states_inherited, states_inherited)
      |> assign(:refs_inherited, refs_inherited)
      |> assign(:has_local_states, has_local_states)
      |> assign(:has_local_refs, has_local_refs)
      |> init_clear_states_modal()
      |> init_clear_refs_modal()
      |> init_delete_spec_modal()

    {:ok, socket}
  end

  # Initialize clear states modal state
  defp init_clear_states_modal(socket) do
    socket
    |> assign(:show_clear_states_modal, false)
  end

  # Initialize clear refs modal state
  defp init_clear_refs_modal(socket) do
    socket
    |> assign(:show_clear_refs_modal, false)
    |> assign(:selected_branch_ids, MapSet.new(socket.assigns.branch_ids))
  end

  # Initialize delete spec modal state
  defp init_delete_spec_modal(socket) do
    socket
    |> assign(:show_delete_spec_modal, false)
  end

  @impl true
  def handle_event("close", _params, socket) do
    # feature-settings.DRAWER.3
    send(self(), "feature_settings_closed")
    {:noreply, assign(socket, :visible, false)}
  end

  # --- Clear States handlers ---

  # feature-settings.CLEAR_STATES.3
  def handle_event("show_clear_states_modal", _params, socket) do
    {:noreply, assign(socket, :show_clear_states_modal, true)}
  end

  def handle_event("cancel_clear_states", _params, socket) do
    {:noreply, assign(socket, :show_clear_states_modal, false)}
  end

  # feature-settings.CLEAR_STATES.5
  def handle_event("confirm_clear_states", _params, socket) do
    feature_name = socket.assigns.feature_name
    implementation = socket.assigns.implementation

    case Specs.delete_feature_impl_state(feature_name, implementation) do
      {:ok, _} ->
        # feature-settings.CLEAR_STATES.6
        # feature-settings.CLEAR_STATES.7
        send(self(), :feature_states_changed)

        {:noreply,
         socket
         |> assign(:show_clear_states_modal, false)
         |> assign(:has_local_states, false)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to clear states")}
    end
  end

  # --- Clear Refs handlers ---

  # feature-settings.CLEAR_REFS.3
  def handle_event("show_clear_refs_modal", _params, socket) do
    {:noreply, assign(socket, :show_clear_refs_modal, true)}
  end

  def handle_event("cancel_clear_refs", _params, socket) do
    # Reset selection to all branches when canceling
    {:noreply,
     socket
     |> assign(:show_clear_refs_modal, false)
     |> assign(:selected_branch_ids, MapSet.new(socket.assigns.branch_ids))}
  end

  # feature-settings.CLEAR_REFS.4_3
  def handle_event("toggle_branch_selection", %{"branch_id" => branch_id}, socket) do
    branch_id = branch_id
    current_selection = socket.assigns.selected_branch_ids

    new_selection =
      if MapSet.member?(current_selection, branch_id) do
        MapSet.delete(current_selection, branch_id)
      else
        MapSet.put(current_selection, branch_id)
      end

    {:noreply, assign(socket, :selected_branch_ids, new_selection)}
  end

  # feature-settings.CLEAR_REFS.6
  def handle_event("confirm_clear_refs", _params, socket) do
    feature_name = socket.assigns.feature_name
    selected_branch_ids = MapSet.to_list(socket.assigns.selected_branch_ids)

    if selected_branch_ids == [] do
      {:noreply, socket}
    else
      # feature-settings.CLEAR_REFS.6
      {:ok, _} = Specs.delete_feature_branch_refs_for_branches(selected_branch_ids, feature_name)

      # feature-settings.CLEAR_REFS.7
      # feature-settings.CLEAR_REFS.8
      send(self(), :feature_refs_changed)

      # Check if any local refs remain
      remaining_local =
        Specs.local_feature_branch_refs_exist?(
          socket.assigns.branch_ids,
          feature_name
        )

      {:noreply,
       socket
       |> assign(:show_clear_refs_modal, false)
       |> assign(:has_local_refs, remaining_local)
       |> assign(:selected_branch_ids, MapSet.new(socket.assigns.branch_ids))}
    end
  end

  # --- Delete Spec handlers ---

  # feature-settings.DELETE_SPEC.3
  def handle_event("show_delete_spec_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_spec_modal, true)}
  end

  def handle_event("cancel_delete_spec", _params, socket) do
    {:noreply, assign(socket, :show_delete_spec_modal, false)}
  end

  # feature-settings.DELETE_SPEC.5
  def handle_event("confirm_delete_spec", _params, socket) do
    spec = socket.assigns.spec

    case Specs.delete_spec(spec) do
      {:ok, _} ->
        # feature-settings.DELETE_SPEC.6_1
        # feature-settings.DELETE_SPEC.6_2
        # feature-settings.DELETE_SPEC.8
        send(self(), :feature_spec_deleted)

        {:noreply, assign(socket, :show_delete_spec_modal, false)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete spec")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "fixed inset-0 z-50 transition-opacity duration-300",
        @visible && "opacity-100 pointer-events-auto",
        !@visible && "opacity-0 pointer-events-none"
      ]}
      phx-window-keydown="close"
      phx-target={@myself}
      phx-key="Escape"
    >
      <%!-- feature-settings.DRAWER.3 --%>
      <div
        class="fixed inset-0 bg-black/50 transition-opacity"
        phx-click="close"
        phx-target={@myself}
        aria-hidden="true"
      />

      <%!-- feature-settings.DRAWER.2 --%>
      <div
        id={"#{@id}-panel"}
        class={[
          "fixed right-0 top-0 h-full w-full max-w-md bg-base-100 shadow-xl",
          "transform transition-transform duration-300 ease-in-out",
          "flex flex-col overflow-hidden",
          @visible && "translate-x-0",
          !@visible && "translate-x-full"
        ]}
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
      >
        <%!-- Drawer header --%>
        <div class="flex items-center justify-between p-4 border-b border-base-300 flex-shrink-0">
          <div class="flex items-center gap-3 shrink-0">
            <.icon name="hero-cube" class="size-6 text-primary" />
            <h2 id={"#{@id}-title"} class="text-lg font-semibold text-base-content">
              Feature Settings
            </h2>
          </div>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-square"
            phx-click="close"
            phx-target={@myself}
            aria-label="Close drawer"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <%!-- Drawer content --%>
        <div class="flex-1 overflow-y-auto p-4 space-y-6">
          <%!-- Info Card --%>
          <div class="p-4 border-1 border-base-300 rounded-lg space-y-3">
            <div class="space-y-1">
              <p class="text-xs text-base-content/70 uppercase tracking-wider">Product</p>
              <div class="flex items-center gap-2">
                <.icon name="custom-boxes" class="size-4 text-accent" />
                <span class="text-sm font-medium">{@product.name}</span>
              </div>
            </div>
            <div>
              <p class="text-xs text-base-content/70 uppercase tracking-wider">Implementation</p>
              <div class="flex items-center gap-2">
                <.icon name="hero-tag" class="size-4 text-secondary" />
                <span class="text-sm font-medium">{@implementation.name}</span>
              </div>
            </div>
            <div>
              <p class="text-xs text-base-content/70 uppercase tracking-wider">Feature</p>
              <div class="flex items-center gap-2">
                <.icon name="hero-cube" class="size-4 text-primary" />
                <span class="text-sm font-medium">{@feature_name}</span>
              </div>
            </div>
          </div>

          <div class="divider"></div>

          <%!-- Clear States Section --%>
          <.clear_states_section
            has_local_states={@has_local_states}
            states_inherited={@states_inherited}
            target={@myself}
          />

          <div class="divider"></div>

          <%!-- Clear Refs Section --%>
          <.clear_refs_section
            has_local_refs={@has_local_refs}
            refs_inherited={@refs_inherited}
            target={@myself}
          />

          <div class="divider"></div>

          <%!-- Delete Spec Section --%>
          <.delete_spec_section
            spec_inherited={@spec_inherited}
            target={@myself}
          />
        </div>
      </div>

      <%!-- Clear States Confirmation Modal --%>
      <%= if @show_clear_states_modal do %>
        <.clear_states_modal
          feature_name={@feature_name}
          target={@myself}
        />
      <% end %>

      <%!-- Clear Refs Confirmation Modal --%>
      <%= if @show_clear_refs_modal do %>
        <.clear_refs_modal
          feature_name={@feature_name}
          tracked_branches={@tracked_branches}
          selected_branch_ids={@selected_branch_ids}
          target={@myself}
        />
      <% end %>

      <%!-- Delete Spec Confirmation Modal --%>
      <%= if @show_delete_spec_modal do %>
        <.delete_spec_modal
          feature_name={@feature_name}
          spec_inherited={@spec_inherited}
          target={@myself}
        />
      <% end %>
    </div>
    """
  end

  # Clear States Section Component
  # feature-settings.CLEAR_STATES.1
  defp clear_states_section(assigns) do
    # feature-settings.CLEAR_STATES.2_1
    # feature-settings.CLEAR_STATES.2_2
    disabled = !assigns.has_local_states || assigns.states_inherited

    assigns = assign(assigns, :disabled, disabled)

    ~H"""
    <div class="space-y-3">
      <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider">
        Feature States
      </h3>

      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="text-sm text-base-content/80">
            Clear all states (status and comments) that have been applied to ACIDs in this feature.
          </p>
          <%= if @states_inherited do %>
            <p class="text-xs text-warning mt-1">
              States are inherited from a parent implementation.
            </p>
          <% end %>
        </div>

        <%!-- feature-settings.CLEAR_STATES.1 --%>
        <button
          type="button"
          class="btn btn-sm"
          phx-click={if !@disabled, do: "show_clear_states_modal", else: nil}
          phx-target={@target}
          disabled={@disabled}
          id="clear-states-btn"
        >
          <.icon name="hero-trash" class="size-4 mr-1" /> Clear States
        </button>
      </div>
    </div>
    """
  end

  # Clear States Modal Component
  defp clear_states_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-[60] bg-black/50 flex items-center justify-center"
      phx-click="cancel_clear_states"
      phx-target={@target}
    >
      <div
        class="relative z-[70] w-full max-w-md mx-4 bg-base-100 rounded-2xl shadow-xl p-6 space-y-5"
        phx-click-away="cancel_clear_states"
        phx-target={@target}
      >
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold">Clear All States?</h3>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-circle"
            phx-click="cancel_clear_states"
            phx-target={@target}
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <%!-- feature-settings.CLEAR_STATES.4_1 --%>
        <div class="alert text-sm">
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-alert" />
          <div>
            <p class="font-semibold">This will clear all requirement states for {@feature_name}.</p>
            <p class="mt-1 text-xs">
              Any inherited states from parent implementations will remain.
            </p>
          </div>
        </div>

        <%!-- feature-settings.CLEAR_STATES.4_2 --%>
        <div class="flex gap-3 justify-end">
          <.button
            type="button"
            class="btn btn-soft"
            phx-click="cancel_clear_states"
            phx-target={@target}
            id="cancel-clear-states-btn"
          >
            Cancel
          </.button>
          <.button
            type="button"
            class="btn btn-warning"
            phx-click="confirm_clear_states"
            phx-target={@target}
            id="confirm-clear-states-btn"
          >
            <.icon name="hero-trash" class="size-4 mr-1" /> Confirm Clear
          </.button>
        </div>
      </div>
    </div>
    """
  end

  # Clear Refs Section Component
  # feature-settings.CLEAR_REFS.1
  defp clear_refs_section(assigns) do
    # feature-settings.CLEAR_REFS.2_1
    # feature-settings.CLEAR_REFS.2_2
    disabled = !assigns.has_local_refs || assigns.refs_inherited

    assigns = assign(assigns, :disabled, disabled)

    ~H"""
    <div class="space-y-3">
      <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider">
        Code References
      </h3>

      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="text-sm text-base-content/80">
            Clear code references that have been pushed from tracked branches.
          </p>
          <%= if @refs_inherited do %>
            <p class="text-xs text-warning mt-1">
              References are inherited from a parent implementation.
            </p>
          <% end %>
        </div>

        <%!-- feature-settings.CLEAR_REFS.1 --%>
        <button
          type="button"
          class="btn btn-sm"
          phx-click={if !@disabled, do: "show_clear_refs_modal", else: nil}
          phx-target={@target}
          disabled={@disabled}
          id="clear-refs-btn"
        >
          <.icon name="hero-trash" class="size-4 mr-1" /> Clear Refs
        </button>
      </div>
    </div>
    """
  end

  # Clear Refs Modal Component
  defp clear_refs_modal(assigns) do
    # feature-settings.CLEAR_REFS.5_2
    clear_disabled = MapSet.size(assigns.selected_branch_ids) == 0

    assigns =
      assigns
      |> assign(:clear_disabled, clear_disabled)
      |> assign(:all_selected_count, length(assigns.tracked_branches))

    ~H"""
    <div
      class="fixed inset-0 z-[60] bg-black/50 flex items-center justify-center"
      phx-click="cancel_clear_refs"
      phx-target={@target}
    >
      <div
        class="relative z-[70] w-full max-w-md mx-4 bg-base-100 rounded-2xl shadow-xl p-6 space-y-5"
        phx-click-away="cancel_clear_refs"
        phx-target={@target}
      >
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold text-warning">Clear Code References?</h3>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-circle"
            phx-click="cancel_clear_refs"
            phx-target={@target}
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <p class="text-sm text-base-content/80">
          Select branches to clear references from:
        </p>

        <%!-- feature-settings.CLEAR_REFS.4 --%>
        <div class="space-y-2 max-h-48 overflow-y-auto">
          <div
            :for={tracked_branch <- @tracked_branches}
            class="flex items-center gap-3 p-2 rounded-lg hover:bg-base-200 cursor-pointer"
            phx-click="toggle_branch_selection"
            phx-value-branch_id={tracked_branch.branch_id}
            phx-target={@target}
          >
            <input
              type="checkbox"
              checked={MapSet.member?(@selected_branch_ids, tracked_branch.branch_id)}
              class="checkbox checkbox-sm"
              id={"clear-refs-branch-#{tracked_branch.branch_id}"}
            />
            <div class="flex-1 min-w-0">
              <%!-- feature-settings.CLEAR_REFS.4_1 --%>
              <p class="text-sm truncate">{tracked_branch.branch.repo_uri}</p>
              <p class="text-xs text-base-content/60 flex items-center gap-1">
                <.icon name="custom-git-branch" class="size-3" />
                {tracked_branch.branch.branch_name}
              </p>
            </div>
          </div>
        </div>

        <%!-- feature-settings.CLEAR_REFS.4_2 --%>
        <%= if MapSet.size(@selected_branch_ids) < @all_selected_count do %>
          <p class="text-xs text-base-content/50">
            {MapSet.size(@selected_branch_ids)} of {@all_selected_count} branches selected
          </p>
        <% end %>

        <%!-- feature-settings.CLEAR_REFS.5_1 --%>
        <div class="flex gap-3 justify-end">
          <.button
            type="button"
            class="btn btn-soft"
            phx-click="cancel_clear_refs"
            phx-target={@target}
            id="cancel-clear-refs-btn"
          >
            Cancel
          </.button>
          <.button
            type="button"
            class="btn btn-warning"
            phx-click="confirm_clear_refs"
            phx-target={@target}
            disabled={@clear_disabled}
            id="confirm-clear-refs-btn"
          >
            <.icon name="hero-trash" class="size-4 mr-1" /> Clear Selected
          </.button>
        </div>
      </div>
    </div>
    """
  end

  # Delete Spec Section Component
  # feature-settings.DELETE_SPEC.1
  defp delete_spec_section(assigns) do
    # feature-settings.DELETE_SPEC.2
    disabled = assigns.spec_inherited

    assigns = assign(assigns, :disabled, disabled)

    ~H"""
    <div class="space-y-3">
      <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider">
        Danger Zone
      </h3>

      <div class="p-4 border border-error/30 rounded-lg bg-error/5 space-y-4">
        <div class="w-full">
          <p class="font-semibold text-error">Delete Spec</p>
          <p class="text-sm text-base-content/60">
            Permanently delete the feature specification.
          </p>
          <%= if @spec_inherited do %>
            <p class="text-xs text-warning mt-1">
              Cannot delete an inherited spec.
            </p>
          <% end %>
        </div>

        <%!-- feature-settings.DELETE_SPEC.1 --%>
        <div class="flex justify-end">
          <button
            type="button"
            class="btn btn-error btn-sm"
            phx-click={if !@disabled, do: "show_delete_spec_modal", else: nil}
            phx-target={@target}
            disabled={@disabled}
            id="delete-spec-btn"
          >
            <.icon name="hero-trash" class="size-4 mr-1" /> Delete Spec
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Delete Spec Modal Component
  defp delete_spec_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-[60] bg-black/50 flex items-center justify-center"
      phx-click="cancel_delete_spec"
      phx-target={@target}
    >
      <div
        class="relative z-[70] w-full max-w-md mx-4 bg-base-100 rounded-2xl shadow-xl p-6 space-y-5"
        phx-click-away="cancel_delete_spec"
        phx-target={@target}
      >
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold text-error">Delete Spec?</h3>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-circle"
            phx-click="cancel_delete_spec"
            phx-target={@target}
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="space-y-1">
          <p class="text-sm text-base-content/80">
            <span class="font-medium">Feature:</span> {@feature_name}
          </p>
        </div>

        <%!-- feature-settings.DELETE_SPEC.4_1 --%>
        <%!-- feature-settings.DELETE_SPEC.4_2 --%>
        <div class="alert text-sm">
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-alert" />
          <div>
            <p class="font-semibold">This action is permanent and cannot be undone.</p>
            <p class="mt-1">
              The feature specification will be permanently deleted.
            </p>
            <%!-- feature-settings.DELETE_SPEC.4_2 --%>
            <p class="mt-2 text-xs">
              If a parent spec exists, its requirements will be used instead.
              If no parent spec exists, you will be redirected to the product page.
            </p>
          </div>
        </div>

        <%!-- feature-settings.DELETE_SPEC.4_3 --%>
        <div class="flex gap-3 justify-end">
          <.button
            type="button"
            class="btn btn-soft"
            phx-click="cancel_delete_spec"
            phx-target={@target}
            id="cancel-delete-spec-btn"
          >
            Cancel
          </.button>
          <.button
            type="button"
            class="btn btn-error"
            phx-click="confirm_delete_spec"
            phx-target={@target}
            id="confirm-delete-spec-btn"
          >
            <.icon name="hero-trash" class="size-4 mr-1" /> Delete Spec
          </.button>
        </div>
      </div>
    </div>
    """
  end
end
