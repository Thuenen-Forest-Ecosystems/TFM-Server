-- ============================================================================
-- STATISTICS: Helper views for Statistics and Analytics
-- ============================================================================
-- THis are helper views for statistics and analytics. They are used by the application directly
-- to generate reports tables and CSV-files for inventory progress insights.
-- ============================================================================
SET search_path TO public;

-- v_plots_not_accessible_due_to_calamities
create or replace view public.v_plots_not_accessible_due_to_calamities with ( security_invoker = true ) as
select
  r.id,
  r.responsible_state,
  o.name as lil,
  r.cluster_id,
  r.cluster_name,
  r.plot_name,
  r.responsible_administration,
  r.responsible_provider,
  r.responsible_troop,
  t.name as troop_name,
  r.completed_at_troop,
  t.is_control_troop as kt,
  r.properties ->> 'forest_status'::text as wald2027,
  a.name_de as wald2027_text,
  r.properties ->> 'accessibility'::text as begehbar2027,
  c.name_de as begehbar2027_text
from
  records r
  join troop t on r.responsible_troop = t.id
  join organizations o on r.responsible_state = o.id
  join lookup.lookup_forest_status a on (r.properties ->> 'forest_status'::text) = a.code::text
  join lookup.lookup_forest_status b on (r.previous_properties ->> 'forest_status'::text) = b.code::text
  join lookup.lookup_accessibility c on (r.properties ->> 'accessibility'::text) = c.code::text
where
  r.completed_at_troop is not null
  and (
    (r.properties ->> 'accessibility'::text) = any (array[6::text, 7::text, 8::text])
  );
  a.grenzart = '42'::jsonb;

-- v_stats_count_controlled_by_kt
create or replace view public.v_stats_count_controlled_by_kt with ( security_invoker = true ) as
select
  tt.responsible_state,
  tt.responsible_administration,
  tt.responsible_provider,
  tt.lil,
  tt.responsible_troop,
  tt.troop_name as aufnahmetrupp,
  count(tt.completed_at_troop_latest) as anzahl_abgabe_at,
  sum(
    case
      when kk.completed_at_troop_latest is null then 0
      else 1
    end
  ) as anzahl_kontrolliert
