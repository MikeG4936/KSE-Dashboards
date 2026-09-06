/* Inspect unstripped metadata from the pinned EdgeTX Lua core. */
#define LUA_CORE
#include <stdio.h>
#include <stdlib.h>
#include "lua.h"
#include "lauxlib.h"
#include "lstate.h"
#include "lobject.h"

static int count;
typedef struct { const void *prototype; int peak; } LocalPeak;
static LocalPeak *local_peaks;
static size_t local_peak_count;

/* Called at the pinned parser's local-limit check, including zero-PC scopes. */
void kse_observe_local_count(const void *prototype, int active) {
  for (size_t i = 0; i < local_peak_count; ++i) {
    if (local_peaks[i].prototype == prototype) {
      if (active > local_peaks[i].peak) local_peaks[i].peak = active;
      return;
    }
  }
  LocalPeak *grown = realloc(local_peaks, (local_peak_count + 1) * sizeof(*grown));
  if (!grown) { fprintf(stderr, "cannot allocate parser observations\n"); exit(2); }
  local_peaks = grown;
  local_peaks[local_peak_count++] = (LocalPeak){prototype, active};
}

static int count_bytes(lua_State *L, const void *data, size_t size, void *out) {
  (void)L; (void)data;
  *(size_t *)out += size;
  return 0;
}

static void inspect(Proto *p, int parent) {
  int id = count++, peak = 0;
  for (size_t i = 0; i < local_peak_count; ++i)
    if (local_peaks[i].prototype == p) peak = local_peaks[i].peak;
  if (id) putchar(',');
  printf("{\"id\":%d,\"parent\":%d,\"line\":%d,\"last_line\":%d,"
         "\"active_locals\":%d,\"registers\":%d,\"upvalues\":%d,"
         "\"instructions\":%d,\"instruction_bytes\":%zu}",
         id, parent, p->linedefined, p->lastlinedefined, peak,
         p->maxstacksize, p->sizeupvalues, p->sizecode,
         (size_t)p->sizecode * sizeof(Instruction));
  for (int i = 0; i < p->sizep; ++i) inspect(p->p[i], id);
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: edgetx-limits source.lua\n"); return 2; }
  lua_State *L = luaL_newstate();
  if (!L) { fprintf(stderr, "cannot allocate Lua state\n"); return 2; }
  int status = luaL_loadfilex(L, argv[1], "t");
  if (status) fprintf(stderr, "%s\n", lua_tostring(L, -1));
  else {
    size_t bytes = 0;
    status = lua_dump(L, count_bytes, &bytes, 1);
    printf("{\"stripped_bytecode_bytes\":%zu,\"prototypes\":[", bytes);
    inspect(clLvalue(L->top - 1)->p, -1);
    printf("]}\n");
  }
  lua_close(L);
  free(local_peaks);
  return status;
}
