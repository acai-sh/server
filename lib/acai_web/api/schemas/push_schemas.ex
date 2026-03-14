defmodule AcaiWeb.Api.Schemas.PushSchemas do
  @moduledoc """
  OpenApiSpex schemas for the push endpoint.

  See push.feature.yaml for ACIDs
  """

  # push.FEAT.1, push.FEAT.2, push.FEAT.3, push.FEAT.4, push.FEAT.5
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
          description:
            "Feature name (alphanumeric, hyphens, underscores only). See push.FEAT.1, push.VALIDATION.1"
        },
        product: %OpenApiSpex.Schema{
          type: :string,
          description: "Product name. See push.FEAT.2"
        },
        description: %OpenApiSpex.Schema{
          type: :string,
          description: "Optional feature description. See push.FEAT.3"
        },
        version: %OpenApiSpex.Schema{
          type: :string,
          default: "1.0.0",
          description: "Optional version string (SemVer). See push.FEAT.4, push.VALIDATION.2"
        },
        prerequisites: %OpenApiSpex.Schema{
          type: :array,
          items: %OpenApiSpex.Schema{type: :string},
          description: "Optional list of prerequisite feature names. See push.FEAT.5"
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

  # push.FEAT_META.1, push.FEAT_META.2, push.FEAT_META.3
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
          type: :string,
          description:
            "Path from repo root (e.g., features/auth.feature.yaml). See push.FEAT_META.1"
        },
        raw_content: %OpenApiSpex.Schema{
          type: :string,
          description: "Optional raw content of the feature file. See push.FEAT_META.2"
        },
        last_seen_commit: %OpenApiSpex.Schema{
          type: :string,
          description: "Commit hash when this feature was last seen. See push.FEAT_META.3"
        }
      },
      example: %{
        path: "features/auth.feature.yaml",
        last_seen_commit: "abc123def456"
      }
    })
  end

  # push.SPEC_REQS.1, push.SPEC_REQS.1-1, push.SPEC_REQS.1-2, push.SPEC_REQS.1-3, push.SPEC_REQS.1-4
  defmodule RequirementDefinition do
    @moduledoc """
    Schema for a single requirement definition.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RequirementDefinition",
      description: "Definition of a single requirement (AC)",
      type: :object,
      required: [:requirement],
      properties: %{
        requirement: %OpenApiSpex.Schema{
          type: :string,
          description: "The requirement text. See push.SPEC_REQS.1-1"
        },
        deprecated: %OpenApiSpex.Schema{
          type: :boolean,
          default: false,
          description: "Whether this requirement is deprecated. See push.SPEC_REQS.1-2"
        },
        note: %OpenApiSpex.Schema{
          type: :string,
          description: "Optional note about this requirement. See push.SPEC_REQS.1-3"
        },
        replaced_by: %OpenApiSpex.Schema{
          type: :array,
          items: %OpenApiSpex.Schema{type: :string},
          description: "Optional list of ACIDs that replace this one. See push.SPEC_REQS.1-4"
        }
      },
      example: %{
        requirement: "System must validate email format",
        deprecated: false
      }
    })
  end

  # push.REQUEST.4, push.REQUEST.4-1, push.REQUEST.4-2, push.REQUEST.4-3
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
          type: :object,
          additionalProperties: %OpenApiSpex.Schema{
            allOf: [RequirementDefinition.schema()]
          },
          description: "Map of ACIDs to requirement definitions. See push.SPEC_REQS.1"
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

  # push.REFS.2-1, push.REFS.2-2
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
          description: "Path to the code reference (e.g., lib/foo.ex:42). See push.REFS.2-2"
        },
        is_test: %OpenApiSpex.Schema{
          type: :boolean,
          default: false,
          description: "Whether this reference is a test. See push.REFS.2-2"
        }
      },
      example: %{
        path: "lib/my_app/auth.ex:42",
        is_test: false
      }
    })
  end

  # push.REFS.1, push.REFS.2, push.REFS.2-1
  defmodule References do
    @moduledoc """
    Schema for references section in push request.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "References",
      description: "Code references grouped by ACID",
      type: :object,
      required: [:data],
      properties: %{
        override: %OpenApiSpex.Schema{
          type: :boolean,
          default: false,
          description: "If true, replaces all existing refs instead of merging. See push.REFS.1"
        },
        data: %OpenApiSpex.Schema{
          type: :object,
          description: "Map of ACIDs to arrays of ref objects. See push.REFS.2, push.REFS.2-1",
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

  # push.STATES.2-2, push.STATES.2-3
  defmodule StateObject do
    @moduledoc """
    Schema for a single state entry.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "StateObject",
      description: "State for a single AC",
      type: :object,
      properties: %{
        status: %OpenApiSpex.Schema{
          type: :string,
          nullable: true,
          description: "Status value (nullable). See push.STATES.2-2"
        },
        comment: %OpenApiSpex.Schema{
          type: :string,
          description: "Optional comment about this state. See push.STATES.2-3"
        }
      },
      example: %{
        status: "completed",
        comment: "Implemented in PR #123"
      }
    })
  end

  # push.STATES.1, push.STATES.2, push.STATES.2-1
  defmodule States do
    @moduledoc """
    Schema for states section in push request.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "States",
      description: "Implementation states grouped by ACID",
      type: :object,
      required: [:data],
      properties: %{
        override: %OpenApiSpex.Schema{
          type: :boolean,
          default: false,
          description:
            "If true, replaces all existing states instead of merging. See push.STATES.1"
        },
        data: %OpenApiSpex.Schema{
          type: :object,
          description: "Map of ACIDs to state objects. See push.STATES.2, push.STATES.2-1",
          additionalProperties: %OpenApiSpex.Schema{allOf: [StateObject.schema()]}
        }
      },
      example: %{
        override: false,
        data: %{
          "auth-feature.AUTH.1" => %{
            status: "completed",
            comment: "Done"
          }
        }
      }
    })
  end

  # push.REQUEST.1, push.REQUEST.2, push.REQUEST.3, push.REQUEST.4, push.REQUEST.5, push.REQUEST.6, push.REQUEST.7, push.REQUEST.8
  defmodule PushRequest do
    @moduledoc """
    Schema for the push request body.
    """
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PushRequest",
      description: "Request body for pushing specs, refs, and states",
      type: :object,
      required: [:repo_uri, :branch_name, :commit_hash],
      properties: %{
        repo_uri: %OpenApiSpex.Schema{
          type: :string,
          description: "Repository URI. See push.REQUEST.1"
        },
        branch_name: %OpenApiSpex.Schema{
          type: :string,
          description: "Branch name. See push.REQUEST.2"
        },
        commit_hash: %OpenApiSpex.Schema{
          type: :string,
          description: "Commit hash. See push.REQUEST.3"
        },
        specs: %OpenApiSpex.Schema{
          type: :array,
          items: %OpenApiSpex.Schema{allOf: [SpecObject.schema()]},
          description: "Optional list of specs to push. See push.REQUEST.4"
        },
        references: %OpenApiSpex.Schema{
          allOf: [References.schema()],
          description: "Optional code references. See push.REQUEST.5"
        },
        states: %OpenApiSpex.Schema{
          allOf: [States.schema()],
          description: "Optional implementation states. See push.REQUEST.6"
        },
        target_impl_name: %OpenApiSpex.Schema{
          type: :string,
          description: "Optional target implementation name. See push.REQUEST.7"
        },
        parent_impl_name: %OpenApiSpex.Schema{
          type: :string,
          description: "Optional parent implementation name for inheritance. See push.REQUEST.8"
        }
      },
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

  # push.RESPONSE.2, push.RESPONSE.3, push.RESPONSE.4
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
          description: "Name of the implementation (null if untracked). See push.RESPONSE.2"
        },
        implementation_id: %OpenApiSpex.Schema{
          type: :string,
          nullable: true,
          description: "ID of the implementation (null if untracked). See push.RESPONSE.2"
        },
        product_name: %OpenApiSpex.Schema{
          type: :string,
          nullable: true,
          description: "Name of the product (null if untracked). See push.RESPONSE.2"
        },
        branch_id: %OpenApiSpex.Schema{
          type: :string,
          description: "ID of the branch. See push.RESPONSE.2"
        },
        specs_created: %OpenApiSpex.Schema{
          type: :integer,
          description: "Number of specs created. See push.RESPONSE.3"
        },
        specs_updated: %OpenApiSpex.Schema{
          type: :integer,
          description: "Number of specs updated. See push.RESPONSE.3"
        },
        warnings: %OpenApiSpex.Schema{
          type: :array,
          items: %OpenApiSpex.Schema{type: :string},
          description: "List of non-fatal warnings. See push.RESPONSE.4"
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

  # push.RESPONSE.1
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

  # push.RESPONSE.5, push.RESPONSE.6, push.RESPONSE.7
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
              description:
                "Error detail message. See push.RESPONSE.5, push.RESPONSE.6, push.RESPONSE.7"
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