from
  (
    select
      t.responsible_state,
      t.lil,
      t.cluster_id,
      t.cluster_name,
      t.plot_name,
      t.responsible_administration,
      t.responsible_provider,
      t.responsible_troop,
      t.troop_name,
      max(t.completed_at_troop) as completed_at_troop_latest
    from
      (
        select
          r1.id,
          r1.responsible_state,
          o1.name as lil,
          r1.cluster_id,
          r1.cluster_name,
          r1.plot_name,
          r1.responsible_administration,
          r1.responsible_provider,
          r1.responsible_troop,
          t1.name as troop_name,
          r1.completed_at_troop
        from
          records r1
          join troop t1 on r1.responsible_troop = t1.id
          join organizations o1 on r1.responsible_state = o1.id
        where
          r1.cluster_name < 1000000000
          and (
            r1.cluster_name < 9999900
            or r1.cluster_name > 10000000
          )
          and r1.completed_at_troop is not null
          and t1.is_control_troop is false
        union
        select
          c2.id,
          c2.responsible_state,
          o2.name as lil,
          c2.cluster_id,
          c2.cluster_name,
          c2.plot_name,
          c2.responsible_administration,
          c2.responsible_provider,
          c2.responsible_troop,
          t2.name as troop_name,
          c2.completed_at_troop
        from
          record_changes c2
          join troop t2 on c2.responsible_troop = t2.id
          join organizations o2 on c2.responsible_state = o2.id
        where
          c2.cluster_name < 1000000000
          and (
            c2.cluster_name < 9999900
            or c2.cluster_name > 10000000
          )
          and c2.completed_at_troop is not null
          and t2.is_control_troop is false
      ) t
    group by
      t.responsible_state,
      t.lil,
      t.cluster_id,
      t.cluster_name,
      t.plot_name,
      t.responsible_administration,
      t.responsible_provider,
      t.responsible_troop,
      t.troop_name
  ) tt
  left join (
    select
      k.responsible_state,
      k.lil,
      k.cluster_id,
      k.cluster_name,
      k.plot_name,
      k.responsible_administration,
      k.responsible_provider,
      k.responsible_troop,
      k.troop_name,
      max(k.completed_at_troop) as completed_at_troop_latest
    from
      (
        select
          r3.id,
          r3.responsible_state,
          o3.name as lil,
          r3.cluster_id,
          r3.cluster_name,
          r3.plot_name,
          r3.responsible_administration,
          r3.responsible_provider,
          r3.responsible_troop,
          t3.name as troop_name,
          r3.completed_at_troop
        from
          records r3
          join troop t3 on r3.responsible_troop = t3.id
          join organizations o3 on r3.responsible_state = o3.id
        where
          r3.cluster_name < 1000000000
          and (
            r3.cluster_name < 9999900
            or r3.cluster_name > 10000000
          )
          and r3.completed_at_troop is not null
          and t3.is_control_troop is true
        union
        select
          c4.id,
          c4.responsible_state,
          o4.name as lil,
          c4.cluster_id,
          c4.cluster_name,
          c4.plot_name,
          c4.responsible_administration,
          c4.responsible_provider,
          c4.responsible_troop,
          t4.name as troop_name,
          c4.completed_at_troop
        from
          record_changes c4
          join troop t4 on c4.responsible_troop = t4.id
          join organizations o4 on c4.responsible_state = o4.id
        where
          c4.cluster_name < 1000000000
          and (
            c4.cluster_name < 9999900
            or c4.cluster_name > 10000000
          )
          and c4.completed_at_troop is not null
          and t4.is_control_troop is true
      ) k
    group by
      k.responsible_state,
      k.lil,
      k.cluster_id,
      k.cluster_name,
      k.plot_name,
      k.responsible_administration,
      k.responsible_provider,
      k.responsible_troop,
      k.troop_name
  ) kk on tt.cluster_name = kk.cluster_name
  and tt.plot_name = kk.plot_name
group by
  tt.responsible_state,
  tt.responsible_administration,
  tt.lil,
  tt.responsible_provider,
  tt.responsible_troop,
  tt.troop_name;

-- v_stats_forest_access_change
create or replace view public.v_stats_forest_access_change with ( security_invoker = true ) as
select
  r.id,
  r.responsible_state,
  o.name as lil,
  r.cluster_id,
  r.cluster_name,
  r.plot_name,
  r.responsible_administration,
  r.responsible_provider,
  r.responsible_troop,
  t.name as troop_name,
  r.completed_at_troop,
  t.is_control_troop as kt,
  r.properties ->> 'forest_status'::text as wald2027,
  r.previous_properties ->> 'forest_status'::text as wald_vorgaenger,
  r.properties ->> 'accessibility'::text as begehbar2027,
  a.name_de as begehbar2027_text,
  r.previous_properties ->> 'accessibility'::text as begehbar_vorgaenger,
  b.name_de as begehbar_vorgaenger_text
from
  records r
  join troop t on r.responsible_troop = t.id
  join organizations o on r.responsible_state = o.id
  join lookup.lookup_accessibility a on (r.properties ->> 'accessibility'::text) = a.code::text
  join lookup.lookup_accessibility b on (r.previous_properties ->> 'accessibility'::text) = b.code::text
where
  r.completed_at_troop is not null
  and (r.properties ->> 'accessibility'::text) <> (r.previous_properties ->> 'accessibility'::text);

