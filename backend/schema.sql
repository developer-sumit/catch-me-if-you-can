-- Soul Serve — complete database schema for a new setup.
--
-- This is the consolidated result of every migration in
-- backend/internal/database/migrations, flattened into one file so a fresh
-- database can be created in a single step:
--
--     psql "$DATABASE_URL" -f backend/schema.sql
--
-- The API still applies its embedded migrations on every boot. Those are
-- idempotent, so running them against a database created from this file is a
-- no-op. When you add a migration, add the same change here.
--
-- Constraints are named explicitly rather than left to PostgreSQL's defaults,
-- because migrations refer to them by name (002 drops and recreates
-- claims_status_check). A database built from this file and one built from the
-- migrations must end up with identical constraint names.

BEGIN;

-- gen_random_uuid() for primary keys.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------- users
-- Kitchens publish surplus; NGOs claim and deliver it. Both live in one table
-- and are told apart by role.
CREATE TABLE IF NOT EXISTS users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL,
  email         text NOT NULL UNIQUE,
  -- bcrypt digest; never a plaintext or reversible value.
  password_hash text NOT NULL,
  role          text NOT NULL CONSTRAINT users_role_check CHECK (role IN ('kitchen','ngo')),
  organization  text NOT NULL DEFAULT '',
  phone         text NOT NULL DEFAULT '',
  address       text NOT NULL DEFAULT '',
  -- Optional, but the service requires both or neither: distance ranking
  -- needs the pair. Enforced in the service layer, not by a constraint, to
  -- match what the migrations build.
  latitude      double precision,
  longitude     double precision,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------- waste_logs
-- One batch of surplus food offered by a kitchen.
CREATE TABLE IF NOT EXISTS waste_logs (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kitchen_id uuid NOT NULL REFERENCES users(id),
  food_type  text NOT NULL,
  quantity   double precision NOT NULL
             CONSTRAINT waste_logs_quantity_check CHECK (quantity > 0),
  unit       text NOT NULL DEFAULT 'kg',
  status     text NOT NULL DEFAULT 'pending'
             CONSTRAINT waste_logs_status_check
             CHECK (status IN ('pending','claimed','completed','expired')),
  claimed_by uuid REFERENCES users(id),
  claimed_at timestamptz,
  notes      text NOT NULL DEFAULT '',
  log_date   date NOT NULL DEFAULT CURRENT_DATE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- --------------------------------------------------------------- claims
-- An NGO's reservation of one waste log, tracked through the delivery
-- progression claimed -> picked_up -> out_for_delivery -> completed. Each
-- stage stamps its own timestamp; a skipped stage simply leaves its column
-- null. The UNIQUE on waste_log_id is what makes claiming race-safe: two NGOs
-- tapping "Claim" at once, only one row survives.
CREATE TABLE IF NOT EXISTS claims (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  waste_log_id        uuid NOT NULL UNIQUE REFERENCES waste_logs(id),
  ngo_id              uuid NOT NULL REFERENCES users(id),
  kitchen_id          uuid NOT NULL REFERENCES users(id),
  status              text NOT NULL DEFAULT 'claimed'
                      CONSTRAINT claims_status_check
                      CHECK (status IN ('claimed','picked_up','out_for_delivery','completed','cancelled')),
  claimed_at          timestamptz NOT NULL DEFAULT now(),
  -- Order matches what the migrations leave behind: 002 appends the two
  -- stage timestamps after completed_at.
  completed_at        timestamptz,
  picked_up_at        timestamptz,
  out_for_delivery_at timestamptz
);

-- -------------------------------------------------------------- indexes
-- Each one backs a query the dashboards run on every load.
CREATE INDEX IF NOT EXISTS idx_waste_kitchen_created
  ON waste_logs (kitchen_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_waste_available
  ON waste_logs (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_claims_ngo_claimed
  ON claims (ngo_id, claimed_at DESC);
CREATE INDEX IF NOT EXISTS idx_claims_kitchen_claimed
  ON claims (kitchen_id, claimed_at DESC);

COMMIT;
