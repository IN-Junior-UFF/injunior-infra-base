#!/bin/bash
set -e

usage() {
  echo "Usage: $0 <user> <password> <database> [app|full]"
  echo "  app  - read/write on tables and sequences (default)"
  echo "  full - all privileges including functions"
  exit 1
}

[ $# -lt 3 ] && usage

if [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_DB" ]; then
  echo "Error: POSTGRES_USER and POSTGRES_DB must be set." >&2
  exit 1
fi

user=$1
password=$2
db=$3
mode=${4:-app}

if [ "$mode" != "app" ] && [ "$mode" != "full" ]; then
  echo "Error: mode must be 'app' or 'full'"
  usage
fi

echo "Creating user '$user' and database '$db' (mode: $mode)..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v user="$user" -v password="$password" -v db="$db" <<-EOSQL
  SELECT format('CREATE USER %I WITH PASSWORD %L', :'user', :'password')
  WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'user')\gexec

  SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'user')
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db')\gexec

  REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
  GRANT CONNECT ON DATABASE :"db" TO :"user";
EOSQL

if [ "$mode" = "full" ]; then
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" \
    -v user="$user" <<-EOSQL
    GRANT USAGE, CREATE ON SCHEMA public TO :"user";

    ALTER DEFAULT PRIVILEGES FOR ROLE :"user" IN SCHEMA public
      GRANT ALL ON TABLES TO :"user";

    ALTER DEFAULT PRIVILEGES FOR ROLE :"user" IN SCHEMA public
      GRANT ALL ON SEQUENCES TO :"user";

    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO :"user";
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO :"user";
    GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO :"user";
EOSQL
else
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" \
    -v user="$user" <<-EOSQL
    GRANT USAGE, CREATE ON SCHEMA public TO :"user";

    ALTER DEFAULT PRIVILEGES FOR ROLE :"user" IN SCHEMA public
      GRANT ALL ON TABLES TO :"user";

    ALTER DEFAULT PRIVILEGES FOR ROLE :"user" IN SCHEMA public
      GRANT ALL ON SEQUENCES TO :"user";

    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO :"user";
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO :"user";
EOSQL
fi

echo "Done."
