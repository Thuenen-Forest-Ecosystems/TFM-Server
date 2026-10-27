#!/usr/bin/env bash
# =============================================================================
# TFM-Server — compare the seed tables (supabase/seeds/public + intern) between
# two databases, typically local <-> production
#
#   ./scripts/compare-seed-tables.sh --remote-url "postgresql://postgres:...@134.110.100.75:3389/postgres"
#   ./scripts/compare-seed-tables.sh --remote-url ... --local-url ... --out /tmp/x --no-detail
#   ./scripts/compare-seed-tables.sh --remote-url ... --only 'tree|plot$'   # tables matching a regex
#
# WHAT IT COMPARES
#   Exactly what supabase/seeding.sh dumps: every table in schema lookup plus
#   the inventory_archive tables listed below (public + intern). The whole
#   table is compared, not only the released rows the seed would contain.
#
#   Rows are compared by CONTENT, not by surrogate id — every upload generates
#   fresh uuids, so local and prod never share them:
#   - own uuid columns (id) are left out, uuid foreign keys (plot_id, tree_id, ...)
#     are replaced by the parent's natural key, recursively
#   - rows are matched on the natural key: a UNIQUE constraint over NOT NULL
#     columns, else intkey/code, else the primary key. Rows whose key is NULL
#     (ci2027 rows from the archive sync have no intkey) match on content.
#   - technical timestamps ($IGNORE_COLUMNS) are left out
#   - geometries are compared snapped to $GEOM_GRID degrees (~0.1 mm): values
#     computed on different hosts differ in the last bits
#   Column sets (name + type) are compared and reported separately; the data
#   check uses the columns both sides have. FKs and keys are read locally.
#
#   Per table: row count + order-independent checksum. Where it differs, rows
#   are hashed per key on both sides and joined locally; only-local /
#   only-remote / changed keys go to --out.
#
#   Read-only: SELECTs and COPY ... TO STDOUT only. Full scans (~3 GB on prod).
#
# EXIT
#   0 = all identical, 1 = differences found, 2 = usage/connection error
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

LOCAL_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
REMOTE_URL=""
OUT_DIR="tmp/seed-compare-$(date +%Y%m%d_%H%M%S)"
DETAIL=1
ONLY=""
IGNORE_COLUMNS="modified_at created_at updated_at"
GEOM_GRID="1e-9"
while [ $# -gt 0 ]; do
    case "$1" in
        --local-url)  LOCAL_URL="${2:?--local-url needs a value}"; shift 2 ;;
        --remote-url) REMOTE_URL="${2:?--remote-url needs a value}"; shift 2 ;;
        --out)        OUT_DIR="${2:?--out needs a value}"; shift 2 ;;
        --no-detail)  DETAIL=0; shift ;;
        --only)       ONLY="${2:?--only needs a regex}"; shift 2 ;;
        -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -n "$REMOTE_URL" ] || { echo "--remote-url is required" >&2; exit 2; }

export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
command -v psql >/dev/null || { echo "psql not found" >&2; exit 2; }
mkdir -p "$OUT_DIR"

# keep in sync with supabase/seeding.sh
PUBLIC_TABLES="cluster cluster_move plot deadwood edges regeneration structure_lt4m structure_gt4m tree subplots_relative_position"
INTERN_TABLES="plot_coordinates notes position tree_coordinates edges_coordinates subplots_relative_position_coordinates plot_support_points"

q() {  # q <url> <sql>  (SET, not PGOPTIONS: the prod pooler rejects startup options)
    psql "$1" --no-psqlrc -X -A -t -q -F $'\t' --set ON_ERROR_STOP=on \
        -c "SET statement_timeout = 0; SET default_transaction_read_only = on" -c "$2"
}

lookup_tables() {
    q "$1" "SELECT 'lookup.' || tablename FROM pg_tables WHERE schemaname = 'lookup' ORDER BY 1"
}

columns() {  # columns <url> <schema.table>  -> name<TAB>type per line, name-sorted
    q "$1" "SELECT a.attname, format_type(a.atttypid, a.atttypmod)
            FROM pg_attribute a
            WHERE a.attrelid = '$2'::regclass AND a.attnum > 0 AND NOT a.attisdropped
            ORDER BY a.attname"
}

