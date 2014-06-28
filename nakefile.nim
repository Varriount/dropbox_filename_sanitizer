import nake, os, times, osproc, zipfiles, md5, dropbox_filename_sanitizer,
  sequtils, json, posix, strutils

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

type Json_info = object
  host: string
  user: string
  ssh_target: string
  seconds: int
  bash_file: string
  compiler_branch: string
  compiler_version_str: string
  nimrod_csources_branch: string
  chunk_file: string
  chunk_number: int
  bin_version: string

proc gen_setup_script(json_info: Json_info): string =
  ## Returns a string with the contents of the shell script to run.
  ##
  ## Pass a Json_info structure read previously with read_json.
  result = """#!/bin/sh

# Set errors to bail out.
set -e
# Display commands
#set -v
BASE_DIR=~/shelltest_dropbox_filename_sanitizer
TEST_DIR="${BASE_DIR}/"""
  result.add($json_info.seconds)
  result.add(""""
NIM_DIR="${TEST_DIR}/compiler"
NIM_BIN="${NIM_DIR}/bin/nimrod"
BABEL_CFG=~/.babel
BABEL_BIN="${BABEL_CFG}/bin"
BABEL_SRC="${TEST_DIR}/babel"

SILENT_LOG=/tmp/silent_log_$$.txt
trap "/bin/rm -f $SILENT_LOG" EXIT

function report_and_exit {
	cat "${SILENT_LOG}";
	echo "\033[91mError running command.\033[39m"
	exit 1;
}

function silent {
	$* 2>>"${SILENT_LOG}" >> "${SILENT_LOG}" || report_and_exit;
}

rm -Rf "${BASE_DIR}" "${BABEL_CFG}"
if test -d "${BASE_DIR}"; then
  echo "Could not purge $BASE_DIR"
  exit 1
fi
mkdir -p "${TEST_DIR}"

silent echo "Downloading Nimrod compiler '""")
  result.add(json_info.compiler_branch)
  result.add("""'…"
silent git clone -q --depth 1 -b """)
  result.add(json_info.compiler_branch)
  result.add(""" git://github.com/Araq/Nimrod.git "${NIM_DIR}"
silent git clone -q --depth 1 -b """)
  result.add(json_info.nimrod_csources_branch)
  result.add(""" git://github.com/nimrod-code/csources "${NIM_DIR}/csources"

silent echo "Compiling csources (""")
  result.add(json_info.nimrod_csources_branch)
  result.add(""")…"
cd "${NIM_DIR}/csources"
silent sh build.sh

silent echo "Compiling koch…"
cd "${NIM_DIR}"
silent bin/nimrod c koch

silent echo "Compiling Nimrod…"
silent ./koch boot -d:release

silent echo "Testing Nimrod compiler invokation through adhoc path…"
export PATH="${NIM_DIR}/bin:${PATH}"
which nimrod
nimrod -v|grep """")
  result.add(json_info.compiler_version_str)
  result.add(""""

silent echo "Downloading Babel package manager…"
silent git clone -q --depth 1 https://github.com/nimrod-code/babel.git "${BABEL_SRC}"
cd "${BABEL_SRC}"

silent echo "Compiling Babel…"
silent nimrod c -r src/babel install

echo "Installing Babel itself through environment path…"
export PATH="${BABEL_BIN}:${PATH}"
silent babel update
silent babel install -y babel
""")

proc gen_chunk_script(json_info: Json_info): string =
  ## Returns the lines for the specified example block in `json_info`.
  ##
  ## The returned block will contain only lines starting with the dollar sign.
  ## The `chunk_number` field is an index starting from zero to infinite into
  ## the `chunk_file` field. This proc always succeeds, it quits on failure.
  var
    pos = 0
    chunk_lines: seq[string] = @[]
    reading_chunk = false

  for line in json_info.chunk_file.lines:
    if not reading_chunk:
      if line.len > 0 and line[0] in WhiteSpace:
        reading_chunk = true

    if reading_chunk:
      if line.len < 1 or not (line[0] in WhiteSpace):
        reading_chunk = false
        if pos == json_info.chunk_number:
          break
        else:
          chunk_lines = @[]
          inc pos
      else:
        var cleaned = line.strip
        if cleaned.len > 0 and cleaned[0] == '$':
          chunk_lines.add(cleaned[1 .. high(cleaned)].strip)

  if pos == json_info.chunk_number and chunk_lines.len > 0:
    result = "\n" & chunk_lines.join("\n") & "\n"
  else:
    quit("Chunk " & $json_info.chunk_number &
      " not found in " & json_info.chunk_file)


proc get_last_git_tag(): string =
  ## Returns the last git tag without the prefixing v.
  ##
  ## Aborts if the tag can't be retrieved. The git command lists tags
  ## alphabetically, so this may break and report not the last tag when numbers
  ## go into double digits.
  let (output, code) = execCmdEx("git tag --list 'v*'")
  doAssert code == 0
  for line in output.split("\n"):
    if line.len > 0:
      doAssert line[0] == 'v'
      result = line[1 .. <line.len].strip
  doAssert(not result.isNil)

proc gen_post_install_script(version: string): string =
  ## Returns the part of the shell script which involves testing the command.
  ##
  ## The testing is simple: see if it is installed in the babel path by running
  ## the command and expecting the correct version number when invoked with the
  ## version switch.
  ##
  ## Usually you will concatenate this to the end of gen_setup_script() +
  ## whatever block you are testing.
  ##
  ## The `version` string should come from the json files and indicates the
  ## expected string dumped by the binary. If you pass the word ``current`` it
  ## will be replaced by the version string from the module. Otherwise it takes
  ## the last tag from the git repository.
  result = """
silent echo "Testing installed binary version."
dropbox_filename_sanitizer -v | grep """"
  if version == "current":
    result.add(dropbox_filename_sanitizer.version_str)
  else:
    result.add(get_last_git_tag())
  result.add(""""

echo "\033[92mTest script finished successfully, removing stuff…\033[39m"
rm -Rf "${BASE_DIR}" "${BABEL_CFG}"
""")


proc read_json(filename: string): Json_info =
  ## Returns a Json_info object with the contents of `filename` or quits.
  let json = filename.parse_file
  doAssert json.kind == JObject
  result.host = json["host"].str
  result.user = json["user"].str
  result.ssh_target = result.user & "@" & result.host
  result.seconds = int(epoch_time())
  result.bash_file = "shell_test_" & $result.seconds & ".sh"
  result.compiler_branch = json["nimrod_branch"].str
  result.compiler_version_str = json["nimrod_version_str"].str
  result.nimrod_csources_branch = json["nimrod_csources_branch"].str
  result.chunk_file = json["chunk_file"].str
  result.chunk_number = int(json["chunk_number"].num)
  result.bin_version = json["bin_version"].str


proc test_shell(cmd: varargs[string, `$`]): bool {.discardable.} =
  ## Like direShell() but doesn't quit, rather raises an exception.
  let
    full_command = cmd.join(" ")
    (output, exit) = full_command.exec_cmd_ex
  result = 0 == exit
  if not result:
    output.echo
    raise new_exception(EAssertionFailed, "Error running " & full_command)


proc run_json_test(json_filename: string) =
  ## Runs a json test file.
  let json_info = read_json(json_filename)

  finally: json_info.bash_file.remove_file

  # Generate the script.
  json_info.bash_file.write_file(gen_setup_script(json_info) &
    gen_chunk_script(json_info) &
    gen_post_install_script(json_info.bin_version))
  doAssert 0 == json_info.bash_file.chmod(
    S_IRWXU or S_IRGRP or S_IXGRP or S_IROTH or S_IXOTH)

  # Send the script to the remote machine and run it after purging previous.
  echo "Starting test for ", json_filename
  test_shell("ssh", json_info.ssh_target, "rm -f 'shell_test_*.sh'")
  echo "Copying current script ", json_info.bash_file, "…"
  test_shell("scp", json_info.bash_file, json_info.ssh_target & ":.")
  echo "Running script remotely…"
  test_shell("ssh", json_info.ssh_target, "./" & json_info.bash_file)
  echo "Removing script…"
  test_shell("ssh", json_info.ssh_target, "rm '" & json_info.bash_file & "'")


task "shell_test", "Pass *.json files for shell testing":
  if paramCount() < 2:
    quit "Pass a json with test info like `nake jsonfile shell_test'."

  # Read data from the json test file.
  var
    failed: seq[string] = @[]
    total = 0
  for f in 1 .. <paramCount():
    total.inc
    let name = param_str(f)
    try:
      run_json_test(name)
    except EAssertionFailed:
      failed.add(name)
      echo "\tFailed: ", name

  echo "Nakefile finished testing ", total, " tests."
  if failed.len < 1:
    echo "Everything works!"
  else:
    for f in failed: echo "\tFailed: ", f
