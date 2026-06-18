-- Source - https://stackoverflow.com/a/33174794
-- Posted by klin, modified by community. See post 'Timeline' for change history
-- Retrieved 2026-06-10, License - CC BY-SA 4.0

select tgname
from pg_trigger
where not tgisinternal
and tgrelid = 'books'::regclass;

    tgname     
---------------
 books_trigger
(1 row)
