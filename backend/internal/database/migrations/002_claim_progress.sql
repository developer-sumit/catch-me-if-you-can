-- Delivery lifecycle for claims: claimed -> picked_up -> out_for_delivery -> completed.
-- Migrations replay on every boot, so every statement here is idempotent.
ALTER TABLE claims ADD COLUMN IF NOT EXISTS picked_up_at timestamptz;
ALTER TABLE claims ADD COLUMN IF NOT EXISTS out_for_delivery_at timestamptz;
ALTER TABLE claims DROP CONSTRAINT IF EXISTS claims_status_check;
ALTER TABLE claims ADD CONSTRAINT claims_status_check CHECK (status IN ('claimed','picked_up','out_for_delivery','completed','cancelled'));
CREATE INDEX IF NOT EXISTS idx_claims_kitchen_claimed ON claims(kitchen_id,claimed_at DESC);
