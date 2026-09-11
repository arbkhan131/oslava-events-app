-- P1 phone registration foundation: add explicit approval states.

DO $$
BEGIN
  ALTER TYPE public.account_status ADD VALUE IF NOT EXISTS 'PENDING_APPROVAL';
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TYPE public.account_status ADD VALUE IF NOT EXISTS 'REJECTED';
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