-- v_stats_forest_boundaries_unchanged
create or replace view public.v_stats_forest_boundaries_unchanged with ( security_invoker = true ) as
select
  a.id,
  a.responsible_state,
  a.lil,
  a.cluster_id,
  a.cluster_name,
  a.plot_name,
  a.responsible_administration,
  a.responsible_provider,
  a.responsible_troop,
  a.troop_name,
  a.completed_at_troop,
  a.kt,
  a.grenznummer,
  a.grenzart,
  a.vorgelagerter_bestand,
  e.name_de as vorgelagerter_bestand_text
from
  (
    select
      r.id,
      r.responsible_state,
      o.name as lil,
      r.cluster_id,
      r.cluster_name,
      r.plot_name,
      r.responsible_administration,
      r.responsible_provider,
      r.responsible_troop,
      t.name as troop_name,
      r.completed_at_troop,
      t.is_control_troop as kt,
      jsonb_array_elements(r.properties -> 'edges'::text) -> 'edge_number'::text as grenznummer,
      jsonb_array_elements(r.properties -> 'edges'::text) -> 'edge_type'::text as grenzart,
      jsonb_array_elements(r.properties -> 'edges'::text) -> 'edge_stand_difference'::text as vorgelagerter_bestand
    from
      records r
      join troop t on r.responsible_troop = t.id
      join organizations o on r.responsible_state = o.id
    where
      r.completed_at_troop is not null
  ) a
  join lookup.lookup_edge_stand_difference e on a.vorgelagerter_bestand::text = e.code::text
where
  a.grenzart = '42'::jsonb;

-- v_stats_forest_status_changed
create or replace view public.v_stats_forest_status_changed with ( security_invoker = true ) as
select
  r.id,
  r.responsible_state,
  o.name as lil,
  r.cluster_id,
  r.cluster_name,
  r.plot_name,
  r.responsible_administration,
  r.responsible_provider,
  r.responsible_troop,
  t.name as troop_name,
  r.completed_at_troop,
  t.is_control_troop as kt,
  r.properties ->> 'forest_status'::text as wald2027,
  a.name_de as wald2027_text,
  r.previous_properties ->> 'forest_status'::text as wald_vorgaenger,
  b.name_de as wald_vorgaenger_text,
  r.properties ->> 'accessibility'::text as begehbar2027,
  r.previous_properties ->> 'accessibility'::text as begehbar_vorgaenger
from
  records r
  join troop t on r.responsible_troop = t.id
  join organizations o on r.responsible_state = o.id
  join lookup.lookup_forest_status a on (r.properties ->> 'forest_status'::text) = a.code::text
  join lookup.lookup_forest_status b on (r.previous_properties ->> 'forest_status'::text) = b.code::text
where
  r.completed_at_troop is not null
  and (r.properties ->> 'forest_status'::text) <> (r.previous_properties ->> 'forest_status'::text);

-- v_stats_forest_status_changed_by_troop
create or replace view public.v_stats_forest_status_changed_by_troop with ( security_invoker = true ) as
select
  z.responsible_state,
  z.lil,
  z.troop_name,
  z.kt,
  sum(z.forest_status_change) as aenderung_waldentscheid,
  sum(z.accessibility_change) as aenderung_begehbar
from
  (
    select
      r.id,
      r.responsible_state,
      o.name as lil,
      r.cluster_id,
      r.cluster_name,
      r.plot_name,
      r.responsible_administration,
      r.responsible_provider,
      r.responsible_troop,
      t.name as troop_name,
      r.completed_at_troop,
      t.is_control_troop as kt,
      case
        when (r.properties ->> 'forest_status'::text) = (r.previous_properties ->> 'forest_status'::text) then 0
        else 1
      end as forest_status_change,
      case
        when (r.properties ->> 'accessibility'::text) = (r.previous_properties ->> 'accessibility'::text) then 0
        else 1
      end as accessibility_change
    from
      records r
      join troop t on r.responsible_troop = t.id
      join organizations o on r.responsible_state = o.id
      join lookup.lookup_forest_status a on (r.properties ->> 'forest_status'::text) = a.code::text
      join lookup.lookup_forest_status b on (r.previous_properties ->> 'forest_status'::text) = b.code::text
    where
      r.completed_at_troop is not null
      and r.cluster_name < 1000000000
      and (
        r.cluster_name < 9999900
        or r.cluster_name > 10000000
      )
  ) z
