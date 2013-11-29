import argument_parser, os, tables, strutils, times

type
  Tglobal = object ## \
    ## Holds all the global variables of the process.
    params: Tcommandline_results
    mutate: bool ## True if the user is mutating problematic files.
    period: int ## Less than 1 if not used, or the minimum elapsed time.


var G: Tglobal

const
  version_str* = "0.2.1" ## Program version as a string.
  version_int* = (major: 0, minor: 2, maintenance: 1) ## \
  ## Program version as an integer tuple.
  ##
  ## Major version changes mean significant new features or a break in
  ## commandline backwards compatibility, either through removal of switches or
  ## modification of their purpose.
  ##
  ## Minor version changes can add switches. Minor
  ## odd versions are development/git/unstable versions. Minor even versions
  ## are public stable releases.
  ##
  ## Maintenance version changes mean bugfixes or non commandline changes.

  param_help = @["-h", "--help"]
  help_help = "Displays commandline help and exits."

  param_version = @["-v", "--version"]
  help_version = "Displays the current version and exists."

  param_period = @["-p", "--period"]
  help_period = "Require elapsed seconds since last run."

  param_mutate = @["-m", "--mutate"]
  help_mutate = "Mangle bad characters into common placeholders, " &
    "by default files are only displayed."

  ignored_paths = @["icon\r", ".", ".."]

  last_run = ".dropbox_filename_sanitizer_last_run"


proc process_commandline() =
  ## Parses the commandline, modifying the global structure.
  var PARAMS: seq[Tparameter_specification] = @[]
  PARAMS.add(new_parameter_specification(PK_HELP,
    names = param_help, help_text = help_help))
  PARAMS.add(new_parameter_specification(PK_INT, names = param_period,
    help_text = help_period))
  PARAMS.add(new_parameter_specification(names = param_version,
    help_text = help_version))
  PARAMS.add(new_parameter_specification(names = param_mutate,
    help_text = help_mutate))

  G.params = parse(PARAMS)

  if G.params.options.has_key(param_version[0]):
    echo "Version ", version_str
    quit()

  if G.params.options.has_key(param_mutate[0]):
    G.mutate = true

  if G.params.options.has_key(param_period[0]):
    G.period = G.params.options[param_period[0]].int_val
    if G.period < 1:
      echo "Period can't be less than 1 second"
      echo_help(params)
      quit()

  if G.params.positional_parameters.len < 1:
    echo "You need to specify files/directories to sanitize."
    echo_help(params)
    quit()


proc mangle_characters(TEXT: var string): bool =
  ## Modifies TEXT to contain only dropbox approved characters.
  ##
  ## See https://www.dropbox.com/help/145 for information about bad chars.
  ## Returns true if TEXT had to be modified, false if there was no change. You
  ## shuold pass as TEXT only the base name of the path, or the slashes will be
  ## changed!
  let original = TEXT
  TEXT = TEXT.strip()
  TEXT = TEXT.replace('/', '_')
  TEXT = TEXT.replace('\\', '_')
  TEXT = TEXT.replace(':', ',')
  TEXT = TEXT.replace('<', '[')
  TEXT = TEXT.replace('>', ']')
  TEXT = TEXT.replace('|', '_')
  TEXT = TEXT.replace('"', '\'')
  TEXT = TEXT.replace('?', '_')
  TEXT = TEXT.replace('*', '_')
  # Trim trailing dots.
  while TEXT.len > 0:
    let last = high(TEXT)
    if TEXT[last] == '.':
      TEXT.setLen(last)
    else:
      break
  result = not (original == TEXT)


proc sanitize(path: string): bool =
  ## Entry point to sanitize a path.
  ##
  ## The path will be sanitized, and then if a directory recursively iterated.
  ## Returns false if something went wrong and the program should quit with a
  ## non zero status.
  let
    is_dir = path.exists_dir
    is_file = path.exists_file
  if (not is_dir) and (not is_file):
    echo "Invalid '" & path & "' not a file or directory."
    return

  # From here on, presume we succeeded and report failures.
  result = true

  let (dir, name, ext) = path.split_file
  var VALID = name & ext
  # Ignore some paths anyway.
  for ignored_path in ignored_paths:
    if cmp_ignore_case(VALID, ignored_path) == 0:
      return
  if mangle_characters(VALID):
    if G.mutate:
      let target = dir / VALID
      echo "'" & path & "' -> '" & target & "'"
      move_file(path, target)
    else:
      echo "Would change '" & path & "' to '" & dir / VALID & "'"

  # Initiate recursion? Only for directories.
  if is_dir:
    let final_path = dir / VALID
    for kind, path in final_path.walk_dir:
      if not sanitize(path):
        result = false


proc ignore_due_to_recent_run(): bool =
  ## Returns true if the program was run within the specified period time.
  ##
  ## The period time is obtained form G.period. The check for the time is
  ## stored using the witness ``last_run`` file's modification time. If there
  ## is a serious problem the proc will quit with an error.
  ##
  ## Invoking this proc will overwrite the witness file if the period has
  ## elapsed or the file does not exist.
  assert G.period > 0, "Invalid period!"
  let
    witness = get_home_dir() / last_run
    now = to_seconds(get_time())

  var WITNESS_TIME: float
  try:
    WITNESS_TIME = to_seconds(getLastModificationTime(witness)) +
      float(G.period)
    if WITNESS_TIME > now:
      result = true
    else:
      witness.write_file("")
  except EOS:
    witness.write_file("")



when isMainModule:
  # Gets parameters and extracts them for easy access.
  process_commandline()
  if G.period > 0:
    if ignore_due_to_recent_run():
      quit()

  var DID_FAIL: bool
  for parameter in G.params.positional_parameters:
    if not sanitize(parameter.str_val):
      DID_FAIL = true

  if DID_FAIL: quit(QuitFailure)
