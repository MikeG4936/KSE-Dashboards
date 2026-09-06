/* Small ROM-library host, not a transmitter/simulator implementation. */
#define LUA_LIB
#include <stdio.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "lobject.h"

extern LROT_TABLE(base_func);
extern LROT_TABLE(mathlib);
extern LROT_TABLE(tablib);
extern LROT_TABLE(strlib);
LROT_BEGIN(rotables, NULL, 0)
LROT_END(rotables, NULL, 0)

/* Firmware print targets its debug sink; fixture traces need host stdout. */
static int host_print(lua_State *L) {
  int count = lua_gettop(L);
  for (int i = 1; i <= count; ++i) {
    size_t length;
    const char *value = luaL_tolstring(L, i, &length);
    if (i > 1) putchar('\t');
    fwrite(value, 1, length, stdout);
    lua_pop(L, 1);
  }
  putchar('\n');
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: edgetx-run fixture.lua [arguments...]\n"); return 2; }
  lua_State *L = luaL_newstate();
  if (!L) { fprintf(stderr, "cannot allocate Lua state\n"); return 2; }
  lua_pushglobaltable(L);
  lua_pushvalue(L, -1); lua_setglobal(L, "_G");
  lua_newtable(L);
  lua_pushrotable(L, LROT_TABLEREF(base_func)); lua_setfield(L, -2, "__index");
  lua_setmetatable(L, -2); lua_pop(L, 1);
  lua_pushrotable(L, LROT_TABLEREF(mathlib)); lua_setglobal(L, "math");
  lua_pushrotable(L, LROT_TABLEREF(tablib)); lua_setglobal(L, "table");
  lua_pushrotable(L, LROT_TABLEREF(strlib)); lua_setglobal(L, "string");
  luaopen_string(L); /* Installs the string metatable. */
  lua_settop(L, 0);
  lua_pushcfunction(L, host_print); lua_setglobal(L, "print");
  lua_newtable(L);
  for (int i = 1; i < argc; ++i) {
    lua_pushstring(L, argv[i]); lua_rawseti(L, -2, i - 1);
  }
  lua_setglobal(L, "arg");
  int status = luaL_loadfile(L, argv[1]);
  if (!status) status = lua_pcall(L, 0, 0, 0);
  if (status) fprintf(stderr, "%s\n", lua_tostring(L, -1));
  lua_close(L);
  return status;
}
