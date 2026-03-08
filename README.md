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

## Product Overview

Acai.sh is an open-source toolkit for spec-driven software development. The toolkit is centered around `feature.yaml` specs docs.
The toolkit supports a specific software development workflow;
1. Features are defined in plain language in `feature.yaml`, as simple lists of key requirements.
2. Requirements each get stable ids like `data-model.TEAMS.1`.
3. The Acai CLI parses your `feature.yaml` files and scans your codebase to find id references in comments and in tests.
4. Data is pushed to the server, so that many collaborators (humans and agents) can share progress, and review/accept/reject implementations.

The server also hosts a dashboard, which presents a simple and intuitive heirarchy.
- Teams that have many Products
- Products that have many Features
- Features that have many Implementations
- Implementation are linked to a single canonical Spec file, and one or more git branches (where requirements are turned into code!)

Under-the-hood, this is the data model;
- teams: Top-level tenant for RBAC and billing.
- users: Pre-existing table for identity, session tokens, and mailer logic.
- access_tokens: Cryptographically hashed tokens granting scoped API access to a team.
- user_team_roles: Join table linking users to teams with specific titles.
- specs: Metadata and tracking for a feature.yaml file at a specific repo path.
- implementations: Specific variants of a feature, such as "Production" or "Prototype".
- tracked_branches: Links specific repository branches to an implementation.
- requirements: The parsed, definition-only content and ACIDs from a spec file.
- requirement_statuses: Per-implementation state (e.g., status, commit) for each requirement.
- code_references: Tracks where a requirement ACID is actively referenced in external code.
- activity_events: Append-only log of domain events for activity feeds and auditing

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
