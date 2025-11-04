-- Database initialization script
-- This script creates the schema and tables for the authentication system

-- Create schema
CREATE SCHEMA IF NOT EXISTS auth;

-- Create tables in order (respecting foreign keys)
\i /docker-entrypoint-initdb.d/auth/tables/user.sql
\i /docker-entrypoint-initdb.d/auth/tables/password.sql
\i /docker-entrypoint-initdb.d/auth/tables/refres_token.sql

-- Load seed data
\i /docker-entrypoint-initdb.d/seed.sql
