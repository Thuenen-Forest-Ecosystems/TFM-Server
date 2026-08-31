SET search_path TO lookup;

-- Code 10 -- Initialisierung, Zuweisung LIL
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Vorarbeiten BIL (beta)',
    name_en = 'Preparatory work federal administration (beta)'
WHERE code = 10;

-- Code 20 -- Anlage Dienstleister und Trupps, Zuweisung Aufnahmetrupp
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Vorarbeiten LIL (beta)',
    name_en = 'Preparatory work state administration (beta)'
WHERE code = 20;

-- Code 31 -- Erstaufnahme durch den Aufnahmetrupp
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Erstaufnahme AT (beta)',
    name_en = 'Initial data collection field team (beta)'
WHERE code = 31;

-- Code 32 -- Wiederholung oder Korrektur durch den Aufnahmetrupp
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Wiederholung/Korrektur AT (beta)',
    name_en = 'Revision/repetition by field team (beta)'
WHERE code = 32;

-- Code 41 -- Feldaufnahme beendet, Pruefung durch die LIL
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Kontrolle LIL nach AT Erstaufnahme (beta)',
    name_en = 'Data check state administration after initial field work (beta)'
WHERE code = 41;

-- Code 42 -- Prüfung nach Korrektur oder Wiederholungsaufnahme
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Kontrolle LIL nach AT Korrektur/Wiederholung (beta)',
    name_en = 'Data check state administration after repetition (beta)'
WHERE code = 42;

-- Code 43 -- Prüfung nach Einsatz des Kontrolltrupps
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Kontrolle LIL nach KT (beta)',
    name_en = 'Data check state administration after control team (beta)'
WHERE code = 43;

-- Code 44 -- Prüfung nach Rückgabe durch die BIL
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Kontrolle LIL nach Rückgabe BIL (beta)',
    name_en = 'Data check state administration after rejection by federal administration (beta)'
WHERE code = 44;

-- Code 50 -- Kontrolltrupp erhebt Daten
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Aufnahme KT (beta)',
    name_en = 'Data collection by control team (beta)'
WHERE code = 50;

-- Code 60 -- Von der LIL akzeptiert, Prüfung durch die BIL
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Kontrolle BIL (beta)',
    name_en = 'Data check federal administration (beta)'
WHERE code = 60;

-- Code 70 -- Ecke abgeschlossen
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Akzeptiert BIL (beta)',
    name_en = 'Accepted by federal administration (beta)'
WHERE code = 70;

COMMENT ON TABLE lookup.lookup_workflow_status IS
    'Eckenstatus (Workflow-Code) nach TFM-Documentation Issue #14. Wird von public.record_workflow_code() erzeugt, nicht von Hand gesetzt. Bezeichnungen tragen bis zur Abnahme den Zusatz "(beta)".';
