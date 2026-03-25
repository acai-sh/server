defmodule AcaiWeb.Api.Schemas.ReadSchemas do
  @moduledoc """
  OpenApiSpex schemas for API read endpoints.
  """

  require OpenApiSpex

  defmodule ErrorResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      type: :object,
      required: [:errors],
      properties: %{
        errors: %OpenApiSpex.Schema{
          type: :object,
          required: [:detail],
          properties: %{
            detail: %OpenApiSpex.Schema{type: :string},
            status: %OpenApiSpex.Schema{type: :string}
          }
        }
      }
    })
  end

  defmodule ImplementationEntry do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ImplementationEntry",
      type: :object,
      required: [:implementation_name, :implementation_id],
      properties: %{
        implementation_name: %OpenApiSpex.Schema{type: :string},
        implementation_id: %OpenApiSpex.Schema{type: :string}
      }
    })
  end

  defmodule ImplementationsData do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ImplementationsData",
      type: :object,
      required: [:product_name, :implementations],
      properties: %{
        product_name: %OpenApiSpex.Schema{type: :string},
        repo_uri: %OpenApiSpex.Schema{type: :string},
        branch_name: %OpenApiSpex.Schema{type: :string},
        implementations: %OpenApiSpex.Schema{
          type: :array,
          items: %OpenApiSpex.Schema{allOf: [ImplementationEntry.schema()]}
        }
      }
    })
  end

  defmodule ImplementationsResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ImplementationsResponse",
      type: :object,
      required: [:data],
      properties: %{
        data: %OpenApiSpex.Schema{allOf: [ImplementationsData.schema()]}
      }
    })
  end

  defmodule SourceObject do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SourceObject",
      type: :object,
      required: [:source_type],
      properties: %{
        source_type: %OpenApiSpex.Schema{type: :string, enum: ["local", "inherited", "none"]},
        implementation_name: %OpenApiSpex.Schema{type: :string},
        branch_names: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :string}}
      }
    })
  end

  defmodule StateObject do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "StateObject",
      type: :object,
      properties: %{
        status: %OpenApiSpex.Schema{type: :string, nullable: true},
        comment: %OpenApiSpex.Schema{type: :string},
        updated_at: %OpenApiSpex.Schema{type: :string}
      }
    })
  end

  defmodule RefObject do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RefObject",
      type: :object,
      required: [:path, :is_test, :repo_uri, :branch_name],
      properties: %{
        path: %OpenApiSpex.Schema{type: :string},
        is_test: %OpenApiSpex.Schema{type: :boolean},
        repo_uri: %OpenApiSpex.Schema{type: :string},
        branch_name: %OpenApiSpex.Schema{type: :string}
      }
    })
  end

  defmodule AcidEntry do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AcidEntry",
      type: :object,
      required: [:acid, :requirement, :state, :refs_count, :test_refs_count],
      properties: %{
        acid: %OpenApiSpex.Schema{type: :string},
        requirement: %OpenApiSpex.Schema{type: :string},
        note: %OpenApiSpex.Schema{type: :string},
        deprecated: %OpenApiSpex.Schema{type: :boolean},
        replaced_by: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :string}},
        state: %OpenApiSpex.Schema{allOf: [StateObject.schema()]},
        refs_count: %OpenApiSpex.Schema{type: :integer},
        test_refs_count: %OpenApiSpex.Schema{type: :integer},
        refs: %OpenApiSpex.Schema{
          type: :array,
          items: %OpenApiSpex.Schema{allOf: [RefObject.schema()]}
        }
      }
    })
  end

  defmodule Summary do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Summary",
      type: :object,
      required: [:total_acids, :status_counts],
      properties: %{
        total_acids: %OpenApiSpex.Schema{type: :integer},
        status_counts: %OpenApiSpex.Schema{type: :object}
      }
    })
  end

  defmodule DanglingStateEntry do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DanglingStateEntry",
      type: :object,
      required: [:acid, :state],
      properties: %{
        acid: %OpenApiSpex.Schema{type: :string},
        state: %OpenApiSpex.Schema{allOf: [StateObject.schema()]}
      }
    })
  end

  defmodule FeatureContextData do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "FeatureContextData",
      type: :object,
      required: [
        :product_name,
        :feature_name,
        :implementation_name,
        :implementation_id,
        :spec_source,
        :states_source,
        :refs_source,
        :summary,
        :acids,
        :warnings
      ],
      properties: %{
        product_name: %OpenApiSpex.Schema{type: :string},
        feature_name: %OpenApiSpex.Schema{type: :string},
        implementation_name: %OpenApiSpex.Schema{type: :string},
        implementation_id: %OpenApiSpex.Schema{type: :string},
        spec_source: %OpenApiSpex.Schema{allOf: [SourceObject.schema()]},
        states_source: %OpenApiSpex.Schema{allOf: [SourceObject.schema()]},
        refs_source: %OpenApiSpex.Schema{allOf: [SourceObject.schema()]},
        summary: %OpenApiSpex.Schema{allOf: [Summary.schema()]},
        acids: %OpenApiSpex.Schema{
          type: :array,
          items: %OpenApiSpex.Schema{allOf: [AcidEntry.schema()]}
        },
        dangling_states: %OpenApiSpex.Schema{
          type: :array,
          items: %OpenApiSpex.Schema{allOf: [DanglingStateEntry.schema()]}
        },
        warnings: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :string}}
      }
    })
  end

  defmodule FeatureContextResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "FeatureContextResponse",
      type: :object,
      required: [:data],
      properties: %{
        data: %OpenApiSpex.Schema{allOf: [FeatureContextData.schema()]}
      }
    })
  end
end
