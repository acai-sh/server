defmodule Acai.Seeds do
  @moduledoc """
  Database seeding functionality for the mapperoni data model.

  Mapperoni is a survey form builder with shareable maps that users add data to.
  Team: mapperoni
  Products: site (web application), api (backend API)

  Features adapted from the actual acai features but mapped to mapperoni domain:
  - Site features: map-editor, map-viewer, project-view, data-explorer, form-editor, field-settings, map-settings
  - API features: core, push
  """

  import Ecto.Query

  alias Acai.Repo
  alias Acai.Accounts
  alias Acai.Teams.{Team, UserTeamRole}
  alias Acai.Products.Product
  alias Acai.Specs.{Spec, SpecImplState, SpecImplRef}
  alias Acai.Implementations.{Implementation, TrackedBranch}

  @doc """
  Runs all seeds.

  ## Options

    * `:silent` - When `true`, suppresses all console output. Defaults to `false`.

  """
  def run(opts \\ []) do
    silent = Keyword.get(opts, :silent, false)

    users = seed_users(silent)
    team = seed_team("mapperoni", silent)
    seed_roles(team, users, silent)

    products = seed_products(team, silent)
    specs = seed_specs(team, products, silent)
    impls = seed_implementations(team, products, silent)
    seed_tracked_branches(impls, silent)
    seed_spec_impl_states(specs, impls, silent)
    seed_spec_impl_refs(specs, impls, silent)

    unless silent do
      IO.puts("\n=== Seeding Complete ===")
      IO.puts("")
      IO.puts("Sample data created:")
      IO.puts("  - Users: #{Enum.map(users, & &1.email) |> Enum.join(", ")}")
      IO.puts("  - Team: #{team.name}")
      IO.puts("  - Products: #{Enum.map(products, & &1.name) |> Enum.join(", ")}")

      IO.puts(
        "  - Site Specs: map-editor, map-viewer, project-view, data-explorer, form-editor, field-settings, map-settings"
      )

      IO.puts("  - API Specs: core-api, push-api")
      IO.puts("  - Implementations: production, staging environments")
      IO.puts("")
      IO.puts("All passwords are: Password123!")
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # User Seeding
  # ---------------------------------------------------------------------------

  defp seed_users(silent) do
    unless silent do
      IO.puts("\n=== Seeding Users ===")
    end

    [
      seed_user("owner@mapperoni.com", silent),
      seed_user("developer@mapperoni.com", silent),
      seed_user("readonly@mapperoni.com", silent)
    ]
  end

  defp seed_user(email, silent) do
    case Accounts.get_user_by_email(email) do
      nil ->
        {:ok, user} = Accounts.register_user(%{email: email, password: "Password123!"})

        unless silent do
          IO.puts("Created user: #{email}")
        end

        user

      user ->
        unless silent do
          IO.puts("User already exists: #{email}")
        end

        user
    end
  end

  # ---------------------------------------------------------------------------
  # Team Seeding
  # ---------------------------------------------------------------------------

  defp seed_team(name, silent) do
    unless silent do
      IO.puts("\n=== Seeding Teams ===")
    end

    case Repo.get_by(Team, name: name) do
      nil ->
        {:ok, team} = Repo.insert(%Team{name: name})

        unless silent do
          IO.puts("Created team: #{name}")
        end

        team

      team ->
        unless silent do
          IO.puts("Team already exists: #{name}")
        end

        team
    end
  end

  # ---------------------------------------------------------------------------
  # Role Seeding
  # ---------------------------------------------------------------------------

  defp seed_roles(team, [owner, dev, readonly], silent) do
    unless silent do
      IO.puts("\n=== Seeding Roles ===")
    end

    seed_role(team, owner, "owner", silent)
    seed_role(team, dev, "developer", silent)
    seed_role(team, readonly, "readonly", silent)
  end

  defp seed_role(team, user, title, silent) do
    existing =
      Repo.one(from r in UserTeamRole, where: r.team_id == ^team.id and r.user_id == ^user.id)

    if existing do
      unless silent do
        IO.puts("Role already exists for user #{user.email} in team #{team.name}")
      end

      existing
    else
      {:ok, role} =
        Repo.insert(%UserTeamRole{team_id: team.id, user_id: user.id, title: title})

      unless silent do
        IO.puts("Assigned role #{title} to #{user.email} in team #{team.name}")
      end

      role
    end
  end

  # ---------------------------------------------------------------------------
  # Product Seeding
  # ---------------------------------------------------------------------------

  defp seed_products(team, silent) do
    unless silent do
      IO.puts("\n=== Seeding Products ===")
    end

    site_product =
      seed_product(
        team,
        "site",
        %{
          description: "Mapperoni web application - map-based survey builder and viewer"
        },
        silent
      )

    api_product =
      seed_product(
        team,
        "api",
        %{
          description: "Mapperoni API - backend services for maps, forms, and data"
        },
        silent
      )

    [site_product, api_product]
  end

  defp seed_product(team, name, attrs, silent) do
    existing = Repo.one(from p in Product, where: p.team_id == ^team.id and p.name == ^name)

    if existing do
      unless silent do
        IO.puts("Product already exists: #{name} in team #{team.name}")
      end

      existing
    else
      attrs =
        Map.merge(
          %{
            name: name,
            description: "Product for demonstration",
            is_active: true,
            team_id: team.id
          },
          attrs
        )

      {:ok, product} = Repo.insert(Product.changeset(%Product{}, attrs))

      unless silent do
        IO.puts("Created product: #{name} in team #{team.name}")
      end

      product
    end
  end

  # ---------------------------------------------------------------------------
  # Spec Seeding
  # ---------------------------------------------------------------------------

  defp seed_specs(team, [site_product, api_product], silent) do
    unless silent do
      IO.puts("\n=== Seeding Specs with JSONB Requirements ===")
    end

    # Site product specs
    map_editor_spec = seed_map_editor_spec(team, site_product, silent)
    map_viewer_spec = seed_map_viewer_spec(team, site_product, silent)
    project_view_spec = seed_project_view_spec(team, site_product, silent)
    data_explorer_spec = seed_data_explorer_spec(team, site_product, silent)
    form_editor_spec = seed_form_editor_spec(team, site_product, silent)
    field_settings_spec = seed_field_settings_spec(team, site_product, silent)
    map_settings_spec = seed_map_settings_spec(team, site_product, silent)

    # API product specs
    core_api_spec = seed_core_api_spec(team, api_product, silent)
    push_api_spec = seed_push_api_spec(team, api_product, silent)

    [
      map_editor_spec,
      map_viewer_spec,
      project_view_spec,
      data_explorer_spec,
      form_editor_spec,
      field_settings_spec,
      map_settings_spec,
      core_api_spec,
      push_api_spec
    ]
  end

  # Site: map-editor feature
  defp seed_map_editor_spec(team, product, silent) do
    seed_spec(
      team,
      product,
      %{
        feature_name: "map-editor",
        feature_description:
          "Interactive map creation and editing interface for building shareable maps",
        repo_uri: "github.com/mapperoni/mapperoni-site",
        branch_name: "main",
        path: "features/site/map-editor.feature.yaml",
        requirements: %{
          "map-editor.CANVAS.1" => %{
            "definition" => "Users must be able to create a new map with a name and description.",
            "note" => "Map names must be unique within a project",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-editor.CANVAS.2" => %{
            "definition" =>
              "The canvas must support zooming from 10% to 500% with smooth transitions.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-editor.CANVAS.3" => %{
            "definition" => "Users must be able to pan the canvas by click-dragging.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-editor.LAYERS.1" => %{
            "definition" =>
              "Users must be able to add multiple layers to a map (base, data, annotations).",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-editor.LAYERS.2" => %{
            "definition" => "Layers must be reorderable via drag-and-drop in the layers panel.",
            "note" => "Layer order affects rendering - top layers overlay bottom layers",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-editor.MARKERS.1" => %{
            "definition" =>
              "Users must be able to place markers on the map at specific coordinates.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-editor.MARKERS.2" => %{
            "definition" => "Markers must support custom icons and colors.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-editor.EXPORT.1" => %{
            "definition" => "Maps must be exportable as PNG, SVG, or GeoJSON formats.",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      },
      silent
    )
  end

  # Site: map-viewer feature
  defp seed_map_viewer_spec(team, product, silent) do
    seed_spec(
      team,
      product,
      %{
        feature_name: "map-viewer",
        feature_description: "Public and embedded map viewing interface for shared maps",
        repo_uri: "github.com/mapperoni/mapperoni-site",
        branch_name: "main",
        path: "features/site/map-viewer.feature.yaml",
        requirements: %{
          "map-viewer.RENDER.1" => %{
            "definition" =>
              "Maps must render correctly on mobile, tablet, and desktop viewports.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-viewer.RENDER.2" => %{
            "definition" => "Map tiles must load progressively as the user pans and zooms.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-viewer.INTERACT.1" => %{
            "definition" => "Clicking a marker must open an info panel with submission data.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-viewer.INTERACT.2" => %{
            "definition" => "Info panels must support rich text and image attachments.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-viewer.EMBED.1" => %{
            "definition" => "Users must be able to generate an embed code for external websites.",
            "note" => "Embeds use an iframe with responsive sizing",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-viewer.SHARE.1" => %{
            "definition" => "Maps must have shareable URLs with optional password protection.",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      },
      silent
    )
  end

  # Site: project-view feature
  defp seed_project_view_spec(team, product, silent) do
    seed_spec(
      team,
      product,
      %{
        feature_name: "project-view",
        feature_description: "Project dashboard showing all maps, forms, and data for a project",
        repo_uri: "github.com/mapperoni/mapperoni-site",
        branch_name: "main",
        path: "features/site/project-view.feature.yaml",
        requirements: %{
          "project-view.DASHBOARD.1" => %{
            "definition" => "The dashboard must display a list of all maps in the project.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "project-view.DASHBOARD.2" => %{
            "definition" =>
              "Each map card must show submission count and last updated timestamp.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "project-view.DASHBOARD.3" => %{
            "definition" => "The dashboard must include a quick-create button for new maps.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "project-view.ANALYTICS.1" => %{
            "definition" => "Project analytics must show total submissions over time.",
            "note" => "Chart is a line graph with daily aggregation",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "project-view.ANALYTICS.2" => %{
            "definition" => "Analytics must show geographic distribution of submissions.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "project-view.MEMBERS.1" => %{
            "definition" => "Project owners must be able to invite collaborators.",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      },
      silent
    )
  end

  # Site: data-explorer feature
  defp seed_data_explorer_spec(team, product, silent) do
    seed_spec(
      team,
      product,
      %{
        feature_name: "data-explorer",
        feature_description: "Tabular and visual data exploration interface for form submissions",
        repo_uri: "github.com/mapperoni/mapperoni-site",
        branch_name: "main",
        path: "features/site/data-explorer.feature.yaml",
        requirements: %{
          "data-explorer.TABLE.1" => %{
            "definition" => "Submissions must be viewable in a sortable, filterable table.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "data-explorer.TABLE.2" => %{
            "definition" => "Table columns must be configurable (show/hide/reorder).",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "data-explorer.TABLE.3" => %{
            "definition" => "Bulk operations must support export and delete for selected rows.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "data-explorer.FILTER.1" => %{
            "definition" =>
              "Users must be able to filter by date range, field values, and location.",
            "note" => "Location filter uses a map bounding box selection",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "data-explorer.VISUAL.1" => %{
            "definition" => "Data must be visualizable as charts (bar, pie, line, heatmap).",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "data-explorer.EXPORT.1" => %{
            "definition" => "Filtered data must be exportable as CSV, Excel, or GeoJSON.",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      },
      silent
    )
  end

  # Site: form-editor feature
  defp seed_form_editor_spec(team, product, silent) do
    seed_spec(
      team,
      product,
      %{
        feature_name: "form-editor",
        feature_description: "Survey form builder for collecting data on maps",
        repo_uri: "github.com/mapperoni/mapperoni-site",
        branch_name: "main",
        path: "features/site/form-editor.feature.yaml",
        requirements: %{
          "form-editor.FIELDS.1" => %{
            "definition" => "Users must be able to add text, number, date, and choice fields.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "form-editor.FIELDS.2" => %{
            "definition" => "Fields must support required/optional validation.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "form-editor.FIELDS.3" => %{
            "definition" => "Fields must be reorderable via drag-and-drop.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "form-editor.LOCATION.1" => %{
            "definition" =>
              "Forms must capture GPS coordinates automatically or allow manual placement.",
            "note" => "Manual placement uses the map click-to-place interaction",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "form-editor.LOCATION.2" => %{
            "definition" =>
              "Forms must support geofencing - restricting submissions to a defined area.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "form-editor.PREVIEW.1" => %{
            "definition" => "Users must be able to preview the form before publishing.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "form-editor.CONDITIONAL.1" => %{
            "definition" =>
              "Fields must support conditional visibility based on other field values.",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      },
      silent
    )
  end

  # Site: field-settings feature
  defp seed_field_settings_spec(team, product, silent) do
    seed_spec(
      team,
      product,
      %{
        feature_name: "field-settings",
        feature_description: "Configuration interface for form field properties and validation",
        repo_uri: "github.com/mapperoni/mapperoni-site",
        branch_name: "main",
        path: "features/site/field-settings.feature.yaml",
        requirements: %{
          "field-settings.VALIDATION.1" => %{
            "definition" =>
              "Text fields must support min/max length and regex pattern validation.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "field-settings.VALIDATION.2" => %{
            "definition" => "Number fields must support min/max value and step increments.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "field-settings.CHOICE.1" => %{
            "definition" =>
              "Choice fields must support single-select, multi-select, and dropdown variants.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "field-settings.CHOICE.2" => %{
            "definition" =>
              "Choice options must be editable inline with add/remove/reorder capabilities.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "field-settings.DEFAULT.1" => %{
            "definition" => "Fields must support default values and placeholder text.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "field-settings.HELP.1" => %{
            "definition" => "Fields must support help text and tooltips for user guidance.",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      },
      silent
    )
  end

  # Site: map-settings feature
  defp seed_map_settings_spec(team, product, silent) do
    seed_spec(
      team,
      product,
      %{
        feature_name: "map-settings",
        feature_description: "Configuration interface for map appearance, behavior, and sharing",
        repo_uri: "github.com/mapperoni/mapperoni-site",
        branch_name: "main",
        path: "features/site/map-settings.feature.yaml",
        requirements: %{
          "map-settings.BASEMAP.1" => %{
            "definition" =>
              "Users must be able to choose from multiple basemap styles (satellite, terrain, street).",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-settings.BASEMAP.2" => %{
            "definition" => "Users must be able to provide a custom tile server URL.",
            "note" => "Useful for organizations with private map data",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-settings.BOUNDS.1" => %{
            "definition" =>
              "Users must be able to set the initial map view bounds and zoom level.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-settings.BOUNDS.2" => %{
            "definition" => "Users must be able to restrict the map to a maximum bounding box.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-settings.CONTROLS.1" => %{
            "definition" =>
              "Users must be able to toggle UI controls (zoom, fullscreen, layer switcher, search).",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-settings.PERMISSIONS.1" => %{
            "definition" => "Users must be able to set map visibility (private, team, public).",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "map-settings.PERMISSIONS.2" => %{
            "definition" => "Public maps must support optional password protection.",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      },
      silent
    )
  end

  # API: core feature
  defp seed_core_api_spec(team, product, silent) do
    seed_spec(
      team,
      product,
      %{
        feature_name: "core-api",
        feature_description:
          "Core API infrastructure - OpenAPI spec, authentication, and routing",
        repo_uri: "github.com/mapperoni/mapperoni-api",
        branch_name: "main",
        path: "features/api/core.feature.yaml",
        requirements: %{
          "core-api.OPENAPI.1" => %{
            "definition" =>
              "API must expose a public /api/openapi.json route with complete spec.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "core-api.OPENAPI.2" => %{
            "definition" => "All endpoints must be namespaced under /api/v1.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "core-api.AUTH.1" => %{
            "definition" =>
              "All routes must require Authorization: Bearer <token> header unless explicitly public.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "core-api.AUTH.2" => %{
            "definition" => "Token validation must check expiration and revocation status.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "core-api.RESPONSE.1" => %{
            "definition" => "All 2xx JSON responses must wrap payload in a root 'data' key.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "core-api.ERROR.1" => %{
            "definition" =>
              "Errors must use a consistent format with code, message, and details fields.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "core-api.STATELESS.1" => %{
            "definition" => "API pipeline must be strictly stateless (no sessions or flash).",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      },
      silent
    )
  end

  # API: push feature
  defp seed_push_api_spec(team, product, silent) do
    seed_spec(
      team,
      product,
      %{
        feature_name: "push-api",
        feature_description: "Push endpoint for CLI to ingest specs, code references, and states",
        repo_uri: "github.com/mapperoni/mapperoni-api",
        branch_name: "main",
        path: "features/api/push.feature.yaml",
        requirements: %{
          "push-api.SPEC.1" => %{
            "definition" =>
              "Push creates a new spec if no matching (repo_uri, branch_name, feature_name) exists.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "push-api.SPEC.2" => %{
            "definition" => "Push updates the existing spec if the combination already exists.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "push-api.SPEC.3" => %{
            "definition" =>
              "Each push must capture the commit hash and raw content for traceability.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "push-api.REF.1" => %{
            "definition" =>
              "Pushing code references must overwrite all existing refs for the spec + implementation.",
            "note" =>
              "References include repo, file path, line/column location, and is_test flag",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "push-api.REF.2" => %{
            "definition" => "Invalid or unknown ACIDs in the push must be skipped and reported.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "push-api.STATE.1" => %{
            "definition" => "States map keys must be full ACID strings.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "push-api.STATE.2" => %{
            "definition" =>
              "States must merge with existing values, overwriting on key collision.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "push-api.IMPL.1" => %{
            "definition" => "Pushing to an untracked branch may auto-create an implementation.",
            "note" => "Implementation name defaults to the branch name",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "push-api.IMPL.2" => %{
            "definition" =>
              "Parent implementation is determined by git upstream or explicit parent field.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "push-api.INHERIT.1" => %{
            "definition" =>
              "Gaining a parent must snapshot states and refs from parent to child.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "push-api.INHERIT.2" => %{
            "definition" =>
              "Uninheriting (setting parent to null) must sever the link but retain existing states.",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "push-api.TX.1" => %{
            "definition" =>
              "All operations within a push must be atomic with rollback on failure.",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      },
      silent
    )
  end

  defp seed_spec(team, product, attrs, silent) do
    unique_suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    defaults = %{
      repo_uri: "github.com/example/repo",
      branch_name: "main",
      path: "features/sample-#{unique_suffix}.feature.yaml",
      last_seen_commit: "abc#{unique_suffix}",
      parsed_at: DateTime.utc_now(:second),
      feature_name: "sample-feature-#{unique_suffix}",
      feature_description: "A sample feature for demonstration",
      feature_version: "1.0.0",
      raw_content: "feature:\n  name: sample",
      requirements: %{},
      team_id: team.id,
      product_id: product.id
    }

    attrs = Map.merge(defaults, attrs)

    existing =
      Repo.one(
        from s in Spec,
          where: s.team_id == ^team.id,
          where: s.feature_name == ^attrs.feature_name
      )

    if existing do
      unless silent do
        IO.puts("Spec already exists: #{attrs.feature_name} in team #{team.name}")
      end

      existing
    else
      {:ok, spec} = Repo.insert(Spec.changeset(%Spec{}, attrs))

      unless silent do
        IO.puts("Created spec: #{spec.feature_name} in product #{product.name}")
      end

      spec
    end
  end

  # ---------------------------------------------------------------------------
  # Implementation Seeding
  # ---------------------------------------------------------------------------

  defp seed_implementations(team, [site_product, api_product], silent) do
    unless silent do
      IO.puts("\n=== Seeding Implementations ===")
    end

    # Site implementations
    site_prod_impl =
      seed_implementation(
        team,
        site_product,
        %{
          name: "production",
          description: "Production environment for mapperoni site"
        },
        silent
      )

    site_staging_impl =
      seed_implementation(
        team,
        site_product,
        %{
          name: "staging",
          description: "Staging environment for mapperoni site"
        },
        silent
      )

    # API implementations
    api_prod_impl =
      seed_implementation(
        team,
        api_product,
        %{
          name: "production",
          description: "Production environment for mapperoni API"
        },
        silent
      )

    api_staging_impl =
      seed_implementation(
        team,
        api_product,
        %{
          name: "staging",
          description: "Staging environment for mapperoni API"
        },
        silent
      )

    [site_prod_impl, site_staging_impl, api_prod_impl, api_staging_impl]
  end

  defp seed_implementation(team, product, attrs, silent) do
    defaults = %{
      name: "production",
      description: "Production environment",
      is_active: true,
      team_id: team.id,
      product_id: product.id
    }

    attrs = Map.merge(defaults, attrs)

    existing =
      Repo.one(
        from i in Implementation,
          where: i.product_id == ^product.id and i.name == ^attrs.name
      )

    if existing do
      unless silent do
        IO.puts("Implementation already exists: #{attrs.name} for product #{product.name}")
      end

      existing
    else
      {:ok, impl} = Repo.insert(Implementation.changeset(%Implementation{}, attrs))

      unless silent do
        IO.puts("Created implementation: #{impl.name} for product #{product.name}")
      end

      impl
    end
  end

  # ---------------------------------------------------------------------------
  # Tracked Branch Seeding
  # ---------------------------------------------------------------------------

  defp seed_tracked_branches([site_prod, site_staging, api_prod, api_staging], silent) do
    unless silent do
      IO.puts("\n=== Seeding Tracked Branches ===")
    end

    # Site branches
    seed_tracked_branch(
      site_prod,
      %{
        repo_uri: "github.com/mapperoni/mapperoni-site",
        branch_name: "main",
        last_seen_commit: "a1b2c3d4e5f6"
      },
      silent
    )

    seed_tracked_branch(
      site_staging,
      %{
        repo_uri: "github.com/mapperoni/mapperoni-site",
        branch_name: "develop",
        last_seen_commit: "b2c3d4e5f6a7"
      },
      silent
    )

    # API branches
    seed_tracked_branch(
      api_prod,
      %{
        repo_uri: "github.com/mapperoni/mapperoni-api",
        branch_name: "main",
        last_seen_commit: "c3d4e5f6a7b8"
      },
      silent
    )

    seed_tracked_branch(
      api_staging,
      %{
        repo_uri: "github.com/mapperoni/mapperoni-api",
        branch_name: "develop",
        last_seen_commit: "d4e5f6a7b8c9"
      },
      silent
    )

    :ok
  end

  defp seed_tracked_branch(implementation, attrs, silent) do
    defaults = %{
      repo_uri: "github.com/example/repo",
      branch_name: "main",
      last_seen_commit: "def123",
      implementation_id: implementation.id
    }

    attrs = Map.merge(defaults, attrs)

    existing =
      Repo.one(
        from b in TrackedBranch,
          where: b.implementation_id == ^implementation.id,
          where: b.repo_uri == ^attrs.repo_uri
      )

    if existing do
      unless silent do
        IO.puts(
          "Tracked branch already exists: #{attrs.repo_uri} for implementation #{implementation.name}"
        )
      end

      existing
    else
      {:ok, branch} = Repo.insert(TrackedBranch.changeset(%TrackedBranch{}, attrs))

      unless silent do
        IO.puts("Created tracked branch: #{branch.repo_uri}/#{branch.branch_name}")
      end

      branch
    end
  end

  # ---------------------------------------------------------------------------
  # SpecImplState Seeding
  # ---------------------------------------------------------------------------

  defp seed_spec_impl_states(
         specs,
         [site_prod, site_staging, api_prod, _api_staging],
         silent
       ) do
    unless silent do
      IO.puts("\n=== Seeding SpecImplStates ===")
    end

    now = DateTime.utc_now() |> DateTime.to_iso8601()

    # Helper to find spec by feature_name
    find_spec = fn name -> Enum.find(specs, &(&1.feature_name == name)) end

    # Site: map-editor states
    map_editor_spec = find_spec.("map-editor")

    seed_spec_impl_state(
      map_editor_spec,
      site_prod,
      %{
        states: %{
          "map-editor.CANVAS.1" => %{"status" => "completed", "updated_at" => now},
          "map-editor.CANVAS.2" => %{"status" => "completed", "updated_at" => now},
          "map-editor.CANVAS.3" => %{
            "status" => "in_progress",
            "comment" => "Touch support pending",
            "updated_at" => now
          },
          "map-editor.LAYERS.1" => %{"status" => "completed", "updated_at" => now},
          "map-editor.LAYERS.2" => %{"status" => "completed", "updated_at" => now},
          "map-editor.MARKERS.1" => %{"status" => "completed", "updated_at" => now},
          "map-editor.MARKERS.2" => %{"status" => "pending", "updated_at" => now},
          "map-editor.EXPORT.1" => %{
            "status" => "blocked",
            "comment" => "Waiting for design specs",
            "updated_at" => now
          }
        }
      },
      silent
    )

    seed_spec_impl_state(
      map_editor_spec,
      site_staging,
      %{
        states: %{
          "map-editor.CANVAS.1" => %{"status" => "completed", "updated_at" => now},
          "map-editor.CANVAS.2" => %{"status" => "completed", "updated_at" => now},
          "map-editor.CANVAS.3" => %{"status" => "completed", "updated_at" => now},
          "map-editor.LAYERS.1" => %{"status" => "completed", "updated_at" => now},
          "map-editor.LAYERS.2" => %{"status" => "completed", "updated_at" => now},
          "map-editor.MARKERS.1" => %{"status" => "completed", "updated_at" => now},
          "map-editor.MARKERS.2" => %{"status" => "completed", "updated_at" => now},
          "map-editor.EXPORT.1" => %{"status" => "completed", "updated_at" => now}
        }
      },
      silent
    )

    # Site: form-editor states
    form_editor_spec = find_spec.("form-editor")

    seed_spec_impl_state(
      form_editor_spec,
      site_prod,
      %{
        states: %{
          "form-editor.FIELDS.1" => %{"status" => "completed", "updated_at" => now},
          "form-editor.FIELDS.2" => %{"status" => "completed", "updated_at" => now},
          "form-editor.FIELDS.3" => %{"status" => "in_progress", "updated_at" => now},
          "form-editor.LOCATION.1" => %{
            "status" => "completed",
            "comment" => "GPS auto-capture working",
            "updated_at" => now
          },
          "form-editor.LOCATION.2" => %{"status" => "pending", "updated_at" => now},
          "form-editor.PREVIEW.1" => %{"status" => "completed", "updated_at" => now},
          "form-editor.CONDITIONAL.1" => %{
            "status" => "blocked",
            "comment" => "Complex dependency graph",
            "updated_at" => now
          }
        }
      },
      silent
    )

    # API: push-api states
    push_api_spec = find_spec.("push-api")

    seed_spec_impl_state(
      push_api_spec,
      api_prod,
      %{
        states: %{
          "push-api.SPEC.1" => %{"status" => "completed", "updated_at" => now},
          "push-api.SPEC.2" => %{"status" => "completed", "updated_at" => now},
          "push-api.SPEC.3" => %{"status" => "completed", "updated_at" => now},
          "push-api.REF.1" => %{"status" => "completed", "updated_at" => now},
          "push-api.REF.2" => %{
            "status" => "in_progress",
            "comment" => "Error reporting needs refinement",
            "updated_at" => now
          },
          "push-api.STATE.1" => %{"status" => "completed", "updated_at" => now},
          "push-api.STATE.2" => %{"status" => "completed", "updated_at" => now},
          "push-api.IMPL.1" => %{"status" => "completed", "updated_at" => now},
          "push-api.IMPL.2" => %{"status" => "completed", "updated_at" => now},
          "push-api.INHERIT.1" => %{"status" => "completed", "updated_at" => now},
          "push-api.INHERIT.2" => %{"status" => "completed", "updated_at" => now},
          "push-api.TX.1" => %{"status" => "completed", "updated_at" => now}
        }
      },
      silent
    )

    :ok
  end

  defp seed_spec_impl_state(spec, implementation, attrs, silent) do
    defaults = %{
      states: %{},
      spec_id: spec.id,
      implementation_id: implementation.id
    }

    attrs = Map.merge(defaults, attrs)

    existing =
      Repo.one(
        from sis in SpecImplState,
          where: sis.spec_id == ^spec.id and sis.implementation_id == ^implementation.id
      )

    if existing do
      unless silent do
        IO.puts(
          "SpecImplState already exists for spec #{spec.feature_name} and implementation #{implementation.name}"
        )
      end

      existing
    else
      {:ok, state} = Repo.insert(SpecImplState.changeset(%SpecImplState{}, attrs))

      unless silent do
        IO.puts("Created spec_impl_state for spec #{spec.feature_name}")
      end

      state
    end
  end

  # ---------------------------------------------------------------------------
  # SpecImplRef Seeding
  # ---------------------------------------------------------------------------

  defp seed_spec_impl_refs(
         specs,
         [site_prod, _site_staging, api_prod, _api_staging],
         silent
       ) do
    unless silent do
      IO.puts("\n=== Seeding SpecImplRefs ===")
    end

    now = DateTime.utc_now()

    # Helper to find spec by feature_name
    find_spec = fn name -> Enum.find(specs, &(&1.feature_name == name)) end

    # Site: map-editor refs - all 8 requirements
    map_editor_spec = find_spec.("map-editor")

    seed_spec_impl_ref(
      map_editor_spec,
      site_prod,
      %{
        refs: %{
          "map-editor.CANVAS.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni_web/live/map_editor_live.ex:45",
              "loc" => "45:8",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni_web/live/map_editor_live_test.exs:23",
              "loc" => "23:1",
              "is_test" => true
            }
          ],
          "map-editor.CANVAS.2" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "assets/js/map_canvas.js:78",
              "loc" => "78:15",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/assets/js/map_canvas_test.js:34",
              "loc" => "34:5",
              "is_test" => true
            }
          ],
          "map-editor.CANVAS.3" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni_web/live/map_editor_live.ex:92",
              "loc" => "92:4",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni_web/live/map_editor_live_test.exs:67",
              "loc" => "67:3",
              "is_test" => true
            }
          ],
          "map-editor.LAYERS.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni/layers/layer_manager.ex:23",
              "loc" => "23:10",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni/layers/layer_manager_test.exs:15",
              "loc" => "15:1",
              "is_test" => true
            }
          ],
          "map-editor.LAYERS.2" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "assets/js/layer_panel.js:45",
              "loc" => "45:12",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/assets/js/layer_panel_test.js:28",
              "loc" => "28:5",
              "is_test" => true
            }
          ],
          "map-editor.MARKERS.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni/maps/marker.ex:34",
              "loc" => "34:5",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni/maps/marker_test.exs:12",
              "loc" => "12:3",
              "is_test" => true
            }
          ],
          "map-editor.MARKERS.2" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni/maps/marker_styles.ex:56",
              "loc" => "56:8",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni/maps/marker_styles_test.exs:22",
              "loc" => "22:1",
              "is_test" => true
            }
          ],
          "map-editor.EXPORT.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni/export/export_service.ex:67",
              "loc" => "67:15",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni/export/export_service_test.exs:44",
              "loc" => "44:3",
              "is_test" => true
            }
          ]
        },
        agent: "github-action",
        commit: "abc123def456",
        pushed_at: now
      },
      silent
    )

    # Site: map-viewer refs - all 6 requirements
    map_viewer_spec = find_spec.("map-viewer")

    seed_spec_impl_ref(
      map_viewer_spec,
      site_prod,
      %{
        refs: %{
          "map-viewer.RENDER.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni_web/live/map_viewer_live.ex:34",
              "loc" => "34:6",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni_web/live/map_viewer_live_test.exs:18",
              "loc" => "18:2",
              "is_test" => true
            }
          ],
          "map-viewer.RENDER.2" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "assets/js/tile_loader.js:89",
              "loc" => "89:4",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/assets/js/tile_loader_test.js:55",
              "loc" => "55:1",
              "is_test" => true
            }
          ],
          "map-viewer.INTERACT.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni_web/live/map_viewer_live.ex:112",
              "loc" => "112:8",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni_web/live/map_viewer_live_test.exs:78",
              "loc" => "78:3",
              "is_test" => true
            }
          ],
          "map-viewer.INTERACT.2" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni/info_panel/info_panel.ex:45",
              "loc" => "45:12",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni/info_panel/info_panel_test.exs:33",
              "loc" => "33:1",
              "is_test" => true
            }
          ],
          "map-viewer.EMBED.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni_web/controllers/embed_controller.ex:23",
              "loc" => "23:5",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni_web/controllers/embed_controller_test.exs:12",
              "loc" => "12:2",
              "is_test" => true
            }
          ],
          "map-viewer.SHARE.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni/sharing/share_service.ex:67",
              "loc" => "67:10",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni/sharing/share_service_test.exs:29",
              "loc" => "29:1",
              "is_test" => true
            }
          ]
        },
        agent: "seeds",
        commit: "xyz789abc123",
        pushed_at: now
      },
      silent
    )

    # Site: form-editor refs - all 7 requirements
    form_editor_spec = find_spec.("form-editor")

    seed_spec_impl_ref(
      form_editor_spec,
      site_prod,
      %{
        refs: %{
          "form-editor.FIELDS.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni/forms/field_types.ex:34",
              "loc" => "34:8",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni/forms/field_types_test.exs:21",
              "loc" => "21:1",
              "is_test" => true
            }
          ],
          "form-editor.FIELDS.2" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni/forms/validation.ex:56",
              "loc" => "56:4",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni/forms/validation_test.exs:44",
              "loc" => "44:3",
              "is_test" => true
            }
          ],
          "form-editor.FIELDS.3" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "assets/js/field_reorder.js:78",
              "loc" => "78:12",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/assets/js/field_reorder_test.js:55",
              "loc" => "55:1",
              "is_test" => true
            }
          ],
          "form-editor.LOCATION.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni/forms/gps_capture.ex:23",
              "loc" => "23:6",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni/forms/gps_capture_test.exs:18",
              "loc" => "18:2",
              "is_test" => true
            }
          ],
          "form-editor.LOCATION.2" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni/forms/geofence.ex:89",
              "loc" => "89:15",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni/forms/geofence_test.exs:67",
              "loc" => "67:1",
              "is_test" => true
            }
          ],
          "form-editor.PREVIEW.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni_web/live/form_preview_live.ex:45",
              "loc" => "45:10",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni_web/live/form_preview_live_test.exs:33",
              "loc" => "33:3",
              "is_test" => true
            }
          ],
          "form-editor.CONDITIONAL.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "lib/mapperoni/forms/conditional_logic.ex:112",
              "loc" => "112:8",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-site",
              "path" => "test/mapperoni/forms/conditional_logic_test.exs:78",
              "loc" => "78:1",
              "is_test" => true
            }
          ]
        },
        agent: "seeds",
        commit: "form456xyz789",
        pushed_at: now
      },
      silent
    )

    # API: push-api refs - all 12 requirements
    push_api_spec = find_spec.("push-api")

    seed_spec_impl_ref(
      push_api_spec,
      api_prod,
      %{
        refs: %{
          "push-api.SPEC.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "lib/mapperoni_api/controllers/push_controller.ex:56",
              "loc" => "56:10",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "test/mapperoni_api/controllers/push_controller_test.exs:34",
              "loc" => "34:1",
              "is_test" => true
            }
          ],
          "push-api.SPEC.2" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "lib/mapperoni_api/controllers/push_controller.ex:89",
              "loc" => "89:12",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "test/mapperoni_api/controllers/push_controller_test.exs:67",
              "loc" => "67:3",
              "is_test" => true
            }
          ],
          "push-api.SPEC.3" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "lib/mapperoni_api/services/spec_service.ex:23",
              "loc" => "23:8",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "test/mapperoni_api/services/spec_service_test.exs:45",
              "loc" => "45:2",
              "is_test" => true
            }
          ],
          "push-api.REF.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "lib/mapperoni_api/services/ref_service.ex:78",
              "loc" => "78:15",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "test/mapperoni_api/services/ref_service_test.exs:56",
              "loc" => "56:1",
              "is_test" => true
            }
          ],
          "push-api.REF.2" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "lib/mapperoni_api/validators/acid_validator.ex:45",
              "loc" => "45:6",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "test/mapperoni_api/validators/acid_validator_test.exs:33",
              "loc" => "33:3",
              "is_test" => true
            }
          ],
          "push-api.STATE.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "lib/mapperoni_api/services/state_service.ex:112",
              "loc" => "112:4",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "test/mapperoni_api/services/state_service_test.exs:89",
              "loc" => "89:1",
              "is_test" => true
            }
          ],
          "push-api.STATE.2" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "lib/mapperoni_api/services/state_service.ex:145",
              "loc" => "145:8",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "test/mapperoni_api/services/state_service_test.exs:112",
              "loc" => "112:2",
              "is_test" => true
            }
          ],
          "push-api.IMPL.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "lib/mapperoni_api/services/impl_service.ex:67",
              "loc" => "67:12",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "test/mapperoni_api/services/impl_service_test.exs:44",
              "loc" => "44:1",
              "is_test" => true
            }
          ],
          "push-api.IMPL.2" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "lib/mapperoni_api/services/impl_service.ex:98",
              "loc" => "98:6",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "test/mapperoni_api/services/impl_service_test.exs:67",
              "loc" => "67:3",
              "is_test" => true
            }
          ],
          "push-api.INHERIT.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "lib/mapperoni_api/services/inheritance_service.ex:34",
              "loc" => "34:10",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "test/mapperoni_api/services/inheritance_service_test.exs:23",
              "loc" => "23:1",
              "is_test" => true
            }
          ],
          "push-api.INHERIT.2" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "lib/mapperoni_api/services/inheritance_service.ex:78",
              "loc" => "78:15",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "test/mapperoni_api/services/inheritance_service_test.exs:56",
              "loc" => "56:2",
              "is_test" => true
            }
          ],
          "push-api.TX.1" => [
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "lib/mapperoni_api/transaction.ex:123",
              "loc" => "123:8",
              "is_test" => false
            },
            %{
              "repo" => "github.com/mapperoni/mapperoni-api",
              "path" => "test/mapperoni_api/transaction_test.exs:78",
              "loc" => "78:1",
              "is_test" => true
            }
          ]
        },
        agent: "seeds",
        commit: "def789abc012",
        pushed_at: now
      },
      silent
    )

    :ok
  end

  defp seed_spec_impl_ref(spec, implementation, attrs, silent) do
    defaults = %{
      refs: %{},
      agent: "seeds",
      commit: "abc123",
      pushed_at: DateTime.utc_now(),
      spec_id: spec.id,
      implementation_id: implementation.id
    }

    attrs = Map.merge(defaults, attrs)

    existing =
      Repo.one(
        from sir in SpecImplRef,
          where: sir.spec_id == ^spec.id and sir.implementation_id == ^implementation.id
      )

    if existing do
      unless silent do
        IO.puts(
          "SpecImplRef already exists for spec #{spec.feature_name} and implementation #{implementation.name}"
        )
      end

      existing
    else
      {:ok, ref} = Repo.insert(SpecImplRef.changeset(%SpecImplRef{}, attrs))

      unless silent do
        IO.puts("Created spec_impl_ref for spec #{spec.feature_name}")
      end

      ref
    end
  end
end
