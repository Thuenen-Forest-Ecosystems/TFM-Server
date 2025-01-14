drop policy "default_policy" on "private_ci2027_001"."lookup_cluster_situation";

drop policy "default_policy" on "private_ci2027_001"."lookup_cluster_status";

create policy "default_policy"
on "private_ci2027_001"."lookup_cluster_situation"
as permissive
for select
to anon
using (true);


create policy "default_policy"
on "private_ci2027_001"."lookup_cluster_status"
as permissive
for select
to anon
using (true);



