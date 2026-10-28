#!/bin/sh
# Tests bin/rm and libexec/trash. Cases that rm leaves to the rm of the
# system are checked against it, whichever rm it is, and every case runs
# under each POSIX shell found here.
set -u
unset CDPATH
export LC_ALL=C

repo=$(cd -P -- "$(dirname -- "$0")/.." && pwd) || exit 1
rm_sh=$repo/bin/rm
trash_sh=$repo/libexec/trash
syspath=/usr/bin:/bin
sysrm=$(PATH=$syspath command -v rm) || exit 1
nl='
'

# "-" runs rm by its #! line.
shells=-
for s in /bin/dash /bin/bash /bin/ash; do
	if [ -x "$s" ] && ! [ "$s" -ef /bin/sh ]; then
		shells=$shells$nl$s
	fi
done
if command -v busybox >/dev/null 2>&1 && ! [ /bin/ash -ef "$(command -v busybox)" ]; then
	shells="$shells${nl}busybox sh"
fi

passed=0 failed=0 name='' envs=''

fail() {
	printf 'FAIL %s: %s\n' "$name" "$1"
	failed=$((failed + 1))
}

# expect fails the case when $2 is not $3, as what $1 is.
expect() {
	[ "$2" = "$3" ] && return 0
	fail "$1:${nl}  want: $(printf '%s' "$2" | sed '2,$s/^/        /')${nl}  got:  $(printf '%s' "$3" | sed '2,$s/^/        /')"
}

# new_env sets T to a new directory with work/, which rm runs in, and
# tmp/, which holds the trash, by the physical paths the trash records.
new_env() {
	T=$(mktemp -d "${TMPDIR:-/tmp}/rm-test.XXXXXX") && T=$(cd -P -- "$T" && pwd) &&
		mkdir "$T/work" "$T/tmp" || exit 1
	envs=$envs$nl$T
}

# create makes the files in work: "d/" is a directory and "l->a" a symlink
# to a.
create() {
	for f do
		case $f in
		*'->'*)
			mkdir -p "$(dirname -- "$T/work/${f%%->*}")" && ln -s "${f#*->}" "$T/work/${f%%->*}"
			;;
		*/) mkdir -p "$T/work/$f" ;;
		*) mkdir -p "$(dirname -- "$T/work/$f")" && printf '%s' "$f" >"$T/work/$f" ;;
		esac || exit 1
	done
}

# files lists what is in $1, each line prefixed by $2: files, symlinks,
# and directories that are empty, with a trailing slash.
files() {
	[ -d "$1" ] || return 0
	(
		cd -P -- "$1" &&
			find . ! -name . \( -type d -empty -exec printf '%s/\n' {} \; -o ! -type d -print \)
	) | sed "s|^\./|$2|" | sort
}