group by
  z.responsible_state,
  z.lil,
  z.troop_name,
  z.kt;

-- v_stats_list_controlled_by_kt
create or replace view public.v_stats_list_controlled_by_kt with ( security_invoker = true ) as
select
  tt.responsible_state,
  tt.responsible_administration,
  tt.lil,
  tt.cluster_name,
  tt.plot_name,
  tt.responsible_troop,
  tt.responsible_provider,
  tt.troop_name as aufnahmetrupp,
  tt.completed_at_troop_latest as abgabe_at,
  kk.troop_name as kontrolltrupp,
  kk.completed_at_troop_latest as abgabe_kt
from
  (
    select
      t.id,
      t.responsible_state,
      t.lil,
      t.cluster_id,
      t.cluster_name,
      t.plot_name,
      t.responsible_administration,
      t.responsible_provider,
      t.responsible_troop,
      t.troop_name,
      max(t.completed_at_troop) as completed_at_troop_latest
    from
      (
        select
          r1.id,
          r1.responsible_state,
          o1.name as lil,
          r1.cluster_id,
          r1.cluster_name,
          r1.plot_name,
          r1.responsible_administration,
          r1.responsible_provider,
          r1.responsible_troop,
          t1.name as troop_name,
          r1.completed_at_troop
        from
          records r1
          join troop t1 on r1.responsible_troop = t1.id
          join organizations o1 on r1.responsible_state = o1.id
        where
          r1.cluster_name < 1000000000
          and (
            r1.cluster_name < 9999900
            or r1.cluster_name > 10000000
          )
          and r1.completed_at_troop is not null
          and t1.is_control_troop is false
        union
        select
          c2.id,
          c2.responsible_state,
          o2.name as lil,
          c2.cluster_id,
          c2.cluster_name,
          c2.plot_name,
          c2.responsible_administration,
          c2.responsible_provider,
          c2.responsible_troop,
          t2.name as troop_name,
          c2.completed_at_troop
        from
          record_changes c2
          join troop t2 on c2.responsible_troop = t2.id
          join organizations o2 on c2.responsible_state = o2.id
        where
          c2.cluster_name < 1000000000
          and (
            c2.cluster_name < 9999900
            or c2.cluster_name > 10000000
          )
          and c2.completed_at_troop is not null
          and t2.is_control_troop is false
      ) t
    group by
      t.id,
      t.responsible_state,
      t.lil,
      t.cluster_id,
      t.cluster_name,
      t.plot_name,
      t.responsible_administration,
      t.responsible_provider,
      t.responsible_troop,
      t.troop_name
  ) tt
  left join (
    select
      k.id,
      k.responsible_state,
      k.lil,
      k.cluster_id,
      k.cluster_name,
      k.plot_name,
      k.responsible_administration,
      k.responsible_provider,
      k.responsible_troop,
      k.troop_name,
      max(k.completed_at_troop) as completed_at_troop_latest
    from
      (
        select
          r3.id,
          r3.responsible_state,
          o3.name as lil,
          r3.cluster_id,
          r3.cluster_name,
          r3.plot_name,
          r3.responsible_administration,
          r3.responsible_provider,
          r3.responsible_troop,
          t3.name as troop_name,
          r3.completed_at_troop
        from
          records r3
          join troop t3 on r3.responsible_troop = t3.id
          join organizations o3 on r3.responsible_state = o3.id
        where
          r3.cluster_name < 1000000000
          and (
            r3.cluster_name < 9999900
            or r3.cluster_name > 10000000
          )
          and r3.completed_at_troop is not null
          and t3.is_control_troop is true
        union
        select
          c4.id,
          c4.responsible_state,
          o4.name as lil,
          c4.cluster_id,
          c4.cluster_name,
          c4.plot_name,
          c4.responsible_administration,
          c4.responsible_provider,
          c4.responsible_troop,
          t4.name as troop_name,
          c4.completed_at_troop
        from
          record_changes c4
          join troop t4 on c4.responsible_troop = t4.id
          join organizations o4 on c4.responsible_state = o4.id
        where
          c4.cluster_name < 1000000000
          and (
            c4.cluster_name < 9999900
            or c4.cluster_name > 10000000
          )
          and c4.completed_at_troop is not null
          and t4.is_control_troop is true
      ) k
    group by
      k.id,
      k.responsible_state,
      k.lil,
      k.cluster_id,
      k.cluster_name,
      k.plot_name,
      k.responsible_administration,
      k.responsible_provider,
      k.responsible_troop,
      k.troop_name
  ) kk on tt.cluster_name = kk.cluster_name
  and tt.plot_name = kk.plot_name
