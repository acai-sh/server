defmodule AcaiWeb.Api.Schemas.FeatureStatesSchemas do
  @moduledoc """
  OpenApiSpex schemas for the feature-states endpoint.
  """

  require OpenApiSpex

  defmodule StateObject do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "FeatureStateObject",
      type: :object,
      required: [:status],
      properties: %{
        status: %OpenApiSpex.Schema{
          type: :string,
          nullable: true,
          enum: ["assigned", "blocked", "incomplete", "completed", "rejected", "accepted"],
          description: "Nullable state status"
        },
        comment: %OpenApiSpex.Schema{
          type: :string,
          description: "Optional state comment"
        }
      }
    })
  end

  defmodule FeatureStatesRequest do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "FeatureStatesRequest",
      type: :object,
      required: [:product_name, :feature_name, :implementation_name, :states],
      properties: %{
        product_name: %OpenApiSpex.Schema{type: :string},
        feature_name: %OpenApiSpex.Schema{type: :string},
        implementation_name: %OpenApiSpex.Schema{type: :string},
        states: %OpenApiSpex.Schema{
          type: :object,
          minProperties: 1,
          additionalProperties: %OpenApiSpex.Schema{allOf: [StateObject.schema()]}
        }
      }
    })
  end

  defmodule FeatureStatesResponseData do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "FeatureStatesResponseData",
      type: :object,
      required: [
        :product_name,
        :feature_name,
        :implementation_name,
        :implementation_id,
        :states_written,
        :warnings
      ],
      properties: %{
        product_name: %OpenApiSpex.Schema{type: :string},
        feature_name: %OpenApiSpex.Schema{type: :string},
        implementation_name: %OpenApiSpex.Schema{type: :string},
        implementation_id: %OpenApiSpex.Schema{type: :string},
        states_written: %OpenApiSpex.Schema{type: :integer},
        warnings: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :string}}
      }
    })
  end

  defmodule FeatureStatesResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "FeatureStatesResponse",
      type: :object,
      required: [:data],
      properties: %{
        data: %OpenApiSpex.Schema{allOf: [FeatureStatesResponseData.schema()]}
      }
    })
  end
end
