#!/bin/sh
# Tests bin/rm and libexec. Cases that rm leaves to the rm of the system
# are checked against it, whichever rm it is, and the cases of rm run under
# each POSIX shell found here. Those of a home on another disk than the
# temporary directories run where /dev/shm is one, as in containers.
set -u
unset CDPATH
export LC_ALL=C

repo=$(cd -P -- "$(dirname -- "$0")/.." && pwd) || exit 1
rm_sh=$repo/bin/rm
trash_sh=$repo/libexec/trash
trash_dir_sh=$repo/libexec/trash-dir
syspath=/usr/bin:/bin
sysrm=$(PATH=$syspath command -v rm) || exit 1
uid=$(id -u)
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

passed=0 failed=0 name='' envs='' xenv=''

fail() {
	printf 'FAIL %s: %s\n' "$name" "$1"
	failed=$((failed + 1))
}

# expect fails the case when $2 is not $3, as what $1 is.
expect() {
	[ "$2" = "$3" ] && return 0
	fail "$1:${nl}  want: $(printf '%s' "$2" | sed '2,$s/^/        /')${nl}  got:  $(printf '%s' "$3" | sed '2,$s/^/        /')"
}

# start names a case that is not run through check.
start() {
	name=$1 before=$failed
}

done_case() {
	[ "$failed" -ne "$before" ] || passed=$((passed + 1))
}

