defmodule AcaiWeb.Live.Components.RequirementDetailsLive do
  @moduledoc """
  Side drawer component that displays requirement details.

  requirement-details.DRAWER: A side drawer that opens when a requirement is selected,
  showing the requirement definition, status, and code references.

  ACIDs:
  - feature-impl-view.DRAWER.4: Lists all refs from feature_branch_refs for this ACID
  - feature-impl-view.DRAWER.4-note: Each ref is sourced from a specific branch
  """
  use AcaiWeb, :live_component

  import AcaiWeb.Helpers.RepoFormatter

  alias Acai.Specs

  @impl true
  def update(assigns, socket) do
    id = Map.get(assigns, :id) || Map.get(assigns, "id")
    acid = Map.get(assigns, :acid) || Map.get(assigns, "acid")
    spec = Map.get(assigns, :spec) || Map.get(assigns, "spec")
    implementation = Map.get(assigns, :implementation) || Map.get(assigns, "implementation")

    aggregated_refs =
      Map.get(assigns, :aggregated_refs) || Map.get(assigns, "aggregated_refs") || []

    if acid && spec && implementation do
      # data-model.SPECS.13: Get requirement data from JSONB
      requirements = spec.requirements || %{}

      # Handle both string and atom keys in the requirements map
      # JSONB data from database uses string keys
      requirement_data = Map.get(requirements, acid)

      # feature-impl-view.INHERITANCE.2: Get status with inheritance walking
      # feature-impl-view.DRAWER.3: Shows status and comment from inherited states
      {spec_impl_state, _state_source_impl_id} =
        Specs.get_feature_impl_state_with_inheritance(spec.feature_name, implementation.id)

      state_data = get_in(spec_impl_state && spec_impl_state.states, [acid])

      # feature-impl-view.DRAWER.4: Get refs for this ACID from aggregated branch refs
      # These are already aggregated across tracked branches
      refs_by_branch = get_refs_by_branch(aggregated_refs, acid)

      # Build requirement struct-like map from JSONB data
      requirement = build_requirement_from_jsonb(acid, requirement_data)

      # Build status struct-like map from JSONB data
      requirement_status = build_status_from_jsonb(state_data)

      socket =
        socket
        |> assign(:id, id)
        |> assign(:acid, acid)
        |> assign(:requirement, requirement)
        |> assign(:implementation, implementation)
        |> assign(:requirement_status, requirement_status)
        |> assign(:refs_by_branch, refs_by_branch)
        |> assign(:visible, Map.get(assigns, :visible, false))

      {:ok, socket}
    else
      # No requirement selected, just update visibility
      {:ok,
       socket
       |> assign(:id, id)
       |> assign(:acid, nil)
       |> assign(:requirement, nil)
       |> assign(:implementation, implementation)
       |> assign(:refs_by_branch, %{})
       |> assign(:visible, Map.get(assigns, :visible) || Map.get(assigns, "visible") || false)}
    end
  end

  # feature-impl-view.DRAWER.4: Get refs for a specific ACID from aggregated branch refs
  # Returns a map of branch => ref_list
  defp get_refs_by_branch(aggregated_refs, acid) when is_list(aggregated_refs) do
    aggregated_refs
    |> Enum.reduce(%{}, fn {branch, refs_map}, acc ->
      case Map.get(refs_map, acid) do
        nil -> acc
        ref_list when is_list(ref_list) -> Map.put(acc, branch, ref_list)
        _ -> acc
      end
    end)
  end

  defp get_refs_by_branch(_, _), do: %{}

  # Build requirement map from JSONB data
  defp build_requirement_from_jsonb(acid, nil) do
    %{
      acid: acid,
      definition: "Definition not available",
      note: nil,
      is_deprecated: false,
      replaced_by: []
    }
  end

  defp build_requirement_from_jsonb(acid, data) do
    %{
      acid: acid,
      definition: Map.get(data, "definition", "No definition"),
      note: Map.get(data, "note"),
      is_deprecated: Map.get(data, "is_deprecated", false),
      replaced_by: Map.get(data, "replaced_by", [])
    }
  end

  # Build status map from JSONB data
  defp build_status_from_jsonb(nil), do: nil

  defp build_status_from_jsonb(data) do
    %{
      status: data["status"],
      note: data["comment"],
      updated_at: data["updated_at"]
    }
  end

  @impl true
  def handle_event("close", _params, socket) do
    # requirement-details.DRAWER.6: Drawer can be dismissed
    # Send event to parent to reset selected_requirement_id
    send(self(), "drawer_closed")
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
          "fixed right-0 top-0 h-full w-full max-w-md lg:max-w-2xl bg-base-100 shadow-xl",
          "transform transition-transform duration-300 ease-in-out",
          "flex flex-col overflow-hidden",
          @visible && "translate-x-0",
          !@visible && "translate-x-full"
        ]}
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
      >
        <%= if @requirement do %>
          <%!-- Drawer header --%>
          <div class="flex items-center justify-between p-4 border-b border-base-300 flex-shrink-0">
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

          <%!-- Drawer content - use relative positioning to allow tooltips to escape --%>
          <div class="flex-1 relative">
            <%!-- Inner scroll container --%>
            <div class="absolute inset-0 overflow-y-auto p-4 space-y-6">
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
                <div class="flex flex-wrap items-center gap-2">
                  <%!-- requirement-details.DRAWER.4-1: If no status exists, renders a clear 'no status' indicator --%>
                  <%= if @requirement_status && @requirement_status.status do %>
                    <%!-- requirement-details.DRAWER.4: Show status value if exists --%>
                    <span class={[
                      "inline-flex items-center gap-1.5 px-2 py-1 rounded-md text-xs font-medium",
                      status_chip_color(@requirement_status.status)
                    ]}>
                      <.icon name="hero-check-circle" class="size-3.5" />
                      {@requirement_status.status}
                    </span>
                  <% else %>
                    <span class="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-base-200/70 text-xs text-base-content/50">
                      <.icon name="hero-minus-circle" class="size-3.5" /> No status
                    </span>
                  <% end %>

                  <%!-- requirement-details.DRAWER.4-2: Implementation context chip --%>
                  <div class="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-secondary/10 text-xs text-secondary font-medium">
                    <.icon name="hero-tag" class="size-3.5" />
                    <span>{@implementation.name}</span>
                  </div>
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
                  <%!-- feature-impl-view.DRAWER.4-note: Each ref is sourced from a specific branch --%>
                  <%!-- requirement-details.DRAWER.5-2: References are grouped by their tracked branch --%>
                  <div :for={{branch, refs} <- @refs_by_branch} class="space-y-2">
                    <%!-- Group header with icon chips for repo and branch --%>
                    <% repo_popover_id = "requirement-drawer-repo-popover-#{branch.id}" %>
                    <div class="flex flex-wrap items-center gap-2">
                      <%!-- feature-impl-view.DRAWER.4-1: References section reuses repo display rules --%>
                      <button
                        type="button"
                        class="badge badge-md badge-soft cursor-pointer transition-colors hover:bg-base-200"
                        popovertarget={repo_popover_id}
                        style={"anchor-name:--requirement-drawer-repo-anchor-#{branch.id}"}
                      >
                        <.icon name="hero-code-bracket-square" class="size-3.5" />
                        <span>{format_repo_name(branch.repo_uri)}</span>
                      </button>
                      <div
                        popover
                        id={repo_popover_id}
                        class="dropdown rounded-box bg-base-100 shadow-sm border border-base-300 p-3 w-80 space-y-2"
                        style={"position-anchor:--requirement-drawer-repo-anchor-#{branch.id}"}
                      >
                        <p class="text-xs uppercase tracking-wider text-base-content/50">
                          Repository URI
                        </p>
                        <a
                          href={repo_http_url(branch.repo_uri)}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="link link-primary text-sm break-all"
                        >
                          {branch.repo_uri}
                        </a>
                      </div>
                      <div class="badge">
                        <.icon name="custom-git-branch" class="size-3.5" />
                        <span>{branch.branch_name}</span>
                      </div>
                    </div>

                    <%!-- References list --%>
                    <ul class="space-y-1">
                      <li :for={ref <- refs} class="flex items-center gap-2">
                        <%!-- requirement-details.DRAWER.5-3: Each reference shows file path and line number --%>
                        <%!-- requirement-details.DRAWER.5-4: Clickable link format --%>
                        <.link
                          href={build_reference_url(branch, ref)}
                          target="_blank"
                          rel="noopener noreferrer"
                          class={[
                            "text-sm hover:underline break-all",
                            ref["is_test"] && "text-info",
                            !ref["is_test"] && "text-base-content/80 hover:text-primary"
                          ]}
                        >
                          {format_path(ref["path"])}
                        </.link>

                        <%!-- Test badge for test references --%>
                        <%= if ref["is_test"] do %>
                          <span class="badge badge-info badge-xs">Test</span>
                        <% end %>
                      </li>
                    </ul>
                  </div>
                <% end %>
              </div>
            </div>
            <%!-- Close relative wrapper and inner scroll container --%>
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

  # feature-impl-view.DRAWER.5: Build the clickable link to source file at specific line
  # Format: https://<repo_uri>/blob/<branch_name>/<path>#L<line>
  # Uses actual branch data from the database
  defp build_reference_url(branch, ref) do
    # feature-impl-view.DRAWER.5: Include line number when available
    {file_path, line} = parse_path_and_line(ref["path"])

    # Use the branch_name from the actual branch record
    base_url = "https://#{branch.repo_uri}/blob/#{branch.branch_name}/#{file_path}"

    # Append line number anchor if present
    if line do
      "#{base_url}#L#{line}"
    else
      base_url
    end
  end

  # Parse path like "lib/my_app/foo.ex:42" into {"lib/my_app/foo.ex", "42"}
  defp parse_path_and_line(path) when is_binary(path) do
    case String.split(path, ":", parts: 2) do
      [file_path, line] -> {file_path, line}
      [file_path] -> {file_path, nil}
    end
  end

  defp parse_path_and_line(_), do: {"", nil}

  # Format path for display (show file:line format)
  defp format_path(path) when is_binary(path), do: path
  defp format_path(_), do: ""

  # Chip background colors for status (used in icon chip badges)
  defp status_chip_color(status) do
    case status do
      "accepted" -> "bg-success/10 text-success"
      "completed" -> "bg-info/10 text-info"
      "assigned" -> "bg-warning/10 text-warning"
      "blocked" -> "bg-error/10 text-error"
      "rejected" -> "bg-error/10 text-error"
      _ -> "bg-base-200/70 text-base-content/70"
    end
  end
end
