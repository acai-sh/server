defmodule AcaiWeb.ImplementationLive do
  use AcaiWeb, :live_view

  import AcaiWeb.Helpers.RepoFormatter

  alias Acai.Teams
  alias Acai.Specs
  alias Acai.Implementations

  # feature-impl-view.ROUTING.1
  @impl true
  def mount(
        %{"team_name" => team_name, "feature_name" => feature_name, "impl_slug" => impl_slug},
        _session,
        socket
      ) do
    team = Teams.get_team_by_name!(team_name)

    # feature-impl-view.ROUTING.3: impl_id is the UUID used for lookup
    # Parse the slug to get the implementation by UUID
    case Implementations.get_implementation_by_slug(impl_slug) do
      nil ->
        # feature-impl-view.ROUTING.3: Redirect if implementation not found
        socket =
          socket
          |> put_flash(:error, "Implementation not found")
          |> push_navigate(to: ~p"/t/#{team.name}/f/#{feature_name}")

        {:ok, socket}

      implementation ->
        # Verify the implementation belongs to this team
        if implementation.team_id == team.id do
          mount_implementation_view(socket, team, implementation, feature_name)
        else
          # Team mismatch - redirect
          socket =
            socket
            |> put_flash(:error, "Implementation not found")
            |> push_navigate(to: ~p"/t/#{team.name}/f/#{feature_name}")

          {:ok, socket}
        end
    end
  end

  # Mount implementation view with data loading
  defp mount_implementation_view(socket, team, implementation, feature_name) do
    # data-model.IMPLS: Implementation belongs to product
    # Preload product for context
    implementation = Acai.Repo.preload(implementation, :product)
    product = implementation.product

    # feature-impl-view.INHERITANCE.1: Find canonical spec using tracked branches + inheritance
    case Specs.resolve_canonical_spec(feature_name, implementation.id) do
      {nil, nil} ->
        # No spec found for this feature anywhere in the ancestry
        socket =
          socket
          |> put_flash(:error, "Feature not found for this implementation")
          |> push_navigate(to: ~p"/t/#{team.name}/f/#{feature_name}")

        {:ok, socket}

      {spec, spec_source} ->
        load_implementation_data(
          socket,
          team,
          product,
          spec,
          implementation,
          feature_name,
          spec_source
        )
    end
  end

  # Load all data for the implementation view
  defp load_implementation_data(
         socket,
         team,
         product,
         spec,
         implementation,
         feature_name,
         spec_source
       ) do
    sort_field = socket.assigns[:sort_field] || :acid
    sort_dir = socket.assigns[:sort_dir] || :asc

    # data-model.SPECS.11: Requirements are JSONB on the spec
    # data-model.SPECS.12: Preload product association for breadcrumb
    # data-model.SPECS.3: Preload branch association for repo info
    spec = Acai.Repo.preload(spec, [:product, :branch])

    # Build requirement rows from the JSONB requirements map
    requirements = build_requirement_rows_from_spec(spec)

    # feature-impl-view.INHERITANCE.2: Load states with inheritance walking
    {spec_impl_state, state_source_impl_id} =
      Specs.get_feature_impl_state_with_inheritance(feature_name, implementation.id)

    states = if spec_impl_state, do: spec_impl_state.states, else: %{}
    states_inherited = state_source_impl_id != nil

    # feature-impl-view.INHERITANCE.3: Aggregate refs with inheritance
    {aggregated_refs, refs_source_impl_id} =
      Implementations.get_aggregated_refs_with_inheritance(feature_name, implementation.id)

    refs_inherited = refs_source_impl_id != nil

    # Load tracked branches with preloaded branch association
    tracked_branches = Implementations.list_tracked_branches(implementation)

    # feature-impl-view.ROUTING.4: Load implementations that can resolve this feature
    # feature-impl-view.INHERITANCE.1: Includes implementations that inherit the feature from parents
    # feature-impl-view.CARDS.1-4
    # Using batched version to avoid N+1 queries
    available_implementations =
      Specs.list_implementations_for_feature_batched(feature_name, product)

    # feature-impl-view.ROUTING.4: Load features scoped to this implementation's tracked branches
    # feature-impl-view.INHERITANCE.1: Includes features inherited from parent implementations
    # feature-impl-view.CARDS.1-3
    available_features = Specs.list_features_for_implementation(implementation, product)

    # Build requirement rows with status and counts
    # feature-impl-view.LIST.2: Table columns are ACID, Status, Definition, Refs count
    # feature-impl-view.LIST.4: Refs column shows total number of code references across all tracked branches
    requirement_rows =
      requirements
      |> Enum.map(fn req ->
        acid = req.acid
        state_data = Map.get(states, acid, %{"status" => nil})

        # feature-impl-view.DRAWER.4: Get refs for this ACID from aggregated branch refs
        acid_refs = Implementations.get_refs_for_acid(aggregated_refs, acid)

        # feature-impl-view.LIST.4: Count ALL refs (test + non-test) across all branches
        refs_count =
          Enum.reduce(acid_refs, 0, fn {_branch, ref_list}, acc ->
            acc + length(ref_list)
          end)

        # Keep tests_count for coverage grids
        tests_count =
          Enum.reduce(acid_refs, 0, fn {_branch, ref_list}, acc ->
            acc + Enum.count(ref_list, fn ref -> Map.get(ref, "is_test", false) end)
          end)

        %{
          id: acid,
          acid: acid,
          definition: req.definition,
          # feature-impl-view.LIST.3: Status column shows state of this implementation, or inherited
          status: state_data["status"],
          refs_count: refs_count,
          tests_count: tests_count,
          note: req.note,
          is_deprecated: req.is_deprecated,
          replaced_by: req.replaced_by
        }
      end)
      # feature-impl-view.LIST.2-2
      # feature-impl-view.LIST.2-3
      |> sort_requirements(sort_field, sort_dir)

    # Load source implementations for inherited items (for popper links)
    states_source_impl =
      if state_source_impl_id do
        Implementations.get_implementation(state_source_impl_id)
        |> Acai.Repo.preload(:team)
      else
        nil
      end

    refs_source_impl =
      if refs_source_impl_id do
        Implementations.get_implementation(refs_source_impl_id)
        |> Acai.Repo.preload(:team)
      else
        nil
      end

    # Preload spec source implementation to avoid render-time query
    spec_source_impl =
      if spec_source.is_inherited && spec_source.source_implementation_id do
        Implementations.get_implementation(spec_source.source_implementation_id)
      else
        nil
      end

    socket =
      socket
      |> assign(:team, team)
      |> assign(:product, product)
      |> assign(:spec, spec)
      |> assign(:implementation, implementation)
      |> assign(:feature_name, feature_name)
      |> assign(:requirements, requirement_rows)
      |> assign(:sort_field, sort_field)
      |> assign(:sort_dir, sort_dir)
      |> assign(:tracked_branches, tracked_branches)
      |> assign(:available_implementations, available_implementations)
      |> assign(:available_features, available_features)
      |> assign(:selected_acid, nil)
      |> assign(:drawer_visible, false)
      |> assign(:spec_source, spec_source)
      |> assign(:spec_inherited, spec_source.is_inherited)
      |> assign(:spec_source_impl, spec_source_impl)
      |> assign(:states, states)
      |> assign(:states_inherited, states_inherited)
      |> assign(:states_source_impl, states_source_impl)
      |> assign(:refs_inherited, refs_inherited)
      |> assign(:refs_source_impl, refs_source_impl)
      |> assign(:drawer_refs_by_branch, %{})
      # impl-settings.DRAWER: Settings drawer state
      |> assign(:impl_settings_visible, false)
      # feature-settings.DRAWER.1: Renders a settings icon button that opens the drawer
      # feature-settings.DRAWER.2: Drawer opens from the right side of the viewport
      # feature-settings.DRAWER.3: Drawer closes when clicking the close button, clicking outside, or pressing Escape
      # feature-settings.DRAWER.4: Drawer displays the feature name and implementation context in its header
      |> assign(:feature_settings_visible, false)
      |> assign(
        :current_path,
        "/t/#{team.name}/i/#{Implementations.implementation_slug(implementation)}/f/#{feature_name}"
      )

    {:ok, socket}
  end

  # Reload implementation data for refresh after track/untrack operations.
  # Similar to load_implementation_data but preserves drawer and other UI state.
  # impl-settings.UNTRACK_BRANCH.8: Preserves drawer visibility during refresh
  # impl-settings.TRACK_BRANCH.9: Preserves drawer visibility during refresh
  defp reload_implementation_data(
         socket,
         team,
         product,
         implementation,
         feature_name
       ) do
    # Resolve the canonical spec (may change if tracked branches changed)
    case Specs.resolve_canonical_spec(feature_name, implementation.id) do
      {nil, nil} ->
        # No spec found - redirect
        socket =
          socket
          |> put_flash(:error, "Feature not found for this implementation")
          |> push_navigate(to: ~p"/t/#{team.name}/f/#{feature_name}")

        {:ok, socket}

      {spec, spec_source} ->
        do_reload_implementation_data(
          socket,
          team,
          product,
          spec,
          implementation,
          feature_name,
          spec_source
        )
    end
  end

  # Internal function that actually reloads the data
  defp do_reload_implementation_data(
         socket,
         team,
         product,
         spec,
         implementation,
         feature_name,
         spec_source
       ) do
    sort_field = socket.assigns[:sort_field] || :acid
    sort_dir = socket.assigns[:sort_dir] || :asc

    # Preload associations
    spec = Acai.Repo.preload(spec, [:product, :branch])

    # Build requirement rows
    requirements = build_requirement_rows_from_spec(spec)

    # Load states with inheritance
    {spec_impl_state, state_source_impl_id} =
      Specs.get_feature_impl_state_with_inheritance(feature_name, implementation.id)

    states = if spec_impl_state, do: spec_impl_state.states, else: %{}
    states_inherited = state_source_impl_id != nil

    # Aggregate refs with inheritance
    {aggregated_refs, refs_source_impl_id} =
      Implementations.get_aggregated_refs_with_inheritance(feature_name, implementation.id)

    refs_inherited = refs_source_impl_id != nil

    # Reload tracked branches (this is what changed!)
    tracked_branches = Implementations.list_tracked_branches(implementation)

    # Reload available implementations and features
    available_implementations =
      Specs.list_implementations_for_feature_batched(feature_name, product)

    available_features = Specs.list_features_for_implementation(implementation, product)

    # Build requirement rows with updated data
    requirement_rows =
      requirements
      |> Enum.map(fn req ->
        acid = req.acid
        state_data = Map.get(states, acid, %{"status" => nil})
        acid_refs = Implementations.get_refs_for_acid(aggregated_refs, acid)

        refs_count =
          Enum.reduce(acid_refs, 0, fn {_branch, ref_list}, acc ->
            acc + length(ref_list)
          end)

        tests_count =
          Enum.reduce(acid_refs, 0, fn {_branch, ref_list}, acc ->
            acc + Enum.count(ref_list, fn ref -> Map.get(ref, "is_test", false) end)
          end)

        %{
          id: acid,
          acid: acid,
          definition: req.definition,
          status: state_data["status"],
          refs_count: refs_count,
          tests_count: tests_count,
          note: req.note,
          is_deprecated: req.is_deprecated,
          replaced_by: req.replaced_by
        }
      end)
      |> sort_requirements(sort_field, sort_dir)

    # Load source implementations
    states_source_impl =
      if state_source_impl_id do
        Implementations.get_implementation(state_source_impl_id)
        |> Acai.Repo.preload(:team)
      else
        nil
      end

    refs_source_impl =
      if refs_source_impl_id do
        Implementations.get_implementation(refs_source_impl_id)
        |> Acai.Repo.preload(:team)
      else
        nil
      end

    spec_source_impl =
      if spec_source.is_inherited && spec_source.source_implementation_id do
        Implementations.get_implementation(spec_source.source_implementation_id)
      else
        nil
      end

    # Update all assigns WITHOUT resetting impl_settings_visible
    socket =
      socket
      |> assign(:team, team)
      |> assign(:product, product)
      |> assign(:spec, spec)
      |> assign(:implementation, implementation)
      |> assign(:feature_name, feature_name)
      |> assign(:requirements, requirement_rows)
      |> assign(:sort_field, sort_field)
      |> assign(:sort_dir, sort_dir)
      |> assign(:tracked_branches, tracked_branches)
      |> assign(:available_implementations, available_implementations)
      |> assign(:available_features, available_features)
      |> assign(:spec_source, spec_source)
      |> assign(:spec_inherited, spec_source.is_inherited)
      |> assign(:spec_source_impl, spec_source_impl)
      |> assign(:states, states)
      |> assign(:states_inherited, states_inherited)
      |> assign(:states_source_impl, states_source_impl)
      |> assign(:refs_inherited, refs_inherited)
      |> assign(:refs_source_impl, refs_source_impl)

    # Note: impl_settings_visible and feature_settings_visible are NOT assigned here - they are preserved by the caller

    {:ok, socket}
  end

  # data-model.SPECS.11: Build requirement rows from JSONB requirements map
  defp build_requirement_rows_from_spec(spec) do
    spec.requirements
    |> Enum.map(fn {acid, data} ->
      %{
        acid: acid,
        definition: Map.get(data, "definition", ""),
        note: Map.get(data, "note"),
        is_deprecated: Map.get(data, "is_deprecated", false),
        replaced_by: Map.get(data, "replaced_by", [])
      }
    end)
  end

  # feature-impl-view.LIST.2-2
  # feature-impl-view.LIST.2-3
  defp sort_requirements(requirements, sort_field, sort_dir) do
    sorted = Enum.sort_by(requirements, &requirement_sort_key(&1, sort_field))

    case sort_dir do
      :desc -> Enum.reverse(sorted)
      _ -> sorted
    end
  end

  defp requirement_sort_key(requirement, :acid) do
    {String.downcase(requirement.acid), String.downcase(requirement.definition || "")}
  end

  defp requirement_sort_key(requirement, :status) do
    {status_sort_rank(requirement.status), String.downcase(requirement.acid)}
  end

  defp requirement_sort_key(requirement, :definition) do
    {String.downcase(requirement.definition || ""), String.downcase(requirement.acid)}
  end

  defp requirement_sort_key(requirement, :refs_count) do
    {requirement.refs_count, String.downcase(requirement.acid)}
  end

  defp requirement_sort_key(requirement, _sort_field),
    do: requirement_sort_key(requirement, :acid)

  defp status_sort_rank("accepted"), do: 1
  defp status_sort_rank("completed"), do: 2
  defp status_sort_rank("assigned"), do: 3
  defp status_sort_rank("blocked"), do: 4
  defp status_sort_rank("rejected"), do: 5
  defp status_sort_rank(_status), do: 6

  defp normalize_sort_field("acid"), do: :acid
  defp normalize_sort_field("status"), do: :status
  defp normalize_sort_field("definition"), do: :definition
  defp normalize_sort_field("refs_count"), do: :refs_count
  defp normalize_sort_field(_field), do: :acid

  defp next_sort_dir(current_field, current_dir, new_field) when current_field == new_field do
    case current_dir do
      :asc -> :desc
      _ -> :asc
    end
  end

  defp next_sort_dir(_current_field, _current_dir, _new_field), do: :asc

  defp acid_dom_id(acid), do: String.replace(acid, ".", "-")

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

  # Handle params for URL changes (patch navigation)
  # feature-impl-view.CARDS.1-2: Reload page data when URL is patched via dropdown changes
  @impl true
  def handle_params(
        %{"team_name" => team_name, "feature_name" => feature_name, "impl_slug" => impl_slug},
        uri,
        socket
      ) do
    # Update current_path for navigation highlighting
    socket = assign(socket, :current_path, URI.parse(uri).path)

    # Only reload data if params have actually changed (not on initial mount)
    current_impl = socket.assigns[:implementation]
    current_team = socket.assigns[:team]
    current_feature = socket.assigns[:feature_name]

    implementation_changed =
      is_nil(current_impl) or
        Implementations.implementation_slug(current_impl) != impl_slug

    team_changed = is_nil(current_team) or current_team.name != team_name
    feature_changed = is_nil(current_feature) or current_feature != feature_name

    should_reload = implementation_changed or team_changed or feature_changed

    if should_reload do
      reload_implementation_data(
        socket,
        team_name,
        impl_slug,
        feature_name,
        implementation_changed,
        team_changed
      )
    else
      {:noreply, socket}
    end
  end

  # Reload implementation data after URL patch (shared logic with mount)
  # When only feature changes, reuse existing team and implementation to avoid unnecessary DB queries
  defp reload_implementation_data(
         socket,
         team_name,
         impl_slug,
         feature_name,
         implementation_changed,
         team_changed
       ) do
    # Reuse existing team if it hasn't changed
    team =
      if team_changed do
        Teams.get_team_by_name!(team_name)
      else
        socket.assigns.team
      end

    # Reuse existing implementation if it hasn't changed
    implementation_result =
      cond do
        implementation_changed ->
          case Implementations.get_implementation_by_slug(impl_slug) do
            nil -> {:error, :not_found}
            impl -> {:ok, impl}
          end

        team_changed ->
          # Team changed but implementation slug didn't - still need to verify the implementation
          case Implementations.get_implementation_by_slug(impl_slug) do
            nil -> {:error, :not_found}
            impl -> {:ok, impl}
          end

        true ->
          # Neither changed, reuse existing
          {:ok, socket.assigns.implementation}
      end

    case implementation_result do
      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Implementation not found")
         |> push_navigate(to: ~p"/t/#{team.name}/f/#{feature_name}")}

      {:ok, implementation} ->
        if implementation.team_id == team.id do
          # Reload all data for the new implementation/feature
          {:ok, new_socket} =
            mount_implementation_view(socket, team, implementation, feature_name)

          {:noreply, new_socket}
        else
          {:noreply,
           socket
           |> put_flash(:error, "Implementation not found")
           |> push_navigate(to: ~p"/t/#{team.name}/f/#{feature_name}")}
        end
    end
  end

  @impl true
  def handle_event("open_drawer", %{"acid" => acid}, socket) do
    # Load refs lazily for this specific ACID when drawer opens
    # feature-impl-view.INHERITANCE.3: Get refs with inheritance walking
    {aggregated_refs, _refs_source_impl_id} =
      Implementations.get_aggregated_refs_with_inheritance(
        socket.assigns.feature_name,
        socket.assigns.implementation.id
      )

    # Extract refs for this ACID only
    drawer_refs_by_branch = get_refs_by_branch(aggregated_refs, acid)

    {:noreply,
     socket
     |> assign(:selected_acid, acid)
     |> assign(:drawer_visible, true)
     |> assign(:drawer_refs_by_branch, drawer_refs_by_branch)}
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply,
     socket
     |> assign(:drawer_visible, false)
     |> assign(:selected_acid, nil)}
  end

  # feature-impl-view.MAIN.2: Renders an 'Implementation Settings' button
  # feature-impl-view.MAIN.2-1: On click, toggles the impl-settings drawer
  def handle_event("open_impl_settings", _params, socket) do
    {:noreply, assign(socket, :impl_settings_visible, true)}
  end

  def handle_event("close_impl_settings", _params, socket) do
    {:noreply, assign(socket, :impl_settings_visible, false)}
  end

  # feature-impl-view.MAIN.1: Renders a 'Feature Settings' button
  # feature-impl-view.MAIN.1-1: On click, toggles the feature-settings drawer
  def handle_event("open_feature_settings", _params, socket) do
    {:noreply, assign(socket, :feature_settings_visible, true)}
  end

  def handle_event("close_feature_settings", _params, socket) do
    {:noreply, assign(socket, :feature_settings_visible, false)}
  end

  # feature-impl-view.CARDS.1-2: Handle implementation dropdown change with patch navigation
  def handle_event("select_implementation", %{"impl_id" => impl_slug}, socket) do
    %{
      team: team,
      feature_name: feature_name,
      available_implementations: available_implementations
    } =
      socket.assigns

    allowed_impl_slugs =
      MapSet.new(available_implementations, &Implementations.implementation_slug/1)

    # feature-impl-view.CARDS.1-4
    if MapSet.member?(allowed_impl_slugs, impl_slug) do
      # Patch to the new URL without full page reload
      {:noreply, push_patch(socket, to: ~p"/t/#{team.name}/i/#{impl_slug}/f/#{feature_name}")}
    else
      {:noreply, put_flash(socket, :error, "Implementation is not available for this feature")}
    end
  end

  # feature-impl-view.LIST.2-2
  # feature-impl-view.LIST.2-3
  def handle_event("sort_requirements", %{"field" => field}, socket) do
    sort_field = normalize_sort_field(field)
    sort_dir = next_sort_dir(socket.assigns[:sort_field], socket.assigns[:sort_dir], sort_field)

    {:noreply,
     socket
     |> assign(:sort_field, sort_field)
     |> assign(:sort_dir, sort_dir)
     |> assign(
       :requirements,
       sort_requirements(socket.assigns.requirements, sort_field, sort_dir)
     )}
  end

  # feature-impl-view.CARDS.1-2: Handle feature dropdown change with patch navigation
  def handle_event("select_feature", %{"feature_name" => new_feature_name}, socket) do
    %{team: team, implementation: implementation} = socket.assigns
    impl_slug = Implementations.implementation_slug(implementation)

    # Patch to the new URL without full page reload
    {:noreply, push_patch(socket, to: ~p"/t/#{team.name}/i/#{impl_slug}/f/#{new_feature_name}")}
  end

  # Handle messages from the RequirementDetailsLive component
  @impl true
  def handle_info("drawer_closed", socket) do
    {:noreply,
     socket
     |> assign(:selected_acid, nil)
     |> assign(:drawer_visible, false)}
  end

  # Handle messages from the ImplementationSettingsLive component
  @impl true
  def handle_info("impl_settings_closed", socket) do
    {:noreply, assign(socket, :impl_settings_visible, false)}
  end

  # Handle messages from the FeatureSettingsLive component
  # feature-settings.DRAWER.3: Drawer closes when clicking outside, close button, or pressing Escape
  @impl true
  def handle_info("feature_settings_closed", socket) do
    {:noreply, assign(socket, :feature_settings_visible, false)}
  end

  # feature-settings.CLEAR_STATES.6: UI updates immediately after deletion to show no states or inherited states
  def handle_info(:feature_states_changed, socket) do
    # Preserve the feature settings drawer visibility state
    feature_settings_visible = socket.assigns[:feature_settings_visible] || false

    # Reload all page data through the loader path to ensure consistency
    %{team: team, implementation: implementation, feature_name: feature_name} = socket.assigns

    # Reload the implementation to get fresh data
    implementation = Acai.Repo.preload(implementation, :product, force: true)

    # Use reload_implementation_data which preserves existing socket assigns
    {:ok, new_socket} =
      reload_implementation_data(
        socket,
        team,
        implementation.product,
        implementation,
        feature_name
      )

    # Restore the drawer visibility state after refresh
    {:noreply, assign(new_socket, :feature_settings_visible, feature_settings_visible)}
  end

  # feature-settings.CLEAR_REFS.7: UI updates immediately after deletion to show no refs or inherited refs
  def handle_info(:feature_refs_changed, socket) do
    # Preserve the feature settings drawer visibility state
    feature_settings_visible = socket.assigns[:feature_settings_visible] || false

    # Reload all page data through the loader path to ensure consistency
    %{team: team, implementation: implementation, feature_name: feature_name} = socket.assigns

    # Reload the implementation to get fresh data
    implementation = Acai.Repo.preload(implementation, :product, force: true)

    # Use reload_implementation_data which preserves existing socket assigns
    {:ok, new_socket} =
      reload_implementation_data(
        socket,
        team,
        implementation.product,
        implementation,
        feature_name
      )

    # Restore the drawer visibility state after refresh
    {:noreply, assign(new_socket, :feature_settings_visible, feature_settings_visible)}
  end

  # feature-settings.DELETE_SPEC.6_1: If a parent spec exists, UI updates to show parent requirements
  # feature-settings.DELETE_SPEC.6_2: If no parent spec exists, user is redirected to /p/:product_name
  def handle_info(:feature_spec_deleted, socket) do
    team = socket.assigns.team
    product = socket.assigns.product
    feature_name = socket.assigns.feature_name
    implementation = socket.assigns.implementation

    # Check if a parent spec exists for this feature
    case Specs.resolve_canonical_spec(feature_name, implementation.id) do
      {nil, nil} ->
        # feature-settings.DELETE_SPEC.6_2: No parent spec - redirect to product page
        {:noreply, push_navigate(socket, to: ~p"/t/#{team.name}/p/#{product.name}")}

      {_spec, _spec_source} ->
        # feature-settings.DELETE_SPEC.6_1: Parent spec exists - reload page to show inherited spec
        {:ok, new_socket} =
          mount_implementation_view(socket, team, implementation, feature_name)

        {:noreply, new_socket}
    end
  end

  # impl-settings.RENAME.8: On successful save, updates the implementation name and UI reflects change
  # After rename, patch to new URL so it aligns with feature-impl-view.ROUTING.1-3
  def handle_info({:implementation_renamed, updated_implementation}, socket) do
    team = socket.assigns.team
    product = socket.assigns.product
    feature_name = socket.assigns.feature_name
    new_slug = Implementations.implementation_slug(updated_implementation)

    # Reload available_implementations to reflect the name change in dropdown
    # This ensures the dropdown shows the updated name instead of stale data
    available_implementations =
      Specs.list_implementations_for_feature_batched(feature_name, product)

    {:noreply,
     socket
     |> assign(:implementation, updated_implementation)
     |> assign(:available_implementations, available_implementations)
     |> push_patch(to: ~p"/t/#{team.name}/i/#{new_slug}/f/#{feature_name}")}
  end

  # impl-settings.UNTRACK_BRANCH.8: UI updates immediately to reflect the removed branch
  # impl-settings.TRACK_BRANCH.9: UI updates immediately to show the newly tracked branch
  # impl-settings.TRACK_BRANCH.10: List of trackable branches refreshes to exclude the newly tracked branch
  def handle_info(:tracked_branches_changed, socket) do
    # Preserve the drawer visibility state so the settings drawer stays open after refresh
    impl_settings_visible = socket.assigns[:impl_settings_visible] || false

    # Reload all page data through the loader path to ensure consistency:
    # - tracked_branches, refs counts, dropdowns, inherited/local context all stay correct
    # We use load_implementation_data directly instead of mount_implementation_view
    # because mount_implementation_view resets assigns like impl_settings_visible
    %{team: team, implementation: implementation, feature_name: feature_name} = socket.assigns

    # Reload the implementation to get fresh tracked_branches
    implementation = Acai.Repo.preload(implementation, :product, force: true)

    # Use reload_implementation_data which preserves existing socket assigns
    {:ok, new_socket} =
      reload_implementation_data(
        socket,
        team,
        implementation.product,
        implementation,
        feature_name
      )

    # Restore the drawer visibility state after refresh
    {:noreply, assign(new_socket, :impl_settings_visible, impl_settings_visible)}
  end

  # impl-settings.DELETE.7: User is redirected to /p/:product_name after deletion
  def handle_info({:implementation_deleted, _implementation}, socket) do
    team = socket.assigns.team
    product = socket.assigns.product

    {:noreply, push_navigate(socket, to: ~p"/t/#{team.name}/p/#{product.name}")}
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
        <%!-- feature-impl-view.MAIN.1: Page header with breadcrumb --%>
        <nav class="flex items-center gap-2 text-sm text-base-content/70">
          <.link navigate={~p"/t/#{@team.name}"} class="hover:text-primary flex items-center gap-1">
            <.icon name="hero-home" class="size-4" />
          </.link>
          <span class="text-base-content/40">/</span>
          <.link navigate={~p"/t/#{@team.name}/p/#{@product.name}"} class="hover:text-primary">
            {@product.name}
          </.link>
          <span class="text-base-content/40">/</span>
          <.link navigate={~p"/t/#{@team.name}/f/#{@feature_name}"} class="hover:text-primary">
            {@feature_name}
          </.link>
          <span class="text-base-content/40">/</span>
          <span class="text-base-content font-medium">{@implementation.name}</span>
        </nav>

        <%!-- feature-impl-view.CARDS.1: Interactive title picker with dropdowns --%>
        <.title_picker
          implementation={@implementation}
          feature_name={@feature_name}
          available_implementations={@available_implementations}
          available_features={@available_features}
        />

        <%!-- feature-impl-view.MAIN.2: Feature description subtitle --%>
        <%= if @spec.feature_description do %>
          <p id="feature-description" class="text-base text-base-content/70 mt-2">
            {@spec.feature_description}
          </p>
        <% end %>

        <div class="flex flex-row-reverse gap-4">
          <%!-- feature-impl-view.MAIN.1: Renders a 'Feature Settings' button --%>
          <%!-- feature-settings.DRAWER.1: Renders a settings icon button that opens the drawer --%>
          <button
            type="button"
            class="btn btn-soft"
            phx-click="open_feature_settings"
            id="feature-settings-btn"
          >
            <.icon name="hero-cog-6-tooth" class="size-5" /> Feature Settings
          </button>

          <%!-- feature-impl-view.MAIN.2: Renders an 'Implementation Settings' button --%>
          <%!-- impl-settings.DRAWER.1: Renders a settings icon button that opens the drawer --%>
          <button
            type="button"
            class="btn btn-soft"
            phx-click="open_impl_settings"
            id="impl-settings-btn"
          >
            <.icon name="hero-cog-6-tooth" class="size-5" /> Impl. Settings
          </button>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- feature-impl-view.CARDS.2: Target spec card with labeled fields and inheritance badge --%>
          <.target_spec_card
            spec={@spec}
            spec_inherited={@spec_inherited}
            spec_source={@spec_source}
            spec_source_impl={@spec_source_impl}
            feature_name={@feature_name}
            team={@team}
          />

          <%!-- feature-impl-view.CARDS.3: Tracked branches card listing branch names --%>
          <.tracked_branches_card branches={@tracked_branches} />
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- implementation-view.REQ_COVERAGE.1 --%>
          <.coverage_section
            title="Status"
            inherited={@states_inherited}
            source_impl={@states_source_impl}
            feature_name={@feature_name}
          >
            <.req_coverage_grid
              requirements={@requirements}
              on_click="open_drawer"
              inherited={@states_inherited}
            />
            <div class="mt-3 pt-3 border-t border-base-200 flex flex-wrap gap-x-3 gap-y-1 text-xs text-base-content/50">
              <span class="flex items-center gap-1">
                <span class={[
                  "w-2 h-2 rounded-sm",
                  @states_inherited && "bg-success/30",
                  !@states_inherited && "bg-success"
                ]} /> accepted
              </span>
              <span class="flex items-center gap-1">
                <span class={[
                  "w-2 h-2 rounded-sm",
                  @states_inherited && "bg-info/30",
                  !@states_inherited && "bg-info"
                ]} /> completed
              </span>
              <span class="flex items-center gap-1">
                <span class={[
                  "w-2 h-2 rounded-sm",
                  @states_inherited && "bg-warning/30",
                  !@states_inherited && "bg-warning"
                ]} /> assigned
              </span>
              <span class="flex items-center gap-1">
                <span class={[
                  "w-2 h-2 rounded-sm",
                  @states_inherited && "bg-error/30",
                  !@states_inherited && "bg-error"
                ]} /> blocked
              </span>
              <span class="flex items-center gap-1">
                <span class={[
                  "w-2 h-2 rounded-sm",
                  @states_inherited && "bg-error/30",
                  !@states_inherited && "bg-error opacity-60"
                ]} /> rejected
              </span>
            </div>
          </.coverage_section>

          <%!-- implementation-view.TEST_COVERAGE: Test coverage grid --%>
          <.coverage_section
            title="Test Coverage"
            inherited={@refs_inherited}
            source_impl={@refs_source_impl}
            feature_name={@feature_name}
          >
            <.test_coverage_grid
              requirements={@requirements}
              on_click="open_drawer"
              inherited={@refs_inherited}
            />
            <% reqs_with_tests = Enum.count(@requirements, &(&1.tests_count > 0)) %>
            <% total_reqs = Enum.count(@requirements) %>
            <% coverage_pct =
              if total_reqs > 0, do: round(reqs_with_tests / total_reqs * 100), else: 0 %>
            <div class="mt-3 pt-3 border-t border-base-200 flex items-center justify-between text-sm">
              <span class="text-base-content/50">{coverage_pct}% covered</span>
              <span class="text-base-content/50">{reqs_with_tests} of {total_reqs}</span>
            </div>
          </.coverage_section>
        </div>

        <%!-- implementation-view.REQ_LIST: Requirements table --%>
        <.requirements_table
          requirements={@requirements}
          on_row_click="open_drawer"
          inherited={@states_inherited}
          sort_field={@sort_field}
          sort_dir={@sort_dir}
        />

        <%!-- Requirement details drawer --%>
        <%!-- data-model.SPECS.11: Pass acid instead of requirement_id --%>
        <%!-- feature-impl-view.DRAWER.4: Pass aggregated_refs from tracked branches --%>
        <%!-- feature-impl-view.INHERITANCE.2: Pass inherited state context and states to drawer --%>
        <.live_component
          module={AcaiWeb.Live.Components.RequirementDetailsLive}
          id="requirement-details-drawer"
          acid={@selected_acid}
          spec={@spec}
          implementation={@implementation}
          refs_by_branch={@drawer_refs_by_branch}
          visible={@drawer_visible}
          states={@states}
          states_inherited={@states_inherited}
          states_source_impl={@states_source_impl}
          feature_name={@feature_name}
        />

        <%!-- Implementation Settings drawer --%>
        <%!-- impl-settings.DRAWER: Settings drawer for implementation management --%>
        <.live_component
          module={AcaiWeb.Live.Components.ImplementationSettingsLive}
          id="implementation-settings-drawer"
          implementation={@implementation}
          product={@product}
          team={@team}
          tracked_branches={@tracked_branches}
          current_branch_id={@spec.branch_id}
          visible={@impl_settings_visible}
        />

        <%!-- Feature Settings drawer --%>
        <%!-- feature-settings.DRAWER.1: Renders a settings icon button that opens the drawer --%>
        <%!-- feature-settings.DRAWER.2: Drawer opens from the right side of the viewport --%>
        <%!-- feature-settings.DRAWER.3: Drawer closes when clicking the close button, clicking outside, or pressing Escape --%>
        <%!-- feature-settings.DRAWER.4: Drawer displays the feature name and implementation context in its header --%>
        <.live_component
          module={AcaiWeb.Live.Components.FeatureSettingsLive}
          id="feature-settings-drawer"
          feature_name={@feature_name}
          implementation={@implementation}
          product={@product}
          team={@team}
          spec={@spec}
          spec_inherited={@spec_inherited}
          tracked_branches={@tracked_branches}
          states_inherited={@states_inherited}
          refs_inherited={@refs_inherited}
          visible={@feature_settings_visible}
        />
      </div>
    </Layouts.app>
    """
  end

  # feature-impl-view.CARDS.1: Interactive title picker with dropdowns
  # feature-impl-view.CARDS.1-3
  # feature-impl-view.CARDS.1-4
  # Rendered directly on background without card wrapper
  defp title_picker(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row sm:items-center gap-3">
      <%!-- Implementation dropdown with popover API --%>
      <div class="flex-shrink-0">
        <button
          class="btn btn-outline lg:btn-xl flex items-center gap-2 justify-start font-bold text-base lg:text-2xl px-2 border-secondary border-dashed"
          popovertarget="impl-popover"
          style="anchor-name:--anchor-impl"
        >
          <.icon name="hero-tag" class="size-5 text-secondary" />
          <span class="truncate">{@implementation.name}</span>
          <.icon name="hero-chevron-down" class="size-4 ml-auto text-base-content/50" />
        </button>
        <ul
          class="dropdown menu w-52 rounded-box bg-base-100 shadow-sm"
          popover
          id="impl-popover"
          style="position-anchor:--anchor-impl"
        >
          <li :for={impl <- @available_implementations}>
            <a
              href="#"
              phx-click="select_implementation"
              phx-value-impl_id={Implementations.implementation_slug(impl)}
              class={[
                "flex items-center gap-2",
                impl.id == @implementation.id && "active"
              ]}
            >
              <.icon name="hero-tag" class="size-5 text-secondary" />
              <span class="truncate">{impl.name}</span>
              <%= if impl.id == @implementation.id do %>
                <.icon name="hero-check" class="size-4 ml-auto text-success" />
              <% end %>
            </a>
          </li>
        </ul>
      </div>

      <span class="text-base lg:text-2xl font-bold">implementation of the</span>

      <%!-- Feature dropdown with popover API --%>
      <div class="flex-shrink-0">
        <button
          class="btn btn-outline lg:btn-xl flex items-center gap-2 justify-start font-bold text-base lg:text-2xl px-2 border-primary border-dashed"
          popovertarget="feature-popover"
          style="anchor-name:--anchor-feature"
        >
          <.icon name="hero-cube" class="size-4 text-primary" />
          <span class="truncate">{@feature_name}</span>
          <.icon name="hero-chevron-down" class="size-4 ml-auto text-base-content/50" />
        </button>
        <ul
          class="dropdown menu w-52 rounded-box bg-base-100 shadow-sm"
          popover
          id="feature-popover"
          style="position-anchor:--anchor-feature"
        >
          <li :for={{name, _value} <- @available_features}>
            <a
              href="#"
              phx-click="select_feature"
              phx-value-feature_name={name}
              class={[
                "flex items-center gap-2",
                name == @feature_name && "active"
              ]}
            >
              <.icon name="hero-cube" class="size-4 text-primary" />
              <span class="truncate">{name}</span>
              <%= if name == @feature_name do %>
                <.icon name="hero-check" class="size-4 ml-auto text-success" />
              <% end %>
            </a>
          </li>
        </ul>
      </div>

      <span class="text-base lg:text-2xl font-bold">feature</span>
    </div>
    """
  end

  # feature-impl-view.CARDS.2: Target spec card with labeled fields and inheritance badge
  defp target_spec_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm">
      <div class="card-body">
        <div class="flex items-center justify-between mb-2">
          <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider">
            Target Spec
          </h3>
          <%!-- feature-impl-view.CARDS.2-2: Inherited badge with popover --%>
          <%= if @spec_inherited do %>
            <% spec_inherited_popover_id = "spec-inherited-popover-#{@spec.id}" %>
            <button
              type="button"
              class="badge badge-warning cursor-pointer transition-colors hover:bg-warning/80"
              popovertarget={spec_inherited_popover_id}
              style="anchor-name:--spec-inherited-anchor"
            >
              <.icon name="hero-cloud-arrow-down" class="size-4" />Inherited
            </button>
            <div
              popover
              id={spec_inherited_popover_id}
              class="dropdown rounded-box bg-base-100 shadow-sm border border-base-300 p-3 w-80 space-y-2"
              style="position-anchor:--spec-inherited-anchor"
            >
              <p class="text-xs text-base-content/70">
                No spec has been pushed for this implementation. It has been inherited from
                <%= if @spec_source_impl do %>
                  <.link
                    navigate={
                      ~p"/t/#{@team.name}/i/#{Acai.Implementations.implementation_slug(@spec_source_impl)}/f/#{@feature_name}"
                    }
                    class="link link-primary"
                  >
                    {@spec_source_impl.name}
                  </.link>
                <% else %>
                  parent implementation
                <% end %>
              </p>
            </div>
          <% end %>
        </div>

        <div class="space-y-3 text-base-content/80">
          <%!-- feature-impl-view.CARDS.2-1: Labeled repo_uri --%>
          <%!-- feature-impl-view.CARDS.2-2: Display only repo name for known patterns --%>
          <% target_spec_repo_popover_id = "target-spec-repo-popover-#{@spec.branch.id}" %>
          <div class="flex items-center gap-2">
            <div class="w-20 flex-shrink-0 flex items-center gap-1.5 text-xs text-base-content/50">
              <.icon name="hero-code-bracket-square" class="size-4" />
              <span>Repo</span>
            </div>
            <%!-- feature-impl-view.CARDS.2-1: Repository badge opens a clickable popover --%>
            <button
              type="button"
              class="badge badge-md badge-soft cursor-pointer transition-colors hover:bg-base-200"
              popovertarget={target_spec_repo_popover_id}
              style="anchor-name:--target-spec-repo-anchor"
            >
              <.icon name="hero-code-bracket-square" class="size-4" />
              <span>{format_repo_name(@spec.branch.repo_uri)}</span>
            </button>
            <div
              popover
              id={target_spec_repo_popover_id}
              class="dropdown rounded-box bg-base-100 shadow-sm border border-base-300 p-3 w-80 space-y-2"
              style="position-anchor:--target-spec-repo-anchor"
            >
              <p class="text-xs uppercase tracking-wider text-base-content/50">Repository URI</p>
              <a
                href={repo_http_url(@spec.branch.repo_uri)}
                target="_blank"
                rel="noopener noreferrer"
                class="link link-primary text-sm break-all"
              >
                {@spec.branch.repo_uri}
              </a>
            </div>
          </div>

          <%!-- feature-impl-view.CARDS.2-1: Labeled branch --%>
          <div class="flex items-center gap-2">
            <div class="w-20 flex-shrink-0 flex items-center gap-1.5 text-xs text-base-content/50">
              <.icon name="custom-git-branch" class="size-3.5" />
              <span>Branch</span>
            </div>
            <span class="text-sm">{@spec.branch.branch_name}</span>
          </div>

          <%!-- feature-impl-view.CARDS.2-1: Labeled path --%>
          <div class="flex items-center gap-2">
            <div class="w-20 flex-shrink-0 flex items-center gap-1.5 text-xs text-base-content/50">
              <.icon name="hero-document-text" class="size-3.5" />
              <span>Path</span>
            </div>
            <span class="text-sm">{@spec.path}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # feature-impl-view.CARDS.3: Tracked branches card
  defp tracked_branches_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm">
      <div class="card-body p-4">
        <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider mb-2 flex-shrink-0">
          Tracked Branches
        </h3>

        <%= if @branches == [] do %>
          <p class="text-sm text-base-content/50 flex-shrink-0">No tracked branches</p>
        <% else %>
          <%!-- feature-impl-view.CARDS.3-1: Tracked branches use same repo display rules as target spec card --%>
          <%!-- Keep the title fixed and scroll only the list when enough rows accumulate --%>
          <div class="flex flex-col gap-2 max-h-32 overflow-y-auto pr-1">
            <div
              :for={tracked_branch <- @branches}
              class="text-sm flex items-center gap-2"
            >
              <% tracked_repo_popover_id = "tracked-branch-repo-popover-#{tracked_branch.branch_id}" %>
              <%!-- feature-impl-view.CARDS.3-1: Repository badge opens a clickable popover --%>
              <button
                type="button"
                class="badge badge-md badge-soft cursor-pointer transition-colors hover:bg-base-200"
                popovertarget={tracked_repo_popover_id}
                style={"anchor-name:--tracked-branch-repo-anchor-#{tracked_branch.branch_id}"}
              >
                <.icon name="hero-code-bracket-square" class="size-4" />
                <span>{format_repo_name(tracked_branch.branch.repo_uri)}</span>
              </button>
              <div
                popover
                id={tracked_repo_popover_id}
                class="dropdown rounded-box bg-base-100 shadow-sm border border-base-300 p-3 w-80 space-y-2"
                style={"position-anchor:--tracked-branch-repo-anchor-#{tracked_branch.branch_id}"}
              >
                <p class="text-xs uppercase tracking-wider text-base-content/50">Repository URI</p>
                <a
                  href={repo_http_url(tracked_branch.branch.repo_uri)}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="link link-primary text-sm break-all"
                >
                  {tracked_branch.branch.repo_uri}
                </a>
              </div>
              <%!-- Branch badge --%>
              <div class="badge badge-md">
                <.icon name="custom-git-branch" class="size-3.5" />
                <span>{tracked_branch.branch.branch_name}</span>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Coverage section wrapper
  defp coverage_section(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm">
      <div class="card-body">
        <div class="flex items-center justify-between mb-3">
          <h3 class="text-sm font-medium text-base-content/70 uppercase tracking-wider">
            {@title}
          </h3>
          <%= if @inherited do %>
            <% inherited_popover_id =
              "inherited-popover-#{@title |> String.downcase() |> String.replace(" ", "-")}" %>
            <button
              type="button"
              class="badge badge-warning cursor-pointer transition-colors hover:bg-warning/80"
              popovertarget={inherited_popover_id}
              style={"anchor-name:--inherited-anchor-#{@title |> String.downcase() |> String.replace(" ", "-")}"}
            >
              <.icon name="hero-cloud-arrow-down" class="size-4" />Inherited
            </button>
            <div
              popover
              id={inherited_popover_id}
              class="dropdown rounded-box bg-base-100 shadow-sm border border-base-300 p-3 w-80 space-y-2"
              style={"position-anchor:--inherited-anchor-#{@title |> String.downcase() |> String.replace(" ", "-")}"}
            >
              <p class="text-xs text-base-content/70">
                No {inheritance_message(@title)} for this implementation. They have been inherited from
                <%= if @source_impl do %>
                  <.link
                    navigate={
                      ~p"/t/#{@source_impl.team.name}/i/#{Implementations.implementation_slug(@source_impl)}/f/#{@feature_name}"
                    }
                    class="link link-primary"
                  >
                    {@source_impl.name}
                  </.link>
                <% else %>
                  parent implementation
                <% end %>
              </p>
            </div>
          <% end %>
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # Helper to get inheritance message based on section title
  defp inheritance_message("Requirements Coverage"), do: "states have been added"
  defp inheritance_message("Test Coverage"), do: "refs have been pushed"
  defp inheritance_message(_), do: "items have been added"

  # implementation-view.REQ_COVERAGE: Requirements coverage grid
  # feature-impl-view.LIST.2-3
  defp req_coverage_grid(assigns) do
    ~H"""
    <div id="requirements-coverage-grid" class="flex flex-wrap gap-2">
      <.link
        :for={req <- @requirements}
        id={"req-coverage-chip-#{acid_dom_id(req.acid)}"}
        data-acid={req.acid}
        phx-click={@on_click}
        phx-value-acid={req.acid}
        class="cursor-pointer"
      >
        <.req_chip requirement={req} inherited={@inherited} />
      </.link>
    </div>
    """
  end

  # implementation-view.REQ_COVERAGE.2: Chip color based on status
  defp req_chip(assigns) do
    ~H"""
    <div
      title={@requirement.acid}
      class={
        [
          "w-6 h-6 rounded-sm cursor-pointer transition-all hover:scale-110",
          # data-model.FEATURE_IMPL_STATES.4-3: Color coding
          # accepted (green), completed (blue), assigned (gold), blocked/rejected (red), null (gray)
          # When inherited, use 30% opacity
          @requirement.status == "accepted" && ((@inherited && "bg-success/30") || "bg-success"),
          @requirement.status == "completed" && ((@inherited && "bg-info/30") || "bg-info"),
          @requirement.status == "assigned" && ((@inherited && "bg-warning/30") || "bg-warning"),
          (@requirement.status == "blocked" || @requirement.status == "rejected") &&
            ((@inherited && "bg-error/30") || "bg-error"),
          (@requirement.status == nil || @requirement.status == "") &&
            ((@inherited && "bg-base-300/30") || "bg-base-300")
        ]
      }
    />
    """
  end

  # implementation-view.TEST_COVERAGE: Test coverage grid
  # feature-impl-view.LIST.2-3
  defp test_coverage_grid(assigns) do
    ~H"""
    <div id="test-coverage-grid" class="flex flex-wrap gap-1.5">
      <.link
        :for={req <- @requirements}
        id={"test-coverage-chip-#{acid_dom_id(req.acid)}"}
        data-acid={req.acid}
        phx-click={@on_click}
        phx-value-acid={req.acid}
        class="cursor-pointer"
      >
        <.test_chip requirement={req} inherited={@inherited} />
      </.link>
    </div>
    """
  end

  # implementation-view.TEST_COVERAGE.2: Chip color based on test references
  defp test_chip(assigns) do
    ~H"""
    <div
      title={"#{@requirement.acid} (#{@requirement.tests_count} tests)"}
      class={
        [
          "w-6 h-6 rounded-sm cursor-pointer transition-all hover:scale-110 flex items-center justify-center text-[10px] font-bold",
          # implementation-view.TEST_COVERAGE.2-1: Green if tests exist
          # When inherited, use 30% opacity and adjust text color
          @requirement.tests_count > 0 &&
            ((@inherited && "bg-success/30 text-success") || "bg-success text-white"),
          # implementation-view.TEST_COVERAGE.2-2: Gray if no tests
          @requirement.tests_count == 0 &&
            ((@inherited && "bg-base-300/30 text-base-content/50") || "bg-base-300 text-white")
        ]
      }
    >
      <%= if @requirement.tests_count > 0 do %>
        {@requirement.tests_count}
      <% end %>
    </div>
    """
  end

  # feature-impl-view.LIST: Requirements table
  # feature-impl-view.LIST.2: Table columns are ACID, Status, Definition, Refs count
  # feature-impl-view.LIST.2-2
  defp requirements_table(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm">
      <div class="card-body p-0">
        <div class="overflow-x-auto">
          <table class="table" id="requirements-list-table">
            <thead>
              <tr>
                <th>
                  <button
                    id="sort-requirements-acid"
                    type="button"
                    phx-click="sort_requirements"
                    phx-value-field="acid"
                    class="flex items-center gap-2"
                  >
                    <span>ACID</span>
                    <span class="text-[10px] uppercase text-base-content/40">
                      {if @sort_field == :acid, do: Atom.to_string(@sort_dir), else: "sort"}
                    </span>
                  </button>
                </th>
                <th>
                  <button
                    id="sort-requirements-status"
                    type="button"
                    phx-click="sort_requirements"
                    phx-value-field="status"
                    class="flex items-center gap-2"
                  >
                    <span>Status</span>
                    <span class="text-[10px] uppercase text-base-content/40">
                      {if @sort_field == :status, do: Atom.to_string(@sort_dir), else: "sort"}
                    </span>
                  </button>
                </th>
                <th>
                  <button
                    id="sort-requirements-definition"
                    type="button"
                    phx-click="sort_requirements"
                    phx-value-field="definition"
                    class="flex items-center gap-2"
                  >
                    <span>Definition</span>
                    <span class="text-[10px] uppercase text-base-content/40">
                      {if @sort_field == :definition, do: Atom.to_string(@sort_dir), else: "sort"}
                    </span>
                  </button>
                </th>
                <th class="text-center">
                  <button
                    id="sort-requirements-refs-count"
                    type="button"
                    phx-click="sort_requirements"
                    phx-value-field="refs_count"
                    class="inline-flex items-center gap-2"
                  >
                    <span>Refs</span>
                    <span class="text-[10px] uppercase text-base-content/40">
                      {if @sort_field == :refs_count, do: Atom.to_string(@sort_dir), else: "sort"}
                    </span>
                  </button>
                </th>
              </tr>
            </thead>
            <tbody>
              <%!-- feature-impl-view.LIST.5: Clicking a row opens the requirement details drawer --%>
              <tr
                :for={req <- @requirements}
                id={"requirement-row-#{String.replace(req.acid, ".", "-")}"}
                class="hover:bg-base-200 cursor-pointer"
                phx-click={@on_row_click}
                phx-value-acid={req.acid}
              >
                <td class="font-mono text-sm">{req.acid}</td>
                <td>
                  <.status_badge status={req.status} inherited={@inherited} />
                </td>
                <td class="max-w-md truncate">{req.definition}</td>
                <td class="text-center">{req.refs_count}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # Status badge for table
  # data-model.FEATURE_IMPL_STATES.4-3: Color coding
  # null (gray), assigned (gold), blocked (red), completed (blue), accepted (green), rejected (red)
  defp status_badge(assigns) do
    ~H"""
    <%= if @status do %>
      <span class={
        [
          "badge badge-sm",
          # Use badge-soft when inherited
          @inherited && "badge-soft",
          @status == "accepted" && "badge-success",
          @status == "completed" && "badge-info",
          @status == "assigned" && "badge-warning",
          (@status == "blocked" || @status == "rejected") && "badge-error"
        ]
      }>
        {@status}
      </span>
    <% else %>
      <span class={[
        "badge badge-sm text-base-content/50",
        (@inherited && "badge-soft badge-ghost") || "badge-ghost"
      ]}>
        No status
      </span>
    <% end %>
    """
  end
end
