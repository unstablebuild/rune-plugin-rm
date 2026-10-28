# An rm command that can be undone

A package for [Rune](https://github.com/unstablebuild/rune) that shadows your system's
`rm` with one that moves what you or your agent intended to remove, to a trash in the
temporary directory or your home's cache instead of deleting it.

```bash
$ rm -rf build
rm: moved files to /var/tmp/rune-trash-me/1761660000-4242 instead of permanently removing them
$ mv /var/tmp/rune-trash-me/1761660000-4242/home/me/src/app/build build
```

## What it installs

Installing this package:

- Adds `rm` to your Rune data directory, `$RUNE_DATADIR/bin`, which Rune puts first on
  the `PATH` of its terminals and of the commands it runs, such as Rune Agent's. Other
  programs and terminals keep the `rm` of your system.
- Adds a `trash` command. Run `:trash` from the command prompt to open a terminal tab
  that lists what each `rm` moved to the trash of the workspace's files, newest first,
  and opens a shell there.

## How it works

`rm` moves each file to a trash on the same disk as the file, so that the move is a
rename, which is as quick as deleting the file whatever its size. The trash is the
first of these that is on the file's disk:

1. `rune-trash-<user>` in `$TMPDIR`, `/var/tmp` or `/tmp`;
2. `rune-trash` in the cache of your home, `$XDG_CACHE_HOME` or `~/.cache`.

Each `rm` gets a directory in the trash named after when it ran and its process ID,
which holds the files at their full paths: removing `/home/me/src/app/build` puts it at
`/var/tmp/rune-trash-me/1761660000-4242/home/me/src/app/build`.

On macOS, `$TMPDIR` is a directory of your own on the disk of your home. On Linux,
`/tmp` is often in memory, so files of your home go to `/var/tmp`, or to the cache of
your home when it is on a disk of its own, as on many btrfs and network setups. Files
on other disks, such as a USB drive or `/dev/shm`, have no trash: `rm` deletes them.

When its standard error is a terminal, `rm` tells you which directory it moved the files
to. Otherwise it prints nothing, as `rm` does, so scripts and agents that read its output
see no difference. With `-v`, it prints each file it moves.

`rm` takes about 10 ms more than the `rm` of the system, which it is a shell script
around.

## Restore files

Move them back from the trash, as above, or run `:trash` to see what is there.
`$RUNE_DATADIR/lib/github.com/unstablebuild/rune-plugin-rm/libexec/trash-dir DIR`
prints the trash of the files in `DIR`.

The system clears the temporary directory on its own schedule, often of days or weeks
without use, and some systems clear `/tmp` when they start. The schedule counts from
when the files were last used, not from when they were removed, so a file you had not
opened in a while can go soon after. `rm` itself deletes what it moved to the trash a
week before or more, and is all that clears the cache of your home. Restore files as
soon as you can.

Until then, the files still take up space on the disk. To free it, remove them from the
trash: `rm` deletes what is already in it, so `rm -rf /var/tmp/rune-trash-me` empties
that trash.

## What it still deletes

`rm` deletes for good, through the `rm` of the system:

- what is on a disk where neither a temporary directory nor the cache of your home is,
  or is already in the trash, or could not be moved;
- what would go to a trash that is not a directory of yours, as when another user
  created it first in a shared `/tmp`, and `rune-trash-<uid>` is not yours either;
- what would go to the cache of a home that is not yours, as when root runs `rm` under
  `sudo` with the home of the user;
- the temporary directory or the cache that holds the trash, with the trash.

Removing a directory that holds the trash further down, such as your home, moves what
it holds to the trash, except the directories on the way to the trash, and fails as `rm`
fails on a directory it cannot remove.

It leaves to the `rm` of the system, which deletes as usual:

- options other than `-f`, `-r`, `-R`, `-d` and `-v` and their long forms, such as `-i`
  and `--one-file-system`, and options after file names;
- directories without `-r`, symlinks named with a trailing slash, and `/`, `.` and
  `..`, which `rm` refuses in its own words.

Nor does it change what does not run `rm` from the `PATH`: `/bin/rm`, `sudo rm`, whose
`PATH` is its own, `find -delete`, `git clean`, and programs that delete files
themselves. A shell that ran `rm` before you installed the package may remember the old
one: run `hash -r` or open a new terminal.

Other versions of this `rm` on the `PATH`, and wrappers that run `rm` again, pass the
files on to the `rm` of the system rather than to each other.

It does not run on Windows.

## Install

Open the [Rune console](https://docs.rune.build/learn/console) and run:

```
pkg install github.com/unstablebuild/rune-plugin-rm
```

To go back to the `rm` of your system, run:

```
pkg remove github.com/unstablebuild/rune-plugin-rm
```

The `trash` command stays in your config until you remove `command.aliases.trash`.

## Develop

```
make test         # run the tests under each POSIX shell found here
make test-docker  # run them on Debian and Alpine, as root and as a user
make lint         # run shellcheck
```

The tests check that what `rm` leaves to the `rm` of the system ends as it would without
the package, whichever `rm` that is.

## License

MIT; see [LICENSE](./LICENSE).