where
  kk.completed_at_troop_latest is not null;

-- v_stats_performance_by_troop_by_month
create or replace view public.v_stats_performance_by_troop_by_month with ( security_invoker = true ) as
select
  a.responsible_state,
  a.responsible_administration,
  a.responsible_provider,
  a.lil,
  a.responsible_troop,
  a.troop_name,
  a.kt,
  to_char(a.completed_as_troop_latest, 'YYYY-MM'::text) as monat,
  count(*) as anzahl
from
  (
    select
      rr.responsible_state,
      rr.responsible_administration,
      rr.responsible_provider,
      o.name as lil,
      rr.cluster_name,
      rr.plot_name,
      rr.responsible_troop,
      t.name as troop_name,
      t.is_control_troop as kt,
      rr.completed_as_troop_latest,
      rr.wald2027,
      rr.begehbar2027
    from
      (
        select
          r.responsible_state,
          r.responsible_administration,
          r.responsible_provider,
          r.cluster_name,
          r.plot_name,
          COALESCE(r.responsible_troop, c.responsible_troop) as responsible_troop,
          COALESCE(r.completed_at_troop, c.completed_at_troop) as completed_as_troop_latest,
          r.wald2027,
          r.begehbar2027
        from
          (
            select
              records.id,
              records.responsible_state,
              records.cluster_name,
              records.plot_name,
              records.responsible_administration,
              records.responsible_provider,
              records.responsible_troop,
              records.completed_at_troop,
              records.properties ->> 'forest_status'::text as wald2027,
              records.properties ->> 'accessibility'::text as begehbar2027
            from
              records
            where
              records.completed_at_troop is not null
              and records.cluster_name < 1000000000
              and (
                records.cluster_name < 9999900
                or records.cluster_name > 10000000
              )
          ) r
          left join (
            select
              record_changes.cluster_name,
              record_changes.plot_name,
              record_changes.responsible_troop,
              max(record_changes.completed_at_troop) as completed_at_troop
            from
              record_changes
            where
              record_changes.completed_at_troop is not null
              and record_changes.cluster_name < 1000000000
              and (
                record_changes.cluster_name < 9999900
                or record_changes.cluster_name > 10000000
              )
            group by
              record_changes.cluster_name,
              record_changes.plot_name,
              record_changes.responsible_troop
          ) c on r.cluster_name = c.cluster_name
          and r.plot_name = c.plot_name
          and r.responsible_troop = c.responsible_troop
      ) rr
      join troop t on rr.responsible_troop = t.id
      join organizations o on rr.responsible_state = o.id
  ) a
group by
  a.responsible_state,
  a.responsible_administration,
  a.responsible_provider,
  a.lil,
  a.responsible_troop,
  a.troop_name,
  a.kt,
  (
    to_char(a.completed_as_troop_latest, 'YYYY-MM'::text)
  )
order by
  a.lil,
  a.troop_name,
  (
    to_char(a.completed_as_troop_latest, 'YYYY-MM'::text)
  );

