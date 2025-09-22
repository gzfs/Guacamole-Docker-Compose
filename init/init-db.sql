-- Guacamole Database Initialization Script
-- This script creates the necessary tables and initial data for Guacamole

-- Create the guacamole_user if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'guacamole_user') THEN
        CREATE ROLE guacamole_user WITH LOGIN PASSWORD 'guacamole_password';
    END IF;
END
$$;

-- Grant necessary privileges
GRANT CONNECT ON DATABASE guacamole_db TO guacamole_user;
GRANT USAGE ON SCHEMA public TO guacamole_user;
GRANT CREATE ON SCHEMA public TO guacamole_user;

-- Note: The actual Guacamole schema will be created by the Guacamole application
-- when it starts up and connects to the database for the first time.
