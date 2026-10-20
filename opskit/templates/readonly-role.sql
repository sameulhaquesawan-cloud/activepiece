DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'opskit_ro') THEN
    CREATE ROLE opskit_ro LOGIN;
  END IF;
END
$$;
ALTER ROLE opskit_ro WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD NULL CONNECTION LIMIT 3;
ALTER ROLE opskit_ro SET default_transaction_read_only = on;
ALTER ROLE opskit_ro SET statement_timeout = '30s';
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM opskit_ro;
GRANT CONNECT ON DATABASE :"db" TO opskit_ro;
GRANT USAGE ON SCHEMA public TO opskit_ro;
GRANT SELECT ON flow, flow_version, flow_run, project TO opskit_ro;
