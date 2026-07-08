-- ============================================================================
-- STATISTICS: Helper views for Statistics and Analytics
-- ============================================================================
-- THis are helper views for statistics and analytics. They are used by the application directly
-- to generate reports tables and CSV-files for inventory progress insights.
-- ============================================================================
SET search_path TO public;

-- for PlotsDeliveredByTroopAndDate
create view public.v_stats_troop_completed_latest with (security_invoker = true) as
select
  a.responsible_state,
  a.responsible_administration,
  a.responsible_provider,
  a.lil,
  a.cluster_name,
  a.plot_name,
  a.responsible_troop,
  a.troop_name,
  a.kt,
  max(a.completed_at_troop) as completed_as_troop_latest,
  a.wald2027,
  a.begehbar2027
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
      r.properties ->> 'forest_status'::text as wald2027,
      r.properties ->> 'accessibility'::text as begehbar2027
    from
      record_changes r
      join troop t on r.responsible_troop = t.id
      join organizations o on r.responsible_state = o.id
    where
      r.completed_at_troop is not null
  ) a
group by
  a.responsible_state,
  a.responsible_administration,
  a.responsible_provider,
  a.lil,
  a.cluster_name,
  a.plot_name,
  a.responsible_troop,
  a.troop_name,
  a.kt,
  a.wald2027,
  a.begehbar2027
order by
  a.lil,
  a.cluster_name,
  a.plot_name,
  a.troop_name;
-- for PerformanceByTroopCumulativeByMonth
create view public.v_stats_performance_by_troop_cumulative_by_month with (security_invoker = true) as
select
  b.responsible_state,
  b.responsible_administration,
  b.responsible_provider,
  b.lil,
  b.responsible_troop,
  b.troop_name,
  b.kt,
  to_char(b.completed_as_troop_latest, 'YYYY-MM'::text) as monat,
  count(*) as anzahl
from
  (
    select
      a.responsible_state,
      a.responsible_administration,
      a.responsible_provider,
      a.lil,
      a.responsible_troop,
      a.troop_name,
      a.kt,
      a.cluster_name,
      a.plot_name,
      max(a.completed_at_troop) as completed_as_troop_latest
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
          r.properties ->> 'forest_status'::text as wald2027,
          r.properties ->> 'accessibility'::text as begehbar2027
        from
          record_changes r
          join troop t on r.responsible_troop = t.id
          join organizations o on r.responsible_state = o.id
        where
          r.completed_at_troop is not null
          and r.cluster_name < 1000000000
          and (
            r.cluster_name < 9999900
            or r.cluster_name > 10000000
          )
      ) a
    group by
      a.responsible_state,
      a.responsible_administration,
      a.responsible_provider,
      a.lil,
      a.responsible_troop,
      a.troop_name,
      a.kt,
      a.cluster_name,
      a.plot_name
  ) b
group by
  b.responsible_state,
  b.responsible_administration,
  b.responsible_provider,
  b.lil,
  b.responsible_troop,
  b.troop_name,
  b.kt,
  (
    to_char(b.completed_as_troop_latest, 'YYYY-MM'::text)
  )
order by
  b.lil,
  b.troop_name,
  (
    to_char(b.completed_as_troop_latest, 'YYYY-MM'::text)
  );
-- for PerformanceByTroopCumulativeByWeek
create view public.v_stats_performance_by_troop_cumulative_by_week with (security_invoker = true) as
select
  b.responsible_state,
  b.responsible_administration,
  b.responsible_provider,
  b.lil,
  b.responsible_troop,
  b.troop_name,
  b.kt,
  to_char(b.completed_as_troop_latest, 'IYYY-IW'::text) as woche,
  count(*) as anzahl
from
  (
    select
      a.responsible_state,
      a.responsible_administration,
      a.responsible_provider,
      a.lil,
      a.responsible_troop,
      a.troop_name,
      a.kt,
      a.cluster_name,
      a.plot_name,
      max(a.completed_at_troop) as completed_as_troop_latest
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
          r.properties ->> 'forest_status'::text as wald2027,
          r.properties ->> 'accessibility'::text as begehbar2027
        from
          record_changes r
          join troop t on r.responsible_troop = t.id
          join organizations o on r.responsible_state = o.id
        where
          r.completed_at_troop is not null
          and r.cluster_name < 1000000000
          and (
            r.cluster_name < 9999900
            or r.cluster_name > 10000000
          )
      ) a
    group by
      a.responsible_state,
      a.responsible_administration,
      a.responsible_provider,
      a.lil,
      a.responsible_troop,
      a.troop_name,
      a.kt,
      a.cluster_name,
      a.plot_name
  ) b
