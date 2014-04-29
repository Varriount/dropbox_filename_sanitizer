import nake, os, times, osproc, zipfiles, md5, dropbox_filename_sanitizer,
  sequtils, json, posix

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
  rst_files = concat(glob_rst(), glob_rst("docs"), glob_rst("docs"/"dist"))

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

    # Normal documentation.
    for rst_file, html_file in all_rst_files():
      rst_file.copy_dist_file(doc_txt_dir)
      html_file.copy_dist_file(doc_html_dir)

    move_file(doc_html_dir/"docs"/"dist"/"readme.html", dest_dir/"readme.html")
    move_file(doc_txt_dir/"docs"/"dist"/"readme.txt", dest_dir/"readme.txt")

    copy_dist_file(exe_name, dest_dir)
    make_zip_from_dir(dest_dir)

when defined(macosx): os_task("macosx")
when defined(linux): os_task("linux")

task "md5", "Computes md5 of files found in dist subdirectory.":
  # Attempts to obtain the git current commit.
  var git_commit = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  let (output, code) = execCmdEx("cd ../root && git log -n 1 --format=%H")
  if code == 0 and output.strip.len == 40:
    git_commit = output.strip
  echo """Add the following notes to the release info:

Compiled with Nimrod version https://github.com/Araq/Nimrod/commit/$2.

[See the changes log](https://github.com/gradha/dropbox_filename_sanitizer/blob/v$1/docs/CHANGES.rst).

Binary MD5 checksums:""" % [dropbox_filename_sanitizer.version_str, git_commit]
  for filename in walk_files(dist_dir/"*.zip"):
    let v = filename.read_file.get_md5
    echo "* ``", v, "`` ", filename.extract_filename

proc gen_script(user, host, dir_name,
    nimrod_git_branch, nimrod_version_string: string): string =
  ## Returns a string with the contents of the shell script to run.
  ##
  ## Pass the name of the host where the script will run and the unix username.
  ## The `nimrod_git_branch` parameter can be a tag or a git commit hash. The
  ## `nimrod_version_string` will be passed to grep as is (beware escaping).
  ##
  ## The `dir_name` parameter should be a random unique string which will be
  ## used as directory base to avoid colliding with other tests. You can pass
  ## the epoch seconds here as a string.
  result = """#!/bin/sh

# Set errors to bail out.
set -e
# Display commands
#set -v
BASE_DIR=~/shelltest_dropbox_filename_sanitizer
TEST_DIR="${BASE_DIR}/"""
  result.add(dir_name)
  result.add(""""
NIM_DIR="${TEST_DIR}/compiler"
NIM_BIN="${NIM_DIR}/bin/nimrod"
BABEL_CFG=~/.babel
BABEL_BIN="${BABEL_CFG}/bin"
BABEL_SRC="${TEST_DIR}/babel"

rm -Rf "${BASE_DIR}" "${BABEL_CFG}"
if test -d "${BASE_DIR}"; then
  echo "Could not purge $BASE_DIR"
  exit 1
fi
mkdir -p "${TEST_DIR}"

echo "Downloading Nimrod compiler '""")
  result.add(nimrod_git_branch)
  result.add("""'…"
git clone --depth 1 -b """)
  result.add(nimrod_git_branch)
  result.add(""" git://github.com/Araq/Nimrod.git "${NIM_DIR}"
git clone --depth 1 git://github.com/nimrod-code/csources "${NIM_DIR}/csources"

echo "Compiling csources…"
cd "${NIM_DIR}/csources"
sh build.sh

echo "Compiling koch…"
cd "${NIM_DIR}"
bin/nimrod c koch

echo "Compiling Nimrod…"
./koch boot -d:release

echo "Testing Nimrod compiler invokation through adhoc path…"
export PATH="${NIM_DIR}/bin:${PATH}"
which nimrod
nimrod -v|grep """")
  result.add(nimrod_version_string)
  result.add(""""

echo "Downloading Babel package manager…"
git clone --depth 1 https://github.com/nimrod-code/babel.git "${BABEL_SRC}"
cd "${BABEL_SRC}"

echo "Compiling Babel…"
nimrod c -r src/babel install

echo "Installing Babel itself through environment path…"
export PATH="${BABEL_BIN}:${PATH}"
babel update
babel install -y babel

# Install dependencies first to avoid troubles, see https://github.com/nimrod-code/babel/issues/37
babel install argument_parser
echo "Testing dropbox_filename_sanitizer babel installation…"
babel install dropbox_filename_sanitizer
echo "Babel finished installing, testing…"
dropbox_filename_sanitizer -v | grep Version

echo "Test script finished successfully, removing stuff…"
rm -Rf "${BASE_DIR}" "${BABEL_CFG}"
""")


proc run_json_test(json_filename: string) =
  ## Runs a json test file.
  let json = json_filename.parse_file
  assert json.kind == JObject
  let
    host = json["host"].str
    user = json["user"].str
    ssh_target = user & "@" & host
    seconds = int(epoch_time())
    bash_file = "shelltest_" & $seconds & ".sh"
    compiler_branch = json["nimrod_branch"].str
    compiler_version_str = json["nimrod_version_str"].str

  finally: bash_file.remove_file

  # Generate the script.
  bash_file.write_file(gen_script(user, host,
    $seconds, compiler_branch, compiler_version_str))
  doAssert 0 == bash_file.chmod(
    S_IRWXU or S_IRGRP or S_IXGRP or S_IROTH or S_IXOTH)

  # Send the script to the remote machine and run it after purging previous.
  echo "Removing previous scripts…"
  direShell("ssh", ssh_target, "rm -f 'shelltest_*.sh'")
  echo "Copying current script ", bash_file, "…"
  direShell("scp", bash_file, ssh_target & ":.")
  echo "Running script remotely…"
  direShell("ssh", ssh_target, "./" & bash_file)


task "shell_test", "Pass *.json files for shell testing":
  if paramCount() < 2:
    quit "Pass a json with test info like `nake jsonfile shell_test'."

  # Read data from the json test file.
  run_json_test(param_str(1))

  echo "Nakefile finished successfully"