-- v_stats_performance_by_troop_by_week
create or replace view public.v_stats_performance_by_troop_by_week with ( security_invoker = true ) as
select
  a.responsible_state,
  a.responsible_administration,
  a.responsible_provider,
  a.lil,
  a.responsible_troop,
  a.troop_name,
  a.kt,
  to_char(a.completed_as_troop_latest, 'IYYY-IW'::text) as woche,
  count(*) as anzahl
from
  (
    select
      rr.responsible_state,
      rr.responsible_administration,
      rr.responsible_provider,
      o.name as lil,
      rr.cluster_name,
      rr.plot_name,
      rr.responsible_troop,
      t.name as troop_name,
      t.is_control_troop as kt,
      rr.completed_as_troop_latest,
      rr.wald2027,
      rr.begehbar2027
    from
      (
        select
          r.responsible_state,
          r.responsible_administration,
          r.responsible_provider,
          r.cluster_name,
          r.plot_name,
          COALESCE(r.responsible_troop, c.responsible_troop) as responsible_troop,
          COALESCE(r.completed_at_troop, c.completed_at_troop) as completed_as_troop_latest,
          r.wald2027,
          r.begehbar2027
        from
          (
            select
              records.id,
              records.responsible_state,
              records.cluster_name,
              records.plot_name,
              records.responsible_administration,
              records.responsible_provider,
              records.responsible_troop,
              records.completed_at_troop,
              records.properties ->> 'forest_status'::text as wald2027,
              records.properties ->> 'accessibility'::text as begehbar2027
            from
              records
            where
              records.completed_at_troop is not null
              and records.cluster_name < 1000000000
              and (
                records.cluster_name < 9999900
                or records.cluster_name > 10000000
              )
          ) r
          left join (
            select
              record_changes.cluster_name,
              record_changes.plot_name,
              record_changes.responsible_troop,
              max(record_changes.completed_at_troop) as completed_at_troop
            from
              record_changes
            where
              record_changes.completed_at_troop is not null
              and record_changes.cluster_name < 1000000000
              and (
                record_changes.cluster_name < 9999900
                or record_changes.cluster_name > 10000000
              )
            group by
              record_changes.cluster_name,
              record_changes.plot_name,
              record_changes.responsible_troop
          ) c on r.cluster_name = c.cluster_name
          and r.plot_name = c.plot_name
          and r.responsible_troop = c.responsible_troop
      ) rr
      join troop t on rr.responsible_troop = t.id
      join organizations o on rr.responsible_state = o.id
  ) a
group by
  a.responsible_state,
  a.responsible_administration,
  a.responsible_provider,
  a.lil,
  a.responsible_troop,
  a.troop_name,
  a.kt,
  (
    to_char(a.completed_as_troop_latest, 'IYYY-IW'::text)
  )
order by
  a.lil,
  a.troop_name,
  (
    to_char(a.completed_as_troop_latest, 'IYYY-IW'::text)
  );

-- v_stats_plots_new_marker
create or replace view public.v_stats_plots_new_marker with ( security_invoker = true ) as
select
  r.id,
  r.responsible_state,
  o.name as lil,
  r.cluster_id,
  r.cluster_name,
  r.plot_name,
  r.responsible_administration,
  r.responsible_provider,
  r.responsible_troop,
  t.name as troop_name,
  r.completed_at_troop,
  t.is_control_troop as kt,
  r.properties ->> 'marker_status'::text as marker_status,
  'alte Markierung nicht wiedergefunden, jedoch Ecke eindeutig identifiziert, neue Marke gesetzt'::text as beschreibung
from
  records r
  join troop t on r.responsible_troop = t.id
  join organizations o on r.responsible_state = o.id
where
  r.completed_at_troop is not null
  and (r.properties ->> 'marker_status'::text) = '2'::text;