# trashed lists the files of work in the trash, prefixed by the number of
# the directory of the rm they are in.
trashed() {
	i=0
	for b in "$T"/tmp/rune-trash-*/*; do
		[ -d "$b" ] || continue
		i=$((i + 1))
		files "$b$T/work" "$i "
	done
}

# run runs $3... in work with $2 on its stdin and PATH $1, and sets code,
# out and err.
run() {
	path=$1 stdin=$2
	shift 2
	(cd "$T/work" && printf '%s' "$stdin" |
		env -i PATH="$path" TMPDIR="$T/tmp" LC_ALL=C "$@" >"$T/out" 2>"$T/err")
	code=$?
	out=$(cat "$T/out") err=$(cat "$T/err")
}

# run_rm runs bin/rm with $3... through shell $1 with $2 on its stdin.
run_rm() {
	shell=$1 stdin=$2
	shift 2
	if [ "$shell" = - ]; then
		run "$repo/bin:$syspath" "$stdin" "$rm_sh" "$@"
	else
		# Word splitting runs "busybox sh".
		# shellcheck disable=SC2086
		run "$repo/bin:$syspath" "$stdin" $shell "$rm_sh" "$@"
	fi
}

# check runs the case named $1, creating files $2 and running rm with
# args $3, under each shell. Lists are separated by spaces, and the
# options after them are:
#
#   code=N      the exit code, 0 by default
#   left=A|B    what is left in work
#   trash=A|B   what is in the trash, as trashed lists it
#   stdout=S    what stdout contains; it is empty by default
#   stderr      stderr is not empty; it is empty by default
#   stdin=S     a line on stdin
#   likerm      the rm of the system removes the files, as it would alone
check() {
	case_files=$1 case_args=$2 case_name=$3
	shift 3
	want_code=0 want_left='' want_trash='' want_out='' want_err=0 stdin='' likerm=''
	for o do
		case $o in
		code=*) want_code=${o#*=} ;;
		left=*) want_left=$(printf '%s' "${o#*=}" | tr '|' '\n') ;;
		trash=*) want_trash=$(printf '%s' "${o#*=}" | tr '|' '\n') ;;
		stdout=*) want_out=${o#*=} ;;
		stderr) want_err=1 ;;
		stdin=*) stdin=${o#*=}$nl ;;
		likerm) likerm=1 ;;
		*) echo "unknown option $o" >&2 && exit 1 ;;
		esac
	done
	if [ -n "$likerm" ]; then
		new_env
		# shellcheck disable=SC2086
		create $case_files
		# shellcheck disable=SC2086
		run "$syspath" "$stdin" "$sysrm" $case_args
		want_code=$code want_left=$(files "$T/work" '') want_err=0
		[ -z "$err" ] || want_err=1
	fi
	IFS=$nl
	for shell in $shells; do
		unset IFS
		name="$shell/$case_name"
		new_env
		# shellcheck disable=SC2086
		create $case_files
		# shellcheck disable=SC2086
		run_rm "$shell" "$stdin" $case_args
		before=$failed
		expect "exit code ($err)" "$want_code" "$code"
		expect 'left in work' "$want_left" "$(files "$T/work" '')"
		expect 'in the trash' "$want_trash" "$(trashed)"
		if [ -z "$want_out" ]; then
			expect stdout '' "$out"
		else
			case $out in *"$want_out"*) ;; *) fail "stdout $out lacks $want_out" ;; esac
		fi
		got_err=0
		[ -z "$err" ] || got_err=1
		expect "stderr is written ($err); the note is only for terminals" "$want_err" "$got_err"
		[ "$failed" -ne "$before" ] || passed=$((passed + 1))
	done
	unset IFS
}

check 'a b' a 'a file' left=b trash='1 a'
check 'd/x d/y/z' '-rf d' 'a tree' trash='1 d/x|1 d/y/z'
check 'a b c' 'a b' 'several files' left=c trash='1 a|1 b'
check d/x '--recursive --force d' 'long options' trash='1 d/x'
check e/ '-r e' 'an empty directory' trash='1 e/'
check 'a l->a' l 'a symlink, not what it names' left=a trash='1 l'
check d/x '-r d/' 'a trailing slash' trash='1 d/x'
check 'a s/' s/../a 'a path through ..' left=s/ trash='1 a'
check -x '-- -x' 'a name like an option after --' trash='1 -x'
check a '-v a' verbose trash='1 a' "stdout=moved 'a' to '"
check 'd/x d/y' '-r d/x d' 'a name already in the directory of the rm' trash='1 d/x|2 d/y'
check '' '-f nope' 'a missing file with -f'
check a 'nope a' 'a missing file' code=1 trash='1 a' stderr
check d/x d 'a directory without -r' likerm
check e/ '-d e' 'an empty directory with -d' likerm
check a '-i a' 'options it does not handle' stdin=y likerm
check a 'a -f' 'options after files' likerm
check a '-rf .' 'rm refuses .' likerm
check '' -f 'no files with -f' likerm
check '' '' 'no files' likerm

name='rm deletes what is in the trash'
before=$failed
new_env
create a
run_rm - '' a
run_rm - '' -rf "$T"/tmp/rune-trash-*
expect "exit code ($err)" 0 "$code"
expect 'trash' '' "$(cd "$T/tmp" && ls)"
[ "$failed" -ne "$before" ] || passed=$((passed + 1))

name='rm skips copies of itself on the PATH'
before=$failed
new_env
create a
mkdir "$T/other" && cp "$rm_sh" "$T/other/rm"
run "$repo/bin:$T/other:$syspath" "y$nl" "$rm_sh" -i a
expect "exit code ($err)" 0 "$code"
expect 'left in work, which the real rm removed' '' "$(files "$T/work" '')"
[ "$failed" -ne "$before" ] || passed=$((passed + 1))

# in_tty runs $@ in a terminal, writing what it shows to $T/tty. The
# script of util-linux, busybox and BSD each take the command their way.
in_tty() {
	line=''
	for a do line="$line '$a'"; done
	if script -qec true /dev/null >/dev/null 2>&1 </dev/null; then
		script -qec "$line" /dev/null
	elif script -qc true /dev/null >/dev/null 2>&1 </dev/null; then
		script -qc "$line" /dev/null
	else
		script -q /dev/null "$@"
	fi >"$T/tty" 2>&1 </dev/null
}

name='rm tells terminals where it moved the files'
before=$failed
if command -v script >/dev/null 2>&1; then
	new_env
	create a
	(cd "$T/work" && in_tty env -i PATH="$repo/bin:$syspath" TMPDIR="$T/tmp" "$rm_sh" a)
	batch=$(echo "$T"/tmp/rune-trash-*/*)
	# BSD script echoes the end of its stdin as ^D and backspaces.
	expect 'shown' "rm: moved files to $batch instead of permanently removing them" \
		"$(tr -d '\r\b' <"$T/tty" | sed 's/^\^D//')"
	expect 'in the trash' '1 a' "$(trashed)"
	[ "$failed" -ne "$before" ] || passed=$((passed + 1))