natkey_columns() {  # natkey_columns <schema.table> -> name<TAB>type per key column (local DB)
    q "$LOCAL_URL" "WITH k AS (
                SELECT CASE WHEN con.contype = 'u' AND bool_and(a.attnotnull) THEN 1
                            WHEN con.contype = 'u' THEN 3 ELSE 4 END AS prio,
                       array_agg(a.attname::text ORDER BY array_position(con.conkey, a.attnum)) AS cols
                FROM pg_constraint con
                JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = ANY(con.conkey)
                WHERE con.conrelid = '$1'::regclass AND con.contype IN ('u', 'p')
                GROUP BY con.oid, con.contype
                UNION ALL
                SELECT 2, array[a.attname::text] FROM pg_attribute a
                WHERE a.attrelid = '$1'::regclass AND a.attname IN ('intkey', 'code') AND NOT a.attisdropped),
            best AS (SELECT cols FROM k ORDER BY prio, cardinality(cols), cols LIMIT 1)
            SELECT c.col, format_type(a.atttypid, a.atttypmod)
            FROM best, unnest(best.cols) WITH ORDINALITY c(col, n)
            JOIN pg_attribute a ON a.attrelid = '$1'::regclass AND a.attname = c.col
            ORDER BY c.n"
}

uuid_fk() {  # uuid_fk <schema.table> <column> -> parent table<TAB>parent column, if a single-column FK
    q "$LOCAL_URL" "SELECT con.confrelid::regclass, pa.attname
            FROM pg_constraint con
            JOIN pg_attribute a  ON a.attrelid = con.conrelid AND a.attnum = con.conkey[1]
            JOIN pg_attribute pa ON pa.attrelid = con.confrelid AND pa.attnum = con.confkey[1]
            WHERE con.conrelid = '$1'::regclass AND con.contype = 'f' AND a.attname = '$2'
              AND cardinality(con.conkey) = 1
            LIMIT 1"
}

# col_expr <table> <alias> <column> <type> -> sets EXPR ("" = leave column out);
# appends LEFT JOINs for uuid FKs to JOINS. bash 3.2: results via globals.
col_expr() {
    local tbl="$1" alias="$2" col="$3" type="$4" fk parent pcol palias
    case " $IGNORE_COLUMNS " in *" $col "*) EXPR=""; return ;; esac
    if [ "$type" = uuid ]; then
        fk="$(uuid_fk "$tbl" "$col")"
        if [ -z "$fk" ]; then EXPR=""; return; fi    # own surrogate id
        parent="$(cut -f1 <<<"$fk")"; pcol="$(cut -f2 <<<"$fk")"
        NJOIN=$((NJOIN + 1)); palias="p$NJOIN"
        JOINS+=" LEFT JOIN $parent $palias ON $palias.\"$pcol\" = $alias.\"$col\""
        key_expr "$parent" "$palias"
        EXPR="$KEY"
    elif [[ "$type" == geometry* ]]; then
        EXPR="st_astext(st_snaptogrid($alias.\"$col\", $GEOM_GRID))"
    else
        EXPR="$alias.\"$col\""
    fi
}

# key_expr <table> <alias> -> sets KEY to a text expression of the natural key.
# Parts are joined with ||, so a NULL anywhere (also in a parent's key) makes KEY NULL.
key_expr() {
    local tbl="$1" alias="$2" k type parts="" keycols
    keycols="$(natkey_columns "$tbl")"
    while IFS=$'\t' read -r k type; do
        col_expr "$tbl" "$alias" "$k" "$type"
        parts+="${parts:+ || '|' || }($EXPR)::text"
    done <<<"$keycols"
    KEY="($parts)"
}

all_tables="$( { lookup_tables "$LOCAL_URL"; lookup_tables "$REMOTE_URL"; } | sort -u)"
for t in $PUBLIC_TABLES; do all_tables+=$'\n'"inventory_archive.$t"; done
for t in $INTERN_TABLES; do all_tables+=$'\n'"inventory_archive.$t"; done
[ -n "$ONLY" ] && all_tables="$(grep -E "$ONLY" <<<"$all_tables" || true)"

DIFFS=0
SUMMARY="$OUT_DIR/summary.tsv"
printf 'table\tseed\tlocal_rows\tremote_rows\tstatus\tnote\n' > "$SUMMARY"

