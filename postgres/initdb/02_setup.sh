#!/bin/bash
set -e

# pg_monitor is only available on 10+
if [[ !("$PG_MAJOR" == 9.* ) ]]; then
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" postgres <<-'EOSQL'
    GRANT pg_monitor TO datadog;
EOSQL
fi

# setup extensions & functions required for collection of statement metrics & samples
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" postgres <<-'EOSQL'
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
    CREATE SCHEMA datadog;
    GRANT USAGE ON SCHEMA datadog TO datadog;
    GRANT USAGE ON SCHEMA public TO datadog;

    CREATE OR REPLACE FUNCTION datadog.explain_statement(l_query TEXT, OUT explain JSON) RETURNS SETOF JSON AS
    $$
      DECLARE
      curs REFCURSOR;
      plan JSON;

      BEGIN
          OPEN curs FOR EXECUTE pg_catalog.concat('EXPLAIN (FORMAT JSON) ', l_query);
          FETCH curs INTO plan;
          CLOSE curs;
          RETURN QUERY SELECT plan;
      END;
    $$
    LANGUAGE plpgsql
    RETURNS NULL ON NULL INPUT
    SECURITY DEFINER;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" pgbench <<-'EOSQL'
    CREATE SCHEMA datadog;
    GRANT USAGE ON SCHEMA datadog TO datadog;
    CREATE OR REPLACE FUNCTION datadog.explain_statement(l_query text, out explain JSON) RETURNS SETOF JSON AS
    $$
      BEGIN
          RETURN QUERY EXECUTE 'EXPLAIN (FORMAT JSON) ' || l_query;
      END;
    $$
    LANGUAGE plpgsql
    RETURNS NULL ON NULL INPUT
    SECURITY DEFINER;
EOSQL
