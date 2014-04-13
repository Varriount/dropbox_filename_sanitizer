import nake, os, times, osproc, zipfiles, md5, dropbox_filename_sanitizer,
  sequtils

const
  dist_dir = "dist"
  name = "dropbox_filename_sanitizer"

template glob_rst(basedir: string = nil): expr =
  ## Shortcut to simplify getting lists of files.
  ##
  ## Pass nil to iterate over rst files in the current directory. This avoids
  ## prefixing the paths with "./" unnecessarily.
  if baseDir.isNil:
    to_seq(walk_files("*.rst"))
  else:
    to_seq(walk_files(basedir/"*.rst"))

let
  exe_name = name.change_file_ext(exe_ext)
  rst_files = concat(glob_rst(), glob_rst("docs"))

proc compile() =
  let
    src = name & ".nim"
    dest = exe_name
  if dest.needs_refresh(src):
    echo "Compiling ", name, "…"
    direShell("nimrod c --verbosity:0 -d:release --out:" & dest, src)

task "babel", "Uses babel to install ouroboros locally":
  direshell("babel install -y")
  echo "Installed"

iterator all_rst_files(): tuple[src, dest: string] =
  for rst_name in rst_files:
    var r: tuple[src, dest: string]
    r.src = rst_name
    # Ignore files if they don't exist, babel version misses some.
    if not r.src.existsFile:
      echo "Ignoring missing ", r.src
      continue
    r.dest = rst_name.change_file_ext("html")
    yield r

proc doc() =
  # Generate html files from the rst docs.
  for rst_file, html_file in all_rst_files():
    if not html_file.needs_refresh(rst_file): continue
    if not shell("nimrod rst2html --verbosity:0", rst_file):
      quit("Could not generate html doc for " & rst_file)
    else:
      echo rst_file & " -> " & html_file

  echo "All docs generated"

task "doc", "Generates HTML docs": doc()

task "check_doc", "Validates rst format":
  for rst_file, html_file in all_rst_files():
    echo "Testing ", rst_file
    let (output, exit) = execCmdEx("rst2html.py " & rst_file & " > /dev/null")
    if output.len > 0 or exit != 0:
      echo "Failed python processing of " & rst_file
      echo output

proc clean() =
  exe_name.remove_file
  dist_dir.remove_dir
  dist_dir.create_dir
  for path in walk_dir_rec("."):
    let ext = splitFile(path).ext
    if ext == ".html":
      echo "Removing ", path
      path.removeFile()
  echo "Temporary files cleaned"

task "clean", "Removes temporal files, mostly.": clean()

proc make_zip_from_dir(dir_name: string): string {.discardable.} =
  ## Builds a zip from the specified dir.
  ##
  ## Creates a .zip in the upper directory with the relative contents. Returns
  ## the path to the generated zip.
  let zip_name = dirname.split_file.dir /
    dir_name.extract_filename & ".zip"
  result = zip_name
  zip_name.remove_file

  var Z: TZipArchive
  if not Z.open(zip_name, fmWrite):
    quit("Couldn't open zip " & zip_name)
  try:
    echo "Adding files to ", zip_name
    let start = len(dirname) + 1
    for path in walk_dir_rec(dir_name):
      let dest = path[start .. high(path)]
      echo dest
      assert existsFile(path)
      Z.addFile(dest, path)
  finally:
    Z.close

  echo "Built ", zip_name, " sized ", zip_name.getFileSize, " bytes."


proc copy_dist_file(src, dest_dir: string ) =
  ## Copies `src` into `dest_dir` maintaining the relative path.
  ##
  ## Additionally files with `.rst` extension are renamed to `.txt` on
  ## destination.
  var dest = dest_dir/src
  if src.split_file.ext == ".rst":
    dest = dest.change_file_ext("txt")

  # Make sure target directory exists.
  dest.split_file.dir.create_dir
  #echo src, " -> ", dest
  src.copy_file_with_permissions(dest)


template os_task(define_name): stmt {.immediate.} =
  task "dist", "Generate distribution binary for " & define_name:
    clean()
    doc()
    compile()
    # Prepare folder with software to be zipped.
    let
      basename = name & "-" &
        dropbox_filename_sanitizer.version_str & "-" & define_name
      dest_dir = dist_dir/basename
      doc_html_dir = dest_dir/"doc_html"
      doc_txt_dir = dest_dir/"doc_txt"

    for rst_file, html_file in all_rst_files():
      rst_file.copy_dist_file(doc_txt_dir)
      html_file.copy_dist_file(doc_html_dir)

    copy_dist_file(exe_name, dest_dir)
    make_zip_from_dir(dest_dir)

when defined(macosx): os_task("macosx")
when defined(linux): os_task("linux")

task "md5", "Computes md5 of files found in dist subdirectory.":
  echo """Add the following notes to the release info:

Compiled with Nimrod version https://github.com/Araq/Nimrod/commit/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.

[See the changes log](https://github.com/gradha/dropbox_filename_sanitizer/blob/v$1/docs/CHANGES.rst).

Binary MD5 checksums:""" % (dropbox_filename_sanitizer.version_str)
  for filename in walk_files(dist_dir/"*.zip"):
    let v = filename.read_file.get_md5
    echo "* ``", v, "`` ", filename.extract_filename
