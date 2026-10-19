"""Run the official pinned minimizer unchanged with virtual desktop file APIs."""
import hashlib
import subprocess


def quote(text):
    equals = "="
    while "]" + equals + "]" in text:
        equals += "="
    return "[" + equals + "[" + text + "]" + equals + "]"


def transform(sources, runner, rf_source, pin, work):
    program = subprocess.check_output(
        ["git", "-C", str(rf_source), "show", pin + ":bin/minimize.lua"])
    official = work / "official-minimize.lua"
    official.write_bytes(program)
    bundle = "files={}\n" + "\n".join(
        "files[ " + quote(name) + " ]=" + quote(text)
        for name, text in sorted(sources.items()))
    adapter = r'''
-- Desktop file API adapter only. The official transform below is unchanged.
local function normalized(path)
  if string.sub(path,1,2)=="./" then path=string.sub(path,2) end
  if string.sub(path,1,1)~="/" then path="/"..path end
  return path
end
io={open=function(path,mode)
  path=normalized(path)
  if mode=="r" and files[path]==nil then return nil end
  if mode=="w" then files[path]="" end
  local file={path=path,pos=1}
  function file:lines()
    return function()
      local text=files[self.path]
      if self.pos>#text then return nil end
      local nextLine=string.find(text,"\n",self.pos,true)
      local line=string.sub(text,self.pos,nextLine and nextLine-1 or #text)
      self.pos=nextLine and nextLine+1 or #text+1
      return line
    end
  end
  function file:write(text) files[self.path]=files[self.path]..text;return self end
  function file:close() return true end
  return file
end}
os={remove=function(path) files[normalized(path)]=nil;return true end,
  rename=function(from,to)
    from,to=normalized(from),normalized(to)
    assert(files[from]~=nil,"missing rename source")
    files[to],files[from]=files[from],nil
    return true
  end}
loadfile=function(path)
  path=normalized(path)
  if not files[path] then return nil,"missing script: "..path end
  return load(files[path],"@"..path)
end
'''
    fixture = work / "run-official-minimizer.lua"
    fixture.write_text(bundle + "\n" + adapter + "\ndofile(" + quote(str(official)) + ")\n"
        + 'print("OUTPUT_BEGIN")\n'
        + 'for path,text in pairs(files) do print("OUTPUT|"..path.."|"..#text);print(text) end\n'
        + 'print("OUTPUT_COMPLETE")\n')
    run = subprocess.run([str(runner), str(fixture)], capture_output=True, timeout=60)
    if run.returncode:
        raise RuntimeError(run.stderr.decode())
    log, serialized = run.stdout.split(b"OUTPUT_BEGIN\n", 1)
    (work / "official-minimize.log").write_bytes(log)
    transformed = {}
    position = 0
    while not serialized[position:].startswith(b"OUTPUT_COMPLETE\n"):
        end = serialized.index(b"\n", position)
        kind, path, size = serialized[position:end].split(b"|")
        assert kind == b"OUTPUT"
        size = int(size)
        content = serialized[end+1:end+1+size]
        assert len(content) == size and serialized[end+1+size:end+2+size] == b"\n"
        transformed[path.decode()] = content.decode()
        position = end + 2 + size
    assert transformed.keys() == sources.keys(), "minimizer lost or invented source files"
    assert "pcall(run, widget)" in transformed["/SCRIPTS/RF2/background.lua"]
    assert "sensor[4]" in transformed["/SCRIPTS/RF2/rf2tlm.lua"]
    original = {name: hashlib.sha256(text.encode()).hexdigest() for name, text in sources.items()}
    changed = {name: hashlib.sha256(text.encode()).hexdigest() for name, text in transformed.items()
               if text != sources[name]}
    metadata = dict(program="bin/minimize.lua", program_sha256=hashlib.sha256(program).hexdigest(),
                    execution="Exact pinned program, unchanged, under EdgeTX Lua host; virtual desktop io/os/loadfile only",
                    original_hashes=original, changed_hashes=changed)
    return transformed, metadata
