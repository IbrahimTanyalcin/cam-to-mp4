#!/bin/bash

shopt -s extglob
progName="${0}"
scriptFolder="$( dirname ${BASH_SOURCE[0]} )"
scriptName="$( basename ${BASH_SOURCE[0]} )"
#available arguments
avArgs=(
    -m --mv --move 
    -c --merge --combine 
    -n --num --number 
    -e --ext --extension 
    --hex 
    --dryRun 
    -p --pat --pattern 
    --progress --prog 
    --noinfo 
    -q --quiet
)
args=("$@")
optStr="?([[:space:]])?(-)-*?([[:space:]])"
logRED='\033[0;31m'
logGREEN='\033[0;32m' 
logBLUE='\033[0;34m'
logCYAN='\033[0;36m' 
logNEUT='\033[0m'
clearLINE='\033[K'

declare trgtFolder
declare mvFolder
declare mergeFileName
declare -i maxProcessed
declare extension
declare hex
declare dryRun
declare -i nFiles
declare pattern
declare noProgress=1
declare noInfo
declare quiet

helpStr="$(sed 's/^\s*//' <<EOL 
    > ˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅˅
    > 03-2023 - Ibrahim Tanyalcin - MIT LICENSE
    > version 0.0.1
    > -m --mv --move      : Move the generated .mp4 files to specified folder. If merge
    >                       option is given, also move the generated .mkv file to there
    > -c --merge --combine: Concat the resulting .mp4 files to a single .mkv file
    > -n --num --number   : Max amount of directories to be processed
    > -e --ext --extension: Extension of input files. Defaults to "media"
    > --hex               : If input files names are not unix epoch, append a random
    >                       hex string to differentiate
    > --dryRun            : Do not do anything, just preview
    > -p --pat --pattern  : A pattern to filter folder basename. Only folders with
    >                       basename matching the pattern are processed.
    > --progress --prog   : Show progress bar
    > --noinfo            : Do not show info on what is being done
    > -q --quiet          : Suppress "ffmpeg" and "mkvmerge" messages/warnings
    > ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
EOL
)"

function includes() {
    local haystack="${@:1: $#-1}"
    local needle="${@: -1}"
    #if [[ " ${haystack[*]} "  =~ " ${needle} " ]];
    if [[ " ${haystack[*]} " == $needle ]];
    then
        return 0
    fi
    return 1
}

#https://stackoverflow.com/questions/1527049/how-can-i-join-elements-of-a-bash-array-into-a-delimited-string#answer-17841619
function join_by {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

function dateOrSelf() {
    if [[ "$1" == [1-9]+([0-9]) ]];
    then
        echo "$(date -d @${1%%_*} "+%Y%m%d-%H%M%S")"
    else
        echo "$1${hex:+_$(hexdump -vn16 -e'4/4 "%08X" 1 "\n"' /dev/urandom)}"
    fi
}

function progress() {
    if [[ -n $noProgress ]];
    then
        return 1
    fi
    frac=$((${3:=20}*$1/$2))
    done=$(($frac > $3 ? $3 : $frac < 0 ? 0 : $frac))
    remaining=$((${3:-20}-"${done}"))
    left=$(seq -s█ "$done"|tr -d '[:digit:]')
    right=$(seq -s░ "$remaining"|tr -d '[:digit:]')
    echo -en "${logGREEN}${4:-progress: }${left}${right}${logNEUT}"
}

function issueWarning() {
    printf "${logRED}---::WARNING::---\n$1\n---::---${logNEUT}\n" ${@: 2};
}

function issueInfo() {
    if [[ -z $noInfo ]];
    then
        printf "${logCYAN}---::INFO: ""$1 ""::---${logNEUT}\n" ${@: 2};
    fi
}

function depsOK() {
    if ! hash 2>/dev/null ffmpeg || ! hash 2>/dev/null mkvmerge;
    then
        issueWarning "$(
            join_by $'\n' \
            "Looks like the dependencies are not installed" \
            "You need %s and %s." \
            "Do 'sudo snap install ffmpeg' or " \
            "'sudo apt install ffmpeg' and" \
            "'sudo apt install mkvtoolnix'" 
        )" "ffmpeg" "mkvmerge"
        exit 1;
    fi
}

#if [[ "$*" == ?(*[[:space:]])?(-)-help?([[:space:]]*) ]]
if includes "$*" *+(--help|-h)*;
then
    echo "${helpStr}";
    exit 1;
fi

depsOK;

