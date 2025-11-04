-- Initialization script: Create auth schema
-- This script is executed automatically when initializing the PostgreSQL container

-- Create the auth schema if it does not exist
CREATE SCHEMA IF NOT EXISTS auth;

-- Confirmation message
DO $$
BEGIN
  RAISE NOTICE 'Auth schema created successfully';
END $$;
