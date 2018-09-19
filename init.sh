#!/bin/bash
#### Global Variables ####
trap failure_exit 1
trap success_exit 0
if [[ "$(dirname $0)"  == "." ]]; then
	WORK_DIR="$(pwd)"
else
	WORK_DIR="$(dirname $0)"
fi
DEBUG=0
VERBOSE=""
QUIET="-q"
FORCE_FLAG=0
REQUIRED_PKGS=( 'cut' 'rev' )
OPTIONAL_PKGS=()
GIT_REPOS=()
REPO_PKGS_DIR="$WORK_DIR"
PY_INIT=0
GIT_INIT=0
PYENV="$WORK_DIR/pyenv"
PIP_TXT="$WORK_DIR/requirements.txt"
PIP_PKGS=()
INIT_CONFIG="$WORK_DIR/init.ini"
RUN_DATE=$(date +%Y-%d-%m-%H-%M-%S)
#### Functions ####
load_config()
{
	if [ ! -f "$INIT_CONFIG" ];then
		[ $DEBUG -eq 1 ] && print -E -R "Missing init config: $INIT_CONFIG"
		return 1
	fi
	[ $DEBUG -eq 1 ] && print -E -B "Loading config from $INIT_CONFIG"
	while read CONF_LINE
	do
		if [[ "${CONF_LINE:0:1}" == "#" ]] || [[ "${CONF_LINE:0:1}" == ";" ]]; then
			[ $DEBUG -eq 1 ] && print -E -B "Skipping commented line: $CONF_LINE"
			continue
		fi
		KEY=""
		VALUE=""
		index=0
		OIFS="$IFS"
		IFS="="
		for l in $CONF_LINE
		do
			case $index in
				0) KEY="$l" ;;
				*)
					if [[ "$VALUE" == "" ]]; then
						VALUE="$l"
					else
						VALUE="$VALUE=$l"
					fi
					;;
			esac
			((index++))
		done
		IFS="$OIFS"
		if [ $DEBUG -eq 1 ]; then
			print -E -B "Parsed the following from $CONF_LINE:"
			print -E -B "	KEY=$KEY"
			print -E -B "	VALUE=$VALUE"
		fi
		case "$KEY" in
			"REPO" | "REPOS")
				GIT_REPOS=( ${GIT_REPOS[@]} "$(echo $VALUE | cut -d\| -f1)" )
				GIT_INIT=1
				;;
			"PY_INIT" )
				PY_INIT=$VALUE
				;;
			"PIP_PACKAGE") PIP_PKGS=( ${PIP_PKGS[@]} "$VALUE" ) ;;
				*) [ $DEBUG -eq 1 ] && print -E -Y "Unrecognized Key: $KEY" ;;
		esac
	done < "$INIT_CONFIG"
	[ $GIT_INIT -eq 1 ] && REQUIRED_PKGS=( ${REQUIRED_PKGS[@]} 'git' )
	[ $PY_INIT -eq 1 ] && REQUIRED_PKGS=( ${REQUIRED_PKGS[@]} 'python' 'virtualenv' )
	if [ $PY_INIT -eq 1 ] && [ ${#PIP_PKGS[@]} -gt 0 ]; then
		for pkg in "${PIP_PKGS[@]}"
		do
			if [ -f "$PIP_TXT" ]; then
				cat "$PIP_TXT" | grep -q "$pkg"
				[ $? -ne 0 ] && echo "$pkg" >> "$PIP_TXT"
			else
				echo "$pkg" >> "$PIP_TXT"
			fi
		done
	fi
	return 0
}
generate_config()
{
	if [ -f "$INIT_CONFIG" ];then
		print -E -Y "Detected existing init config: $INIT_CONFIG"
		print -E -Y "Moving to $INIT_CONFIG.$RUN_DATE"
		mv -f "$INIT_CONFIG" "$INIT_CONFIG.$RUN_DATE"
	fi
	touch "$INIT_CONFIG"
	KEYS=( "REPO" "PY_INIT" "PIP_PACKAGE" )
	for k in "${KEYS[@]}"
	do
		INPUT=""
		print -B -S "---------------- $k ----------------"
		echo "" >> "$INIT_CONFIG"
		echo "# ---------------- $k ---------------- #" >> "$INIT_CONFIG"
		case "$k" in
			"REPO")
				echo "# REPO=REPO-URL|REPO-DIR|REPO-INIT" >> "$INIT_CONFIG"
				echo "# REPO-URL: can be git or https, if login is required, you will be prompted during init process." >> "$INIT_CONFIG"
				echo "# REPO-DIR: Destination directory for cloning. default: $WORK_DIR" >> "$INIT_CONFIG"
				echo "# REPO-PIP: Will add the REPO-DIR as a local pip package to be installed. Adds to config by PIP_PACKAGE=$WORK_DIR/REPO-DIR" >> "$INIT_CONFIG"
				while :
				do
					print -Y -n "Set repo-url to clone (Leave blank to continue): "
					read INPUT
					if [[ "$INPUT" != "" ]];then
						repo_url="$INPUT"
						INPUT=""
						print -B -S "---------------- REPO-DIR ----------------"
						repo_dir="$(echo $repo_url | rev | cut -d \/ -f1 | rev)"
						print -Y -n "Set directory to clone repo to (Leave blank for default=$repo_dir): "
						read INPUT
						[[ "$INPUT" != "" ]] && repo_dir="$INPUT"
						INPUT=""
						print -B -S "---------------- REPO-INIT ----------------"
						repo_init=""
						print -Y -n "Set the init command (Ex: init.sh -I) (Leave blank to skip): "
						read INPUT
						[[ "$INPUT" != "" ]] && repo_init="$INPUT"
						INPUT=""
						print -B -S "---------------- REPO-PIP ----------------"
						[ $FORCE_FLAG -eq 1 ] && INPUT="y"
						while :
						do
							case "$INPUT" in
								"N" | "n")
									break
									;;
								"Y" | "y")
									echo "PIP_PACKAGE=$WORK_DIR/$repo_dir" >> "$INIT_CONFIG"
									break
									;;
								*)
									print -Y -n "Is this a pip package that you want installed? (Y/[N]): "
									read -n 1 INPUT
									echo ""
									[[ "$INPUT" == "" ]] && INPUT="n"
									;;
								esac
						done
						echo "$k=$repo_url|$repo_dir|$repo_init" >> "$INIT_CONFIG"
					else
						break
					fi
				done
				;;
			"PY_INIT")
				echo "# set $k=0 to skip creating $PYENV with virtualenv. This is the default." >> "$INIT_CONFIG"
				echo "# set $k=1 to create $PYENV with virtualenv." >> "$INIT_CONFIG"
				[ $FORCE_FLAG -eq 1 ] && INPUT="y"
				while :
				do
					case "$INPUT" in
						"N" | "n")
							echo "$k=0" >> "$INIT_CONFIG"
							break
							;;
						"Y" | "y")
							echo "$k=1" >> "$INIT_CONFIG"
							break
							;;
						*)
							print -Y -n "Initialize a virtualenv with python if $PIP_TXT exists? (Y/N): "
							read -n 1 INPUT
							echo ""
							;;
						esac
				done
				;;
			"PIP_PACKAGE")
				echo "# Optionally specifiy pip packages to install locally with virtualenv." >> "$INIT_CONFIG"
				echo "# If one of the git repos is designated as a pip repo, then it's corresponding PIP_PACKAGE will be added near the same line." >> "$INIT_CONFIG"
				echo "# Examples: " >> "$INIT_CONFIG"
				echo "# PIP_PACKAGE=isort" >> "$INIT_CONFIG"
				echo "# PIP_PACKAGE=requests==1.0" >> "$INIT_CONFIG"
				echo "# PIP_PACKAGE=https://github.com/some_cool_module.git" >> "$INIT_CONFIG"
				echo "# PIP_PACKAGE=/Absolute/path/to/local/package" >> "$INIT_CONFIG"
				while :
				do
					print -Y -n -S "Add a pip package to install (Ex: isort==4.3.4) (Leave blank to skip): "
					read INPUT
					if [[ "$INPUT" != "" ]]; then
						echo "$k=$INPUT" >> "$INIT_CONFIG"
					else
						break
					fi
				done
				;;
		esac
	done
	echo "" >> "INIT_CONFIG"
	echo "# $0 generated config on $RUN_DATE @ $INIT_CONFIG" >> "$INIT_CONFIG"
}
print()
{
	local OPTIND
	if [ "$(uname -s)" == "Darwin" ];then
		Black='\033[0;30m'        # Black
		Red='\033[0;31m'          # Red
		Green='\033[0;32m'        # Green
		Yellow='\033[0;33m'       # Yellow
		Blue='\033[0;34m'         # Blue
		Purple='\033[0;35m'       # Purple
		Cyan='\033[0;36m'         # Cyan
		White='\033[0;37m'        # White
		# Bold
		BBlack='\033[1;30m'       # Black
		BRed='\033[1;31m'         # Red
		BGreen='\033[1;32m'       # Green
		BYellow='\033[1;33m'      # Yellow
		BBlue='\033[1;34m'        # Blue
		BPurple='\033[1;35m'      # Purple
		BCyan='\033[1;36m'        # Cyan
		BWhite='\033[1;37m'       # White
		# Background
		On_Black='\033[40m'       # Black
		On_Red='\033[41m'         # Red
		On_Green='\033[42m'       # Green
		On_Yellow='\033[43m'      # Yellow
		On_Blue='\033[44m'        # Blue
		On_Purple='\033[45m'      # Purple
		On_Cyan='\033[46m'        # Cyan
		On_White='\033[47m'       # White
		NC='\033[m'               # Color Reset
	else
		Black='\e[0;30m'        # Black
		Red='\e[0;31m'          # Red
		Green='\e[0;32m'        # Green
		Yellow='\e[0;33m'       # Yellow
		Blue='\e[0;34m'         # Blue
		Purple='\e[0;35m'       # Purple
		Cyan='\e[0;36m'         # Cyan
		White='\e[0;37m'        # White
		# Bold
		BBlack='\e[1;30m'       # Black
		BRed='\e[1;31m'         # Red
		BGreen='\e[1;32m'       # Green
		BYellow='\e[1;33m'      # Yellow
		BBlue='\e[1;34m'        # Blue
		BPurple='\e[1;35m'      # Purple
		BCyan='\e[1;36m'        # Cyan
		BWhite='\e[1;37m'       # White
		# Background
		On_Black='\e[40m'       # Black
		On_Red='\e[41m'         # Red
		On_Green='\e[42m'       # Green
		On_Yellow='\e[43m'      # Yellow
		On_Blue='\e[44m'        # Blue
		On_Purple='\e[45m'      # Purple
		On_Cyan='\e[46m'        # Cyan
		On_White='\e[47m'       # White
		NC="\e[m"               # Color Reset
	fi
	if which cowsay >&/dev/null; then
		local CS="$(which cowsay)"
	else
		local CS=""
	fi
	if which figlet >&/dev/null; then
		local FIG="$(which figlet)"
	else
		local FIG=""
	fi
	if which printf >&/dev/null; then
		local PRINTF_E=0
	else
		local PRINTF_E=1
	fi
	local DEBUG=0
	local FGND=""
	local BKGN=""
	local BOLD=0
	local NL=1
	local PNL=0
	local STRING=" "
	local STYLE=""
	local POS=0
	local RAINBOW=0
	local RANDOM_COLOR=0
	local ERR_OUT=0
	while getopts "f:b:IcnpFAKRGYBPCWS:vZzE" cprint_opt
	do
		case "$cprint_opt" in
			"f")					# Set foreground/text color.
				case "$OPTARG" in
					"black") [ $BOLD -eq 0 ] && FGND="$Black" || FGDN="$BBlack" ;;
					"red") [ $BOLD -eq 0 ] && FGND="$Red" || FGND="$BRed" ;;
					"green") [ $BOLD -eq 0 ] && FGND="$Green" || FGND="$BGreen" ;;
					"yellow") [ $BOLD -eq 0 ] && FGND="$Yellow" || FGND="$BYellow" ;;
					"blue") [ $BOLD -eq 0 ] && FGND="$Blue" || FGND="$BBlue" ;;
					"purple") [ $BOLD -eq 0 ] && FGND="$Purple" || FGND="$BPurple" ;;
					"cyan") [ $BOLD -eq 0 ] && FGND="$Cyan" || FGND="$BCyan" ;;
					"white") [ $BOLD -eq 0 ] && FGND="$White" || FGND="$BWhite" ;;
					"*") [ $DEBUG -eq 1 ] && (>&2 echo "Unrecognized Arguement: $OPTARG") ;;
				esac
				;;
			"b")					# Set background color.
				case "$OPTARG" in
					"black") BKGN="$On_Black" ;;
					"red") BKGN="$On_Red" ;;
					"green") BKGN="$On_Green" ;;
					"yellow") BKGN="$On_Yellow" ;;
					"blue") BKGN="$On_Blue" ;;
					"purple") BKGN="$On_Purple" ;;
					"cyan") BKGN="$On_Cyan" ;;
					"white") BKGN="$On_White" ;;
					"*") [ $DEBUG -eq 1 ] && (>&2 echo "Unrecognized Arguement: $OPTARG") ;;
				esac
				;;
			"I") BOLD=1 ;;				# Enable bold text.
			"c")
				local WIDTH=0
				local POS=0
				WIDTH=$(tput cols)					# Current screen width
				if [ $WIDTH -le 80 ]; then
					POS=0
				else
					POS=$((( $WIDTH - 80 ) / 2 ))		# Middle of screen based on screen width
				fi
				;;				# Center the text in screen.
			"n") NL=0 ;;	 			# Print with newline.
			"p") ((PNL++)) ;; 			# Prepend with newline.
			"F") [ -f "$FIG" ] && STYLE="$FIG" ;;
			"A") [ -f "$CS" ] && STYLE="$CS" ;;
			"K") [ $BOLD -eq 0 ] && FGND="$Black" ||  FGDN="$BBlack" ;;
			"R") [ $BOLD -eq 0 ] && FGND="$Red" || FGND="$BRed" ;;
			"G") [ $BOLD -eq 0 ] && FGND="$Green" || FGND="$BGreen" ;;
			"Y") [ $BOLD -eq 0 ] && FGND="$Yellow" || FGND="$BYellow" ;;
			"B") [ $BOLD -eq 0 ] && FGND="$Blue" || FGND="$BBlue" ;;
			"P") [ $BOLD -eq 0 ] && FGND="$Purple" || FGND="$BPurple" ;;
			"C") [ $BOLD -eq 0 ] && FGND="$Cyan" || FGND="$BCyan" ;;
			"W") [ $BOLD -eq 0 ] && FGND="$White" || FGND="$BWhite";;
			"S") STRING="$OPTARG" ;;
			"v") DEBUG=1 ;;
			"Z") RANDOM_COLOR=1 ;;
			"z") RAINBOW=1 ;;
			"E") ERR_OUT=1 ;;
			"*") [ $DEBUG -eq 1 ] && (>&2 echo "Unknown Arguement: $opt") ;;
		esac
	done
	if [[ "$STRING" == " " ]];then
		shift "$((OPTIND - 1))"
		STRING="$@"
	fi
	if [ $DEBUG -eq 1 ]; then
		(>&2 echo "FGND: $FGND")
		(>&2 echo "BKGN: $BKGN")
		(>&2 echo "BOLD: $BOLD")
		(>&2 echo "NL: $NL")
		(>&2 echo "PNL: $PNL")
		(>&2 echo "POS: $POS")
		(>&2 echo "STYLE: $STYLE")
		(>&2 echo "RAINBOW: $RAINBOW")
		(>&2 echo "PRINTF_E: $PRINTF_E")
		(>&2 echo "ERR_OUT: $ERR_OUT")
		(>&2 echo "STRING: $STRING")
	fi
	#process_prenl()
	while [ $PNL -ne 0 ]
	do
		if [ $PRINTF_E -eq 0 ];then
			if [ $ERR_OUT -eq 1 ]; then
				(>&2 printf "\n")
			else
				printf "\n"
			fi
		else
			if [ $ERR_OUT -eq 1 ]; then
				(>&2 echo "")
			else
				echo ""
			fi
		fi
		((PNL--))
	done
	#process_string()
	string_proc="$STRING"
	[ $RAINBOW -eq 1 ] || [ $RANDOM_COLOR -eq 1 ] && colors=( "$Red" "$Green" "$Gellow" "$Blue" "$Purple" "$Cyan" )
	if [ $POS -eq 0 ]; then # non-centered strings
		[ ! -z $STYLE ] && string_proc="$($STYLE $string_proc)" # Apply style
		[ ! -z $BKGN ] && string_proc="$BKGN$string_proc" # Apply background color
		if [ $RAINBOW -eq 0 ]; then # rainbow not invoked, so just apply the foreground
			[ $RANDOM_COLOR -eq 1 ] && FGND="${colors[$RANDOM % ${#colors[@]}]}"
			[ ! -z $FGND ] && string_proc="$FGND$string_proc"
		elif [ -z $STYLE ]; then # Rainbow invoked. Only apply rainbow if not styled.
			string_proc_r=""
			words=($string_proc)
			for c in "${words[@]}" # Loop through each word separated by spaces
			do
				FGND="${colors[$RANDOM % ${#colors[@]}]}"
				[ $DEBUG -eq 1 ] && (>&2 echo "Random seed: $RANDOM")
				string_proc_r="$string_proc_r$FGND$c "
			done
			string_proc=$string_proc_r # Assign final result back to string_proc
		fi
		[ ! -z $FGND ] || [ ! -z $BKGN ] && string_proc="$string_proc$NC"	# Append color reset if foreground/background is set.
		if [ $PRINTF_E -eq 0 ]; then # if printf exists
			if [ $ERR_OUT -eq 1 ]; then # print to stderr
				(>&2 printf -- "$string_proc")
			else # print to stdout
				printf -- "$string_proc"
			fi
		else # printf doesn't exist
			[ $DEBUG -eq 1 ] && (>&2 echo "printf not found, reverting to echo.")
			if [ $ERR_OUT -eq 1 ]; then # print to stderr
				(>&2 echo "$string_proc")
			else # print to stdout
				echo "$string_proc"
			fi
		fi
	else # Centered strings
		if [ $PRINTF_E -eq 0 ]; then # if printf exists
			if [ $ERR_OUT -eq 1 ]; then # print to stderr
				(>&2 printf -- "$FGND$BKGN%$POS"s"$NC" "$string_proc")
			else # print to stdout
				printf -- "$FGND$BKGN%$POS"s"$NC" "$string_proc"
			fi
		else # printf doesn't exist
			[ $DEBUG -eq 1 ] && (>&2 "printf not found, reverting to echo.")
			if [ $ERR_OUT -eq 1 ]; then # print to stderr
				(>&2 echo "$FGND""$BKGN""$string_proc""$NC")
			else # print to stdout
				echo "$FGND""$BKGN""$string_proc""$NC"
			fi
		fi
	fi
	#process_nl()
	if [ $PRINTF_E -eq 0 ];then
		if [ $NL -eq 1 ]; then
			if [ $ERR_OUT -eq 1 ]; then
				(>&2 printf "\n")
			else
				printf "\n"
			fi
		fi
	else
		if [ $NL -eq 1 ]; then
			if [ $ERR_OUT -eq 1 ]; then
				(>&2 echo "")
			else
				echo ""
			fi
		fi
	fi
}
check_requirements()
{
	if [ $# -lt 1 ];then
		[ $DEBUG -eq 1 ] && print -E -R "No binary package list to check."
		return 0
	fi
	missing=0
	arr=("$@")
	for p in "${arr[@]}"
	do
		if which "$p"  >&/dev/null; then
			[ $DEBUG -eq 1 ] && print -E -G "Found $p"
		else
			print -E -Y "Missing binary package: $p"
			((missing++))
		fi
	done
	return $missing
}
repo_check()
{
	missing=0
	for url in "${GIT_REPOS[@]}"
	do
		r="$(cat $INIT_CONFIG | grep $url)"
		repo_dir="$(echo $r | cut -d \| -f 2)"
		if [ ! -d "$repo_dir" ]; then
			print -E -R "Missing $repo_dir."
			((missing++))
		else
			print -E -G "Found $repo_dir"
		fi
	done
	if [ $missing -gt 0 ]; then
		print -E -R "Missing $missing directories."
		reply=""
		[ $FORCE_FLAG -eq 1 ] && reply="y"
		while :
		do
			case "$reply" in
				"N" | "n")
					print -Y "Skipping repo init."
					break
					;;
				"Y" | "y")
					print -G "Starting repo init."
					repo_init
					break
					;;
				*)
					print -Y -n "Would you like to setup repos now? (Y/N): "
					read -n 1 reply
					echo ""
					;;
				esac
		done
	fi
}
repo_init()
{
	mkdir -p "$REPO_PKGS_DIR"
	git_succeed=0
	for url in "${GIT_REPOS[@]}"
	do
		r="$(cat $INIT_CONFIG | grep $url)"
		repo_url="$url"
		repo_dir="$(echo $r | cut -d \| -f2)"
		repo_init="$(echo $r | cut -d \| -f3)"
		if [ $DEBUG -eq 1 ];then
			print -E -B "Executing repo init with the following: "
			print -E -B "	repo_url: $repo_url"
			print -E -B "	repo_dir: $repo_dir"
			print -E -B "	repo_init: $repo_init"
		fi
		cd "$REPO_PKGS_DIR"
		[[ "$repo_dir" == "" ]] && repo_dir="$(echo $repo_url | rev | cut -d \/ -f1 | rev)"
		if [ -d "$repo_dir" ]; then
			cd "$REPO_PKGS_DIR/$repo_dir"
			git pull "$QUIET"
			git_succeed=$?
		else
			git clone "$QUIET" --depth 1 "$repo_url" "$repo_dir"
			git_succeed=$?
		fi
		if [ $git_succeed -eq 0 ] && [[ "$repo_init" != "" ]]; then
			cd "$REPO_PKGS_DIR/$repo_dir"
			$repo_init
			[ $? -ne 0 ] && print -E -R "Init command failed. Check output."
		fi
		if [ $git_succeed -ne 0 ] && [[ "$repo_init" != "" ]]; then
			print -E -R "Git clone/pull failed. Skipping init command: $repo_init"
		fi
		if [ $git_succeed -ne 0 ] && [[ "$repo_init" == "" ]]; then
			print -E -R "Git clone/pull failed."
		fi
	done
	cd "$WORK_DIR"
}
repo_reset()
{
	mkdir -p "$REPO_PKGS_DIR"
	cd "$REPO_PKGS_DIR"
	for url in "${GIT_REPOS[@]}"
	do
		r="$(cat $INIT_CONFIG | grep $url)"
		repo_dir="$(echo $r | cut -d \| -f2)"
		if [ $DEBUG -eq 1 ];then
			print -E -B "Executing repo reset with the following:"
			print -E -B "	repo_dir: $repo_dir"
		fi
		if [ -d "$REPO_PKGS_DIR/$repo_dir" ]; then
			rm -rf "$VERBOSE" -- "$REPO_PKGS_DIR/$repo_dir"
		else
			[ $DEBUG -eq 1 ] && print -E -B "Missing $REPO_PKGS_DIR/$repo_dir"
		fi
	done
}
python_check()
{
	cd "$WORK_DIR"
	missing=0
	if [ ! -d "$PYENV" ]; then
		print -E -R "$PYENV not found."
		((missing++))
	fi
	if [ ! -f "$PYENV/updated" ] || [ "$PIP_TXT" -nt "$PYENV/updated" ]; then
		print -E -R "Virtual Environment pacakges need to be installed/updated."
		((missing++))
	fi
	if [ $missing -gt 0 ]; then
		print -E -R "Missing $missing directories."
		reply=""
		[ $FORCE_FLAG -eq 1 ] && reply="y"
		while :
		do
			case "$reply" in
				"N" | "n")
					print -Y "Skipping python init."
					break
					;;
				"Y" | "y")
					print -G "Starting python init."
					python_init
					break
					;;
				*)
					print -Y -n "Would you like to setup python now? (Y/N): "
					read -n 1 reply
					echo ""
					;;
				esac
			done
	fi
	cd "$WORK_DIR"
}
python_init()
{
	if [ ! -d "$PYENV" ]; then
		virtualenv "$QUIET" "$PYENV"
	fi
	if [ ! -f "$PYENV/updated" ] ||  [ "$PIP_TXT" -nt "$PYENV/updated" ]; then
		"$PYENV/bin/pip" "$QUIET" install -r "$PIP_TXT"
		if [ $? -eq 0 ]; then
			touch "$PYENV/updated"
			print -E -G "Python requirements installed."
		else
			print -E -R "Python requirements not installed."
			exit 1
		fi
		PY_ACTIVATE="$PYENV/bin/activate"
		print -E -G "Manually Activate python virtual environment: source $PY_ACTIVATE"
		print -E -G "Or overrride python binary by adding the following alias to your environment:"
		print -E -G "alias python=\'$PYENV/bin/python\'"
	fi
}
python_reset()
{
	rm -rf "$VERBOSE" "$PYENV"
	find "$WORK_DIR" -type f -iname "*.pyc" -exec rm -f "$VERBOSE" {} \;
}
usage()
{
	echo ""
	echo "	Usage for $0:"
	echo "		-h: Show this dialog."
	echo "		-I: Begin intialization."
	echo "		-R: Reset setup. Remove repos and python setup."
	echo "		-C: Check setup."
	echo "		-G: Generate repo configuration file @ $INIT_CONFIG"
	echo "		-F: Force=\"Y\" for all questions."
	echo "		-D: Enabled debugging."
	echo ""
}
#### Project Specific Functions ####
init()
{
	# Add custom init commands here.
	[ $GIT_INIT -eq 1 ] && repo_init
	[ $PY_INIT -eq 1 ] && python_init
}
reset()
{
	# Add custom reset commands here.
	[ $GIT_INIT -eq 1 ] && repo_reset
	[ $PY_INIT -eq 1 ] && python_reset
}
check()
{
	# Add custom check commands here.
	[ $GIT_INIT -eq 1 ] && repo_check
	[ $PY_INIT -eq 1 ] && python_check
}
failure_exit()
{
	print -E -R "$0: Detected fatal issue. Exiting."
}
success_exit()
{
	print -E -G "$0: Exiting with no errors."
}
#### Main Run ####
if [ $# -lt 1 ]; then
	print -E -R "Missing arguments."
	usage
else
	INIT_FLAG=0
	RESET_FLAG=0
	CHECK_FLAG=0
	GENERATE_FLAG=0
	while getopts "hIRCGFD" opt
	do
		case "$opt" in
			"h") usage ;;
			"I") INIT_FLAG=1 ;;
			"R") RESET_FLAG=1 ;;
			"C") CHECK_FLAG=1 ;;
			"G") GENERATE_FLAG=1 ;;
			"F") FORCE_FLAG=1 ;;
			"D")
				DEBUG=1
				VERBOSE="-v"
				QUIET="$VERBOSE"
				;;
			"*") print -E -Y "Unrecognized arguments: $opt" ;;
		esac
	done
	[ $GENERATE_FLAG -eq 1 ] && generate_config
	load_config
	check_requirements "${REQUIRED_PKGS[@]}"
	[ $? -gt 0 ] && print -E -R "Missing $? required binary package(s)." && exit 1
	check_requirements "${OPTIONAL_PKGS[@]}"
	[ $? -gt 0 ] && [ $DEBUG -eq 1 ] && print -E -Y "Missing $? optional binary package(s)."
	[ $INIT_FLAG -eq 1 ] && init
	[ $RESET_FLAG -eq 1 ] && reset
	[ $CHECK_FLAG -eq 1 ] && check
fi
exit 0
