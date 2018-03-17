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
OPTIONAL_PKGS=( )
GIT_REPOS=( )
PY_INIT=0
GIT_INIT=0
PYENV_NAME="pyenv"
PYENV="$WORK_DIR/$PYENV_NAME"
PIP_TXT="$WORK_DIR/requirements.txt"
INIT_CONFIG="$WORK_DIR/init.ini"
RUN_DATE=$(date +%Y-%d-%m-%H-%M-%S)
#### Functions ####
load_config()
{
	if [ ! -f "$INIT_CONFIG" ];then
		print -R "Missing init config: $INIT_CONFIG"
		return 0
	fi
	while read CONF_LINE
	do
		[[ "${CONF_LINE:0:1}" == "#" ]] || [[ "${CONF_LINE:0:1}" == ";" ]] && continue
		value_count=$(echo $CONF_LINE | tr -dc '=' | wc -l)
		KEY=""
		VALUE=""
		index=0
		while [ $index -lt $value_count ]
		do
			case $index in
				0) KEY="$(echo $CONF_LINE | cut -d= -f$index)" ;;
				*)
					if [[ "$VALUE" == "" ]]; then
						VALUE="$(echo $CONF_LINE | cut -d= -f$index)"
					else
						VALUE="$VALUE=$(echo $CONF_LINE | cut -d= -f$index)"
					fi
					;;
				esac
				((index++))
		done
		case "$KEY" in
			"REPO" | "REPOS")
				GIT_REPOS=( ${GIT_REPOS[@]} "$VALUE" )
				GIT_INIT=1
				REQUIRED_PKGS=( ${REQUIRED_PKGS[@]} 'git' )
				;;
			"PY_INIT" )
				PY_INIT=$VALUE
				REQUIRED_PKGS=( ${REQUIRED_PKGS[@]} 'python' 'virtualenv' )
				;;
				*) echo "Unrecognized Key: $KEY" ;;
		esac
	done < "$INIT_CONFIG"
}
generate_config()
{
	if [ -f "$INIT_CONFIG" ];then
		print -Y "Detected existing init config: $INIT_CONFIG"
		print -Y "Moving to $INIT_CONFIG.$RUN_DATE"
		mv -f "$INIT_CONFIG" "$INIT_CONFIG.$RUN_DATE"
	fi
	touch "$INIT_CONFIG"
	KEYS=(
	"REPO"
	"PY_INIT"
	)
	for k in "${KEYS[@]}"
	do
		INPUT=""
		print -B -S "---------------- $k ----------------"
		case "$k" in
			"REPO")
				while :
				do
					print -Y -n "Set repo-url to clone (Leave blank to continue): "
					read INPUT
					if [[ "$INPUT" != "" ]];then
						repo_url="$INPUT"
						print -B -S "---------------- REPO-DIR ----------------"
						repo_dir="$(echo $INPUT | rev | cut -d \/ -f1 | rev)"
						print -Y -n "Set directory to clone repo to (Leave blank for default=$repo_dir): "
						read INPUT
						[[ "$INPUT" != "" ]] && repo_dir="$INPUT"
						print -B -S "---------------- REPO-INIT ----------------"
						repo_init=""
						print -Y -n "Set the init command (Ex: init.sh -I) (Leave blank to skip): "
						read INPUT
						[[ "$INPUT" != "" ]] && repo_init="$INPUT"
						echo "$k=$repo_url|$repo_dir|$repo_init" >> "$INIT_CONFIG"
					else
						break
					fi
				done
				;;
			"PY_INIT")
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
		esac
	done
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
	local ERR_OUT=0
	while getopts "f:b:IcnpFAKRGYBPCWvS:" cprint_opt
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
			"v") DEBUG=1 ;;
			"S") STRING="$OPTARG" ;;
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
	[ ! -z $STYLE ] && string_proc="$($STYLE $string_proc)"
	if [ $POS -eq 0 ]; then
		[ ! -z $BKGN ] && string_proc="$BKGN$string_proc"
		if [ $RAINBOW -eq 1 ]; then
			string_proc_r=""
			words=($string_proc)
			for c in "${words[@]}"
			do
				#random_color()
				colors=( "$Red" "$Green" "$Gellow" "$Blue" "$Purple" "$Cyan" )
				FGND="${colors[$RANDOM % ${#colors[@]}]}"
				[ $DEBUG -eq 1 ] && (>&2 echo "Random seed: $RANDOM")
				string_proc_r="$string_proc_r$FGND$c "
			done
			string_proc=$string_proc_r
		else
			[ ! -z $FGND ] && string_proc="$FGND$string_proc"
		fi
		[ ! -z $FGND ] || [ ! -z $BKGN ] && string_proc="$string_proc$NC"	# Append color reset if foreground/background is set.
		if [ $PRINTF_E -eq 0 ]; then
			if [ $ERR_OUT -eq 1 ]; then
				(>&2 printf -- "$string_proc")
			else
				printf -- "$string_proc"
			fi
		else
			[ $DEBUG -eq 1 ] && (>&2 echo "printf not found, reverting to echo.")
			if [ $ERR_OUT -eq 1 ]; then
				(>&2 echo "$string_proc")
			else
				echo "$string_proc"
			fi
		fi
	else
		if [ $PRINTF_E -eq 0 ]; then
			if [ $ERR_OUT -eq 1 ]; then
				(>&2 printf -- "$FGND$BKGN%$POS"s"$NC" "$string_proc")
			else
				printf -- "$FGND$BKGN%$POS"s"$NC" "$string_proc"
			fi
		else
			[ $DEBUG -eq 1 ] && (>&2 "printf not found, reverting to echo.")
			if [ $ERR_OUT -eq 1 ]; then
				(>&2 echo "$FGND""$BKGN""$string_proc""$NC")
			else
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
		[ $DEBUG -eq 1 ] && print -R "No binary package list to check."
		return 0
	fi
	missing=0
	arr=("$@")
	for p in "${arr[@]}"
	do
		if which "$p"  >&/dev/null; then
			[ $DEBUG -eq 1 ] && print -G "Found $p"
		else
			print -Y "Missing binary package: $p"
			((missing++))
		fi
	done
	return $missing
}
repo_chek()
{
	missing=0
	for r in "${GIT_REPOS[@]}"
		do
			repo_dir="$(echo $r | cut -d \| -f 2)"
			if [ ! -d "$repo_dir" ]; then
				print -R "Missing $repo_dir."
				((missing++))
			fi
		done
		if [ $missing -gt 0 ]; then
			print -R "Missing $missing directories."
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
	cd "$WORK_DIR"
	git_succeed=0
	for r in "${GIT_REPOS[@]}"
	do
		repo_url="$(echo $r | cut -d \| -f1)"
		repo_dir="$(echo $r | cut -d \| -f2)"
		repo_init="$(echo $r | cut -d \| -f3)"
		if [ $DEBUG -eq 1 ];then
			print -B "Executing repo init with the following: "
			print -B "repo_url: $repo_url"
			print -B "repo_dir: $repo_dir"
			print -B "repo_init: $repo_init"
		fi
		[[ "$repo_dir" == "" ]] && repo_dir="$(echo $repo_url | rev | cut -d \/ -f1 | rev)"
		if [ -d "$repo_dir" ]; then
			cd "$WORK_DIR/$repo_dir"
			git pull "$QUIET"
			git_succeed=$?
		else
			git clone "$QUIET" --depth 1 "$repo_url" "$repo_dir"
			git_succeed=$?
		fi
		if [ $git_succeed -eq 0 ];then
			if [[ "$repo_init" != "" ]];then
				cd "$WORK_DIR/$repo_dir/"
				$repo_init
			fi
			[ $? -ne 0 ] && print -R "Init command reported failure. Check output."
		else
			print -R "Git clone/pull failed. Skipping init command: $repo_init"
		fi
	done
}
python_check()
{
	missing=0
	if [ ! -d "$PYENV" ]; then
		print -R "$PYENV not found."
		((missing++))
	fi
	if [ ! -f "$PYENV/updated" ] || [ "$PIP_TXT" -nt "$PYENV/updated" ]; then
		print -R "Virtual Environment pacakges need to be installed/updated."
		((missing++))
	fi
	if [ $missing -gt 0 ]; then
		print -R "Missing $missing directories."
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
}
python_init()
{
	cd "$WORK_DIR"
	if [ ! -d "$PYENV" ]; then
		virtualenv "$QUIET" "$PYENV_NAME"
	fi
	if [ ! -f "$PYENV/updated" ] ||  [ "$PIP_TXT" -nt "$PYENV/updated" ]; then
		"$PYENV/bin/pip" "$QUIET" install -r "$PIP_TXT"
		if [ $? -eq 0 ]; then
			touch "$PYENV/updated"
			print -G "Requirements installed."
		else
			print -R "Requirements not installed."
			exit 1
		fi
		PY_PATH="$WORK_DIR/$PYENV_NAME/bin/python"
		if [ ! -d "$WORK_DIR/backups" ]; then
			mkdir -p "$WORK_DIR/backups"
		fi
		ls "$WORK_DIR" | while read line
		do
			if [ -f "$WORK_DIR/$line" ]; then
				if [[ "$(head -1 "$WORK_DIR/$line")" == "#!/usr/bin/python" ]]; then
					print -Y "Detected python file, modifiying shebang to $PY_PATH"
					WC=$(cat $WORK_DIR/$line | wc -l | sed -e "s/^\ *//g")
					sed -i.$RUN_DATE.$WC "1s|.*|\#\!$PY_PATH|g" "$WORK_DIR/$line"
					print -Y "Storing backup to $WORK_DIR/backups/$line.$RUN_DATE.$WC"
					mv -f "$WORK_DIR/$line.$RUN_DATE.$WC" "$WORK_DIR/backups/"
					chmod +x "$WORK_DIR/$line"
				fi
			fi
		done
	fi
}
repo_reset()
{
	for r in "${GIT_REPOS[@]}"
	do
		repo_dir="$(echo $r | cut -d \| -f2)"
		if [ $DEBUG -eq 1 ];then
			print -B "Executing repo reset with the following:"
			print -B "repo_dir: $repo_dir"
		fi
		if [ -d "$WORK_DIR/$repo_dir" ]; then
			rm -rf "$VERBOSE" -- "$WORK_DIR/$repo_dir"
		else
			[ $DEBUG -eq 1 ] && print -B "Missing $WORK_DIR/$repo_dir"
		fi
	done
}
python_reset()
{
	if [ -d "$PYENV" ]; then
		rm -rf "$VERBOSE" -- "$PYENV"
	fi
	if [ -d "$WORK_DIR/backups" ];then
		ls "$WORK_DIR/backups" | while read line
		do
			OWC="$(echo $line | rev | cut -d . -f1 | rev)"
			FDATE="$(echo $line | rev | cut -d . -f2 | rev)"
			OFN="${line/.$OWC/}"
			OFN="${OFN/.$FDATE/}"
			[ $DEBUG -eq 1 ] && echo "$WORK_DIR/backups/$line line count = $OWC. Old file name: $OFN"
			if [ ! -f $WORK_DIR/$OFN ]; then
				print -R "$WORK_DIR/$OFN is missing! Restoring from backups."
				WC=$OWC
			else
				WC=$(cat $WORK_DIR/$OFN | wc -l | sed -e "s/^\ *//g")
				[ $DEBUG -eq 1 ] && print -B "$WORK_DIR/$OFN found. Line count = $WC."
			fi
			if [ $OWC -ne $WC ]; then
				print -Y "$WORK_DIR/$OFN has been modified. Retaining backups."
				diff "$WORK_DIR/$OFN" "$WORK_DIR/backups/$line"
			else
				[ $DEBUG -eq 1 ] && print -B "Line count for $line ($OWC) equals line count for $OFN ($WC)"
				cp -f "$WORK_DIR/backups/$line" "$WORK_DIR/$OFN"
			fi
		done
	fi
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
	[ $DEBUG -eq 1 ] && print -B "Place custom init procedures here."
	[ $GIT_INIT -eq 1 ] && repo_init
	[ $PY_INIT -eq 1 ] && python_init
}
reset()
{
	[ $DEBUG -eq 1 ] && print -B "Place custom reset procedures here."
	[ $GIT_INIT -eq 1 ] && repo_reset
	[ $PY_INIT -eq 1 ] && python_reset
}
check()
{
	[ $DEBUG -eq 1 ] && print -B "Place custom check procedures here."
	[ $GIT_INIT -eq 1 ] && repo_check
	[ $PY_INIT -eq 1 ] && python_check
}
failure_exit()
{
	print -R "Detected fatal issue. Exiting."
}
success_exit()
{
	print -G "Exiting with no errors."
}
#### Main Run ####
if [ $# -lt 1 ]; then
	print -R "Missing arguments."
	usage
else
	load_config
	check_requirements "${REQUIRED_PKGS[@]}"
	if [ $? -gt 0 ];then
		print -R "Missing $? required binary package(s)."
		exit 1
	fi
	check_requirements "${OPTIONAL_PKGS[@]}"
	if [ $? -gt 0 ]; then
		print -Y "Missing $? optional binary package(s). Will Skip setup procedures which require them."
	fi
	while getopts "hIRCGFD" opt
	do
		case "$opt" in
			"h") usage ;;
			"I") init ;;
			"R") reset ;;
			"C") check ;;
			"G") generate_config ;;
			"F") FORCE_FLAG=1 ;;
			"D")
				DEBUG=1
				VERBOSE="-v"
				QUIET="$VERBOSE"
				;;
			"*")
				print -Y "Unrecognized arguments: $opt"
				;;
		esac
	done
fi
exit 0
