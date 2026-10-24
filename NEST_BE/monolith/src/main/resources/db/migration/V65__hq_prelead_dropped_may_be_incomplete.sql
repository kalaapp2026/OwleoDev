-- V64 required every column for any row that is not a PRELEAD. A pre-lead that is dropped is still
-- the same incomplete row (it never had an owner, plan or bank accounts), so DROPPED must be allowed
-- to be incomplete too. A dropped *lead* keeps what it had; nothing needs to clear it.
ALTER TABLE hq_leads DROP CONSTRAINT hq_leads_lead_complete;
ALTER TABLE hq_leads ADD CONSTRAINT hq_leads_lead_complete CHECK (
    stage IN ('PRELEAD', 'DROPPED') OR (
        academy_email IS NOT NULL AND academy_phone IS NOT NULL AND address_line1 IS NOT NULL AND pin IS NOT NULL
        AND owner_name IS NOT NULL AND owner_phone IS NOT NULL AND owner_email IS NOT NULL
        AND plan_code IS NOT NULL AND est_students IS NOT NULL AND demo_days IS NOT NULL
    )
);
