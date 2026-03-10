defmodule Acai.Specs do
  @moduledoc """
  Context for specs, spec_impl_states, and spec_impl_refs.
  """

  import Ecto.Query
  alias Acai.Repo
  alias Acai.Specs.{Spec, SpecImplState, SpecImplRef}
  alias Acai.Teams.Team
  alias Acai.Products.Product

  # --- Specs ---

  @doc """
  Lists all specs for a team.
  """
  def list_specs(_current_scope, %Team{} = team) do
    Repo.all(from s in Spec, where: s.team_id == ^team.id)
  end

  @doc """
  Lists all specs for a product.
  """
  def list_specs_for_product(%Product{} = product) do
    Repo.all(from s in Spec, where: s.product_id == ^product.id)
  end

  @doc """
  Gets a spec by ID.
  """
  def get_spec!(id), do: Repo.get!(Spec, id)

  @doc """
  Creates a spec for a team and product.
  """
  def create_spec(_current_scope, %Team{} = team, %Product{} = product, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:team_id, team.id)
      |> Map.put(:product_id, product.id)

    %Spec{}
    |> Spec.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a spec.
  """
  def update_spec(%Spec{} = spec, attrs) do
    spec
    |> Spec.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a changeset for a spec.
  """
  def change_spec(%Spec{} = spec, attrs \\ %{}) do
    Spec.changeset(spec, attrs)
  end

  # --- Products Navigation ---

  @doc """
  Returns all specs for a team, grouped by product name.
  """
  def list_specs_grouped_by_product(%Team{} = team) do
    specs =
      Repo.all(
        from s in Spec,
          where: s.team_id == ^team.id,
          preload: [:product]
      )

    Enum.group_by(specs, fn s -> s.product.name end)
  end

  @doc """
  Gets a spec by feature_name for a team.
  Returns the first matching spec if multiple exist (e.g. across different branches).
  """
  def get_spec_by_feature_name(%Team{} = team, feature_name) do
    Repo.all(
      from s in Spec,
        where: s.team_id == ^team.id and s.feature_name == ^feature_name,
        limit: 1
    )
    |> List.first()
  end

  @doc """
  Gets specs for a team by feature_name (case-insensitive).
  Returns the actual feature_name (from database) and the list of specs.
  Returns nil if no matching feature is found.
  """
  def get_specs_by_feature_name(%Team{} = team, feature_name) do
    actual_feature_name =
      Repo.one(
        from s in Spec,
          where: s.team_id == ^team.id,
          where: fragment("lower(?)", s.feature_name) == ^String.downcase(feature_name),
          select: s.feature_name,
          limit: 1
      )

    if actual_feature_name do
      specs =
        Repo.all(
          from s in Spec,
            where: s.team_id == ^team.id and s.feature_name == ^actual_feature_name
        )

      # Ensure requirements field is loaded (it should be by default since it's JSONB)
      {actual_feature_name, specs}
    else
      nil
    end
  end

  @doc """
  Gets specs for a team by product name (case-insensitive).
  Returns the actual product name (from the database) and the list of specs.
  Returns nil if no matching product is found.
  """
  def get_specs_by_product_name(%Team{} = team, product_name) do
    product =
      Repo.one(
        from p in Product,
          where: p.team_id == ^team.id,
          where: fragment("lower(?)", p.name) == ^String.downcase(product_name),
          limit: 1
      )

    if product do
      specs =
        Repo.all(
          from s in Spec,
            where: s.team_id == ^team.id and s.product_id == ^product.id
        )

      {product.name, specs}
    else
      nil
    end
  end

  # --- SpecImplStates ---

  @doc """
  Gets a spec_impl_state for a spec and implementation.
  Returns nil if not found.
  """
  def get_spec_impl_state(%Spec{} = spec, %Acai.Implementations.Implementation{} = implementation) do
    Repo.one(
      from sis in SpecImplState,
        where: sis.spec_id == ^spec.id and sis.implementation_id == ^implementation.id
    )
  end

  @doc """
  Creates a spec_impl_state for a spec and implementation.
  """
  def create_spec_impl_state(
        %Spec{} = spec,
        %Acai.Implementations.Implementation{} = implementation,
        attrs
      ) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:spec_id, spec.id)
      |> Map.put(:implementation_id, implementation.id)

    %SpecImplState{}
    |> SpecImplState.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a spec_impl_state.
  """
  def update_spec_impl_state(%SpecImplState{} = state, attrs) do
    state
    |> SpecImplState.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Upserts a spec_impl_state by (spec_id, implementation_id).
  On conflict, replaces the states JSONB field.
  """
  def upsert_spec_impl_state(
        %Spec{} = spec,
        %Acai.Implementations.Implementation{} = implementation,
        attrs
      ) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:spec_id, spec.id)
      |> Map.put(:implementation_id, implementation.id)

    %SpecImplState{}
    |> SpecImplState.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:states, :updated_at]},
      conflict_target: [:spec_id, :implementation_id],
      returning: true
    )
  end

  # --- SpecImplState Batch Queries ---

  @doc """
  Batch gets spec_impl_state data for multiple specs and implementations.
  Returns a map of {spec_id, implementation_id} => %{completed: count, total: count}.

  This is used for building the feature × implementation matrix where each cell
  shows completion percentage.
  """
  def batch_get_spec_impl_completion(specs, implementations)
      when is_list(specs) and is_list(implementations) do
    spec_ids = Enum.map(specs, & &1.id)
    impl_ids = Enum.map(implementations, & &1.id)

    # Fetch all spec_impl_states for the given specs and implementations
    states =
      Repo.all(
        from sis in SpecImplState,
          where: sis.spec_id in ^spec_ids and sis.implementation_id in ^impl_ids,
          select: {sis.spec_id, sis.implementation_id, sis.states}
      )

    # Build a map of {spec_id, impl_id} => completion data
    # feature-view.MAIN.3: Both completed and accepted count toward completion
    states
    |> Enum.map(fn {spec_id, impl_id, state_map} ->
      completed_count =
        Enum.count(state_map, fn {_acid, attrs} ->
          attrs["status"] in ["completed", "accepted"]
        end)

      total_count = map_size(state_map)

      {{spec_id, impl_id}, %{completed: completed_count, total: total_count}}
    end)
    |> Map.new()
  end

  # --- SpecImplRefs ---

  @doc """
  Gets a spec_impl_ref for a spec and implementation.
  Returns nil if not found.
  """
  def get_spec_impl_ref(%Spec{} = spec, %Acai.Implementations.Implementation{} = implementation) do
    Repo.one(
      from sir in SpecImplRef,
        where: sir.spec_id == ^spec.id and sir.implementation_id == ^implementation.id
    )
  end

  @doc """
  Creates a spec_impl_ref for a spec and implementation.
  """
  def create_spec_impl_ref(
        %Spec{} = spec,
        %Acai.Implementations.Implementation{} = implementation,
        attrs
      ) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:spec_id, spec.id)
      |> Map.put(:implementation_id, implementation.id)

    %SpecImplRef{}
    |> SpecImplRef.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a spec_impl_ref.
  """
  def update_spec_impl_ref(%SpecImplRef{} = ref, attrs) do
    ref
    |> SpecImplRef.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Upserts a spec_impl_ref by (spec_id, implementation_id).
  On conflict, replaces the refs, agent, commit, and pushed_at fields.
  """
  def upsert_spec_impl_ref(
        %Spec{} = spec,
        %Acai.Implementations.Implementation{} = implementation,
        attrs
      ) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:spec_id, spec.id)
      |> Map.put(:implementation_id, implementation.id)

    %SpecImplRef{}
    |> SpecImplRef.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:refs, :agent, :commit, :pushed_at, :updated_at]},
      conflict_target: [:spec_id, :implementation_id],
      returning: true
    )
  end
end
