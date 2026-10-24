-- HQ Onboarding gets a stage BEFORE the lead: PRELEAD.
--
-- A pre-lead is an academy HQ has heard of and wants to follow up: only the academy's own details
-- (name, type, where it is, how to reach it). None of what a lead needs to become a real account -
-- the owner, the plan, the expected students, the bank accounts - is known yet, so those columns must
-- be allowed to be empty for this stage.
--
-- Making a lead out of a pre-lead fills them in. From LEAD onwards they are required again, now by
-- the database and not only by the form, so a half-filled row can never reach a demo.
ALTER TABLE hq_leads DROP CONSTRAINT hq_leads_stage_check;
ALTER TABLE hq_leads ADD CONSTRAINT hq_leads_stage_check
    CHECK (stage IN ('PRELEAD', 'LEAD', 'DEMO', 'LIVE', 'DROPPED'));

ALTER TABLE hq_leads
    ALTER COLUMN academy_email DROP NOT NULL,
    ALTER COLUMN academy_phone DROP NOT NULL,
    ALTER COLUMN address_line1 DROP NOT NULL,
    ALTER COLUMN pin           DROP NOT NULL,
    ALTER COLUMN owner_name    DROP NOT NULL,
    ALTER COLUMN owner_phone   DROP NOT NULL,
    ALTER COLUMN owner_email   DROP NOT NULL,
    ALTER COLUMN plan_code     DROP NOT NULL,
    ALTER COLUMN est_students  DROP NOT NULL,
    ALTER COLUMN demo_days     DROP NOT NULL;

-- Every row that is not a pre-lead still has all of it.
ALTER TABLE hq_leads ADD CONSTRAINT hq_leads_lead_complete CHECK (
    stage = 'PRELEAD' OR (
        academy_email IS NOT NULL AND academy_phone IS NOT NULL AND address_line1 IS NOT NULL AND pin IS NOT NULL
        AND owner_name IS NOT NULL AND owner_phone IS NOT NULL AND owner_email IS NOT NULL
        AND plan_code IS NOT NULL AND est_students IS NOT NULL AND demo_days IS NOT NULL
    )
);