else
	echo "SKIP $name: no script(1)"
fi

name='trash says when it is empty'
before=$failed
new_env
run "$syspath" '' env SHELL=/bin/pwd sh "$trash_sh"
expect "exit code ($err)" 0 "$code"
expect 'output' "The trash is empty.$nl$T/work" "$out"
[ "$failed" -ne "$before" ] || passed=$((passed + 1))

name='trash lists what each rm moved, newest first, and opens a shell in the trash'
before=$failed
new_env
create d/x d/y/z e/ a
run_rm - '' -rf d e
run_rm - '' a
set -- "$T"/tmp/rune-trash-*/*
expect 'directories of the rms' 2 "$#"
old=$1 new=$2
for b in "$old" "$new"; do
	case $(files "$b$T/work" '') in a) new=$b ;; *) old=$b ;; esac
done
touch -t 202001010000 "$old"
run "$syspath" '' env SHELL=/bin/pwd sh "$trash_sh"
expect "exit code ($err)" 0 "$code"
line() { printf '%s\n' "$out" | sed -n "$1p"; }
case $(line 1) in "$new  ("*")") ;; *) fail "the newest first: $out" ;; esac
expect 'what the newest moved' "  $T/work/a" "$(line 2)"
expect 'the oldest' "$old  (2020-01-01 00:00)" "$(line 3)"
expect 'what the oldest moved' "  $T/work/d/x$nl  $T/work/d/y/z$nl  $T/work/e/" \
	"$(printf '%s\n' "$out" | sed -n 4,6p | sort)"
expect 'shell in the trash' "${new%/*}" "$(printf '%s\n' "$out" | tail -n 1)"
[ "$failed" -ne "$before" ] || passed=$((passed + 1))

IFS=$nl
for T in $envs; do
	[ -n "$T" ] && /bin/rm -rf "$T"
done
unset IFS

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]