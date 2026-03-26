defmodule AcaiWeb.Api.Schemas.PushSchemas do
  @moduledoc """
  OpenApiSpex schemas for the push endpoint.
  """

  defmodule Feature do
    @moduledoc """
    Schema for feature metadata in a push request.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Feature",
      description: "Feature metadata",
      type: :object,
      required: [:name, :product],
      properties: %{
        name: %OpenApiSpex.Schema{
          type: :string,
          description: "Feature name (alphanumeric, hyphens, underscores only)"
        },
        product: %OpenApiSpex.Schema{
          type: :string,
          description: "Product name"
        },
        description: %OpenApiSpex.Schema{
          # push.ABUSE.2-6
          type: :string,
          maxLength: 5_000,
          description: "Optional feature description"
        },
        version: %OpenApiSpex.Schema{
          type: :string,
          default: "1.0.0",
          description: "Optional version string (SemVer)"
        },
        prerequisites: %OpenApiSpex.Schema{
          type: :array,
          items: %OpenApiSpex.Schema{type: :string},
          description: "Optional list of prerequisite feature names"
        }
      },
      example: %{
        name: "auth-feature",
        product: "my-app",
        description: "Authentication feature",
        version: "1.0.0",
        prerequisites: []
      }
    })
  end

  defmodule FeatureMeta do
    @moduledoc """
    Schema for feature metadata about the source file.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "FeatureMeta",
      description: "Metadata about the feature file location",
      type: :object,
      required: [:path, :last_seen_commit],
      properties: %{
        path: %OpenApiSpex.Schema{
          # push.ABUSE.2-7, push.ABUSE.2-4
          type: :string,
          maxLength: 1_024,
          description: "Path from repo root (e.g., features/auth.feature.yaml)"
        },
        raw_content: %OpenApiSpex.Schema{
          # push.ABUSE.2-4
          type: :string,
          maxLength: 102_400,
          description: "Optional raw content of the feature file"
        },
        last_seen_commit: %OpenApiSpex.Schema{
          type: :string,
          description: "Commit hash when this feature was last seen"
        }
      },
      example: %{
        path: "features/auth.feature.yaml",
        last_seen_commit: "abc123def456"
      }
    })
  end

  defmodule RequirementDefinition do
    @moduledoc """
    Schema for a single requirement definition.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RequirementDefinition",
      description: "Definition of a single requirement (acceptance criteria)",
      type: :object,
      required: [:requirement],
      properties: %{
        requirement: %OpenApiSpex.Schema{
          # push.ABUSE.2-5
          type: :string,
          maxLength: 2_000,
          description: "The requirement text describing the acceptance criteria"
        },
        deprecated: %OpenApiSpex.Schema{
          type: :boolean,
          default: false,
          description: "Whether this requirement is deprecated"
        },
        note: %OpenApiSpex.Schema{
          type: :string,
          description: "Optional note about this requirement"
        },
        replaced_by: %OpenApiSpex.Schema{
          type: :array,
          items: %OpenApiSpex.Schema{type: :string},
          description: "Optional list of requirement IDs that replace this one"
        }
      },
      example: %{
        requirement: "System must validate email format",
        deprecated: false
      }
    })
  end

  defmodule SpecObject do
    @moduledoc """
    Schema for a single spec object in the push request.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SpecObject",
      description: "A single spec to push",
      type: :object,
      required: [:feature, :requirements, :meta],
      properties: %{
        feature: %OpenApiSpex.Schema{
          allOf: [Feature.schema()],
          description: "Feature metadata"
        },
        requirements: %OpenApiSpex.Schema{
          # push.ABUSE.2-3
          type: :object,
          maxProperties: 200,
          additionalProperties: %OpenApiSpex.Schema{
            allOf: [RequirementDefinition.schema()]
          },
          description: "Map of requirement IDs to requirement definitions"
        },
        meta: %OpenApiSpex.Schema{
          allOf: [FeatureMeta.schema()],
          description: "Feature file metadata"
        }
      },
      example: %{
        feature: %{
          name: "auth-feature",
          product: "my-app",
          version: "1.0.0"
        },
        requirements: %{
          "auth-feature.AUTH.1" => %{requirement: "Must validate credentials"}
        },
        meta: %{
          path: "features/auth.feature.yaml",
          last_seen_commit: "abc123"
        }
      }
    })
  end

  defmodule RefObject do
    @moduledoc """
    Schema for a single code reference.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RefObject",
      description: "A code reference",
      type: :object,
      required: [:path],
      properties: %{
        path: %OpenApiSpex.Schema{
          type: :string,
          description: "Path to the code reference (e.g., lib/foo.ex:42)"
        },
        is_test: %OpenApiSpex.Schema{
          type: :boolean,
          default: false,
          description: "Whether this reference is a test"
        }
      },
      example: %{
        path: "lib/my_app/auth.ex:42",
        is_test: false
      }
    })
  end

  defmodule References do
    @moduledoc """
    Schema for references section in push request.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "References",
      description: "Code references grouped by requirement ID",
      type: :object,
      required: [:data],
      properties: %{
        override: %OpenApiSpex.Schema{
          type: :boolean,
          default: false,
          description: "If true, replaces all existing refs instead of merging"
        },
        data: %OpenApiSpex.Schema{
          # push.ABUSE.2-2
          type: :object,
          maxProperties: 10_000,
          description: "Map of requirement IDs to arrays of ref objects",
          additionalProperties: %OpenApiSpex.Schema{
            type: :array,
            items: %OpenApiSpex.Schema{allOf: [RefObject.schema()]}
          }
        }
      },
      example: %{
        override: false,
        data: %{
          "auth-feature.AUTH.1" => [
            %{path: "lib/my_app/auth.ex:42", is_test: false}
          ]
        }
      }
    })
  end

  defmodule PushRequest do
    @moduledoc """
    Schema for the push request body.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PushRequest",
      description: "Request body for pushing specs and refs",
      type: :object,
      required: [:repo_uri, :branch_name, :commit_hash],
      properties: %{
        product_name: %OpenApiSpex.Schema{
          type: :string,
          description:
            "Optional product name used for refs-only implementation creation or linking"
        },
        repo_uri: %OpenApiSpex.Schema{
          # push.ABUSE.2-8
          type: :string,
          maxLength: 2_048,
          description:
            "`repo_uri` should be in the format `host/owner/repo` (e.g. `github.com/my-org/my-repo`). Supported hosts for deep linking are `github.com`, `gitlab.com`, and `bitbucket.org`. Self-hosted instances may work for tracking but deep links are not guaranteed yet."
        },
        branch_name: %OpenApiSpex.Schema{
          type: :string,
          description: "Git branch name being pushed (e.g., 'main', 'feature/auth-123')"
        },
        commit_hash: %OpenApiSpex.Schema{
          type: :string,
          description:
            "Full 40-character Git commit SHA that this push represents (e.g., 'abc123def456...')"
        },
        specs: %OpenApiSpex.Schema{
          # push.ABUSE.2-1
          type: :array,
          maxItems: 100,
          items: %OpenApiSpex.Schema{allOf: [SpecObject.schema()]},
          description: "Optional list of specs to push"
        },
        references: %OpenApiSpex.Schema{
          allOf: [References.schema()],
          description: "Optional code references"
        },
        target_impl_name: %OpenApiSpex.Schema{
          type: :string,
          description:
            "Name of the implementation (deployment environment) to associate this branch with. An implementation represents a deployable instance of your product (e.g., 'production', 'staging', 'mobile-app-v2'). For spec-push creation flows, a missing implementation may be auto-created within the product. For refs-only pushes, `product_name` + `target_impl_name` must resolve to an existing implementation unless `parent_impl_name` is also provided to create a new child implementation."
        },
        parent_impl_name: %OpenApiSpex.Schema{
          type: :string,
          description:
            "Name of a parent implementation for inheritance. When creating a new implementation, it will inherit the parent's baseline and refs (e.g., create 'feature-branch-impl' with parent 'main' to start with main's baseline). Useful for short-lived branches that extend an existing implementation"
        }
      },
      additionalProperties: false,
      example: %{
        repo_uri: "github.com/my-org/my-repo",
        branch_name: "main",
        commit_hash: "abc123def456",
        specs: [
          %{
            feature: %{
              name: "auth-feature",
              product: "my-app"
            },
            requirements: %{
              "auth-feature.AUTH.1" => %{requirement: "Must validate credentials"}
            },
            meta: %{
              path: "features/auth.feature.yaml",
              last_seen_commit: "abc123def456"
            }
          }
        ]
      }
    })
  end

  defmodule PushResponseData do
    @moduledoc """
    Schema for the push response data.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PushResponseData",
      description: "Response data for a successful push",
      type: :object,
      properties: %{
        implementation_name: %OpenApiSpex.Schema{
          type: :string,
          nullable: true,
          description:
            "Name of the implementation (deployment environment) this branch is linked to, such as 'production' or 'staging'. Null if the branch is not tracked by any implementation"
        },
        implementation_id: %OpenApiSpex.Schema{
          type: :string,
          nullable: true,
          description:
            "Unique ID of the implementation. Null if the branch is not tracked by any implementation"
        },
        product_name: %OpenApiSpex.Schema{
          type: :string,
          nullable: true,
          description: "Name of the product (null if untracked)"
        },
        branch_id: %OpenApiSpex.Schema{
          type: :string,
          description: "ID of the branch"
        },
        specs_created: %OpenApiSpex.Schema{
          type: :integer,
          description: "Number of specs created"
        },
        specs_updated: %OpenApiSpex.Schema{
          type: :integer,
          description: "Number of specs updated"
        },
        warnings: %OpenApiSpex.Schema{
          type: :array,
          items: %OpenApiSpex.Schema{type: :string},
          description: "List of non-fatal warnings"
        }
      },
      example: %{
        implementation_name: "production",
        implementation_id: "123e4567-e89b-12d3-a456-426614174000",
        product_name: "my-app",
        branch_id: "123e4567-e89b-12d3-a456-426614174001",
        specs_created: 1,
        specs_updated: 0,
        warnings: []
      }
    })
  end

  defmodule PushResponse do
    @moduledoc """
    Schema for a successful push response.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PushResponse",
      description: "Successful push response",
      type: :object,
      required: [:data],
      properties: %{
        data: %OpenApiSpex.Schema{
          allOf: [PushResponseData.schema()],
          description: "Push response data"
        }
      },
      example: %{
        data: %{
          implementation_name: "production",
          implementation_id: "123e4567-e89b-12d3-a456-426614174000",
          product_name: "my-app",
          branch_id: "123e4567-e89b-12d3-a456-426614174001",
          specs_created: 1,
          specs_updated: 0,
          warnings: []
        }
      }
    })
  end

  defmodule ErrorResponse do
    @moduledoc """
    Schema for error responses.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      description: "Error response",
      type: :object,
      required: [:errors],
      properties: %{
        errors: %OpenApiSpex.Schema{
          type: :object,
          required: [:detail],
          properties: %{
            detail: %OpenApiSpex.Schema{
              type: :string,
              description: "Error detail message"
            },
            status: %OpenApiSpex.Schema{
              type: :string,
              description: "HTTP status code as string"
            }
          }
        }
      },
      example: %{
        errors: %{
          detail: "Validation failed: feature_name is required",
          status: "UNPROCESSABLE_ENTITY"
        }
      }
    })
  end
end