for (( i=0; i<"${#args[@]}"; ++i ))
do
    case "${args[$i],,}" in
        -e|--ext|--extension)
            (( ++i ))
            if includes "${args[$i]}" $optStr;
            then
                issueWarning "$(
                    join_by $'\n' \
                    "-e|--ext|--extension arguments expects a value." \
                    "For example: .media"
                )"
                exit 1;
            fi
            extension="${args[$i]}"
        ;;
        -n|--num|--number)
            (( ++i ))
            if includes "${args[$i]}" $optStr;
            then
                issueWarning "$(
                    join_by $'\n' \
                    "-n|--num|--number arguments expects an integer value." \
                    "For example: 1000"
                )"
                exit 1;
            fi
            maxProcessed="${args[$i]}"
        ;;
        -m|--move|--mv)
            (( ++i ))
            if includes "${args[$i]}" $optStr;
            then
                issueWarning "$(
                    join_by $'\n' \
                    "-m|--mv|--move arguments expects a folder name." \
                    "For example: someFolderName"
                )"
                exit 1;
            fi
            mvFolder="${args[$i]}"
        ;;
        -c|--combine|--merge)
            (( ++i ))
            if includes "${args[$i]}" $optStr;
            then
                issueWarning "$(
                    join_by $'\n' \
                    "-c|--merge|--combine arguments expects a file name" \
                    "without extension." \
                    "For example: someFileName"
                )"
                exit 1;
            fi
            mergeFileName="${args[$i]}"
        ;;
        -p|--pat|--pattern)
            (( ++i ))
            if includes "${args[$i]}" $optStr;
            then
                issueWarning "$(
                    join_by $'\n' \
                    "-p|--pat|--pattern arguments expects a quoted pattern." \
                    "For example: \"some*folder\""
                )"
                exit 1;
            fi
            pattern="${args[$i]}"
        ;;
        --hex)
            hex=1
        ;;
        --dryrun)
            dryRun=1
        ;;
        -q|--quiet)
            quiet=1
        ;;
        --noinfo)
            noInfo=1
        ;;
        --prog|--progress)
            noProgress=
        ;;
        !(--*|-*))
            trgtFolder="${args[$i]}"
        ;;
        ?(-)-*)
            issueWarning "UNKNOWN OPTION %s" ${args[$i]}
            echo "${helpStr}";
            exit 1;
        ;;
    esac
done

issueInfo "CD %s" "${trgtFolder}"
#do not do [[ -z "$dryRun" ]] &&, report if the folder does not exist
cd "${trgtFolder}" || issueWarning "%s does not seem to exist" "${trgtFolder}";
j=0;
k=$(find . -maxdepth 1 -mindepth 1 ! -name '.*' -type d | wc -l)
for d in */; do
    echo -en "\r${clearLINE}"
    if [[ -n "$pattern" && "${d%/*}" != $pattern ]];
    then
        issueInfo "IGNORING: %s" "${trgtFolder}/$d"
        continue
    fi
    issueInfo "PROCESSING: %s" "${trgtFolder}/$d"
    if [[ -n "$dryRun" ]];
    then
        continue
    fi
    progress "$j" "$k" 40
    while IFS= read -r line; do
        echo -en "\r${clearLINE}"
        [[ -z "$quiet" ]] && echo "$line"
    done <<< "$(
        ffmpeg \
        -y \
        -safe 0 \
        -f concat \
        -i <(find "${trgtFolder}/$d/" -type f -name "*.${extension:=media}" -printf "file '%p'\n" | sort) \
        -c copy \
        -crf 18 \
        "${trgtFolder}/$d/$(dateOrSelf "$(sed -e 's/\(\/.*$\|_.*$\)//g' <(echo "$d"))").mp4" \
        $([[ -n "$quiet" ]] && echo "-nostats -loglevel 0" || echo "") \
        2>&1 
    )";
    ((++j));
    if [[ "$j" -ge "${maxProcessed:=$(((2**32)))}" ]]; then
        issueWarning "MAX (%s) DIRECTIORIES REACHED" "${maxProcessed}"
        break;
    fi
done

[[ -z "$dryRun" ]] && nFiles=$(find . -type f -name "*.mp4" | wc -l)
if [[ nFiles -le 0 ]];
then
    issueInfo "NO FILES PROCESSED"
    [[ -z "$dryRun" ]] && exit
fi

#no ${mvFolder+x}, no empty string allowed
if ! [[ -z "$mvFolder" ]];
then
    mvFolder="$trgtFolder/${mvFolder##*/}"
    issueInfo "MOVING FILES TO %s" "$mvFolder"
    if [[ -z "$dryRun" ]];
    then
        mkdir -p "$mvFolder"
        find . -type f -name "*.mp4" -print0 | xargs -0 -I {} mv {} "$mvFolder"
    fi
else
    mvFolder="$trgtFolder"
fi

if ! [[ -z "$mergeFileName" ]];
then 
    issueInfo "MERGING FILES into %s.mkv" "${mvFolder}/${mergeFileName}"
    if [[ -z "$dryRun" ]];
    then
        mkvmerge -o "${mvFolder}/${mergeFileName}.mkv" \
        $(find "$mvFolder" -type f -name "*.mp4" ! -size 0 -printf "%p\n" | sort | sed ':a;N;$!ba;s/\n/ \+ /g') \
        $([[ -n "$quiet" ]] && echo "-q" || echo "")
    fi
fi
