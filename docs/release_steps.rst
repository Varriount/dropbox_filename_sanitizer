==================================================================
What to do for a new public release of dropbox_filename_sanitizer?
==================================================================

* Create new milestone with version number (``vXXX``) at
  https://github.com/gradha/dropbox_filename_sanitizer/issues/milestones.
* Create new dummy issue `Release versionname` and assign to that milestone.
* Annotate the release issue with the Nimrod commit used to compile sources,
  can the nake ``md5`` task to check the final commit.
* ``git flow release start versionname`` (versionname without v).
* Update version numbers:

  * Modify `README.rst <../README.rst>`_.
  * Modify `docs/CHANGES.rst <CHANGES.rst>`_ with list of changes and
    version/number.
  * Modify `dropbox_filename_sanitizer.babel
    <../dropbox_filename_sanitizer.babel>`_.
  * Modify `dropbox_filename_sanitizer.nim
    <../dropbox_filename_sanitizer.nim>`_.

* ``git commit -av`` into the release branch the version number changes.
* ``git flow release finish versionname`` (the tagname is versionname without
  ``v``). When specifying the tag message, copy and paste a text version of the
  changes log into the message. Add rst item markers.
* Move closed issues to the release milestone.
* ``git push origin master stable --tags``.
* Build binaries for macosx/linux with nake ``dist`` command.
* Attach the binaries to the appropriate release at
  `https://github.com/gradha/dropbox_filename_sanitizer/releases
  <https://github.com/gradha/dropbox_filename_sanitizer/releases>`_.

  * Use nake ``md5`` task to generate md5 values, add them to the release.
  * Follow the tag link of the release and create a hyper link to its changes
    log on (e.g.
    `https://github.com/gradha/dropbox_filename_sanitizer/blob/v0.2.1/docs/CHANGES.rst
    <https://github.com/gradha/dropbox_filename_sanitizer/blob/v0.2.1/docs/CHANGES.rst>`_).
  * Also add to the release text the Nimrod compiler version noted in the
    release issue.

* Increase version numbers, ``master`` branch gets +0.0.1:

  * Modify `README.rst <../README.rst>`_.
  * Modify `dropbox_filename_sanitizer.nim
    <../dropbox_filename_sanitizer.nim>`_.
  * Modify `dropbox_filename_sanitizer.babel
    <../dropbox_filename_sanitizer.babel>`_.
  * Add to `docs/CHANGES.rst <CHANGES.rst>`_ development version with unknown
    date.

* ``git commit -av`` into ``master`` with *Bumps version numbers for
  development version. Refs #release issue*.
* ``git push origin master stable --tags``.
* Close the dummy release issue.
* Announce at
  `http://forum.nimrod-lang.org/t/302 <http://forum.nimrod-lang.org/t/302>`_.
* Close the milestone on github.
