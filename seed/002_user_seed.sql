-- ============================================================================
-- Seed data for user-service database (user_db)
-- Provides user profiles, master profiles, and role assignments.
-- ============================================================================

-- Pre-determined UUIDs (consistent with auth-service seed):
-- Admin:      a0000000-0000-0000-0000-000000000001
-- Customer:   b0000000-0000-0000-0000-000000000002
-- Master:     c0000000-0000-0000-0000-000000000003

-- ----------------------------------------------------------------------------
-- User profiles
-- ----------------------------------------------------------------------------

INSERT INTO user_profiles (id, first_name, last_name, avatar_url, phone, birthdate, updated_at)
VALUES
    ('a0000000-0000-0000-0000-000000000001', 'Admin',   'Adminov',  '', '+79991112233', '1990-01-15', NOW()),
    ('b0000000-0000-0000-0000-000000000002', 'Ivan',    'Ivanov',   '', '+79992223344', '1995-05-20', NOW()),
    ('c0000000-0000-0000-0000-000000000003', 'Petr',    'Petrov',   '', '+79993334455', '1988-09-10', NOW())
ON CONFLICT (id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- Master profile (only for the master user)
-- ----------------------------------------------------------------------------

INSERT INTO master_profiles (user_id, is_active, description, experience_years, rating, completed_orders, updated_at)
VALUES
    ('c0000000-0000-0000-0000-000000000003', TRUE, 'Experienced full-stack developer specializing in web and mobile applications.', 7, 4.85, 42, NOW())
ON CONFLICT (user_id) DO NOTHING;

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
