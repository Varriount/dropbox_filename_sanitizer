import nake, os, times

let
  rst_files = @["LICENSE", "README", "CHANGES", "docindex"]

task "babel", "Uses babel to install ouroboros locally":
  if shell("babel install"):
    echo "Installed"

proc needs_refresh(target: string, src: varargs[string]): bool =
  assert len(src) > 0, "Pass some parameters to check for"
  var targetTime: float
  try:
    targetTime = toSeconds(getLastModificationTime(target))
  except EOS:
    return true

  for s in src:
    let srcTime = toSeconds(getLastModificationTime(s))
    if srcTime > targetTime:
      return true

task "doc", "Generates HTML docs":
  # Generate html files from the rst docs.
  for rst_name in rst_files:
    let rst_file = rst_name & ".rst"
    # Ignore files if they don't exist, babel version misses some.
    if not rst_file.existsFile:
      echo "Ignoring missing ", rst_file
      continue
    let html_file = rst_name & ".html"
    if not html_file.needs_refresh(rst_file): continue
    if not shell("nimrod rst2html --verbosity:0", rst_file):
      quit("Could not generate html doc for " & rst_file)
    else:
      echo "Generated " & rst_name & ".html"
