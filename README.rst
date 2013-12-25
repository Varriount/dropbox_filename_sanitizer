Dropbox filename sanitizer
==========================

This little command line program displays and/or mangles the specified files to
conform to `characters allowed to synchronize correctly on Dropbox
<https://www.dropbox.com/help/145>`_. I wrote this after having files shared
with people and much later learning they weren't even getting them! The program
is implemented in the `Nimrod programming language <http://nimrod-lang.org>`_.


License
=======

`MIT license <LICENSE.rst>`_.


Installation
============

Stable version
--------------

Install the `Nimrod compiler <http://nimrod-lang.org>`_. Then use `Nimrod's
babel package manager <https://github.com/nimrod-code/babel>`_ to install the
binary::

    $ babel update
    $ babel install dropbox_filename_sanitizer

Development version
-------------------

Install the `Nimrod compiler <http://nimrod-lang.org>`_. Then use `Nimrod's
babel package manager <https://github.com/nimrod-code/babel>`_ to install
locally the github checkout::

    $ git clone https://github.com/gradha/dropbox_filename_sanitizer.git
    $ cd dropbox_filename_sanitizer
    $ git checkout develop
    $ babel install


Usage
=====

Once you have installed the package with Babel, and presuming you have
configured Babel's binary directory to be in your ``$PATH``, you can run the
command freely and pass the directory where your Dropbox shared folder exist::

    $ dropbox_filename_sanitizer /home/user/Dropbox

This will display all the files that have conflicting characters and the name
they would be mangled into. Pass the ``-m`` or ``--mutate`` switch to actually
perform renaming of these files. All behaviour is recursive.

If you want to invoke this program periodically you can put the command into
your `crontab <https://en.wikipedia.org/wiki/Cron>`_. But if you don't want to
use cron or want to execute it from other login scripts, you can use the ``-p``
or ``--period`` switch to specify how many seconds need to have elapsed since
the last run of the program using this switch to actually scan the directories.
What this means is that if you put the following line in your login scripts::

    dropbox_filename_sanitizer -p 3600 -m /home/user/Dropbox

The command will create a ``~/.dropbox_filename_sanitizer_last_run`` to
remember when was the last time it was run, and if 3600 seconds have not
elapsed, the command will quit without checking the folder. In general the
command is fast enough that you don't have to care, but maybe you want to put
this into a semi-automatic script which *may* run at a high frequency and don't
want to spam your hard drive with I/O requests.


Documentation
=============

There is not much more documentation documentation, you can see all the files
on the github project linked from the `docindex file <docindex.rst>`_ and
``dropbox_filename_sanitizer_last_run --help`` will display the command line
usage. You can also read the files installed with the babel package and use the
``doc`` `nakefile task <https://github.com/fowlmouth/nake>`_ to build their
HTML version. Unix example::

    $ cd `babel path dropbox_filename_sanitizer`
    $ nake doc
    $ open docindex.html


Changes
=======

This is version 0.3.2. For a list of changes see the `docs/CHANGES.rst file
<docs/CHANGES.rst>`_.


Git branches
============

This project uses the `git-flow branching model
<https://github.com/nvie/gitflow>`_. Which means the ``master`` default branch
doesn't *see* much movement, development happens in another branch like
``develop``. Most people will be fine using the ``master`` branch, but if you
want to contribute something please check out first the ``develop`` branch and
do pull requests against that.


Feedback
========

You can send me feedback through `github's issue tracker
<https://github.com/gradha/dropbox_filename_sanitizer/issues>`_. I also take a
look from time to time to `Nimrod's forums <http://forum.nimrod-lang.org>`_
where you can talk to other nimrod programmers.
