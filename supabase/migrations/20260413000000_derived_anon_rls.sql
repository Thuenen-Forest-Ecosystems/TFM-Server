-- Fix: allow anon role to SELECT on derived tables (RLS policies)
-- The original migration only granted SELECT TO authenticated.

DROP POLICY IF EXISTS "allow_read_derived_tree" ON derived.tree;
CREATE POLICY "allow_read_derived_tree" ON derived.tree FOR SELECT TO authenticated, anon USING (true);

DROP POLICY IF EXISTS "allow_read_derived_regen" ON derived.regeneration;
CREATE POLICY "allow_read_derived_regen" ON derived.regeneration FOR SELECT TO authenticated, anon USING (true);

DROP POLICY IF EXISTS "allow_read_derived_dw" ON derived.deadwood;
CREATE POLICY "allow_read_derived_dw" ON derived.deadwood FOR SELECT TO authenticated, anon USING (true);
