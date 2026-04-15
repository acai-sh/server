FROM restic/restic:0.18.1

# Install PostgreSQL 17 client tools to match the postgres:17.9 server
RUN apk add --no-cache postgresql17-client curl

# Verify pg_dump is available
RUN pg_dump --version
