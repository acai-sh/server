defmodule AcaiWeb.Live.Components.RequirementDetailsLive do
  @moduledoc """
  Side drawer component that displays requirement details.

  requirement-details.DRAWER: A side drawer that opens when a requirement is selected,
  showing the requirement definition, status, and code references.
  """
  use AcaiWeb, :live_component

  alias Acai.Specs
  alias Acai.Implementations

  @impl true
  def update(
        %{id: id, requirement: requirement, implementation: implementation} = assigns,
        socket
      ) do
    # requirement-details.DRAWER.4: Get the requirement status for this implementation
    requirement_status = Implementations.get_requirement_status(requirement, implementation)

    # requirement-details.DRAWER.5-1: Get code references filtered by implementation's tracked branches
    # requirement-details.DRAWER.5-2: Group by tracked branch
    refs_by_branch =
      Specs.list_code_references_for_requirement_and_implementation(requirement, implementation)

    socket =
      socket
      |> assign(:id, id)
      |> assign(:requirement, requirement)
      |> assign(:implementation, implementation)
      |> assign(:requirement_status, requirement_status)
      |> assign(:refs_by_branch, refs_by_branch)
      |> assign(:visible, Map.get(assigns, :visible, false))

    {:ok, socket}
  end

  def update(
        %{id: id, requirement_id: requirement_id, implementation: implementation} = assigns,
        socket
      ) do
    if requirement_id do
      requirement = Specs.get_requirement_with_refs!(requirement_id)
      update(Map.merge(assigns, %{requirement: requirement}), socket)
    else
      # No requirement selected, just update visibility and set requirement to nil
      socket =
        socket
        |> assign(:id, id)
        |> assign(:implementation, implementation)
        |> assign(:visible, Map.get(assigns, :visible, false))
        |> assign(:requirement, nil)

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    # requirement-details.DRAWER.6: Drawer can be dismissed
    {:noreply, assign(socket, :visible, false)}
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
      <%!-- requirement-details.DRAWER.6: Backdrop click dismisses drawer --%>
      <div
        class="fixed inset-0 bg-black/50 transition-opacity"
        phx-click="close"
        phx-target={@myself}
        aria-hidden="true"
      />

      <%!-- Side drawer panel --%>
      <div
        id={"#{@id}-panel"}
        class={[
          "fixed right-0 top-0 h-full w-full max-w-md bg-base-100 shadow-xl",
          "transform transition-transform duration-300 ease-in-out",
          "flex flex-col",
          @visible && "translate-x-0",
          !@visible && "translate-x-full"
        ]}
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
      >
        <%= if @requirement do %>
          <%!-- Drawer header --%>
          <div class="flex items-center justify-between p-4 border-b border-base-300">
            <%!-- requirement-details.DRAWER.1: Renders the requirement ACID as the drawer title --%>
            <h2 id={"#{@id}-title"} class="text-lg font-semibold text-base-content">
              {@requirement.acid}
            </h2>
            <%!-- requirement-details.DRAWER.6: Close button --%>
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
            <%!-- requirement-details.DRAWER.2: Renders the full requirement definition text --%>
            <div class="space-y-2">
              <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider text-xs">
                Definition
              </h3>
              <p class="text-base-content leading-relaxed">
                {@requirement.definition}
              </p>
            </div>

            <%!-- requirement-details.DRAWER.3: Renders the requirement note if one exists --%>
            <div :if={@requirement.note} class="space-y-2">
              <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider text-xs">
                Note
              </h3>
              <p class="text-base-content/80 text-sm">
                {@requirement.note}
              </p>
            </div>

            <%!-- requirement-details.DRAWER.4: Status section --%>
            <div class="space-y-2">
              <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider text-xs">
                Status
              </h3>
              <div class="flex items-center gap-3">
                <%!-- requirement-details.DRAWER.4-1: If no status exists, renders a clear 'no status' indicator --%>
                <%= if @requirement_status && @requirement_status.status do %>
                  <%!-- requirement-details.DRAWER.4: Show status value if exists --%>
                  <span class={[
                    "badge",
                    status_badge_color(@requirement_status.status)
                  ]}>
                    {@requirement_status.status}
                  </span>
                <% else %>
                  <span class="badge badge-ghost text-base-content/50">
                    No status
                  </span>
                <% end %>

                <%!-- requirement-details.DRAWER.4-2: Renders the implementation name as context label --%>
                <span class="text-sm text-base-content/50 truncate">
                  in {@implementation.name}
                </span>
              </div>
            </div>

            <%!-- requirement-details.DRAWER.7: Comment section from status note --%>
            <div
              :if={@requirement_status && @requirement_status.note}
              class="space-y-2 bg-base-200/50 p-4 rounded-lg border border-base-300"
            >
              <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider text-xs">
                Status Comment
              </h3>
              <p class="text-sm text-base-content/80 italic leading-relaxed">
                "{@requirement_status.note}"
              </p>
            </div>

            <%!-- requirement-details.DRAWER.5: References section --%>
            <div class="space-y-3">
              <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider">
                References
              </h3>

              <%= if map_size(@refs_by_branch) == 0 do %>
                <p class="text-sm text-base-content/50">
                  No code references found for this requirement in the tracked branches.
                </p>
              <% else %>
                <%!-- requirement-details.DRAWER.5-2: References are grouped by their tracked branch --%>
                <div :for={{branch, refs} <- @refs_by_branch} class="space-y-2">
                  <%!-- Group header shows repo_uri and branch_name --%>
                  <div class="flex items-center gap-2 text-sm font-medium text-base-content/80">
                    <.icon name="hero-git-branch" class="size-4" />
                    <span>{branch.repo_uri}</span>
                    <span class="text-base-content/40">/</span>
                    <span class="text-primary">{branch.branch_name}</span>
                  </div>

                  <%!-- References list --%>
                  <ul class="ml-6 space-y-1">
                    <li :for={ref <- refs} class="flex items-center gap-2">
                      <%!-- requirement-details.DRAWER.5-5: Test references visually distinguished --%>
                      <%= if ref.is_test do %>
                        <.icon name="hero-beaker" class="size-4 text-info flex-shrink-0" />
                      <% else %>
                        <.icon
                          name="hero-code-bracket"
                          class="size-4 text-base-content/50 flex-shrink-0"
                        />
                      <% end %>

                      <%!-- requirement-details.DRAWER.5-3: Each reference shows file path and line number --%>
                      <%!-- requirement-details.DRAWER.5-4: Clickable link format --%>
                      <.link
                        href={build_reference_url(ref)}
                        target="_blank"
                        rel="noopener noreferrer"
                        class={[
                          "text-sm hover:underline",
                          ref.is_test && "text-info",
                          !ref.is_test && "text-base-content/80 hover:text-primary"
                        ]}
                      >
                        {format_path(ref.path)}
                      </.link>

                      <%!-- Test badge for test references --%>
                      <%= if ref.is_test do %>
                        <span class="badge badge-info badge-xs">Test</span>
                      <% end %>
                    </li>
                  </ul>
                </div>
              <% end %>
            </div>
          </div>
        <% else %>
          <%!-- Empty drawer when no requirement selected --%>
          <div class="flex items-center justify-between p-4 border-b border-base-300">
            <h2 id={"#{@id}-title"} class="text-lg font-semibold text-base-content">
              Requirement Details
            </h2>
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
          <div class="flex-1 flex items-center justify-center p-4">
            <p class="text-base-content/50">No requirement selected</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # requirement-details.DRAWER.5-4: Build the clickable link
  # Format: https://<repo_uri>/blob/<branch_name>/<path>
  defp build_reference_url(ref) do
    # Extract just the file path (without line number) for the URL
    {file_path, _line} = parse_path_and_line(ref.path)

    "https://#{ref.branch.repo_uri}/blob/#{ref.branch.branch_name}/#{file_path}"
  end

  # Parse path like "lib/my_app/foo.ex:42" into {"lib/my_app/foo.ex", "42"}
  defp parse_path_and_line(path) do
    case String.split(path, ":", parts: 2) do
      [file_path, line] -> {file_path, line}
      [file_path] -> {file_path, nil}
    end
  end

  # Format path for display (show file:line format)
  defp format_path(path) do
    path
  end

  # Badge colors for different statuses
  defp status_badge_color(status) do
    case status do
      "accepted" -> "badge-success"
      "completed" -> "badge-info"
      "pending" -> "badge-warning"
      "blocked" -> "badge-error"
      _ -> "badge-ghost"
    end
  end
end