# new_env sets T to a new directory in $1, or the temporary directory,
# with work/, which rm runs in, and tmp/, which holds the trash, by the
# physical paths the trash records.
new_env() {
	T=$(mktemp -d "${1:-${TMPDIR:-/tmp}}/rm-test.XXXXXX") && T=$(cd -P -- "$T" && pwd) &&
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

# trashed lists the files of $2, or work, in trash $1, or the one in tmp,
# prefixed by the number of the directory of the rm they are in.
trashed() {
	i=0
	for b in "${1:-$T/tmp/rune-trash-$uid}"/*; do
		[ -d "$b" ] || continue
		i=$((i + 1))
		files "$b${2:-$T/work}" "$i "
	done
}

# run runs $3... in work with $2 on its stdin and PATH $1, and the
# variables of xenv, and sets code, out and err. It fails the case when
# the command takes more than 30 seconds.
run() {
	path=$1
	printf '%s' "$2" >"$T/in"
	shift 2
	(
		cd "$T/work" || exit
		# xenv splits into the variables.
		# shellcheck disable=SC2086
		exec env -i PATH="$path" TMPDIR="$T/tmp" LC_ALL=C $xenv "$@" <"$T/in" >"$T/out" 2>"$T/err"
	) &
	pid=$! i=0
	while kill -0 "$pid" 2>/dev/null; do
		i=$((i + 1))
		if [ "$i" -gt 150 ]; then
			kill -9 "$pid"
			fail "$* did not finish"
			break
		fi
		sleep 0.2
	done
	wait "$pid"
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
		start "$shell/$case_name"
		new_env
		# shellcheck disable=SC2086
		create $case_files
		# shellcheck disable=SC2086
		run_rm "$shell" "$stdin" $case_args
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
		done_case
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
check "it's" "it's" 'a name with a quote' trash="1 it's"
check a '-v a' verbose trash='1 a' "stdout=moved 'a' to '"
check 'd/x d/y' '-r d/x d' 'a name already in the directory of the rm' trash='1 d/x|2 d/y'
check '' '-f nope' 'a missing file with -f'
check a 'nope a' 'a missing file' code=1 trash='1 a' stderr
check 'a b' 'a b ./a' 'a file named twice' trash='1 a|1 b' likerm
check 'a b' '-f a b a' 'a file named twice with -f' trash='1 a|1 b' likerm
check d/x d 'a directory without -r' likerm
check e/ '-d e' 'an empty directory with -d' likerm
check a '-i a' 'options it does not handle' stdin=y likerm
check a 'a -f' 'options after files' likerm
check a '-rf .' 'rm refuses .' likerm
check '' -f 'no files with -f' likerm
check '' '' 'no files' likerm

start 'many files, which rm moves some at a time'
new_env
mkdir "$T/work/d"
i=0
while [ "$i" -lt 3000 ]; do
	: >"$T/work/d/f$i"
	i=$((i + 1))
done
t0=$(date +%s)
run_rm - '' -f "$T"/work/d/*
t1=$(date +%s)
expect "exit code ($err)" 0 "$code"
expect 'left' '' "$(ls "$T/work/d")"
expect 'in the trash' 3000 "$(trashed | wc -l | tr -d ' ')"
echo "INFO $name: $((t1 - t0))s"
done_case

start 'rm deletes what is in the trash'
new_env
create a
run_rm - '' a
run_rm - '' -rf "$T/tmp/rune-trash-$uid"
expect "exit code ($err)" 0 "$code"
expect 'trash' '' "$(cd "$T/tmp" && ls)"
done_case

start 'rm skips copies of itself on the PATH'
new_env
create a
mkdir "$T/other" && cp "$rm_sh" "$T/other/rm"
run "$repo/bin:$T/other:$syspath" "y$nl" "$rm_sh" -i a
expect "exit code ($err)" 0 "$code"
expect 'left in work, which the real rm removed' '' "$(files "$T/work" '')"
done_case

start 'rm skips other versions of itself on the PATH'
new_env
create a b
mkdir "$T/a" "$T/b"
# The version that was published first.
cp "$repo/scripts/testdata/rm-c2cbd58" "$T/a/rm"
{ cat "$rm_sh" && echo '# another version'; } >"$T/b/rm"
chmod 755 "$T/a/rm" "$T/b/rm"
run "$T/b:$T/a:$syspath" "y$nl" "$T/b/rm" -i a
expect "exit code ($err)" 0 "$code"
expect 'left in work, which the real rm removed' b "$(files "$T/work" '')"
run "$T/a:$T/b:$syspath" "n$nl" "$T/a/rm" -i b
expect "exit code ($err)" 0 "$code"
expect 'left in work, which the real rm asked about' b "$(files "$T/work" '')"
done_case

start 'rm passes files to a wrapper that runs the first rm on the PATH again'
new_env
create a
mkdir "$T/wrapper"
printf '#!/bin/sh\nexec rm "$@"\n' >"$T/wrapper/rm"
chmod 755 "$T/wrapper/rm"
run "$repo/bin:$T/wrapper:$syspath" "y$nl" "$rm_sh" -i a
expect "exit code ($err)" 0 "$code"
expect 'left in work, which the real rm removed' '' "$(files "$T/work" '')"
done_case

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

start 'rm tells terminals where it moved the files'
if command -v script >/dev/null 2>&1; then
	new_env
	create a
	(cd "$T/work" && in_tty env -i PATH="$repo/bin:$syspath" TMPDIR="$T/tmp" "$rm_sh" a)
	batch=$(echo "$T/tmp/rune-trash-$uid"/*)
	# BSD script echoes the end of its stdin as ^D and backspaces.
	expect 'shown' "rm: moved files to $batch instead of permanently removing them" \
		"$(tr -d '\r\b' <"$T/tty" | sed 's/^\^D//')"
	expect 'in the trash' '1 a' "$(trashed)"
	done_case
else
	echo "SKIP $name: no script(1)"
fi

start 'rm deletes what it moved a week ago or more, at most hourly'
new_env
create a b
root=$T/tmp/rune-trash-$uid
now=$(date +%s)
mkdir -m 700 "$root" && mkdir -p "$root/1-1/x" "$root/$((now - 3600))-2/x"
run_rm - '' a
i=0
while [ -e "$root/1-1" ] && [ "$i" -lt 50 ]; do
	sleep 0.2
	i=$((i + 1))
done
! [ -e "$root/1-1" ] || fail 'the batch of a week ago is left'
[ -e "$root/$((now - 3600))-2" ] || fail 'the batch of an hour ago is gone'
mkdir -p "$root/1-3/x"
run_rm - '' b
sleep 1
[ -e "$root/1-3" ] || fail 'rm pruned again within the hour'
done_case

start 'trash-dir prints the trash rm moves the files of the directory to'
new_env
run "$syspath" '' sh "$trash_dir_sh" "$T/work"
expect "exit code ($err)" 0 "$code"
expect 'trash' "$T/tmp/rune-trash-$uid" "$out"
run "$syspath" '' sh "$trash_dir_sh"
expect 'the trash of the current directory' "$T/tmp/rune-trash-$uid" "$out"
done_case

start 'trash says when it is empty'
new_env
run "$syspath" '' env SHELL=/bin/pwd sh "$trash_sh" "$T/tmp/rune-trash-$uid"
expect "exit code ($err)" 0 "$code"
expect 'output' "The trash is empty: $T/tmp/rune-trash-$uid$nl$T/work" "$out"
done_case

start 'trash lists what each rm moved, newest first, and opens a shell in the trash'
new_env
create d/x d/y/z e/ a
run_rm - '' -rf d e
run_rm - '' a
root=$T/tmp/rune-trash-$uid
set -- "$root"/*
expect 'directories of the rms' 2 "$#"
old=$1 new=$2
for b in "$old" "$new"; do
	case $(files "$b$T/work" '') in a) new=$b ;; *) old=$b ;; esac
done
touch -t 202001010000 "$old"
run "$syspath" '' env SHELL=/bin/pwd sh "$trash_sh" "$root"
expect "exit code ($err)" 0 "$code"
line() { printf '%s\n' "$out" | sed -n "$1p"; }
case $(line 1) in "$new  ("*")") ;; *) fail "the newest first: $out" ;; esac
expect 'what the newest moved' "  $T/work/a" "$(line 2)"
expect 'the oldest' "$old  (2020-01-01 00:00)" "$(line 3)"
expect 'what the oldest moved' "  $T/work/d/x$nl  $T/work/d/y/z$nl  $T/work/e/" \
	"$(printf '%s\n' "$out" | sed -n 4,6p | sort)"
expect 'shell in the trash' "$root" "$(printf '%s\n' "$out" | tail -n 1)"
done_case

start 'trash lists the files of the 10 newest rms, and counts the rest'
new_env
root=$T/tmp/rune-trash-$uid
mkdir -m 700 "$root"
i=1
while [ "$i" -le 12 ]; do
	mkdir -p "$root/$i-1/x" && : >"$root/$i-1/x/f"
	touch -t "2020010100$(printf %02d "$i")" "$root/$i-1"
	i=$((i + 1))
done
run "$syspath" '' env SHELL=/bin/pwd sh "$trash_sh" "$root"
expect "exit code ($err)" 0 "$code"
expect 'the rms listed' 10 "$(printf '%s\n' "$out" | grep -c '  (2020-')"
expect 'the newest first' "$root/12-1  (2020-01-01 00:12)" "$(printf '%s\n' "$out" | sed -n 1p)"
expect 'the rest' '…and what 2 more rms moved' "$(printf '%s\n' "$out" | grep 'more rms')"
done_case

dev_of() {
	stat -c %d -- "$1" 2>/dev/null || stat -f %d -- "$1" 2>/dev/null
}

# Root can test what it is to be another user.
if [ "$uid" -eq 0 ]; then
	start 'a trash another user made first, as USER may name them'
	new_env
	create a
	mkdir "$T/tmp/rune-trash-someone" && chown 1000 "$T/tmp/rune-trash-someone"
	xenv=USER=someone
	run_rm - '' a
	xenv=''
	expect "exit code ($err)" 0 "$code"
	expect 'in the trash of the uid' '1 a' "$(trashed)"
	expect "in the other user's" '' "$(ls "$T/tmp/rune-trash-someone")"
	done_case
fi

shm=''
if [ -d /dev/shm ] && [ -w /dev/shm ]; then
	shm=$(dev_of /dev/shm)
	for t in "${TMPDIR:-/tmp}" /var/tmp /tmp; do
		[ "$(dev_of "$t")" != "$shm" ] || shm=''
	done
fi
if [ -z "$shm" ]; then
	echo 'SKIP a home on another disk than the temporary directories: no /dev/shm on one'
else
	host_tmp=$(mktemp -d "${TMPDIR:-/tmp}/rm-test.XXXXXX") && envs=$envs$nl$host_tmp
	# new_home sets T to an environment on /dev/shm, with home/ as the home.
	new_home() {
		new_env /dev/shm
		mkdir "$T/home"
		xenv="HOME=$T/home TMPDIR=$host_tmp"
	}
	ctrash() {
		trashed "${1:-$T/home/.cache}/rune-trash" "${2:-$T/work}"
	}

	start 'the files of a disk without a temporary directory go to the cache of the home'
	new_home
	create a d/x
	run_rm - '' -r a d
	expect "exit code ($err)" 0 "$code"
	expect 'in the trash' "1 a${nl}1 d/x" "$(ctrash)"
	expect 'in the temporary directory' '' "$(ls "$host_tmp")"
	run "$syspath" '' sh "$trash_dir_sh" "$T/work"
	expect 'trash-dir' "$T/home/.cache/rune-trash" "$out"
	done_case

	start 'XDG_CACHE_HOME holds the trash'
	new_home
	mkdir "$T/cache"
	xenv="$xenv XDG_CACHE_HOME=$T/cache"
	create a
	run_rm - '' a
	expect "exit code ($err)" 0 "$code"
	expect 'in the trash' '1 a' "$(ctrash "$T/cache")"
	done_case

	start 'removing the home keeps the trash, and moves the rest to it'
	new_home
	mkdir -p "$T/home/src/app" "$T/home/.cache/pip"
	: >"$T/home/.profile"
	: >"$T/home/src/app/main.go"
	: >"$T/home/.cache/pip/x"
	run_rm - '' -rf "$T/home"
	expect 'exit code' 1 "$code"
	expect 'message' "rm: cannot remove '$T/home': it holds the trash, $T/home/.cache/rune-trash" "$err"
	expect 'left in the home' .cache "$(ls -A "$T/home")"
	expect 'left in the cache' rune-trash "$(ls -A "$T/home/.cache")"
	expect 'in the trash' "1 .cache/pip/x${nl}1 .profile${nl}1 src/app/main.go" \
		"$(ctrash '' "$T/home")"
	done_case

	start 'removing the cache removes the trash'
	new_home
	create a
	run_rm - '' a
	run_rm - '' -rf "$T/home/.cache"
	expect "exit code ($err)" 0 "$code"
	expect 'left in the home' '' "$(ls -A "$T/home")"
	done_case

	start 'a disk with no trash'
	new_env /dev/shm
	create a
	xenv="TMPDIR=$host_tmp"
	run_rm - '' a
	expect "exit code ($err)" 0 "$code"
	expect 'left' '' "$(files "$T/work" '')"
	run "$syspath" '' sh "$trash_dir_sh" "$T/work"
	expect 'trash-dir fails' 1 "$code"
	expect 'trash-dir says why' \
		"rm: no trash is on the disk of $T/work, so rm deletes its files for good" "$err"
	xenv=''
	done_case

	if [ "$uid" -eq 0 ]; then
		start "root with another user's home deletes for good"
		new_home
		chown 1000 "$T/home"
		create a
		run_rm - '' a
		expect "exit code ($err)" 0 "$code"
		expect 'left' '' "$(files "$T/work" '')"
		expect 'left in the home' '' "$(ls -A "$T/home")"
		done_case
	fi
	xenv=''
fi

IFS=$nl
for T in $envs; do
	[ -n "$T" ] && /bin/rm -rf "$T"
done
unset IFS

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]