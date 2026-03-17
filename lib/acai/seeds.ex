defmodule Acai.Seeds do
  @moduledoc """
  Database seeding functionality for the seed-data feature spec.

  This module creates the foundational data set for the mapperoni team:
  - Users: owner, developer, readonly (all confirmed with password "password123456")
  - Team: mapperoni
  - Products: site (with description), api (without description)
  - Implementations: site has 4, api has 2, with proper inheritance graph
  - Tracked branches: linking implementations to repo branches
  - Access tokens: 3 for developer, 1 for owner, 0 for readonly
  - Specs: api (core, mcp), site (map-editor, form-editor, ai-chat, map-settings)
  - Implementation states: realistic journeys for all features
  - Branch refs: realistic code references with variety

  All seeding operations are idempotent - running multiple times converges
  to the same state without creating duplicates.
  """

  import Ecto.Query

  alias Acai.Repo
  alias Acai.Accounts
  alias Acai.Accounts.User
  alias Acai.Teams.{Team, UserTeamRole, AccessToken}
  alias Acai.Teams.Permissions
  alias Acai.Products.Product
  alias Acai.Implementations
  alias Acai.Implementations.{Implementation, Branch, TrackedBranch}
  alias Acai.Specs.{Spec, FeatureImplState, FeatureBranchRef}

  # Deterministic raw tokens for idempotent token generation
  @seeded_tokens [
    # seed-data.TOKENS.1: developer has 3 access tokens
    %{email: "developer@mapperoni.com", name: "CLI Development", token_key: "dev_cli"},
    %{email: "developer@mapperoni.com", name: "IDE Integration", token_key: "dev_ide"},
    %{email: "developer@mapperoni.com", name: "CI/CD Pipeline", token_key: "dev_cicd"},
    # seed-data.TOKENS.2: owner has 1 access token
    %{email: "owner@mapperoni.com", name: "Admin Access", token_key: "owner_admin"}
  ]

  # ============================================================================
  # Spec Manifests (seed-data.SPECS.*)
  # ============================================================================

  # seed-data.SPECS.1: api product has 2 specs (core, mcp) on backend main branch
  # seed-data.SPECS.1-1: core has 10 requirements
  # seed-data.SPECS.1-2: mcp has 20 requirements
  @api_specs [
    %{
      feature_name: "core",
      feature_version: "1.0.0",
      feature_description: "Core API functionality for mapperoni services",
      path: "specs/core.feature.yaml",
      raw_content: "# Core API Feature Specification\n# 10 requirements for core functionality",
      requirements: %{
        "core.AUTH.1" => %{
          definition: "API must support JWT-based authentication",
          is_deprecated: false
        },
        "core.AUTH.2" => %{definition: "Tokens must expire after 24 hours", is_deprecated: false},
        "core.RATE.1" => %{
          definition: "API must enforce rate limiting per client",
          is_deprecated: false
        },
        "core.RATE.2" => %{
          definition: "Rate limits must be configurable per endpoint",
          is_deprecated: false
        },
        "core.LOG.1" => %{definition: "All API requests must be logged", is_deprecated: false},
        "core.LOG.2" => %{
          definition: "Logs must include request ID for tracing",
          is_deprecated: false
        },
        "core.HEALTH.1" => %{
          definition: "Health check endpoint must return 200",
          is_deprecated: false
        },
        "core.HEALTH.2" => %{
          definition: "Health check must verify database connectivity",
          is_deprecated: false
        },
        "core.CORS.1" => %{
          definition: "API must support CORS for browser clients",
          is_deprecated: false
        },
        "core.VERSION.1" => %{
          definition: "API version must be included in response headers",
          is_deprecated: false
        }
      },
      branch_key: :api_backend_main,
      product_name: "api"
    },
    %{
      feature_name: "mcp",
      feature_version: "1.0.0",
      feature_description: "Model Context Protocol service for map and survey data access",
      path: "specs/mcp.feature.yaml",
      raw_content: "# MCP Feature Specification\n# 20 requirements for MCP service",
      requirements: %{
        "mcp.MAP.1" => %{
          definition: "MCP must provide read access to map data",
          is_deprecated: false
        },
        "mcp.MAP.2" => %{
          definition: "MCP must provide write access to map data",
          is_deprecated: false
        },
        "mcp.MAP.3" => %{
          definition: "Map data queries must support pagination",
          is_deprecated: false
        },
        "mcp.MAP.4" => %{
          definition: "Map data must be filterable by bounding box",
          is_deprecated: false
        },
        "mcp.MAP.5" => %{definition: "Map data must support GeoJSON format", is_deprecated: false},
        "mcp.FORM.1" => %{
          definition: "MCP must provide read access to survey form data",
          is_deprecated: false
        },
        "mcp.FORM.2" => %{
          definition: "MCP must provide write access to survey form data",
          is_deprecated: false
        },
        "mcp.FORM.3" => %{definition: "Form data must support versioning", is_deprecated: false},
        "mcp.FORM.4" => %{definition: "Form submissions must be validated", is_deprecated: false},
        "mcp.FORM.5" => %{
          definition: "Form data must support conditional logic",
          is_deprecated: false
        },
        "mcp.SYNC.1" => %{
          definition: "MCP must support real-time data synchronization",
          is_deprecated: false
        },
        "mcp.SYNC.2" => %{definition: "Sync conflicts must be resolvable", is_deprecated: false},
        "mcp.SYNC.3" => %{definition: "Offline changes must queue for sync", is_deprecated: false},
        "mcp.PERF.1" => %{
          definition: "Map queries must complete within 100ms",
          is_deprecated: false
        },
        "mcp.PERF.2" => %{
          definition: "Form queries must complete within 50ms",
          is_deprecated: false
        },
        "mcp.AUTH.1" => %{definition: "MCP must validate API tokens", is_deprecated: false},
        "mcp.AUTH.2" => %{definition: "MCP must enforce role-based access", is_deprecated: false},
        "mcp.CACHE.1" => %{
          definition: "Frequently accessed maps must be cached",
          is_deprecated: false
        },
        "mcp.CACHE.2" => %{
          definition: "Cache invalidation must be supported",
          is_deprecated: false
        },
        "mcp.EXPORT.1" => %{definition: "MCP must support data export", is_deprecated: false}
      },
      branch_key: :api_backend_main,
      product_name: "api"
    }
  ]

  # ============================================================================
  # Implementation State Manifests (seed-data.IMPL_STATES.*)
  # States are keyed by (implementation_id, feature_name) - not by spec version
  # ============================================================================

  @impl_states [
    # seed-data.IMPL_STATES.1: api / Production - all ACIDs for all features have `accepted` state
    # Core feature states
    %{
      product_name: "api",
      impl_name: "Production",
      feature_name: "core",
      states: %{
        "core.AUTH.1" => %{status: "accepted"},
        "core.AUTH.2" => %{status: "accepted"},
        "core.RATE.1" => %{status: "accepted"},
        "core.RATE.2" => %{status: "accepted"},
        "core.LOG.1" => %{status: "accepted"},
        "core.LOG.2" => %{status: "accepted"},
        "core.HEALTH.1" => %{status: "accepted"},
        "core.HEALTH.2" => %{status: "accepted"},
        "core.CORS.1" => %{status: "accepted"},
        "core.VERSION.1" => %{status: "accepted"}
      }
    },
    # MCP feature states
    %{
      product_name: "api",
      impl_name: "Production",
      feature_name: "mcp",
      states: %{
        "mcp.MAP.1" => %{status: "accepted"},
        "mcp.MAP.2" => %{status: "accepted"},
        "mcp.MAP.3" => %{status: "accepted"},
        "mcp.MAP.4" => %{status: "accepted"},
        "mcp.MAP.5" => %{status: "accepted"},
        "mcp.FORM.1" => %{status: "accepted"},
        "mcp.FORM.2" => %{status: "accepted"},
        "mcp.FORM.3" => %{status: "accepted"},
        "mcp.FORM.4" => %{status: "accepted"},
        "mcp.FORM.5" => %{status: "accepted"},
        "mcp.SYNC.1" => %{status: "accepted"},
        "mcp.SYNC.2" => %{status: "accepted"},
        "mcp.SYNC.3" => %{status: "accepted"},
        "mcp.PERF.1" => %{status: "accepted"},
        "mcp.PERF.2" => %{status: "accepted"},
        "mcp.AUTH.1" => %{status: "accepted"},
        "mcp.AUTH.2" => %{status: "accepted"},
        "mcp.CACHE.1" => %{status: "accepted"},
        "mcp.CACHE.2" => %{status: "accepted"},
        "mcp.EXPORT.1" => %{status: "accepted"}
      }
    },
    # seed-data.IMPL_STATES.2: api / Staging - no states for any feature (all inherited)
    # Intentionally omitted for both core and mcp features to test inheritance

    # seed-data.IMPL_STATES.3: site / map-editor / Production — all ACIDs have `accepted` state
    %{
      product_name: "site",
      impl_name: "Production",
      feature_name: "map-editor",
      states: %{
        "map-editor.UI.1" => %{status: "accepted"},
        "map-editor.UI.2" => %{status: "accepted"},
        "map-editor.UI.3" => %{status: "accepted"},
        "map-editor.DRAW.1" => %{status: "accepted"},
        "map-editor.DRAW.2" => %{status: "accepted"},
        "map-editor.EDIT.1" => %{status: "accepted"},
        "map-editor.SAVE.1" => %{status: "accepted"},
        "map-editor.EXPORT.1" => %{status: "accepted"}
      }
    },
    # seed-data.IMPL_STATES.3-note: site / map-editor does NOT have states on Staging, feat/ai-chat, or fix-map-settings
    # Intentionally omitted for those implementations

    # seed-data.IMPL_STATES.4: site / form-editor / Production — all ACIDs have `accepted` state
    %{
      product_name: "site",
      impl_name: "Production",
      feature_name: "form-editor",
      states: %{
        "form-editor.UI.1" => %{status: "accepted"},
        "form-editor.UI.2" => %{status: "accepted"},
        "form-editor.FIELD.1" => %{status: "accepted"},
        "form-editor.FIELD.2" => %{status: "accepted"},
        "form-editor.FIELD.3" => %{status: "accepted"},
        "form-editor.LOGIC.1" => %{status: "accepted"},
        "form-editor.PREVIEW.1" => %{status: "accepted"},
        "form-editor.PUBLISH.1" => %{status: "accepted"}
      }
    },
    # seed-data.IMPL_STATES.4-1: site / form-editor / Staging — all ACIDs have `accepted` state
    %{
      product_name: "site",
      impl_name: "Staging",
      feature_name: "form-editor",
      states: %{
        "form-editor.UI.1" => %{status: "accepted"},
        "form-editor.UI.2" => %{status: "accepted"},
        "form-editor.FIELD.1" => %{status: "accepted"},
        "form-editor.FIELD.2" => %{status: "accepted"},
        "form-editor.FIELD.3" => %{status: "accepted"},
        "form-editor.LOGIC.1" => %{status: "accepted"},
        "form-editor.PREVIEW.1" => %{status: "accepted"},
        "form-editor.PUBLISH.1" => %{status: "accepted"}
      }
    },
    # seed-data.IMPL_STATES.4-note: site / form-editor does NOT have states on feat/ai-chat or fix-map-settings
    # Intentionally omitted for those implementations

    # seed-data.IMPL_STATES.5: site / ai-chat / feat/ai-chat — mix of null, assigned, and completed states
    %{
      product_name: "site",
      impl_name: "feat/ai-chat",
      feature_name: "ai-chat",
      states: %{
        # null status - omitted from map (ai-chat.UI.1, ai-chat.UI.2)
        # assigned status
        "ai-chat.INPUT.1" => %{status: "assigned"},
        "ai-chat.INPUT.2" => %{status: "assigned"},
        # completed status
        "ai-chat.AI.1" => %{status: "completed"},
        "ai-chat.AI.2" => %{status: "completed"},
        "ai-chat.ACTION.1" => %{status: "completed"},
        "ai-chat.ACTION.2" => %{status: "completed"},
        "ai-chat.FEEDBACK.1" => %{status: "completed"}
      }
    },
    # seed-data.IMPL_STATES.5-note: site / ai-chat does NOT have states on Production, Staging, or fix-map-settings
    # Intentionally omitted for those implementations

    # seed-data.IMPL_STATES.6: site / map-settings / Production — all accepted and 1 completed ACID
    %{
      product_name: "site",
      impl_name: "Production",
      feature_name: "map-settings",
      states: %{
        "map-settings.UI.1" => %{status: "accepted"},
        "map-settings.BASEMAP.1" => %{status: "accepted"},
        "map-settings.LAYERS.1" => %{status: "accepted"},
        "map-settings.LAYERS.2" => %{status: "completed"},
        "map-settings.PERMISSIONS.1" => %{status: "accepted"},
        "map-settings.SHARE.1" => %{status: "accepted"}
      }
    },
    # seed-data.IMPL_STATES.6-1: site / map-settings / fix-map-settings — all accepted and 1 completed ACID
    %{
      product_name: "site",
      impl_name: "fix-map-settings",
      feature_name: "map-settings",
      states: %{
        "map-settings.UI.1" => %{status: "accepted"},
        "map-settings.BASEMAP.1" => %{status: "accepted"},
        "map-settings.LAYERS.1" => %{status: "accepted"},
        "map-settings.LAYERS.2" => %{status: "completed"},
        "map-settings.PERMISSIONS.1" => %{status: "accepted"},
        "map-settings.PERMISSIONS.2" => %{status: "accepted"},
        "map-settings.SHARE.1" => %{status: "accepted"}
      }
    }
    # seed-data.IMPL_STATES.6-note: site / map-settings does NOT have states on Staging or feat/ai-chat
    # Intentionally omitted for those implementations
  ]

  # ============================================================================
  # Branch Ref Manifests (seed-data.REFS.*)
  # Refs are keyed by (branch_id, feature_name) - not by spec version
  # ============================================================================

  @branch_refs [
    # seed-data.REFS.1: backend main - every ACID in api features has at least 1 ref
    %{
      branch_key: :api_backend_main,
      feature_name: "core",
      commit: "e1f2a3b4c5d6",
      refs: %{
        "core.AUTH.1" => [%{path: "lib/api/auth.ex:42", is_test: false}],
        "core.AUTH.2" => [%{path: "lib/api/auth.ex:55", is_test: false}],
        "core.RATE.1" => [%{path: "lib/api/rate_limiter.ex:30", is_test: false}],
        "core.RATE.2" => [%{path: "lib/api/rate_limiter.ex:45", is_test: false}],
        "core.LOG.1" => [%{path: "lib/api/logger.ex:12", is_test: false}],
        "core.LOG.2" => [%{path: "lib/api/logger.ex:28", is_test: false}],
        "core.HEALTH.1" => [%{path: "lib/api/health.ex:10", is_test: false}],
        "core.HEALTH.2" => [%{path: "lib/api/health.ex:25", is_test: false}],
        "core.CORS.1" => [%{path: "lib/api/cors.ex:15", is_test: false}],
        "core.VERSION.1" => [%{path: "lib/api/version.ex:8", is_test: false}]
      }
    },
    %{
      branch_key: :api_backend_main,
      feature_name: "mcp",
      commit: "e1f2a3b4c5d6",
      refs: %{
        "mcp.MAP.1" => [%{path: "lib/mcp/map.ex:30", is_test: false}],
        "mcp.MAP.2" => [%{path: "lib/mcp/map.ex:45", is_test: false}],
        "mcp.MAP.3" => [%{path: "lib/mcp/map.ex:60", is_test: false}],
        "mcp.MAP.4" => [%{path: "lib/mcp/map.ex:75", is_test: false}],
        "mcp.MAP.5" => [%{path: "lib/mcp/map.ex:90", is_test: false}],
        "mcp.FORM.1" => [%{path: "lib/mcp/form.ex:25", is_test: false}],
        "mcp.FORM.2" => [%{path: "lib/mcp/form.ex:40", is_test: false}],
        "mcp.FORM.3" => [%{path: "lib/mcp/form.ex:55", is_test: false}],
        "mcp.FORM.4" => [%{path: "lib/mcp/form.ex:70", is_test: false}],
        "mcp.FORM.5" => [%{path: "lib/mcp/form.ex:85", is_test: false}],
        "mcp.SYNC.1" => [%{path: "lib/mcp/sync.ex:20", is_test: false}],
        "mcp.SYNC.2" => [%{path: "lib/mcp/sync.ex:35", is_test: false}],
        "mcp.SYNC.3" => [%{path: "lib/mcp/sync.ex:50", is_test: false}],
        "mcp.PERF.1" => [%{path: "lib/mcp/benchmarks.ex:15", is_test: true}],
        "mcp.PERF.2" => [%{path: "lib/mcp/benchmarks.ex:30", is_test: true}],
        "mcp.AUTH.1" => [%{path: "lib/mcp/auth.ex:22", is_test: false}],
        "mcp.AUTH.2" => [%{path: "lib/mcp/auth.ex:38", is_test: false}],
        "mcp.CACHE.1" => [%{path: "lib/mcp/cache.ex:18", is_test: false}],
        "mcp.CACHE.2" => [%{path: "lib/mcp/cache.ex:35", is_test: false}],
        "mcp.EXPORT.1" => [%{path: "lib/mcp/export.ex:12", is_test: false}]
      }
    },

    # seed-data.REFS.2: feat/ai-chat - completed requirements have refs, null status do not
    # Completed ACIDs: ai-chat.AI.1, ai-chat.AI.2, ai-chat.ACTION.1, ai-chat.ACTION.2, ai-chat.FEEDBACK.1
    %{
      branch_key: :site_frontend_feat_ai,
      feature_name: "ai-chat",
      commit: "c3d4e5f6a7b8",
      refs: %{
        "ai-chat.AI.1" => [%{path: "src/components/ai/ChatAI.tsx:45", is_test: false}],
        "ai-chat.AI.2" => [%{path: "src/components/ai/ChatAI.tsx:67", is_test: false}],
        "ai-chat.ACTION.1" => [%{path: "src/components/ai/Actions.tsx:23", is_test: false}],
        "ai-chat.ACTION.2" => [%{path: "src/components/ai/Actions.tsx:56", is_test: false}],
        "ai-chat.FEEDBACK.1" => [
          %{path: "src/components/ai/Feedback.tsx:34", is_test: false},
          %{path: "test/ai/Feedback.test.tsx:12", is_test: true}
        ]
        # ai-chat.UI.1, ai-chat.UI.2, ai-chat.INPUT.1, ai-chat.INPUT.2 intentionally omitted (null status)
      }
    },

    # seed-data.REFS.3: Other features with variety of refs (production and test refs)
    %{
      branch_key: :site_frontend_main,
      feature_name: "map-editor",
      commit: "a1b2c3d4e5f6",
      refs: %{
        "map-editor.UI.1" => [
          %{path: "src/components/map/Editor.tsx:30", is_test: false},
          %{path: "test/map/Editor.test.tsx:15", is_test: true}
        ],
        "map-editor.UI.2" => [%{path: "src/components/map/Controls.tsx:22", is_test: false}],
        "map-editor.UI.3" => [%{path: "src/components/map/Layers.tsx:40", is_test: false}],
        "map-editor.DRAW.1" => [%{path: "src/components/map/Drawing.tsx:55", is_test: false}],
        "map-editor.DRAW.2" => [%{path: "src/components/map/Drawing.tsx:78", is_test: false}],
        "map-editor.EDIT.1" => [
          %{path: "src/components/map/Editing.tsx:33", is_test: false},
          %{path: "test/map/Editing.test.tsx:20", is_test: true}
        ],
        "map-editor.SAVE.1" => [%{path: "src/services/map/save.ts:18", is_test: false}],
        "map-editor.EXPORT.1" => [%{path: "src/services/map/export.ts:25", is_test: false}]
      }
    },
    %{
      branch_key: :site_frontend_main,
      feature_name: "form-editor",
      commit: "a1b2c3d4e5f6",
      refs: %{
        "form-editor.UI.1" => [%{path: "src/components/form/Builder.tsx:42", is_test: false}],
        "form-editor.UI.2" => [%{path: "src/components/form/Builder.tsx:65", is_test: false}],
        "form-editor.FIELD.1" => [
          %{path: "src/components/form/fields/Text.tsx:28", is_test: false}
        ],
        "form-editor.FIELD.2" => [
          %{path: "src/components/form/fields/Number.tsx:30", is_test: false}
        ],
        "form-editor.FIELD.3" => [
          %{path: "src/components/form/fields/Select.tsx:35", is_test: false}
        ],
        "form-editor.LOGIC.1" => [
          %{path: "src/components/form/Logic.tsx:50", is_test: false},
          %{path: "test/form/Logic.test.tsx:25", is_test: true}
        ],
        "form-editor.PREVIEW.1" => [%{path: "src/components/form/Preview.tsx:38", is_test: false}],
        "form-editor.PUBLISH.1" => [%{path: "src/services/form/publish.ts:22", is_test: false}]
      }
    },
    %{
      branch_key: :site_frontend_dev,
      feature_name: "form-editor",
      commit: "b2c3d4e5f6a7",
      refs: %{
        "form-editor.UI.1" => [%{path: "src/components/form/Builder.tsx:45", is_test: false}],
        "form-editor.FIELD.4" => [
          %{path: "src/components/form/fields/FileUpload.tsx:40", is_test: false},
          %{path: "test/form/FileUpload.test.tsx:18", is_test: true}
        ],
        "form-editor.VALIDATE.1" => [
          %{path: "src/components/form/Validation.tsx:55", is_test: false}
        ]
      }
    },
    %{
      branch_key: :site_frontend_fix_map,
      feature_name: "map-settings",
      commit: "d4e5f6a7b8c9",
      refs: %{
        "map-settings.UI.1" => [%{path: "src/components/settings/Panel.tsx:35", is_test: false}],
        "map-settings.BASEMAP.1" => [
          %{path: "src/components/settings/Basemap.tsx:42", is_test: false}
        ],
        "map-settings.LAYERS.1" => [
          %{path: "src/components/settings/Layers.tsx:50", is_test: false}
        ],
        "map-settings.LAYERS.2" => [
          %{path: "src/components/settings/LayerOrder.tsx:28", is_test: false},
          %{path: "test/settings/LayerOrder.test.tsx:22", is_test: true}
        ],
        "map-settings.PERMISSIONS.1" => [
          %{path: "src/components/settings/Permissions.tsx:60", is_test: false}
        ],
        "map-settings.PERMISSIONS.2" => [
          %{path: "src/components/settings/TeamPermissions.tsx:45", is_test: false}
        ],
        "map-settings.SHARE.1" => [%{path: "src/services/settings/share.ts:30", is_test: false}]
      }
    },

    # seed-data.REFS.4: Dangling refs - ACIDs not associated with any seeded spec
    %{
      branch_key: :site_frontend_main,
      feature_name: "unimplemented-feature",
      commit: "a1b2c3d4e5f6",
      refs: %{
        "unimplemented-feature.CONCEPT.1" => [%{path: "docs/future/ideas.md:10", is_test: false}],
        "unimplemented-feature.CONCEPT.2" => [%{path: "docs/future/ideas.md:25", is_test: false}]
      }
    },
    %{
      branch_key: :api_backend_main,
      feature_name: "future-api",
      commit: "e1f2a3b4c5d6",
      refs: %{
        "future-api.IDEA.1" => [%{path: "docs/api/roadmap.md:15", is_test: false}]
      }
    }
  ]

  # seed-data.SPECS.3: site product has 6 spec versions for 4 features
  @site_specs [
    # seed-data.SPECS.3-1: map-editor has 1 spec version on main
    %{
      feature_name: "map-editor",
      feature_version: "1.0.0",
      feature_description: "Interactive map editing interface",
      path: "specs/map-editor.feature.yaml",
      raw_content: "# Map Editor Feature Specification",
      requirements: %{
        "map-editor.UI.1" => %{
          definition: "Map editor must display base layer",
          is_deprecated: false
        },
        "map-editor.UI.2" => %{
          definition: "Map editor must support zoom controls",
          is_deprecated: false
        },
        "map-editor.UI.3" => %{
          definition: "Map editor must support layer toggles",
          is_deprecated: false
        },
        "map-editor.DRAW.1" => %{
          definition: "User can draw polygons on map",
          is_deprecated: false
        },
        "map-editor.DRAW.2" => %{definition: "User can draw points on map", is_deprecated: false},
        "map-editor.EDIT.1" => %{
          definition: "User can edit existing shapes",
          is_deprecated: false
        },
        "map-editor.SAVE.1" => %{definition: "Changes must be savable", is_deprecated: false},
        "map-editor.EXPORT.1" => %{
          definition: "Maps must be exportable as images",
          is_deprecated: false
        }
      },
      branch_key: :site_frontend_main,
      product_name: "site"
    },
    # seed-data.SPECS.3-2: form-editor has 2 spec versions (main and dev)
    %{
      feature_name: "form-editor",
      feature_version: "1.0.0",
      feature_description: "Survey form builder interface",
      path: "specs/form-editor.feature.yaml",
      raw_content: "# Form Editor Feature Specification v1.0.0",
      requirements: %{
        "form-editor.UI.1" => %{
          definition: "Form editor must show field palette",
          is_deprecated: false
        },
        "form-editor.UI.2" => %{
          definition: "Form editor must support drag-drop",
          is_deprecated: false
        },
        "form-editor.FIELD.1" => %{definition: "Support text input fields", is_deprecated: false},
        "form-editor.FIELD.2" => %{
          definition: "Support number input fields",
          is_deprecated: false
        },
        "form-editor.FIELD.3" => %{
          definition: "Support select dropdown fields",
          is_deprecated: false
        },
        "form-editor.LOGIC.1" => %{
          definition: "Support conditional field visibility",
          is_deprecated: false
        },
        "form-editor.PREVIEW.1" => %{
          definition: "Form preview must be available",
          is_deprecated: false
        },
        "form-editor.PUBLISH.1" => %{
          definition: "Forms must be publishable",
          is_deprecated: false
        }
      },
      branch_key: :site_frontend_main,
      product_name: "site"
    },
    %{
      feature_name: "form-editor",
      feature_version: "1.1.0",
      feature_description: "Survey form builder interface (dev version)",
      path: "specs/form-editor.feature.yaml",
      raw_content: "# Form Editor Feature Specification v1.1.0",
      requirements: %{
        "form-editor.UI.1" => %{
          definition: "Form editor must show field palette",
          is_deprecated: false
        },
        "form-editor.UI.2" => %{
          definition: "Form editor must support drag-drop",
          is_deprecated: false
        },
        "form-editor.FIELD.1" => %{definition: "Support text input fields", is_deprecated: false},
        "form-editor.FIELD.2" => %{
          definition: "Support number input fields",
          is_deprecated: false
        },
        "form-editor.FIELD.3" => %{
          definition: "Support select dropdown fields",
          is_deprecated: false
        },
        "form-editor.FIELD.4" => %{definition: "Support file upload fields", is_deprecated: false},
        "form-editor.LOGIC.1" => %{
          definition: "Support conditional field visibility",
          is_deprecated: false
        },
        "form-editor.PREVIEW.1" => %{
          definition: "Form preview must be available",
          is_deprecated: false
        },
        "form-editor.PUBLISH.1" => %{
          definition: "Forms must be publishable",
          is_deprecated: false
        },
        "form-editor.VALIDATE.1" => %{
          definition: "Custom validation rules supported",
          is_deprecated: false
        }
      },
      branch_key: :site_frontend_dev,
      product_name: "site"
    },
    # seed-data.SPECS.3-3: ai-chat has 1 spec version only on feat/ai-chat
    %{
      feature_name: "ai-chat",
      feature_version: "0.1.0",
      feature_description: "AI-powered chat interface for map assistance",
      path: "specs/ai-chat.feature.yaml",
      raw_content: "# AI Chat Feature Specification",
      requirements: %{
        "ai-chat.UI.1" => %{definition: "Chat interface must be accessible", is_deprecated: false},
        "ai-chat.UI.2" => %{definition: "Chat must show message history", is_deprecated: false},
        "ai-chat.INPUT.1" => %{
          definition: "User can type natural language queries",
          is_deprecated: false
        },
        "ai-chat.INPUT.2" => %{definition: "Voice input must be supported", is_deprecated: false},
        "ai-chat.AI.1" => %{
          definition: "AI must understand map-related queries",
          is_deprecated: false
        },
        "ai-chat.AI.2" => %{
          definition: "AI must provide contextual responses",
          is_deprecated: false
        },
        "ai-chat.ACTION.1" => %{definition: "AI can trigger map actions", is_deprecated: false},
        "ai-chat.ACTION.2" => %{definition: "AI can create survey forms", is_deprecated: false},
        "ai-chat.FEEDBACK.1" => %{definition: "Users can rate AI responses", is_deprecated: false}
      },
      branch_key: :site_frontend_feat_ai,
      product_name: "site"
    },
    # seed-data.SPECS.3-4: map-settings has 2 spec versions (main and fix-map-settings)
    %{
      feature_name: "map-settings",
      feature_version: "1.0.0",
      feature_description: "Map configuration and settings panel",
      path: "specs/map-settings.feature.yaml",
      raw_content: "# Map Settings Feature Specification v1.0.0",
      requirements: %{
        "map-settings.UI.1" => %{
          definition: "Settings panel must be accessible",
          is_deprecated: false
        },
        "map-settings.BASEMAP.1" => %{
          definition: "User can change basemap style",
          is_deprecated: false
        },
        "map-settings.LAYERS.1" => %{
          definition: "User can manage layer visibility",
          is_deprecated: false
        },
        "map-settings.LAYERS.2" => %{definition: "User can reorder layers", is_deprecated: false},
        "map-settings.PERMISSIONS.1" => %{
          definition: "Map permissions can be configured",
          is_deprecated: false
        },
        "map-settings.SHARE.1" => %{
          definition: "Maps can be shared via link",
          is_deprecated: false
        }
      },
      branch_key: :site_frontend_main,
      product_name: "site"
    },
    %{
      feature_name: "map-settings",
      feature_version: "1.0.1",
      feature_description: "Map configuration and settings panel (fix version)",
      path: "specs/map-settings.feature.yaml",
      raw_content: "# Map Settings Feature Specification v1.0.1",
      requirements: %{
        "map-settings.UI.1" => %{
          definition: "Settings panel must be accessible",
          is_deprecated: false
        },
        "map-settings.BASEMAP.1" => %{
          definition: "User can change basemap style",
          is_deprecated: false
        },
        "map-settings.LAYERS.1" => %{
          definition: "User can manage layer visibility",
          is_deprecated: false
        },
        "map-settings.LAYERS.2" => %{definition: "User can reorder layers", is_deprecated: false},
        "map-settings.PERMISSIONS.1" => %{
          definition: "Map permissions can be configured",
          is_deprecated: false
        },
        "map-settings.PERMISSIONS.2" => %{
          definition: "Team permissions supported",
          is_deprecated: false
        },
        "map-settings.SHARE.1" => %{
          definition: "Maps can be shared via link",
          is_deprecated: false
        }
      },
      branch_key: :site_frontend_fix_map,
      product_name: "site"
    }
  ]

  @doc """
  Runs all seeds.

  ## Options

    * `:silent` - When `true`, suppresses all console output. Defaults to `false`.

  """
  def run(opts \\ []) do
    silent = Keyword.get(opts, :silent, false)

    # seed-data.ENVIRONMENT.1: Seed data runs automatically during devcontainer build
    # seed-data.ENVIRONMENT.2: Seeding must be idempotent

    users = seed_users(silent)
    team = seed_team("mapperoni", silent)
    seed_roles(team, users, silent)

    products = seed_products(team, silent)
    branches = seed_implementation_graph(team, products, silent)
    seed_access_tokens(team, users, silent)

    # Phase 2: Specs, States, and Refs
    seed_specs(team, products, branches, silent)
    seed_impl_states(team, products, silent)
    seed_branch_refs(team, branches, silent)

    unless silent do
      IO.puts("\n=== Seeding Complete ===")
      IO.puts("")
      IO.puts("Sample data created:")
      IO.puts("  - Users: owner@mapperoni.com, developer@mapperoni.com, readonly@mapperoni.com")
      IO.puts("  - Team: #{team.name}")
      IO.puts("  - Products: site, api")
      IO.puts("  - Site Implementations: Production, Staging, feat/ai-chat, fix-map-settings")
      IO.puts("  - API Implementations: Production, Staging")
      IO.puts("  - Access Tokens: 3 for developer, 1 for owner, 0 for readonly")
      IO.puts("  - Specs: api (core, mcp), site (map-editor, form-editor, ai-chat, map-settings)")
      IO.puts("  - Implementation States: Realistic journeys for all features")
      IO.puts("  - Branch Refs: References with variety across branches")
      IO.puts("")
      IO.puts("All passwords are: password123456")
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

    # seed-data.USERS.1: Pregenerate the 3 required user accounts
    users = [
      seed_user("owner@mapperoni.com", silent),
      seed_user("developer@mapperoni.com", silent),
      seed_user("readonly@mapperoni.com", silent)
    ]

    users
  end

  defp seed_user(email, silent) do
    case Accounts.get_user_by_email(email) do
      nil ->
        # seed-data.USERS.2: All users have password "password123456"
        # seed-data.USERS.3: All users have confirmed emails
        # Do NOT use Accounts.register_user/1 as it only uses email_changeset
        {:ok, user} =
          %User{}
          |> User.email_changeset(%{email: email})
          |> Repo.insert!()
          |> User.password_changeset(%{password: "password123456"})
          |> Repo.update()
          |> case do
            {:ok, user} -> User.confirm_changeset(user) |> Repo.update()
            error -> error
          end

        unless silent do
          IO.puts("Created user: #{email}")
        end

        user

      existing_user ->
        # Converge existing user to required state
        existing_user = converge_user_credentials(existing_user, silent)

        unless silent do
          IO.puts("User already exists (converged): #{email}")
        end

        existing_user
    end
  end

  # Converges an existing user to the required seed state
  # seed-data.USERS.2: Ensure password is "password123456"
  # seed-data.USERS.3: Ensure user is confirmed
  defp converge_user_credentials(user, silent) do
    user = Repo.preload(user, [])

    # Check if password needs updating
    needs_password = not User.valid_password?(user, "password123456")

    # Check if confirmation is needed
    needs_confirmation = is_nil(user.confirmed_at)

    cond do
      needs_password or needs_confirmation ->
        user =
          if needs_password do
            {:ok, updated} =
              user
              |> User.password_changeset(%{password: "password123456"})
              |> Repo.update()

            unless silent do
              IO.puts("  -> Updated password for #{user.email}")
            end

            updated
          else
            user
          end

        user =
          if needs_confirmation do
            {:ok, confirmed} =
              user
              |> User.confirm_changeset()
              |> Repo.update()

            unless silent do
              IO.puts("  -> Confirmed #{user.email}")
            end

            confirmed
          else
            user
          end

        user

      true ->
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

    # seed-data.USERS.4: Generates one team called "mapperoni"
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

  defp seed_roles(team, users, silent) do
    unless silent do
      IO.puts("\n=== Seeding Roles ===")
    end

    # seed-data.USERS.5: All 3 users have their assigned role in this team
    roles_map = %{
      "owner@mapperoni.com" => "owner",
      "developer@mapperoni.com" => "developer",
      "readonly@mapperoni.com" => "readonly"
    }

    Enum.each(users, fn user ->
      role_title = Map.get(roles_map, user.email)
      seed_role(team, user, role_title, silent)
    end)
  end

  defp seed_role(team, user, title, silent) do
    existing =
      Repo.one(from r in UserTeamRole, where: r.team_id == ^team.id and r.user_id == ^user.id)

    if existing do
      # Reconcile incorrect existing roles
      if existing.title != title do
        # Use update_all since UserTeamRole has no primary key
        {1, _} =
          from(r in UserTeamRole,
            where: r.team_id == ^team.id and r.user_id == ^user.id
          )
          |> Repo.update_all(set: [title: title])

        unless silent do
          IO.puts("Updated role for #{user.email} to #{title} in team #{team.name}")
        end

        # Return the updated role
        Repo.one!(from r in UserTeamRole, where: r.team_id == ^team.id and r.user_id == ^user.id)
      else
        unless silent do
          IO.puts("Role already exists for user #{user.email} in team #{team.name}")
        end

        existing
      end
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

    # seed-data.PRODUCTS.1: Create 2 products: api and site
    # seed-data.PRODUCTS.2: site has description, api does not

    site_product =
      seed_product(
        team,
        "site",
        %{description: "Mapperoni web application - map-based survey builder and viewer"},
        silent
      )

    api_product =
      seed_product(
        team,
        "api",
        %{description: nil},
        silent
      )

    [site_product, api_product]
  end

  defp seed_product(team, name, attrs, silent) do
    existing = Repo.one(from p in Product, where: p.team_id == ^team.id and p.name == ^name)

    if existing do
      # Reconcile product description
      if existing.description != attrs.description do
        {:ok, updated} =
          existing
          |> Product.changeset(%{description: attrs.description})
          |> Repo.update()

        unless silent do
          IO.puts("Updated product description: #{name} in team #{team.name}")
        end

        updated
      else
        unless silent do
          IO.puts("Product already exists: #{name} in team #{team.name}")
        end

        existing
      end
    else
      attrs =
        Map.merge(
          %{
            name: name,
            description: attrs.description,
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
  # Implementation Graph Seeding
  # ---------------------------------------------------------------------------

  defp seed_implementation_graph(team, [site_product, api_product], silent) do
    unless silent do
      IO.puts("\n=== Seeding Implementation Graph ===")
    end

    # Create branch identities first (team-scoped)
    branches = seed_branch_identities(team, silent)

    # Site implementations with inheritance
    # seed-data.IMPLS.1: site has 4 implementations
    site_prod = seed_site_production(team, site_product, branches, silent)
    site_staging = seed_site_staging(team, site_product, site_prod, branches, silent)
    _site_feat_ai = seed_site_feat_ai_chat(team, site_product, site_staging, branches, silent)
    _site_fix_map = seed_site_fix_map_settings(team, site_product, site_staging, branches, silent)

    # API implementations with inheritance
    # seed-data.IMPLS.2: api has 2 implementations
    api_prod = seed_api_production(team, api_product, branches, silent)
    _api_staging = seed_api_staging(team, api_product, api_prod, branches, silent)

    # Return branches map for use by Phase 2 seeders
    branches
  end

  # ---------------------------------------------------------------------------
  # Branch Identity Seeding
  # ---------------------------------------------------------------------------

  defp seed_branch_identities(team, silent) do
    unless silent do
      IO.puts("\n=== Seeding Branch Identities ===")
    end

    # Create stable repo URIs
    repo_frontend = "github.com/mapperoni/frontend"
    repo_backend = "github.com/mapperoni/backend"
    repo_microservices = "github.com/mapperoni/microservices"

    # Site repos need: main, dev, feat/ai-chat, fix-map-settings, fix-#123, refactor/map-settings-compat
    # API repos need: main, dev

    %{
      # Site - frontend repo branches
      site_frontend_main:
        get_or_create_branch(team, repo_frontend, "main", "a1b2c3d4e5f6", silent),
      site_frontend_dev: get_or_create_branch(team, repo_frontend, "dev", "b2c3d4e5f6a7", silent),
      site_frontend_feat_ai:
        get_or_create_branch(team, repo_frontend, "feat/ai-chat", "c3d4e5f6a7b8", silent),
      site_frontend_fix_map:
        get_or_create_branch(team, repo_frontend, "fix-map-settings", "d4e5f6a7b8c9", silent),

      # Site - backend repo branches
      site_backend_main: get_or_create_branch(team, repo_backend, "main", "e5f6a7b8c9d0", silent),
      site_backend_dev: get_or_create_branch(team, repo_backend, "dev", "f6a7b8c9d0e1", silent),
      site_backend_fix_123:
        get_or_create_branch(team, repo_backend, "fix-#123", "a7b8c9d0e1f2", silent),
      site_backend_refactor:
        get_or_create_branch(
          team,
          repo_backend,
          "refactor/map-settings-compat",
          "b8c9d0e1f2a3",
          silent
        ),

      # Site - microservices repo branches
      site_microservices_main:
        get_or_create_branch(team, repo_microservices, "main", "c9d0e1f2a3b4", silent),
      site_microservices_dev:
        get_or_create_branch(team, repo_microservices, "dev", "d0e1f2a3b4c5", silent),
      site_microservices_refactor:
        get_or_create_branch(
          team,
          repo_microservices,
          "refactor/map-settings-compat",
          "e1f2a3b4c5d6",
          silent
        ),

      # API - backend repo branches (same repo as site backend but different usage)
      api_backend_main: get_or_create_branch(team, repo_backend, "main", "e1f2a3b4c5d6", silent),
      api_backend_dev: get_or_create_branch(team, repo_backend, "dev", "f2a3b4c5d6e7", silent)
    }
  end

  defp get_or_create_branch(team, repo_uri, branch_name, last_seen_commit, silent) do
    case Implementations.get_branch_by_identity(team.id, repo_uri, branch_name) do
      nil ->
        attrs = %{
          team_id: team.id,
          repo_uri: repo_uri,
          branch_name: branch_name,
          last_seen_commit: last_seen_commit
        }

        {:ok, branch} =
          %Branch{}
          |> Branch.changeset(attrs)
          |> Repo.insert()

        unless silent do
          IO.puts("Created branch: #{repo_uri}/#{branch_name}")
        end

        branch

      existing ->
        # Update last_seen_commit to ensure convergence
        {:ok, updated} =
          existing
          |> Branch.changeset(%{last_seen_commit: last_seen_commit})
          |> Repo.update()

        unless silent do
          IO.puts("Branch exists (updated): #{repo_uri}/#{branch_name}")
        end

        updated
    end
  end

  # ---------------------------------------------------------------------------
  # Site Implementations
  # ---------------------------------------------------------------------------

  # seed-data.IMPLS.1-2: Production tracks branches main, main, and main (for 3 repos)
  defp seed_site_production(team, product, branches, silent) do
    impl =
      seed_implementation(
        team,
        product,
        %{name: "Production", description: "Production environment for mapperoni site"},
        nil,
        silent
      )

    # seed-data.IMPLS.1-1: Each implementation tracks 3 github repos
    # Production: frontend/main, backend/main, microservices/main
    seed_tracked_branch(impl, branches.site_frontend_main, silent)
    seed_tracked_branch(impl, branches.site_backend_main, silent)
    seed_tracked_branch(impl, branches.site_microservices_main, silent)

    impl
  end

  # seed-data.IMPLS.1-3: Staging tracks branches dev, dev, and dev
  # seed-data.IMPLS.1-7: Staging inherits from Production
  defp seed_site_staging(team, product, parent_impl, branches, silent) do
    impl =
      seed_implementation(
        team,
        product,
        %{name: "Staging", description: "Staging environment for mapperoni site"},
        parent_impl.id,
        silent
      )

    # Staging: frontend/dev, backend/dev, microservices/dev
    seed_tracked_branch(impl, branches.site_frontend_dev, silent)
    seed_tracked_branch(impl, branches.site_backend_dev, silent)
    seed_tracked_branch(impl, branches.site_microservices_dev, silent)

    impl
  end

  # seed-data.IMPLS.1-4: feat/ai-chat tracks branches feat/ai-chat, dev, and dev
  # seed-data.IMPLS.1-6: feat/ai-chat inherits from Staging
  defp seed_site_feat_ai_chat(team, product, parent_impl, branches, silent) do
    impl =
      seed_implementation(
        team,
        product,
        %{name: "feat/ai-chat", description: "Feature branch for AI chat integration"},
        parent_impl.id,
        silent
      )

    # feat/ai-chat: frontend/feat/ai-chat, backend/dev, microservices/dev
    seed_tracked_branch(impl, branches.site_frontend_feat_ai, silent)
    seed_tracked_branch(impl, branches.site_backend_dev, silent)
    seed_tracked_branch(impl, branches.site_microservices_dev, silent)

    impl
  end

  # seed-data.IMPLS.1-5: fix-map-settings tracks branches fix-map-settings, fix-#123, and refactor/map-settings-compat
  # seed-data.IMPLS.1-6: fix-map-settings inherits from Staging
  defp seed_site_fix_map_settings(team, product, parent_impl, branches, silent) do
    impl =
      seed_implementation(
        team,
        product,
        %{name: "fix-map-settings", description: "Bug fix branch for map settings"},
        parent_impl.id,
        silent
      )

    # fix-map-settings: frontend/fix-map-settings, backend/fix-#123, microservices/refactor/map-settings-compat
    seed_tracked_branch(impl, branches.site_frontend_fix_map, silent)
    seed_tracked_branch(impl, branches.site_backend_fix_123, silent)
    seed_tracked_branch(impl, branches.site_microservices_refactor, silent)

    impl
  end

  # ---------------------------------------------------------------------------
  # API Implementations
  # ---------------------------------------------------------------------------

  # seed-data.IMPLS.2-1: Each api implementation tracks 1 github repo: backend
  defp seed_api_production(team, product, _branches, silent) do
    impl =
      seed_implementation(
        team,
        product,
        %{name: "Production", description: "Production environment for mapperoni API"},
        nil,
        silent
      )

    # API Production: backend/main
    # We'll create a branch for the API product specifically
    branch =
      get_or_create_branch(
        team,
        "github.com/mapperoni/api-backend",
        "main",
        "g3h4i5j6k7l8",
        silent
      )

    seed_tracked_branch(impl, branch, silent)

    impl
  end

  # seed-data.IMPLS.2-1: API Staging tracks backend/dev
  # seed-data.IMPLS.2-2: api Staging inherits from api Production
  defp seed_api_staging(team, product, parent_impl, _branches, silent) do
    impl =
      seed_implementation(
        team,
        product,
        %{name: "Staging", description: "Staging environment for mapperoni API"},
        parent_impl.id,
        silent
      )

    # API Staging: backend/dev
    branch =
      get_or_create_branch(
        team,
        "github.com/mapperoni/api-backend",
        "dev",
        "h4i5j6k7l8m9",
        silent
      )

    seed_tracked_branch(impl, branch, silent)

    impl
  end

  # ---------------------------------------------------------------------------
  # Implementation Helpers
  # ---------------------------------------------------------------------------

  defp seed_implementation(team, product, attrs, parent_id, silent) do
    defaults = %{
      name: "production",
      description: "Production environment",
      is_active: true,
      team_id: team.id,
      product_id: product.id,
      parent_implementation_id: parent_id
    }

    attrs = Map.merge(defaults, attrs)

    existing =
      Repo.one(
        from i in Implementation,
          where: i.product_id == ^product.id and i.name == ^attrs.name
      )

    if existing do
      # Reconcile existing implementation
      changes = %{}

      changes =
        if existing.description != attrs.description,
          do: Map.put(changes, :description, attrs.description),
          else: changes

      changes =
        if existing.parent_implementation_id != attrs.parent_implementation_id,
          do: Map.put(changes, :parent_implementation_id, attrs.parent_implementation_id),
          else: changes

      if changes != %{} do
        {:ok, updated} =
          existing
          |> Implementation.changeset(changes)
          |> Repo.update()

        unless silent do
          IO.puts("Updated implementation: #{attrs.name} for product #{product.name}")
        end

        updated
      else
        unless silent do
          IO.puts("Implementation already exists: #{attrs.name} for product #{product.name}")
        end

        existing
      end
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

  defp seed_tracked_branch(implementation, branch, silent) do
    defaults = %{
      repo_uri: branch.repo_uri,
      implementation_id: implementation.id,
      branch_id: branch.id
    }

    # The unique constraint is on [:implementation_id, :repo_uri]
    # so we look for existing by implementation + repo, not branch_id
    existing =
      Repo.one(
        from tb in TrackedBranch,
          where: tb.implementation_id == ^implementation.id,
          where: tb.repo_uri == ^branch.repo_uri
      )

    if existing do
      # Reconcile: update branch_id if different
      if existing.branch_id != branch.id do
        {:ok, updated} =
          existing
          |> Ecto.Changeset.change(branch_id: branch.id)
          |> Repo.update()

        unless silent do
          IO.puts(
            "Updated tracked branch: #{branch.repo_uri}/#{branch.branch_name} for #{implementation.name}"
          )
        end

        updated
      else
        unless silent do
          IO.puts(
            "Tracked branch already exists: #{branch.repo_uri}/#{branch.branch_name} for implementation #{implementation.name}"
          )
        end

        existing
      end
    else
      {:ok, tracked_branch} = Repo.insert(TrackedBranch.changeset(%TrackedBranch{}, defaults))

      unless silent do
        IO.puts(
          "Created tracked branch: #{branch.repo_uri}/#{branch.branch_name} for #{implementation.name}"
        )
      end

      tracked_branch
    end
  end

  # ---------------------------------------------------------------------------
  # Access Token Seeding
  # ---------------------------------------------------------------------------

  defp seed_access_tokens(team, users, silent) do
    unless silent do
      IO.puts("\n=== Seeding Access Tokens ===")
    end

    users_by_email = Enum.into(users, %{}, &{&1.email, &1})

    Enum.each(@seeded_tokens, fn token_config ->
      user = Map.get(users_by_email, token_config.email)
      seed_deterministic_token(team, user, token_config, silent)
    end)

    # Verify readonly has no tokens (seed-data.TOKENS.3)
    readonly_user = Map.get(users_by_email, "readonly@mapperoni.com")

    existing_readonly_tokens =
      Repo.all(from t in AccessToken, where: t.user_id == ^readonly_user.id)

    if existing_readonly_tokens != [] do
      # Delete any erroneous tokens for readonly
      Enum.each(existing_readonly_tokens, fn token ->
        Repo.delete!(token)

        unless silent do
          IO.puts("Deleted erroneous token for readonly user")
        end
      end)
    end
  end

  defp seed_deterministic_token(team, user, config, silent) do
    # Generate deterministic token values for idempotency
    # Format: seed_{token_key}_{user_id}
    raw_token = "seed_#{config.token_key}_#{user.id}"
    token_hash = Base.encode16(:crypto.hash(:sha256, raw_token), case: :lower)
    token_prefix = String.slice(raw_token, 0, 7)

    existing =
      Repo.one(
        from t in AccessToken,
          where: t.user_id == ^user.id and t.token_hash == ^token_hash
      )

    if existing do
      unless silent do
        IO.puts("Access token already exists: #{config.name} for #{user.email}")
      end

      existing
    else
      # Build the token struct with associations pre-set since changeset doesn't cast user_id/team_id
      token_struct = %AccessToken{
        user_id: user.id,
        team_id: team.id
      }

      attrs = %{
        name: config.name,
        token_hash: token_hash,
        token_prefix: token_prefix,
        scopes: Permissions.scopes_for(get_role_for_email(user.email)),
        expires_at: nil,
        revoked_at: nil
      }

      {:ok, token} = Repo.insert(AccessToken.changeset(token_struct, attrs))

      unless silent do
        IO.puts("Created access token: #{config.name} for #{user.email}")
      end

      token
    end
  end

  defp get_role_for_email(email) do
    case email do
      "owner@mapperoni.com" -> "owner"
      "developer@mapperoni.com" -> "developer"
      "readonly@mapperoni.com" -> "readonly"
      _ -> "readonly"
    end
  end

  # ---------------------------------------------------------------------------
  # Spec Seeding (Phase 2)
  # ---------------------------------------------------------------------------

  defp seed_specs(team, products, branches, silent) do
    unless silent do
      IO.puts("\n=== Seeding Specs ===")
    end

    products_by_name = Enum.into(products, %{}, &{&1.name, &1})

    # Seed API specs (seed-data.SPECS.1, seed-data.SPECS.1-1, seed-data.SPECS.1-2)
    Enum.each(@api_specs, fn spec_config ->
      product = Map.get(products_by_name, spec_config.product_name)
      branch = Map.get(branches, spec_config.branch_key)
      seed_spec(team, product, branch, spec_config, silent)
    end)

    # Seed Site specs (seed-data.SPECS.3, seed-data.SPECS.3-1 through 3-4)
    Enum.each(@site_specs, fn spec_config ->
      product = Map.get(products_by_name, spec_config.product_name)
      branch = Map.get(branches, spec_config.branch_key)
      seed_spec(team, product, branch, spec_config, silent)
    end)
  end

  defp seed_spec(_team, product, branch, config, silent) do
    now = DateTime.utc_now(:second)

    spec_attrs = %{
      branch_id: branch.id,
      product_id: product.id,
      feature_name: config.feature_name,
      feature_description: config.feature_description,
      feature_version: config.feature_version,
      path: config.path,
      raw_content: config.raw_content,
      last_seen_commit: branch.last_seen_commit,
      parsed_at: now,
      requirements: config.requirements
    }

    # Check for existing spec by branch_id + feature_name
    existing =
      Repo.one(
        from s in Spec,
          where: s.branch_id == ^branch.id and s.feature_name == ^config.feature_name
      )

    if existing do
      # Update existing spec (idempotent)
      changes = %{}

      changes =
        if existing.feature_version != spec_attrs.feature_version,
          do: Map.put(changes, :feature_version, spec_attrs.feature_version),
          else: changes

      changes =
        if existing.feature_description != spec_attrs.feature_description,
          do: Map.put(changes, :feature_description, spec_attrs.feature_description),
          else: changes

      changes =
        if existing.path != spec_attrs.path,
          do: Map.put(changes, :path, spec_attrs.path),
          else: changes

      changes =
        if existing.raw_content != spec_attrs.raw_content,
          do: Map.put(changes, :raw_content, spec_attrs.raw_content),
          else: changes

      changes =
        if existing.last_seen_commit != spec_attrs.last_seen_commit,
          do: Map.put(changes, :last_seen_commit, spec_attrs.last_seen_commit),
          else: changes

      changes =
        if existing.requirements != spec_attrs.requirements,
          do: Map.put(changes, :requirements, spec_attrs.requirements),
          else: changes

      if changes != %{} do
        {:ok, updated} =
          existing
          |> Spec.changeset(changes)
          |> Repo.update()

        unless silent do
          IO.puts(
            "Updated spec: #{config.feature_name} v#{config.feature_version} on #{branch.branch_name}"
          )
        end

        updated
      else
        unless silent do
          IO.puts(
            "Spec already exists: #{config.feature_name} v#{config.feature_version} on #{branch.branch_name}"
          )
        end

        existing
      end
    else
      {:ok, spec} =
        %Spec{}
        |> Spec.changeset(spec_attrs)
        |> Repo.insert()

      unless silent do
        IO.puts(
          "Created spec: #{config.feature_name} v#{config.feature_version} on #{branch.branch_name}"
        )
      end

      spec
    end
  end

  # ---------------------------------------------------------------------------
  # Implementation State Seeding (Phase 2)
  # ---------------------------------------------------------------------------

  defp seed_impl_states(_team, products, silent) do
    unless silent do
      IO.puts("\n=== Seeding Implementation States ===")
    end

    products_by_name = Enum.into(products, %{}, &{&1.name, &1})

    # Get all implementations for the products
    product_ids = Enum.map(products, & &1.id)

    implementations =
      Repo.all(from i in Implementation, where: i.product_id in ^product_ids)
      |> Enum.group_by(& &1.product_id)

    # Build lookup: {product_name, impl_name} -> implementation
    impl_lookup =
      for {product_name, product} <- products_by_name,
          impls = Map.get(implementations, product.id, []),
          impl <- impls,
          into: %{} do
        {{product_name, impl.name}, impl}
      end

    Enum.each(@impl_states, fn state_config ->
      key = {state_config.product_name, state_config.impl_name}

      case Map.get(impl_lookup, key) do
        nil ->
          unless silent do
            IO.puts(
              "Warning: Implementation not found for #{state_config.product_name}/#{state_config.impl_name}"
            )
          end

        implementation ->
          seed_impl_state(implementation, state_config, silent)
      end
    end)
  end

  defp seed_impl_state(implementation, config, silent) do
    state_attrs = %{
      implementation_id: implementation.id,
      feature_name: config.feature_name,
      states: config.states
    }

    # Check for existing state
    existing =
      Repo.one(
        from fis in FeatureImplState,
          where:
            fis.implementation_id == ^implementation.id and
              fis.feature_name == ^config.feature_name
      )

    if existing do
      # Update if states differ
      if existing.states != state_attrs.states do
        {:ok, updated} =
          existing
          |> FeatureImplState.changeset(%{states: state_attrs.states})
          |> Repo.update()

        unless silent do
          IO.puts("Updated state: #{config.feature_name} for #{implementation.name}")
        end

        updated
      else
        unless silent do
          IO.puts("State already exists: #{config.feature_name} for #{implementation.name}")
        end

        existing
      end
    else
      {:ok, state} =
        %FeatureImplState{}
        |> FeatureImplState.changeset(state_attrs)
        |> Repo.insert()

      unless silent do
        IO.puts("Created state: #{config.feature_name} for #{implementation.name}")
      end

      state
    end
  end

  # ---------------------------------------------------------------------------
  # Branch Ref Seeding (Phase 2)
  # ---------------------------------------------------------------------------

  defp seed_branch_refs(_team, branches, silent) do
    unless silent do
      IO.puts("\n=== Seeding Branch Refs ===")
    end

    Enum.each(@branch_refs, fn ref_config ->
      case Map.get(branches, ref_config.branch_key) do
        nil ->
          unless silent do
            IO.puts("Warning: Branch not found for key #{ref_config.branch_key}")
          end

        branch ->
          seed_branch_ref(branch, ref_config, silent)
      end
    end)
  end

  defp seed_branch_ref(branch, config, silent) do
    now = DateTime.utc_now(:second)

    ref_attrs = %{
      branch_id: branch.id,
      feature_name: config.feature_name,
      refs: config.refs,
      commit: config.commit,
      pushed_at: now
    }

    # Check for existing ref
    existing =
      Repo.one(
        from fbr in FeatureBranchRef,
          where:
            fbr.branch_id == ^branch.id and
              fbr.feature_name == ^config.feature_name
      )

    if existing do
      # Update if refs differ
      if existing.refs != ref_attrs.refs or existing.commit != ref_attrs.commit do
        {:ok, updated} =
          existing
          |> FeatureBranchRef.changeset(%{refs: ref_attrs.refs, commit: ref_attrs.commit})
          |> Repo.update()

        unless silent do
          IO.puts("Updated refs: #{config.feature_name} on #{branch.branch_name}")
        end

        updated
      else
        unless silent do
          IO.puts("Refs already exist: #{config.feature_name} on #{branch.branch_name}")
        end

        existing
      end
    else
      {:ok, ref} =
        %FeatureBranchRef{}
        |> FeatureBranchRef.changeset(ref_attrs)
        |> Repo.insert()

      unless silent do
        IO.puts("Created refs: #{config.feature_name} on #{branch.branch_name}")
      end

      ref
    end
  end
end
