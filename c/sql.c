// The one C shim: SQLite in, JSON rows out. Nothing else crosses the ABI.
// FRONTIER_VFS_EXT names datasource-store's fdb_vfs_ext loadable extension; with it loaded,
// a database URL of file:frontier?vfs=weft_fdb keeps the pages in FoundationDB.
#include <lean/lean.h>
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char *buf; size_t len, cap; int rows; } sb;
static void sb_put(sb *s, const char *p, size_t n) {
  if (s->len + n + 1 > s->cap) { s->cap = (s->cap + n + 1) * 2; s->buf = realloc(s->buf, s->cap); }
  memcpy(s->buf + s->len, p, n); s->len += n; s->buf[s->len] = 0;
}
static void sb_str(sb *s, const char *p) { sb_put(s, p, strlen(p)); }
static void sb_json(sb *s, const char *p) {
  sb_str(s, "\"");
  for (; *p; p++) {
    unsigned char c = *p;
    if (c == '"' || c == '\\') { char e[3] = {'\\', c, 0}; sb_str(s, e); }
    else if (c < 0x20) { char e[8]; snprintf(e, 8, "\\u%04x", c); sb_str(s, e); }
    else sb_put(s, (const char *)&c, 1);
  }
  sb_str(s, "\"");
}
static int cb(void *ud, int n, char **vals, char **cols) {
  sb *s = ud;
  sb_str(s, s->rows++ ? ",{" : "{");
  for (int i = 0; i < n; i++) {
    if (i) sb_str(s, ",");
    sb_json(s, cols[i]); sb_str(s, ":");
    if (vals[i]) sb_json(s, vals[i]); else sb_str(s, "null");
  }
  sb_str(s, "}");
  return 0;
}

// frontier_sql : String -> String -> String   ({"rows":[...]} or {"error":"..."})
LEAN_EXPORT lean_obj_res frontier_sql(b_lean_obj_arg db_s, b_lean_obj_arg sql_s) {
  const char *db = lean_string_cstr(db_s), *sql = lean_string_cstr(sql_s);
  sqlite3 *h = NULL; char *err = NULL;
  sb s = {0}; s.buf = malloc(64); s.cap = 64; s.buf[0] = 0;
  int rc = sqlite3_open_v2(db, &h, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_URI, NULL);
  if (rc != SQLITE_OK) { sb_str(&s, "{\"error\":"); sb_json(&s, h ? sqlite3_errmsg(h) : "open"); sb_str(&s, "}"); goto out; }
  const char *ext = getenv("FRONTIER_VFS_EXT");
  if (ext && *ext) {
    sqlite3_enable_load_extension(h, 1);
    if (sqlite3_load_extension(h, ext, NULL, &err) != SQLITE_OK) { sb_str(&s, "{\"error\":"); sb_json(&s, err ? err : "load_extension"); sb_str(&s, "}"); sqlite3_free(err); goto out; }
  }
  sqlite3_busy_timeout(h, 5000);
  sb_str(&s, "{\"rows\":[");
  if (sqlite3_exec(h, sql, cb, &s, &err) != SQLITE_OK) {
    s.len = 0; s.buf[0] = 0; sb_str(&s, "{\"error\":"); sb_json(&s, err ? err : "exec"); sb_str(&s, "}"); sqlite3_free(err); goto out;
  }
  sb_str(&s, "]}");
out:
  if (h) sqlite3_close(h);
  lean_obj_res r = lean_mk_string(s.buf);
  free(s.buf);
  return r;
}
