-- A readable number on every bill, and the GST rate that was in force when it was raised.
--
-- gst_rate is stored per bill so that changing the rate later never rewrites an old bill, and so
-- that bills raised before GST was charged at all (rate 0) keep their original total when an
-- adjustment or offer makes the bill be recalculated.
ALTER TABLE academy_invoices ADD COLUMN gst_rate NUMERIC(5,2) NOT NULL DEFAULT 0;
ALTER TABLE academy_invoices ADD COLUMN number   VARCHAR(24);

UPDATE academy_invoices i SET number = x.n
FROM (SELECT id, 'INV-' || substr(period, 3, 2) || substr(period, 6, 2) || '-' ||
             lpad((row_number() OVER (PARTITION BY period ORDER BY created_at, id))::text, 3, '0') AS n
      FROM academy_invoices) x
WHERE x.id = i.id;

ALTER TABLE academy_invoices ALTER COLUMN number SET NOT NULL;
CREATE UNIQUE INDEX uq_invoice_number ON academy_invoices (number);
