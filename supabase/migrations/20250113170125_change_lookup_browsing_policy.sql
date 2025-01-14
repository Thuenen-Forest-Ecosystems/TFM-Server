drop policy "default_policy" on "private_ci2027_001"."lookup_browsing";

alter table "private_ci2027_001"."deadwood" drop column "selectable_by";

alter table "private_ci2027_001"."deadwood" drop column "updatable_by";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION private_ci2027_001.copy_select_access_by_to_plot()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$DECLARE
    plot_row RECORD;
BEGIN

    FOR plot_row IN
        SELECT id
        FROM private_ci2027_001.plot
        WHERE cluster_id = NEW.cluster_name::int4
    LOOP
        UPDATE private_ci2027_001.plot
        SET selectable_by = NEW.selectable_by
        WHERE id = plot_row.id;

        UPDATE private_ci2027_001.tree
        SET selectable_by = NEW.selectable_by
        WHERE plot_id =  plot_row.id;

        UPDATE private_ci2027_001.deadwood
        SET selectable_by = NEW.selectable_by
        WHERE plot_id =  plot_row.id;
    END LOOP;

    RETURN NEW;
END;$function$
;

create policy "default_policy"
on "private_ci2027_001"."lookup_browsing"
as permissive
for select
to anon
using (true);



