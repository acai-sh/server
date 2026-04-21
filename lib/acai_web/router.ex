defmodule AcaiWeb.Router do
  use AcaiWeb, :router

  import AcaiWeb.UserAuth
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AcaiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_content_security_policy
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_query_params
    # core.ENG.6 - API pipeline is strictly stateless (no session/flash)
    plug OpenApiSpex.Plug.PutApiSpec, module: AcaiWeb.Api.ApiSpec
  end

  pipeline :api_authenticated do
    # core.ENG.8 - All routes require Authorization header with Bearer token
    plug AcaiWeb.Api.Plugs.BearerAuth
    # core.ENG.1
    plug AcaiWeb.Api.Plugs.ControllerAction
    plug AcaiWeb.Api.Plugs.QueryArrayNormalizer
    plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true
    # core.OPERATIONS.1 - Load runtime API operation config and enforce shared request-size caps.
    plug AcaiWeb.Api.Plugs.OperationConfig
  end

  scope "/", AcaiWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  defp put_content_security_policy(conn, _opts) do
    put_resp_header(conn, "content-security-policy", content_security_policy())
  end

  defp content_security_policy do
    directives = [
      "base-uri 'self'",
      "frame-ancestors 'self'"
    ]

    case AcaiWeb.Plausible.origin() do
      nil ->
        Enum.join(directives, "; ")

      origin ->
        Enum.join(
          directives ++
            [
              "script-src 'self' 'unsafe-inline' #{origin}",
              "connect-src 'self' ws: wss: #{origin}"
            ],
          "; "
        )
    end
  end

  # API v1 scope - core.ENG.7
  scope "/api/v1", AcaiWeb.Api do
    pipe_through :api

    # core.API.1 - Expose public /api/v1/openapi.json route
    # This route is public (no auth required)
    get "/openapi.json", OpenApiController, :spec

    # All other API routes go through authentication pipeline
    pipe_through :api_authenticated

    # push.ENDPOINT.1 - POST /api/v1/push
    # push.ENDPOINT.2 - Content-Type application/json (handled by pipeline)
    # push.ENDPOINT.3 - Requires Authorization Bearer token header (handled by BearerAuth plug)
    post "/push", PushController, :create

    # feature-states.ENDPOINT.1 - PATCH /api/v1/feature-states
    # feature-states.ENDPOINT.2 - JSON request body is handled by the API pipeline
    # feature-states.ENDPOINT.3 - Requires Authorization Bearer token header via the authenticated pipeline
    # This route lives in the authenticated API scope because state writes must be team-scoped and rate-limited.
    patch "/feature-states", FeatureStatesController, :update

    # implementations.ENDPOINT.1 - GET /api/v1/implementations
    # implementations.ENDPOINT.2 - Requires Authorization Bearer token header
    get "/implementations", ImplementationsController, :index

    # feature-context.ENDPOINT.1 - GET /api/v1/feature-context
    # feature-context.ENDPOINT.2 - Requires Authorization Bearer token header
    get "/feature-context", FeatureContextController, :show

    # implementation-features.ENDPOINT.1 - GET /api/v1/implementation-features
    # implementation-features.ENDPOINT.2 - Requires Authorization Bearer token header
    # This route stays in the authenticated API scope because it summarizes team-scoped feature data.
    get "/implementation-features", ImplementationFeaturesController, :index
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:acai, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AcaiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", AcaiWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", AcaiWeb do
    pipe_through [:browser, :require_authenticated_user]

    # team-list.MAIN.2, team-list.MAIN.3
    live_session :require_authenticated_user,
      on_mount: [{AcaiWeb.UserAuth, :ensure_authenticated}] do
      live "/teams", TeamsLive
      # team-view.MAIN.1
      live "/t/:team_name", TeamLive
      # product-view.MAIN.1
      live "/t/:team_name/p/:product_name", ProductLive
      # feature-view.MAIN
      live "/t/:team_name/f/:feature_name", FeatureLive
      # implementation-view.MAIN
      # feature-impl-view.ROUTING.1: Route uses /t/:team_name/i/:impl_name-:impl_id/f/:feature_name
      # The :impl_slug parameter captures the format "{sanitized_name}-{uuid_without_dashes}"
      live "/t/:team_name/i/:impl_slug/f/:feature_name", ImplementationLive
      # team-settings.AUTH.1
      live "/t/:team_name/settings", TeamSettingsLive
      # team-tokens.MAIN.1
      live "/t/:team_name/tokens", TeamTokensLive
    end

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/admin" do
    pipe_through [:browser, :require_authenticated_user]

    # dashboard.ROUTING.1
    # dashboard.AUTH.3
    live_dashboard "/dashboard",
      metrics: AcaiWeb.Telemetry,
      live_session_name: :admin_live_dashboard,
      on_mount: [
        {AcaiWeb.UserAuth, :ensure_authenticated},
        {AcaiWeb.UserAuth, :ensure_sudo_mode},
        {AcaiWeb.UserAuth, :ensure_global_admin}
      ]
  end

  scope "/", AcaiWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
