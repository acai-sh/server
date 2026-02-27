# Acai Server

This package, the Acai Server, is a self-hostable monolith intended to be deployed on a VPS like Hetzner, or ran locally as as devcontainer. It contains several containerized services, which are orchestrated with `docker-compose`.

- `app` - The Frontend and the JSON API, built with Elixir & Phoenix. This is what you see when you visit [https://www.acai.sh](https://www.acai.sh)  
- `db` - Postgres 18, managed via Ecto migrations
- `backup` - Backup automation service, built with Restic, targeting an S3 bucket of your choice  
- `caddy` - Reverse proxy, routing external traffic to the internal app container  

The project directories follow the conventional Phoenix layout, with the addition of an `infra` folder that contains all docker configurations.

## Quickstart

> 👉 Want to start shipping ASAP? Just trying it out? **Use our [hosted service instead.](https://app.acai.sh)**

Otherwise, choose from one of the deployment options below.

## Devcontainers

This is the easiest way to host a local instance, and also the preferred pathway for contributors.

**Prerequisites**   
* [ ] Docker Desktop or Podman
* [ ] (Optional) DevPod client

**Steps:**  
1.  Create `/infra/.env` with:
    ```sh
    CADDYFILE=devcontainer
    POSTGRES_DB=acai_dev
    ```
2. Open in VSCode / Zed / DevPod 🎉
3. Access app in `localhost:4000` by default.

### Parallel Devcontainers

This is very useful for running multiple agents in parallel. Each container has it's own isolated postgres instance and git history, so that test runs and migrations never clash.

1. Clone the project again for each additional instance you wish to run.
```
projects/
├── acai-server-1/
│   └── infra/
│       ├── .env
├── acai-server-2/
│   └── infra/
│       ├── .env
```
2. Configure the .env in each to avoid clashes. See `.env.example` for more info.
```sh
INSTANCE_NAME=acai-devpod-2 # Prevent instance name conflict
URL_PORT=4002       # App accessible at localhost:4002 (Default is 4000 if omitted)
HTTP_PORT=8082      # Prevent Caddy port 80 conflict 
HTTPS_PORT=8443     # Prevent Caddy port 443 conflict
```
3. (Optional) To authenticate git and gh cli for agent use, use `gh auth login` with a PAT, and then run `gh auth setup-git`

## Troubleshooting & Tips
- **Confirm proxy is working:** `http://localhost:4000/_caddy`
- **Running Tests:** `MIX_ENV=test mix test` - don't forget the `MIX_ENV=test` part