group by
  b.responsible_state,
  b.responsible_administration,
  b.responsible_provider,
  b.lil,
  b.responsible_troop,
  b.troop_name,
  b.kt,
  (
    to_char(b.completed_as_troop_latest, 'IYYY-IW'::text)
  )
order by
  b.lil,
  b.troop_name,
  (to_char(b.completed_as_troop_latest, 'IYYY-IW'::text));
-- for CountControlledByKT
create view public.v_stats_count_controlled_by_kt with (security_invoker = true) as
select
  c.responsible_state,
  c.responsible_administration,
  c.responsible_provider,
  c.lil,
  c.aufnahmetrupp,
  sum(
    case
      when c.completed_as_troop_latest_by_at is not null then 1
      else 0
    end
  ) as count_completed_latest_by_at,
  sum(
    case
      when c.completed_as_troop_latest_by_kt is not null then 1
      else 0
    end
  ) as count_completed_latest_by_kt,
  sum(
    case
      when c.updated_at_latest is not null then 1
      else 0
    end
  ) as count_updated_at_latest
from
  (
    select
      COALESCE(a.responsible_state, b.responsible_state) as responsible_state,
      COALESCE(
        a.responsible_administration,
        b.responsible_administration
      ) as responsible_administration,
      COALESCE(a.responsible_provider, b.responsible_provider) as responsible_provider,
      COALESCE(a.lil, b.lil) as lil,
      COALESCE(a.cluster_name, b.cluster_name) as cluster_name,
      COALESCE(a.plot_name, b.plot_name) as plot_name,
      a.responsible_troop,
      a.troop_name as aufnahmetrupp,
      max(a.completed_at_troop) as completed_as_troop_latest_by_at,
      b.troop_name as kontrolltrupp,
      max(b.completed_at_troop) as completed_as_troop_latest_by_kt,
      max(b.updated_at) as updated_at_latest
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
          r.completed_at_troop
        from
          record_changes r
          join troop t on r.responsible_troop = t.id
          join organizations o on r.responsible_state = o.id
        where
          r.completed_at_troop is not null
          and t.is_control_troop is false
          and r.cluster_name < 1000000000
          and (
            r.cluster_name < 9999900
            or r.cluster_name > 10000000
          )
      ) a
      full join (
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
          r.updated_at
        from
          record_changes r
          join troop t on r.responsible_troop = t.id
          join organizations o on r.responsible_state = o.id
        where
          r.completed_at_troop is not null
          and t.is_control_troop is true
          and r.cluster_name < 1000000000
          and (
            r.cluster_name < 9999900
            or r.cluster_name > 10000000
          )
      ) b on a.cluster_name = b.cluster_name
      and a.plot_name = b.plot_name
    group by
      a.responsible_state,
      b.responsible_state,
      a.responsible_administration,
      b.responsible_administration,
      a.responsible_provider,
      b.responsible_provider,
      a.lil,
      b.lil,
      a.cluster_name,
      b.cluster_name,
      a.plot_name,
      b.plot_name,
      a.responsible_troop,
      a.troop_name,
      b.troop_name
  ) c
group by
  c.responsible_state,
  c.responsible_administration,
  c.responsible_provider,
  c.lil,
  c.aufnahmetrupp;
-- for PlotsNewMarker2
create view public.v_stats_plots_new_marker with (security_invoker = true) as
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

-- for PlotsNewMarker3
create view public.v_stats_plots_new_marker_3 with (security_invoker = true) as
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
-- for PlotsNewMarker4
create view public.v_stats_plots_new_marker_4 with (security_invoker = true) as
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

-- for ForestAccessChange
create view public.v_stats_forest_access_change with (security_invoker = true) as
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

-- for ForestStatusChange
create view public.v_stats_forest_status_changed with (security_invoker = true) as
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

-- for ForestBoundariesUnchanged
create view public.v_stats_forest_boundaries_unchanged with (security_invoker = true) as
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
  a.grenzart
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
      jsonb_array_elements(r.properties -> 'edges'::text) -> 'edge_type'::text as grenzart
    from
      records r
      join troop t on r.responsible_troop = t.id
      join organizations o on r.responsible_state = o.id
    where
      r.completed_at_troop is not null
  ) a
where
  a.grenzart = '42'::jsonb;