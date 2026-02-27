FROM restic/restic:0.18.1

# Install PostgreSQL 18 client tools to match the postgres:18.3 server
# Alpine 3.21+ includes postgresql18 packages
RUN apk add --no-cache postgresql18-client curl

# Verify pg_dump is available
RUN pg_dump --version
