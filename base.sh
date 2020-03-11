#!/usr/bin/env bash

error_exit()    { printf '%s\n' "$@" >&2; exit 1; }
exit_if_error() { local ec=$1; shift; (($ec)) && error_exit "$@"; }
cd_base()       { cd -- "$BASE_HOME" || exit_if_error 1 "Can't cd to BASE_HOME at '$BASE_HOME'"; }

show_common_help() {
    cat << EOF
Usage: base [-b DIR] [-t TEAM] [-x] [install|embrace|update|run|status|help] ...
-b DIR  - use DIR as BASE_HOME directory
-t TEAM - use TEAM as BASE_TEAM
-x      - turn on bash debug mode

install - install Base
embrace - override .bash_profile and .bashrc so that Base gets enabled upon login
update  - update Base by running 'git pull' in BASE_HOME directory
run     - run the rest of the command line after initializing Base
status  - check if Base is installed or not
help    - show this help message

When invoked without any arguments, base gives you an interactive bash shell with Base initialized.
EOF
}

base_init() {
    local base_init=$BASE_HOME/base_init.sh
    [[ -f $base_init ]] && source "$base_init"
}

get_base_home() {
    # if BASE_HOME is not already set, source .baserc to see it is defined there
    if [[ ! $BASE_HOME ]]; then
        local baserc=$HOME/.baserc
        [[ -f $baserc ]] && source "$baserc"
    fi

    # if BASE_HOME is still not set, go with the default value
    BASE_HOME=${BASE_HOME:-$HOME/base}
}

create_base_home() {
    # if set, BASE_HOME must hold a directory name
    if [[ -e $BASE_HOME && ! -d $BASE_HOME ]]; then
        error_exit "$BASE_HOME exists but it is not a directory!"
    else
        mkdir -- "$BASE_HOME"
        exit_if_error $? "Can't create directory '$BASE_HOME'"
    fi
}

