defmodule AcaiWeb.Router do
  use AcaiWeb, :router

  import AcaiWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AcaiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    # core.ENG.6 - API pipeline is strictly stateless (no session/flash)
    plug OpenApiSpex.Plug.PutApiSpec, module: AcaiWeb.Api.ApiSpec
  end

  pipeline :api_authenticated do
    # core.ENG.8 - All routes require Authorization header with Bearer token
    plug AcaiWeb.Api.Plugs.BearerAuth
  end

  scope "/", AcaiWeb do
    pipe_through :browser

    get "/", PageController, :home
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
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:acai, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

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

  scope "/", AcaiWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
