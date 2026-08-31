SET search_path TO lookup;

-- Code 10 -- Initialisierung, Zuweisung LIL
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Vorarbeiten BIL (beta)',
    name_en = 'Preparation NFI management (beta)'
WHERE code = 10;

-- Code 20 -- Anlage Dienstleister und Trupps, Zuweisung Aufnahmetrupp
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Vorarbeiten LIL (beta)',
    name_en = 'Preparation state management (beta)'
WHERE code = 20;

-- Code 31 -- Erstaufnahme durch den Aufnahmetrupp
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Aufnahme im Feld AT (beta)',
    name_en = 'Field survey (beta)'
WHERE code = 31;

-- Code 32 -- Wiederholung oder Korrektur durch den Aufnahmetrupp
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Aufnahme im Feld AT (beta)',
    name_en = 'Repeat survey (beta)'
WHERE code = 32;

-- Code 41 -- Feldaufnahme beendet, Pruefung durch die LIL
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Qualitaetskontrolle LIL (beta)',
    name_en = 'Quality control state (beta)'
WHERE code = 41;

-- Code 42 -- Pruefung nach Korrektur oder Wiederholungsaufnahme
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Qualitaetskontrolle LIL (beta)',
    name_en = 'Quality control state (beta)'
WHERE code = 42;

-- Code 43 -- Pruefung nach Einsatz des Kontrolltrupps
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Qualitaetskontrolle LIL (beta)',
    name_en = 'Quality control state (beta)'
WHERE code = 43;

-- Code 44 -- Pruefung nach Rueckgabe durch die BIL
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Qualitaetskontrolle LIL (beta)',
    name_en = 'Quality control state (beta)'
WHERE code = 44;

-- Code 50 -- Kontrolltrupp erhebt Daten
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Kontrolle/Korrektur im Feld (beta)',
    name_en = 'Control survey (beta)'
WHERE code = 50;

-- Code 60 -- Von der LIL akzeptiert, Pruefung durch die BIL
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Qualitaetskontrolle BIL (beta)',
    name_en = 'Quality control NFI (beta)'
WHERE code = 60;

-- Code 70 -- Ecke abgeschlossen
UPDATE lookup.lookup_workflow_status SET
    name_de = 'Akzeptiert BIL (beta)',
    name_en = 'Accepted (beta)'
WHERE code = 70;

COMMENT ON TABLE lookup.lookup_workflow_status IS
    'Eckenstatus (Workflow-Code) nach TFM-Documentation Issue #14. Wird von public.record_workflow_code() erzeugt, nicht von Hand gesetzt. Bezeichnungen tragen bis zur Abnahme den Zusatz "(beta)".';
