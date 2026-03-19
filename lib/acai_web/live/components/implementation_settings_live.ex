defmodule AcaiWeb.Live.Components.ImplementationSettingsLive do
  @moduledoc """
  Side drawer component for implementation settings.

  impl-settings.DRAWER: A side drawer for managing implementation settings including
  rename, track/untrack branches, and delete workflows.
  """
  use AcaiWeb, :live_component

  alias Acai.Implementations

  @impl true
  def update(assigns, socket) do
    id = Map.get(assigns, :id) || Map.get(assigns, "id")
    implementation = Map.get(assigns, :implementation) || Map.get(assigns, "implementation")
    product = Map.get(assigns, :product) || Map.get(assigns, "product")
    team = Map.get(assigns, :team) || Map.get(assigns, "team")
    visible = Map.get(assigns, :visible, false)

    tracked_branches =
      Map.get(assigns, :tracked_branches) || Map.get(assigns, "tracked_branches", [])

    current_branch_id =
      Map.get(assigns, :current_branch_id) || Map.get(assigns, "current_branch_id")

    socket =
      socket
      |> assign(:id, id)
      |> assign(:implementation, implementation)
      |> assign(:product, product)
      |> assign(:team, team)
      |> assign(:visible, visible)
      |> assign(:tracked_branches, tracked_branches)
      |> assign(:current_branch_id, current_branch_id)
      |> init_rename_state(implementation)
      |> init_track_branch_state()
      |> init_untrack_state()
      |> init_delete_state()

    {:ok, socket}
  end

  # Initialize rename form state
  # impl-settings.RENAME.1: Renders a text input pre-populated with the current implementation name
  defp init_rename_state(socket, implementation) do
    changeset = Implementations.change_implementation(implementation)

    socket
    |> assign(:rename_form, to_form(changeset))
    |> assign(:rename_error, nil)
  end

  # Initialize track branch state
  # impl-settings.TRACK_BRANCH.1: Renders a dropdown or list of trackable branches
  defp init_track_branch_state(socket) do
    socket
    |> assign(:trackable_branches, [])
    |> assign(:selected_branch_id, nil)
    |> assign(:show_track_branch_ui, false)
  end

  # Initialize untrack state
  defp init_untrack_state(socket) do
    socket
    |> assign(:show_untrack_modal, false)
    |> assign(:branch_to_untrack, nil)
  end

  # Initialize delete state
  # impl-settings.DELETE.2: Button is visually distinct to indicate destructive action
  defp init_delete_state(socket) do
    socket
    |> assign(:show_delete_modal, false)
    |> assign(:delete_confirm_name, "")
  end

  @impl true
  def handle_event("close", _params, socket) do
    # impl-settings.DRAWER.3: Drawer closes when clicking the close button, clicking outside, or pressing Escape
    send(self(), "impl_settings_closed")
    {:noreply, assign(socket, :visible, false)}
  end

  # --- Rename handlers ---

  # impl-settings.RENAME.3: Input supports editing the implementation name
  def handle_event("rename_changed", %{"implementation" => params}, socket) do
    implementation = socket.assigns.implementation
    new_name = params["name"] || ""

    # impl-settings.RENAME.7_2: Error clears when user modifies the input
    changeset =
      implementation
      |> Implementations.change_implementation(%{name: new_name})
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, rename_form: to_form(changeset), rename_error: nil)}
  end

  # impl-settings.RENAME.6: On click, validates the new name is unique within the product
  def handle_event("save_rename", %{"implementation" => params}, socket) do
    implementation = socket.assigns.implementation
    new_name = String.trim(params["name"] || "")

    # impl-settings.RENAME.5: Save button is disabled when input is empty or whitespace-only
    if new_name == "" do
      {:noreply, assign(socket, rename_error: "Name cannot be empty")}
    else
      # Check uniqueness
      if Implementations.implementation_name_unique?(implementation, new_name) do
        case Implementations.update_implementation(implementation, %{name: new_name}) do
          {:ok, updated_implementation} ->
            # impl-settings.RENAME.8: On successful save, updates the implementation name and UI reflects change
            send(self(), {:implementation_renamed, updated_implementation})

            socket =
              socket
              |> assign(:implementation, updated_implementation)
              |> init_rename_state(updated_implementation)

            {:noreply, socket}

          {:error, _changeset} ->
            # impl-settings.RENAME.7_1: On validation failure, displays error message "Implementation name already exists"
            {:noreply, assign(socket, rename_error: "Implementation name already exists")}
        end
      else
        {:noreply, assign(socket, rename_error: "Implementation name already exists")}
      end
    end
  end

  # --- Track Branch handlers ---

  def handle_event("show_track_branch_ui", _params, socket) do
    implementation = socket.assigns.implementation

    # impl-settings.TRACK_BRANCH.1: Load trackable branches
    trackable_branches = Implementations.list_trackable_branches(implementation)

    {:noreply,
     socket
     |> assign(:trackable_branches, trackable_branches)
     |> assign(:show_track_branch_ui, true)}
  end

  def handle_event("cancel_track_branch", _params, socket) do
    # impl-settings.TRACK_BRANCH.7: Cancel button clears the current selection
    {:noreply,
     socket
     |> assign(:show_track_branch_ui, false)
     |> assign(:selected_branch_id, nil)}
  end

  def handle_event("select_branch_to_track", %{"branch_id" => branch_id}, socket) do
    {:noreply, assign(socket, :selected_branch_id, branch_id)}
  end

  # impl-settings.TRACK_BRANCH.8: On save, adds the selected branch to tracked branches
  def handle_event("save_track_branch", _params, socket) do
    implementation = socket.assigns.implementation
    branch_id = socket.assigns.selected_branch_id

    if branch_id do
      # Find the selected branch to get its repo_uri
      branch = Enum.find(socket.assigns.trackable_branches, fn b -> b.id == branch_id end)

      if branch do
        attrs = %{
          branch_id: branch_id,
          repo_uri: branch.repo_uri
        }

        case Implementations.create_tracked_branch(implementation, attrs) do
          {:ok, _tracked_branch} ->
            # impl-settings.TRACK_BRANCH.9: UI updates immediately to show the newly tracked branch
            # impl-settings.TRACK_BRANCH.10: List of trackable branches refreshes to exclude the newly tracked branch
            send(self(), :tracked_branches_changed)

            {:noreply,
             socket
             |> assign(:show_track_branch_ui, false)
             |> assign(:selected_branch_id, nil)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to track branch")}
        end
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # --- Untrack Branch handlers ---

  # impl-settings.UNTRACK_BRANCH.5: Clicking a delete button opens a confirmation modal
  def handle_event("confirm_untrack", %{"branch_id" => branch_id}, socket) do
    branch_to_untrack =
      Enum.find(socket.assigns.tracked_branches, fn tb -> tb.branch_id == branch_id end)

    if branch_to_untrack do
      {:noreply,
       socket
       |> assign(:branch_to_untrack, branch_to_untrack)
       |> assign(:show_untrack_modal, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_untrack", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_untrack_modal, false)
     |> assign(:branch_to_untrack, nil)}
  end

  # impl-settings.UNTRACK_BRANCH.7: On confirmation, removes the branch from tracked branches
  def handle_event("confirm_untrack_branch", _params, socket) do
    branch_to_untrack = socket.assigns.branch_to_untrack

    if branch_to_untrack do
      case Implementations.delete_tracked_branch(branch_to_untrack) do
        {:ok, _} ->
          # impl-settings.UNTRACK_BRANCH.8: UI updates immediately to reflect the removed branch and any affected refs
          send(self(), :tracked_branches_changed)

          {:noreply,
           socket
           |> assign(:show_untrack_modal, false)
           |> assign(:branch_to_untrack, nil)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to untrack branch")}
      end
    else
      {:noreply, socket}
    end
  end

  # --- Delete Implementation handlers ---

  # impl-settings.DELETE.3: Clicking the button opens a confirmation modal
  def handle_event("show_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, true)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_modal, false)
     |> assign(:delete_confirm_name, "")}
  end

  def handle_event("update_delete_confirm_name", %{"confirm_name" => name}, socket) do
    {:noreply, assign(socket, :delete_confirm_name, name)}
  end

  # impl-settings.DELETE.6: On confirmation, permanently deletes the implementation
  def handle_event("confirm_delete", _params, socket) do
    implementation = socket.assigns.implementation
    confirm_name = String.trim(socket.assigns.delete_confirm_name)

    # impl-settings.DELETE.5: Delete button in modal requires additional confirmation (e.g. type name)
    if confirm_name == implementation.name do
      case Implementations.delete_implementation(implementation) do
        {:ok, _} ->
          # impl-settings.DELETE.7: User is redirected to /p/:product_name
          send(self(), {:implementation_deleted, implementation})
          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to delete implementation")}
      end
    else
      {:noreply, socket}
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
      <%!-- impl-settings.DRAWER.3: Drawer closes when clicking outside --%>
      <div
        class="fixed inset-0 bg-black/50 transition-opacity"
        phx-click="close"
        phx-target={@myself}
        aria-hidden="true"
      />

      <%!-- impl-settings.DRAWER.2: Drawer opens from the right side of the viewport --%>
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
          <div class="flex items-center gap-3">
            <.icon name="hero-tag" class="size-6 text-secondary" />
            <h2 id={"#{@id}-title"} class="text-lg font-semibold text-base-content">
              Implementation Settings
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
        <div class="flex-1 overflow-y-auto p-4 space-y-8">
          <%!-- Info Card --%>
          <div class="p-4 bg-base-100 border-1 border-base-300 rounded-lg space-y-3">
            <div class="space-y-1">
              <p class="text-xs text-base-content/70 uppercase tracking-wider">Product</p>
              <div class="flex items-center gap-2">
                <.icon name="custom-boxes" class="size-4 text-accent" />
                <span class="text-sm font-medium">{@product.name}</span>
              </div>
            </div>
            <div class="space-y-1">
              <p class="text-xs text-base-content/70 uppercase tracking-wider">Implementation</p>
              <div class="flex items-center gap-2">
                <.icon name="hero-tag" class="size-4 text-secondary" />
                <span class="text-sm font-medium">{@implementation.name}</span>
              </div>
            </div>
          </div>

          <%!-- Rename Section --%>
          <.rename_section
            implementation={@implementation}
            rename_form={@rename_form}
            rename_error={@rename_error}
            target={@myself}
          />

          <%!-- Tracked Branches Section --%>
          <.tracked_branches_section
            tracked_branches={@tracked_branches}
            current_branch_id={@current_branch_id}
            show_track_branch_ui={@show_track_branch_ui}
            trackable_branches={@trackable_branches}
            selected_branch_id={@selected_branch_id}
            target={@myself}
          />

          <%!-- Delete Section --%>
          <.delete_section
            implementation={@implementation}
            product={@product}
            target={@myself}
          />
        </div>
      </div>

      <%!-- Untrack Branch Confirmation Modal --%>
      <%= if @show_untrack_modal && @branch_to_untrack do %>
        <.untrack_modal
          branch_to_untrack={@branch_to_untrack}
          target={@myself}
        />
      <% end %>

      <%!-- Delete Implementation Confirmation Modal --%>
      <%= if @show_delete_modal do %>
        <.delete_modal
          implementation={@implementation}
          product={@product}
          delete_confirm_name={@delete_confirm_name}
          target={@myself}
        />
      <% end %>
    </div>
    """
  end

  # Rename Section Component
  # impl-settings.RENAME: Component for renaming the implementation
  defp rename_section(assigns) do
    current_name = assigns.implementation.name
    new_name = assigns.rename_form[:name].value || ""
    trimmed_name = String.trim(new_name)

    # impl-settings.RENAME.4: Save button is disabled when input value matches current name
    # impl-settings.RENAME.5: Save button is disabled when input is empty or whitespace-only
    save_disabled =
      trimmed_name == "" || String.trim(current_name) == trimmed_name

    assigns =
      assigns
      |> assign(:save_disabled, save_disabled)
      |> assign(:trimmed_name, trimmed_name)

    ~H"""
    <div class="space-y-3">
      <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider">
        Implementation Name
      </h3>

      <.form
        for={@rename_form}
        id="rename-implementation-form"
        phx-change="rename_changed"
        phx-submit="save_rename"
        phx-target={@target}
        class="space-y-3"
      >
        <.input
          field={@rename_form[:name]}
          type="text"
          autocomplete="off"
        />

        <%!-- impl-settings.RENAME.7_1: On validation failure, displays error message --%>
        <%= if @rename_error do %>
          <p class="text-sm text-error">{@rename_error}</p>
        <% end %>

        <%!-- impl-settings.RENAME.2: Renders a Save button next to the input --%>
        <div class="flex justify-end">
          <.button
            type="submit"
            variant="primary"
            id="save-rename-btn"
            disabled={@save_disabled}
          >
            Save
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  # Tracked Branches Section Component
  # impl-settings.UNTRACK_BRANCH: Component for removing tracked branches
  # impl-settings.TRACK_BRANCH: Component for adding new tracked branches
  defp tracked_branches_section(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider">
          Tracked Branches
        </h3>
        <%!-- Show Add button when not in track UI mode --%>
        <%= if !@show_track_branch_ui do %>
          <button
            type="button"
            class="btn btn-sm btn-ghost"
            phx-click="show_track_branch_ui"
            phx-target={@target}
            id="show-track-branch-btn"
          >
            <.icon name="hero-plus" class="size-4 mr-1" /> Add
          </button>
        <% end %>
      </div>

      <%= if @show_track_branch_ui do %>
        <%!-- Track Branch UI --%>
        <.track_branch_ui
          trackable_branches={@trackable_branches}
          selected_branch_id={@selected_branch_id}
          target={@target}
        />
      <% else %>
        <%!-- Tracked Branches List --%>
        <%= if @tracked_branches == [] do %>
          <p class="text-sm text-base-content/50">No tracked branches</p>
        <% else %>
          <div class="space-y-2">
            <%!-- impl-settings.UNTRACK_BRANCH.1: Renders a list of all currently tracked branches --%>
            <div
              :for={tracked_branch <- @tracked_branches}
              class="flex items-center justify-between gap-2 p-2 bg-base-200 rounded-lg"
            >
              <div class="min-w-0 flex-1">
                <%!-- impl-settings.UNTRACK_BRANCH.2: Each branch entry displays the full repo_uri and branch name --%>
                <p class="text-sm font-medium truncate">{tracked_branch.branch.repo_uri}</p>
                <p class="text-xs text-base-content/60 flex items-center gap-1">
                  <.icon name="custom-git-branch" class="size-3" />
                  {tracked_branch.branch.branch_name}
                </p>
              </div>

              <%!-- impl-settings.UNTRACK_BRANCH.4_1: Delete button is disabled for the branch containing the target spec --%>
              <% is_current_spec_branch = tracked_branch.branch_id == @current_branch_id %>
              <button
                type="button"
                class="btn btn-ghost btn-sm btn-square"
                phx-click={if !is_current_spec_branch, do: "confirm_untrack", else: nil}
                phx-value-branch_id={tracked_branch.branch_id}
                phx-target={@target}
                disabled={is_current_spec_branch}
                title={
                  if is_current_spec_branch,
                    do: "This is the current feature's branch and cannot be untracked",
                    else: "Untrack branch"
                }
                id={"untrack-branch-btn-#{tracked_branch.branch_id}"}
              >
                <.icon name="hero-trash" class={["size-4", is_current_spec_branch && "opacity-30"]} />
              </button>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Track Branch UI Component
  defp track_branch_ui(assigns) do
    # impl-settings.TRACK_BRANCH.6: Save button is disabled when no branch is selected
    save_disabled = is_nil(assigns.selected_branch_id)

    assigns = assign(assigns, :save_disabled, save_disabled)

    ~H"""
    <div class="space-y-3 p-3 bg-base-200 rounded-lg">
      <%= if @trackable_branches == [] do %>
        <p class="text-sm text-base-content/60">No trackable branches available.</p>
      <% else %>
        <p class="text-sm text-base-content/70">Select a branch to track:</p>

        <%!-- impl-settings.TRACK_BRANCH.1: Renders a dropdown or list of trackable branches --%>
        <div class="space-y-1 max-h-48 overflow-y-auto">
          <div
            :for={branch <- @trackable_branches}
            class={[
              "flex items-center justify-between p-2 rounded cursor-pointer transition-colors",
              @selected_branch_id == branch.id && "bg-primary/10",
              @selected_branch_id != branch.id && "hover:bg-base-300"
            ]}
            phx-click="select_branch_to_track"
            phx-value-branch_id={branch.id}
            phx-target={@target}
            id={"trackable-branch-#{branch.id}"}
          >
            <div class="min-w-0 flex-1">
              <%!-- impl-settings.TRACK_BRANCH.4: Each option displays full repo_uri plus branch name --%>
              <p class="text-sm truncate">{branch.repo_uri}</p>
              <p class="text-xs text-base-content/60 flex items-center gap-1">
                <.icon name="custom-git-branch" class="size-3" />
                {branch.branch_name}
              </p>
            </div>
            <%= if @selected_branch_id == branch.id do %>
              <.icon name="hero-check" class="size-4 text-primary" />
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- impl-settings.TRACK_BRANCH.5: Renders Save and Cancel buttons --%>
      <%!-- impl-settings.TRACK_BRANCH.5: Renders Save and Cancel buttons --%>
      <div class="flex gap-2 justify-end pt-2">
        <.button
          type="button"
          phx-click="cancel_track_branch"
          phx-target={@target}
          id="cancel-track-branch-btn"
        >
          Cancel
        </.button>
        <.button
          type="button"
          variant="primary"
          phx-click="save_track_branch"
          phx-target={@target}
          disabled={@save_disabled}
          id="save-track-branch-btn"
        >
          Save
        </.button>
      </div>
    </div>
    """
  end

  # Untrack Modal Component
  defp untrack_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-[60] bg-black/50 flex items-center justify-center"
      phx-click="cancel_untrack"
      phx-target={@target}
    >
      <div
        class="relative z-[70] w-full max-w-md mx-4 bg-base-100 rounded-2xl shadow-xl p-6 space-y-5"
        phx-click-away="cancel_untrack"
        phx-target={@target}
      >
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold">Untrack Branch?</h3>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-circle"
            phx-click="cancel_untrack"
            phx-target={@target}
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <%!-- impl-settings.UNTRACK_BRANCH.6_1: Confirmation modal displays the branch name and repo_uri --%>
        <div class="space-y-2">
          <p class="text-sm text-base-content/80">
            <span class="font-medium">Repository:</span> {@branch_to_untrack.branch.repo_uri}
          </p>
          <p class="text-sm text-base-content/80">
            <span class="font-medium">Branch:</span> {@branch_to_untrack.branch.branch_name}
          </p>
        </div>

        <%!-- impl-settings.UNTRACK_BRANCH.6_2: Confirmation modal explains that refs may disappear from the feature view --%>
        <div class="alert alert-warning text-sm">
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
          <div>
            <p>Code references from this branch will no longer appear in the feature view.</p>
            <%!-- impl-settings.UNTRACK_BRANCH.9: User can re-track the branch later without data loss --%>
            <p class="mt-1 text-xs">
              You can re-track this branch later without losing any data.
            </p>
          </div>
        </div>

        <%!-- impl-settings.UNTRACK_BRANCH.6_3: Confirmation modal renders Cancel and Untrack buttons --%>
        <div class="flex gap-3 justify-end">
          <.button
            type="button"
            phx-click="cancel_untrack"
            phx-target={@target}
            id="cancel-untrack-btn"
            class="btn btn-soft"
          >
            Cancel
          </.button>
          <.button
            type="button"
            class="btn btn-warning"
            phx-click="confirm_untrack_branch"
            phx-target={@target}
            id="confirm-untrack-btn"
          >
            Untrack
          </.button>
        </div>
      </div>
    </div>
    """
  end

  # Delete Section Component
  defp delete_section(assigns) do
    ~H"""
    <div class="space-y-3">
      <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider">
        Danger Zone
      </h3>

      <div class="p-4 border border-error/30 rounded-lg bg-error/5 space-y-4">
        <div class="w-full">
          <p class="font-semibold text-error">Delete Implementation</p>
          <p class="text-sm text-base-content/60">
            Permanently delete this implementation and all associated data.
          </p>
        </div>
        <%!-- impl-settings.DELETE.1: Renders a Delete Implementation button with warning styling --%>
        <%!-- impl-settings.DELETE.2: Button is visually distinct to indicate destructive action --%>
        <div class="flex justify-end">
          <.button
            type="button"
            class="btn btn-error btn-sm"
            phx-click="show_delete_modal"
            phx-target={@target}
            id="delete-implementation-btn"
          >
            <.icon name="hero-trash" class="size-4 mr-1" /> Delete Implementation
          </.button>
        </div>
      </div>
    </div>
    """
  end

  # Delete Modal Component
  defp delete_modal(assigns) do
    # impl-settings.DELETE.5: Delete button in modal requires additional confirmation (e.g. type name)
    confirm_match = String.trim(assigns.delete_confirm_name) == assigns.implementation.name

    assigns = assign(assigns, :confirm_match, confirm_match)

    ~H"""
    <div
      class="fixed inset-0 z-[60] bg-black/50 flex items-center justify-center"
      phx-click-away="cancel_delete"
      phx-target={@target}
    >
      <div class="relative z-[70] w-full max-w-md mx-4 bg-base-100 rounded-2xl shadow-xl p-6 space-y-5">
        <div class="flex items-center justify-between">
          <%!-- impl-settings.DELETE.4_2: Modal displays warning text that deletion is irreversible --%>
          <h3 class="text-lg font-semibold text-error">Delete Implementation?</h3>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-circle"
            phx-click="cancel_delete"
            phx-target={@target}
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <%!-- impl-settings.DELETE.4_1: Modal displays the implementation name and product name --%>
        <div class="space-y-1">
          <p class="text-sm text-base-content/80">
            <span class="font-medium">Implementation:</span> {@implementation.name}
          </p>
          <p class="text-sm text-base-content/80">
            <span class="font-medium">Product:</span> {@product.name}
          </p>
        </div>

        <%!-- impl-settings.DELETE.4_3: Modal explains that all associated feature states and refs will be cleared --%>
        <%!-- impl-settings.DELETE.4_4: Modal explains that child implementations will lose inherited states and refs --%>
        <div class="alert alert-soft text-sm">
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-alert" />
          <div>
            <p class="font-semibold">This action is permanent and cannot be undone.</p>
            <p class="mt-1">
              This will permanently delete all feature states (status & comments) applied to it, and they can't be recovered.
            </p>
            <p class="mt-2">
              Child implementations will be preserved, but lose any inherited states and references.
            </p>
          </div>
        </div>

        <%!-- impl-settings.DELETE.5: Delete button in modal requires additional confirmation (e.g. type name) --%>
        <div class="space-y-2">
          <p class="text-sm">
            To confirm, type <span class="font-mono font-semibold">{@implementation.name}</span>
            below:
          </p>
          <form id="delete-confirm-form" phx-change="update_delete_confirm_name" phx-target={@target}>
            <input
              id="confirm-delete-name-input"
              type="text"
              name="confirm_name"
              value={@delete_confirm_name}
              placeholder={@implementation.name}
              autocomplete="off"
              class="input input-bordered w-full"
            />
          </form>
        </div>

        <%!-- impl-settings.DELETE.4_5: Modal renders Cancel and Delete buttons --%>
        <div class="flex gap-3 justify-end">
          <.button
            type="button"
            class="btn btn-soft"
            phx-click="cancel_delete"
            phx-target={@target}
            id="cancel-delete-btn"
          >
            Cancel
          </.button>
          <.button
            type="button"
            class="btn btn-error"
            phx-click="confirm_delete"
            phx-target={@target}
            disabled={!@confirm_match}
            id="confirm-delete-btn"
          >
            <.icon name="hero-trash" class="size-4 mr-1" /> Delete Implementation
          </.button>
        </div>
      </div>
    </div>
    """
  end
end