verify_base() {
    # now make sure BASE_HOME directory is actually a git repo
    local git=$BASE_HOME/.git
    if [[ ! -d $git ]]; then
        glb_error_message="Directory '$BASE_HOME' isn't a git repo"
        return 1
    else
        local oldpwd=$PWD
        cd -- "$git" || { glb_error_message="Can't cd to '$git' directory"; return 1; }
        if ! git rev-parse --git-dir &>/dev/null; then
            glb_error_message="Directory '$git' isn't a git repo"
            return 1
        fi
        local file missing
        for file in base_init.sh lib/bash_profile lib/bashrc; do
            if [[ ! -f $BASE_HOME/$file ]]; then
                missing+=($file)
            fi
        done
        cd -- "$oldpwd"
        if (( ${#missing[@]} > 0)); then
            glb_error_message="Files missing in base repo: ${missing[@]}"
            return 1
        fi
    fi
    return 0
}

do_install() {
    local repo="git@github.com:codeforester/base.git"
    if [[ -d $BASE_HOME ]]; then
        printf '%s\n' "base is already installed at '$BASE_HOME'"
    else
        git clone "$repo" "$BASE_HOME"
        exit_if_error $? "Couldn't install base"
        printf '%s\n' "Installed base at '$BASE_HOME'"
        #
        # patch .baserc
        # This is how we remember custom BASE_HOME path and BASE_TEAM values.
        # The user is free to put custom code into the .baserc file.
        # A marker is appended to the lines managed by base CLI
        #
        local baserc=$HOME/.baserc
        local baserc_temp=$HOME/.baserc.temp
        local marker="# BASE_MARKER, do not delete"
        if [[ ! -f $baserc ]]; then
            touch -- "$baserc"
            exit_if_error $? "Couldn't create '$baserc'"
        else
            local base_text_array=("export BASE_HOME=$BASE_HOME $marker"
                                   "export BASE_TEAM=$BASE_TEam $marker")
            local base_text
            printf -v base_text '%s\n' "${base_text_array[@]}"
            cat <(grep -v -- "$marker" "$baserc") - <<< "base_text" > "$baserc_temp"
            exit_if_error $? "Couldn't create '$baserc_temp'"
            mv -f -- "$baserc_temp" "$baserc"
            exit_if_error $? "Couldn't overwrite '$baserc'"
        fi
    fi
    exit 0
}

do_embrace() {
    if ! verify_base; then
        error_exit "$glb_error_message"
    fi
    local base_bash_profile=$BASE_HOME/lib/bash_profile
    local base_bashrc=$BASE_HOME/lib/bashrc
    local bash_profile=$HOME/.bash_profile
    local bashrc=$HOME/.bashrc
    if [[ -L $bash_profile ]]; then
        local bash_profile_link=$(readlink "$bash_profile")
    fi
    if [[ -L $bashrc ]]; then
        local bashrc_link=$(readlink "$bashrc")
    fi
    local current_time
    printf -v current_time '%(%Y-%m-%d:%H:%M:%S)T' -1
    if [[ $bash_profile_link = $base_bash_profile ]]; then
        printf '%s\n' "$bash_profile is already symlinked to $base_bash_profile"
    else
        local bash_profile_backup=$HOME/.bash_profile.$current_time
        printf '%s\n' "Backing up $bash_profile to $bash_profile_backup and overriding it with $base_bash_profile"
        if cp -- "$bash_profile" "$bash_profile_backup"; then
            ln -sf -- "$base_bash_profile" "$bash_profile"
        else
            exit_if_error $? "ERROR: can't create a backup of $bash_profile"
        fi
    fi
    if [[ $bashrc_link = $base_bashrc ]]; then
        printf '%s\n' "$bashrc is already symlinked to $base_bashrc"
    else
        local bashrc_backup=$HOME/.bashrc.$current_time
        printf '%s\n' "Backing up $bashrc to $bashrc_backup and overriding it with $base_bashrc"
        if cp -- "$bashrc" "$bashrc_backup"; then
            ln -sf -- "$base_bashrc" "$bashrc"
        else
            exit_if_error $? "ERROR: can't create a backup of $bashrc"
        fi
    fi
}

do_update() {
    if [[ -d $BASE_HOME ]]; then
        cd -- "$BASE_HOME" || error_exit "Can't cd to BASE_HOME at '$BASE_HOME'"
        git pull
    else
        printf '%s\n' "ERROR: base is not installed at BASE_HOME '$BASE_HOME'"
        exit 1
    fi
}

do_run() {
    base_init
    "$@"
}

do_status() {
    if [[ ! -d $BASE_HOME ]]; then
        printf '%s\n' "base is not installed at '$BASE_HOME'"
        exit 1
    fi

    if ! verify_base; then
        error_exit "$glb_error_message"
    else
        printf '%s\n' "base is installed at $BASE_HOME"
    fi
    exit 0
}

do_shell() {
    export BASE_SHELL=1
    exec bash --rcfile "$BASE_HOME/lib/bash_profile"
}

main() {
    if [[ $1 =~ -h|--help|-help|help ]]; then
        show_common_help
        exit 0
    fi

    while getopts "hb:t:x" opt; do
        case $opt in
        b) export BASE_HOME=$OPTARG
           ;;
        t) export BASE_TEAM=$OPTARG
           ;;
        x) set -x
           ;;
        *) show_common_help >&2
           exit 2
           ;;
        esac
    done
    shift $((OPTIND-1))
    command=$1
    shift 2>/dev/null
    get_base_home
    case $command in
    install)
        do_install
        ;;
    update)
        do_update
        ;;
    embrace)
        do_embrace
        ;;
    run)
        do_run "$@"
        ;;
    status)
        do_status
        ;;
    help)
        show_common_help
        ;;
    "")
        do_shell
        ;;
    *)
        printf '%s\n' "Unrecognized command: $command" >&2
        show_common_help >&2
        exit 2
        ;;
    esac
}

main "$@"