for tbl in $all_tables; do
    case " $INTERN_TABLES " in *" ${tbl#inventory_archive.} "*) seed=intern ;; *) seed=public ;; esac
    printf '%-62s ' "$tbl" >&2

    lcols="$(columns "$LOCAL_URL" "$tbl" 2>/dev/null || true)"
    rcols="$(columns "$REMOTE_URL" "$tbl" 2>/dev/null || true)"
    if [ -z "$lcols" ] || [ -z "$rcols" ]; then
        note="missing on $([ -z "$lcols" ] && echo local || echo remote)"
        printf '%s\t%s\t\t\tMISSING\t%s\n' "$tbl" "$seed" "$note" >> "$SUMMARY"
        echo "MISSING ($note)" >&2; DIFFS=1; continue
    fi

    note=""
    only_l="$(comm -23 <(cut -f1 <<<"$lcols") <(cut -f1 <<<"$rcols") | paste -sd, -)"
    only_r="$(comm -13 <(cut -f1 <<<"$lcols") <(cut -f1 <<<"$rcols") | paste -sd, -)"
    type_diff="$(join -t $'\t' <(echo "$lcols") <(echo "$rcols") | awk -F'\t' '$2 != $3 {print $1 "(" $2 "/" $3 ")"}' | paste -sd, -)"
    [ -n "$only_l" ] && note+="cols only local: $only_l; "
    [ -n "$only_r" ] && note+="cols only remote: $only_r; "
    [ -n "$type_diff" ] && note+="type local/remote: $type_diff; "

    JOINS=""; NJOIN=0; exprs=""
    common="$(join -t $'\t' <(echo "$lcols") <(echo "$rcols"))"
    while IFS=$'\t' read -r col ltype rtype; do
        col_expr "$tbl" t "$col" "$ltype"
        [ -n "$EXPR" ] && exprs+="${exprs:+, }$EXPR"
    done <<<"$common"
    key_expr "$tbl" t
    rowexpr="md5(ROW($exprs)::text)"
    from="$tbl t$JOINS"
    # rows without a usable key (NULL intkey) are matched on content
    keyexpr="coalesce($KEY, 'content:' || $rowexpr)"

    checksum_sql="SELECT count(*),
                         coalesce(sum(('x' || substr(h, 1, 15))::bit(60)::bigint), 0),
                         coalesce(sum(('x' || substr(h, 16, 15))::bit(60)::bigint), 0)
                  FROM (SELECT $rowexpr AS h FROM $from) s"

    lsum="$(q "$LOCAL_URL" "$checksum_sql")"
    rsum="$(q "$REMOTE_URL" "$checksum_sql")"
    lrows="$(cut -f1 <<<"$lsum")"; rrows="$(cut -f1 <<<"$rsum")"

    if [ "$lsum" = "$rsum" ]; then
        status=IDENTICAL
        [ -n "$note" ] && status=IDENTICAL_DATA
    else
        status=DIFFERENT; DIFFS=1
        if [ "$DETAIL" = 1 ]; then
            dump_sql="COPY (SELECT $keyexpr, $rowexpr FROM $from) TO STDOUT"
            base="$OUT_DIR/${tbl//./__}"
            q "$LOCAL_URL"  "$dump_sql" | LC_ALL=C sort > "$base.local.tsv"
            q "$REMOTE_URL" "$dump_sql" | LC_ALL=C sort > "$base.remote.tsv"
            LC_ALL=C join -t $'\t' -v1 "$base.local.tsv" "$base.remote.tsv" | cut -f1 > "$base.only_local.txt"
            LC_ALL=C join -t $'\t' -v2 "$base.local.tsv" "$base.remote.tsv" | cut -f1 > "$base.only_remote.txt"
            LC_ALL=C join -t $'\t' "$base.local.tsv" "$base.remote.tsv" | awk -F'\t' '$2 != $3 {print $1}' | uniq > "$base.changed.txt"
            dups="$(cut -f1 "$base.local.tsv" | uniq -d | wc -l | tr -d ' ')"
            rm -f "$base.local.tsv" "$base.remote.tsv"
            note+="only local: $(wc -l < "$base.only_local.txt" | tr -d ' '), only remote: $(wc -l < "$base.only_remote.txt" | tr -d ' '), changed: $(wc -l < "$base.changed.txt" | tr -d ' ')"
            [ "$dups" != 0 ] && note+=", key not unique locally ($dups keys)"
        fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$tbl" "$seed" "$lrows" "$rrows" "$status" "${note%; }" >> "$SUMMARY"
    echo "$status  local=$lrows remote=$rrows ${note:+ — ${note%; }}" >&2
done

echo >&2
echo "summary: $SUMMARY" >&2
exit $DIFFS
