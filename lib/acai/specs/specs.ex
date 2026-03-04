defmodule Acai.Specs do
  @moduledoc """
  Context for specs, requirements, and code references.
  """

  import Ecto.Query
  alias Acai.Repo
  alias Acai.Specs.{Spec, Requirement, CodeReference}
  alias Acai.Teams.Team

  # --- Specs ---

  def list_specs(_current_scope, %Team{} = team) do
    Repo.all(from s in Spec, where: s.team_id == ^team.id)
  end

  def get_spec!(id), do: Repo.get!(Spec, id)

  def create_spec(_current_scope, %Team{} = team, attrs) do
    %Spec{}
    |> Spec.changeset(attrs)
    |> Ecto.Changeset.put_change(:team_id, team.id)
    |> Repo.insert()
  end

  def update_spec(%Spec{} = spec, attrs) do
    spec
    |> Spec.changeset(attrs)
    |> Repo.update()
  end

  def change_spec(%Spec{} = spec, attrs \\ %{}) do
    Spec.changeset(spec, attrs)
  end

  # --- Requirements ---

  def list_requirements(%Spec{} = spec) do
    Repo.all(from r in Requirement, where: r.spec_id == ^spec.id)
  end

  def get_requirement!(id), do: Repo.get!(Requirement, id)

  def create_requirement(%Spec{} = spec, attrs) do
    %Requirement{}
    |> Requirement.changeset(attrs)
    |> Ecto.Changeset.put_change(:spec_id, spec.id)
    |> Repo.insert()
  end

  def update_requirement(%Requirement{} = requirement, attrs) do
    requirement
    |> Requirement.changeset(attrs)
    |> Repo.update()
  end

  def change_requirement(%Requirement{} = requirement, attrs \\ %{}) do
    Requirement.changeset(requirement, attrs)
  end

  # --- Code References ---

  def list_code_references(%Requirement{} = requirement) do
    Repo.all(from c in CodeReference, where: c.requirement_id == ^requirement.id)
  end

  def get_code_reference!(id), do: Repo.get!(CodeReference, id)

  def create_code_reference(%Requirement{} = requirement, attrs) do
    %CodeReference{}
    |> CodeReference.changeset(attrs)
    |> Ecto.Changeset.put_change(:requirement_id, requirement.id)
    |> Repo.insert()
  end

  def change_code_reference(%CodeReference{} = code_reference, attrs \\ %{}) do
    CodeReference.changeset(code_reference, attrs)
  end
end
