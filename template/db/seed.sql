-- Seed data for testing
-- This script creates demo users with known passwords

-- Insert demo users
INSERT INTO auth.user (username, full_name) VALUES
  ('example', 'Example User'),
  ('admin', 'Administrator User'),
  ('testuser', 'Test User Demo');

-- Insert passwords with bcrypt hashes
-- Password for 'example': abc123
-- Hash: $2a$12$xD7YBrtKpb5uFoiFm/EGTOPMI8BpQTLtz0uzAOQ4aRZlK66CEmEny

-- Password for 'admin' and 'testuser': password123
-- Hash: $2a$12$pZx//tHL63Jf0B6T./MH.OuPT8jTIFBZoZyLXtgoAxPr3T3mVTrIy

INSERT INTO auth.password (id_user, password_hash) VALUES
  (1, '$2a$12$xD7YBrtKpb5uFoiFm/EGTOPMI8BpQTLtz0uzAOQ4aRZlK66CEmEny'),  -- example/abc123
  (2, '$2a$12$pZx//tHL63Jf0B6T./MH.OuPT8jTIFBZoZyLXtgoAxPr3T3mVTrIy'),  -- admin/password123
  (3, '$2a$12$pZx//tHL63Jf0B6T./MH.OuPT8jTIFBZoZyLXtgoAxPr3T3mVTrIy');  -- testuser/password123
