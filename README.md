# Acai Server

This package, the Acai Server, is a self-hostable monolith intended to be deployed on a VPS like Hetzner, or ran locally as as devcontainer. It contains several containerized services, which are orchestrated with `docker-compose`.

- `app` - The Frontend and the JSON REST API, built with Elixir & Phoenix. This is what you see when you visit [https://www.acai.sh](https://www.acai.sh)  
- `db` - Postgres 18, managed via Ecto migrations
- `backup` - Backup automation service, built with Restic, targeting an S3 bucket of your choice  
- `caddy` - Reverse proxy, routing external traffic to the internal app container  

The project directories follow the conventional Phoenix layout, with the addition of an `infra` folder that contains all docker configurations.

## Quickstart

> 👉 Want to start shipping ASAP? Just trying it out? **Use our [hosted service instead.](https://app.acai.sh)**

Otherwise, choose from one of the deployment options below.

### Devcontainers & DevPods

This is the easiest way to host a local instance (or multiple in parallel)

**Prerequisites**   
* [ ] Docker Desktop or Podman
* [ ] DevPod CLI

**Steps:**  
1.  Create `/infra/.env` with:
    ```sh
    CADDYFILE=devcontainer
    POSTGRES_DB=acai_dev
    ```
2. `devpod up .` (from repo root)
3. `ssh server.devpod`
4. `mix phx.server`
4. Access app in `localhost:4000` by default  

#### Parallel Devcontainers

This is very useful for running multiple agents in parallel. Each container has it's own isolated postgres instance and git history, so that test runs and migrations never clash.

1. Clone the project again for each additional instance you wish to run.
```
projects/
├── server/
│   └── infra/
│       ├── .env
├── server-2/
│   └── infra/
│       ├── .env
```
2. Configure the .env in each to avoid clashes; add these to `.env`;
```sh
INSTANCE_NAME=acai-devpod-2 # Prevent instance name conflict
URL_PORT=4002       # App accessible at localhost:4002 (Default is 4000 if omitted)
HTTP_PORT=8082      # Prevent Caddy port 80 conflict 
HTTPS_PORT=8443     # Prevent Caddy port 443 conflict
```
3. (Optional) To authenticate git and gh cli for agent use, use `gh auth login` with a PAT, and then run `gh auth setup-git`

## Troubleshooting & Tips
- **Confirm proxy is working:** `http://localhost:4000/_caddy`
