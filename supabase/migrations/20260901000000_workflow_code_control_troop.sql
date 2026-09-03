-- ============================================================================
-- MIGRATION: Abgabe des Kontrolltrupps fuehrt auf Code 43, nicht auf 50
-- ============================================================================
-- Gemeldet im Beta-Test am 01.09.2026:
-- https://github.com/Thuenen-Forest-Ecosystems/TFM-Documentation/issues/14
--   "Kontrolltrupp ist fertig (completed_at_tropp gesetzt), es erfolgt kein
--    Wechsel auf Status 43"
--
-- Ursache: in public.record_workflow_code() aus 20260825000000 stand die Regel
-- fuer 50 vor allen completed_at_troop-Regeln. Der Kontrolltrupp bleibt nach
-- seiner Abgabe zugewiesen -- die Abgabe setzt nur completed_at_troop und
-- raeumt responsible_troop nicht ab --, also blieb 50 dauerhaft der erste
-- Treffer und die Ecke hing in "Aufnahme KT" fest.
--
-- Korrektur: eine Regel fuer 43 VOR der Regel fuer 50. Sie fragt
-- is_control_troop des aktuell zugewiesenen Trupps ab und nicht
-- seen_control_troop aus der Historie; damit braucht der Wechsel keine bereits
-- geschriebene record_changes-Zeile, sondern greift mit der Abgabe selbst. Die
-- Historien-Variante bleibt darunter stehen: sie deckt die Ecken ab, deren
-- Kontrolltrupp nach der Abgabe wieder abgezogen wurde.
--
-- Damit gewinnt 43 auch gegen 44. Das ist die gewollte Reihenfolge "spaetestes
-- Ereignis zuerst": ein Kontrolltrupp, der jetzt noch zugewiesen ist, wurde
-- nach einer etwaigen Rueckgabe durch die BIL eingesetzt.
--
-- Die Signatur bleibt gleich, deshalb genuegt CREATE OR REPLACE.
-- public.view_records_details zeigt unveraendert auf diese Funktion und wird
-- nicht angefasst -- es bleibt bei einer einzigen Definition der Ableitung.
-- ============================================================================

SET search_path TO public;

CREATE OR REPLACE FUNCTION public.record_workflow_code(
    rec public.records,
    is_control_troop boolean,
    repeated_survey boolean,
    seen_control_troop boolean,
    returned_by_administration boolean
) RETURNS smallint
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
SELECT (CASE
    WHEN rec.completed_at_administration IS NOT NULL                       THEN 70
    WHEN rec.completed_at_state          IS NOT NULL                       THEN 60
    WHEN rec.completed_at_troop IS NOT NULL AND is_control_troop           THEN 43
    WHEN rec.responsible_troop  IS NOT NULL AND is_control_troop           THEN 50
    WHEN rec.completed_at_troop IS NOT NULL AND returned_by_administration THEN 44
    WHEN rec.completed_at_troop IS NOT NULL AND seen_control_troop         THEN 43
    WHEN rec.completed_at_troop IS NOT NULL AND repeated_survey            THEN 42
    WHEN rec.completed_at_troop          IS NOT NULL                       THEN 41
    WHEN rec.responsible_troop  IS NOT NULL AND repeated_survey            THEN 32
    WHEN rec.responsible_troop           IS NOT NULL                       THEN 31
    WHEN rec.responsible_state           IS NOT NULL                       THEN 20
    WHEN rec.responsible_administration  IS NOT NULL                       THEN 10
END)::smallint;
$$;

COMMENT ON FUNCTION public.record_workflow_code(public.records, boolean, boolean, boolean, boolean) IS
    'Eckenstatus einer records-Zeile nach lookup.lookup_workflow_status. is_control_troop aus troop.is_control_troop des zugewiesenen Trupps, die uebrigen drei aus public.view_record_workflow_history. Ein noch zugewiesener Kontrolltrupp ergibt 50 vor und 43 nach seiner Abgabe. NULL, wenn nicht einmal responsible_administration gesetzt ist.';