-- v_stats_plots_new_marker_3
create or replace view public.v_stats_plots_new_marker_3 with ( security_invoker = true ) as
select
  r.id,
  r.responsible_state,
  o.name as lil,
  r.cluster_id,
  r.cluster_name,
  r.plot_name,
  r.responsible_administration,
  r.responsible_provider,
  r.responsible_troop,
  t.name as troop_name,
  r.completed_at_troop,
  t.is_control_troop as kt,
  r.properties ->> 'marker_status'::text as marker_status,
  'erstmals Markierung gesetzt'::text as beschreibung
from
  records r
  join troop t on r.responsible_troop = t.id
  join organizations o on r.responsible_state = o.id
where
  r.completed_at_troop is not null
  and (r.properties ->> 'marker_status'::text) = '3'::text;

-- v_stats_plots_new_marker_4
create or replace view public.v_stats_plots_new_marker_4 with ( security_invoker = true ) as
select
  r.id,
  r.responsible_state,
  o.name as lil,
  r.cluster_id,
  r.cluster_name,
  r.plot_name,
  r.responsible_administration,
  r.responsible_provider,
  r.responsible_troop,
  t.name as troop_name,
  r.completed_at_troop,
  t.is_control_troop as kt,
  r.properties ->> 'marker_status'::text as marker_status,
  'alte Markierung nicht gefunden; Neuaufnahme'::text as beschreibung
from
  records r
  join troop t on r.responsible_troop = t.id
  join organizations o on r.responsible_state = o.id
where
  r.completed_at_troop is not null
  and r.cluster_name < 1000000000
  and (
    r.cluster_name < 9999900
    or r.cluster_name > 10000000
  )
  and (r.properties ->> 'marker_status'::text) = '4'::text;

-- v_stats_troop_completed_latest
create or replace view public.v_stats_troop_completed_latest with ( security_invoker = true ) as
select
  rr.responsible_state,
  rr.responsible_administration,
  rr.responsible_provider,
  o.name as lil,
  rr.cluster_name,
  rr.plot_name,
  rr.responsible_troop,
  t.name as troop_name,
  t.is_control_troop as kt,
  rr.completed_as_troop_latest,
  rr.wald2027,
  rr.begehbar2027
from
  (
    select
      r.responsible_state,
      r.responsible_administration,
      r.responsible_provider,
      r.cluster_name,
      r.plot_name,
      COALESCE(r.responsible_troop, c.responsible_troop) as responsible_troop,
      COALESCE(r.completed_at_troop, c.completed_at_troop) as completed_as_troop_latest,
      r.wald2027,
      r.begehbar2027
    from
      (
        select
          records.id,
          records.responsible_state,
          records.cluster_name,
          records.plot_name,
          records.responsible_administration,
          records.responsible_provider,
          records.responsible_troop,
          records.completed_at_troop,
          records.properties ->> 'forest_status'::text as wald2027,
          records.properties ->> 'accessibility'::text as begehbar2027
        from
          records
        where
          records.completed_at_troop is not null
          and records.cluster_name < 1000000000
          and (
            records.cluster_name < 9999900
            or records.cluster_name > 10000000
          )
      ) r
      left join (
        select
          record_changes.cluster_name,
          record_changes.plot_name,
          record_changes.responsible_troop,
          max(record_changes.completed_at_troop) as completed_at_troop
        from
          record_changes
        where
          record_changes.completed_at_troop is not null
          and record_changes.cluster_name < 1000000000
          and (
            record_changes.cluster_name < 9999900
            or record_changes.cluster_name > 10000000
          )
        group by
          record_changes.cluster_name,
          record_changes.plot_name,
          record_changes.responsible_troop
      ) c on r.cluster_name = c.cluster_name
      and r.plot_name = c.plot_name
      and r.responsible_troop = c.responsible_troop
  ) rr
  join troop t on rr.responsible_troop = t.id
  join organizations o on rr.responsible_state = o.id
order by
  o.name,
  rr.cluster_name,
  rr.plot_name,
  t.name;
 