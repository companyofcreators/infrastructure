-- ============================================================================
-- Seed data for auth-service database (auth_db)
-- Provides test credentials and role assignments.
-- ============================================================================

-- Pre-determined UUIDs shared across all microservices.
-- Admin:      a0000000-0000-0000-0000-000000000001
-- Customer:   b0000000-0000-0000-0000-000000000002
-- Master:     c0000000-0000-0000-0000-000000000003

-- ----------------------------------------------------------------------------
-- Credentials
-- ----------------------------------------------------------------------------
-- Password hashes are bcrypt ($2a$10$...):
--   admin123    -> $2a$10$k/o5i6ykutXmWcuOjLHBieTXp2ulIMPcV73rrKNJMFeWaqgtgCs86
--   password123 -> $2a$10$Qavju8a4yExEjFrIw1/AP.Nm6l2cok4om/7MsJz3Tj2jRJS86cEZy
-- ----------------------------------------------------------------------------

INSERT INTO credentials (id, email, password_hash, verified, created_at)
VALUES
    ('a0000000-0000-0000-0000-000000000001', 'admin@example.com',    '$2a$10$k/o5i6ykutXmWcuOjLHBieTXp2ulIMPcV73rrKNJMFeWaqgtgCs86', TRUE,  NOW()),
    ('b0000000-0000-0000-0000-000000000002', 'customer@example.com', '$2a$10$Qavju8a4yExEjFrIw1/AP.Nm6l2cok4om/7MsJz3Tj2jRJS86cEZy', TRUE,  NOW()),
    ('c0000000-0000-0000-0000-000000000003', 'master@example.com',   '$2a$10$Qavju8a4yExEjFrIw1/AP.Nm6l2cok4om/7MsJz3Tj2jRJS86cEZy', TRUE,  NOW())
ON CONFLICT (id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- User roles
-- ----------------------------------------------------------------------------

INSERT INTO user_roles (user_id, role, created_at)
VALUES
    -- Admin: has both 'user' and 'admin' roles
    ('a0000000-0000-0000-0000-000000000001', 'user',  NOW()),
    ('a0000000-0000-0000-0000-000000000001', 'admin', NOW()),

    -- Customer: basic user role
    ('b0000000-0000-0000-0000-000000000002', 'user', NOW()),

    -- Master: has both 'user' and 'master' roles
    ('c0000000-0000-0000-0000-000000000003', 'user',   NOW()),
    ('c0000000-0000-0000-0000-000000000003', 'master', NOW())
ON CONFLICT (user_id, role) DO NOTHING;

-- ----------------------------------------------------------------------------
-- User profiles
-- ----------------------------------------------------------------------------

INSERT INTO user_profiles (user_id, name, first_name, last_name, middle_name, birthdate, phone)
VALUES
    ('a0000000-0000-0000-0000-000000000001', 'Admin User',     'Admin',   'User',     '',           NULL,            '+79000000001'),
    ('b0000000-0000-0000-0000-000000000002', 'Customer User',  'Customer', 'User',    '',           NULL,            '+79000000002'),
    ('c0000000-0000-0000-0000-000000000003', 'Master User',    'Master',   'User',    '',           NULL,            '+79000000003')
ON CONFLICT (user_id) DO NOTHING;
