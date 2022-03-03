#!/usr/bin/env bash

# A directory that an Ansible playbooks are located in.
ANSIBLE_DIRECTORY_PATH="${ANSIBLE_DIRECTORY_PATH:-/opt/ansible}"

# A directory path that python venv will be installed.
# It will be created under ANSIBLE_DIRECTORY_PATH if you specify relative path.
PYTHON_VIRTUALENV_DIRECTORY_PATH="${PYTHON_VIRTUALENV_DIRECTORY_PATH:-venv}"

# A path of requirements.txt which information of requirement packages of python are in.
REQUIREMENTS_TXT_PATH="${REQUIREMENTS_TXT_PATH:-requirements.txt}"
# A path of requirements.yml which information of requirement packages of ansible galaxy are in.
REQUIREMENTS_YML_PATH="${REQUIREMENTS_YML_PATH:-requirements.yml}"

FONT_COLOR_RED='\033[0;31m'
FONT_COLOR_GREEN='\033[0;32m'
FONT_COLOR_END='\033[0m'

log_err() {
    echo -e "${FONT_COLOR_RED}ERROR${FONT_COLOR_END}: $1" >&2
}
log_notice() {
    echo -e "${FONT_COLOR_GREEN}NOTICE${FONT_COLOR_END}: $1"
}

main() {
    local inventry_file="$1"
    local target="$2"

    [[ -z "$inventry_file" ]] && {
        log_err "This program requires inventry file."
        return 1
    }
    [[ -z "$target" ]] && {
        log_err "This program requires target host."
        return 1
    }

    [[ -z "$ANSIBLE_DIRECTORY_PATH" ]] && {
        log_err "A variable ANSIBLE_DIRECTORY_PATH must not be empty."
        return 1
    }
    [[ -z "$REQUIREMENTS_TXT_PATH" ]] && {
        log_err "A variable REQUIREMENTS_TXT_PATH must not be empty."
        return 1
    }
    cd "$ANSIBLE_DIRECTORY_PATH" || {
        log_err "Failed to change directory to $ANSIBLE_DIRECTORY_PATH"
        return 1
    }

    activate_python_virtual_env || {
        log_err "Failed to activate python venv"
        return 1
    }

    create_ansible_environment || {
        log_err "Failed to create Ansible environment"
        return 1
    }

    prepare_ssh_key || {
        log_err "Failed to prepare ssh-keys to authenticate"
        return 1
    }

    ansible-playbook $@
}

activate_python_virtual_env() {
    # venv directory has already been prepared?
    if ! venv_has_already_prepared; then
        python3 -m "$PYTHON_VIRTUALENV_DIRECTORY_PATH" "${PYTHON_VIRTUALENV_DIRECTORY_PATH}/" || {
            log_err "Failed to install python virtual env in $ANSIBLE_DIRECTORY_PATH"
            return 1
        }
        source ${PYTHON_VIRTUALENV_DIRECTORY_PATH}/bin/activate
        pip install --upgrade pip
    else
        source ${PYTHON_VIRTUALENV_DIRECTORY_PATH}/bin/activate
    fi
    return 0
}

create_ansible_environment() {
    # Create symbolic link to cache packages of ansible-galaxy
    ln -s "${ANSIBLE_DIRECTORY_PATH}/.ansible" ~/.ansible

    if [[ ! -z "$REQUIREMENTS_TXT_PATH" ]]; then
        pip install -r "${REQUIREMENTS_TXT_PATH}" || {
            log_err "Failed to install requirements with a command \"pip install -r ${REQUIREMENTS_TXT_PATH}\"."
            return 1
        }
    else
        log_notice "A variable REQUIREMENTS_TXT_PATH is empty. Then installing dependencies of python has skipped."
    fi

    if [[ ! -z "$REQUIREMENTS_YML_PATH" ]];then
        ansible-galaxy install -r "${REQUIREMENTS_YML_PATH}" || {
            log_err "Failed to install requirements with a command \"ansible-galaxy install -r \"${REQUIREMENTS_YML_PATH}\"."
            return 1
        }
    else
        log_notice "A variable REQUIREMENTS_TXT_PATH is empty. Then installing dependencies of python has skipped."
    fi

    return 0
}

prepare_ssh_key() {
    # Copy .ssh directory if /.ssh directory is already existed.
    if [ -d /.ssh ]; then
        cp -a /.ssh /root/.ssh
    elif [ -f "/private-key" ]; then
        mkdir ~/.ssh
        cp /private-key ~/.ssh/private-key || {
            log_err "Failed to copy /private-key to user's ssh config directory"
            return 1
        }

        cat << EOF > ~/.ssh/config
Host *
    ServerAliveInterval 120
    PreferredAuthentications publickey,password,gssapi-with-mic,hostbased,keyboard-interactive
    User root
    IdentityFile ~/.ssh/private-key
EOF
    else
        # There are no private keys 
        return
    fi

    chown -R root:root ~/.ssh
    chmod 700 ~/.ssh
    chmod -R 600 ~/.ssh/*
}

venv_has_already_prepared() {
    [ ! -d "${PYTHON_VIRTUALENV_DIRECTORY}" ] && return 1

    source "${PYTHON_VIRTUALENV_DIRECTORY}/bin/activate" || {
        # Delete venv directory and return flase if activation has failed.
        rm -rf "$PYTHON_VIRTUALENV_DIRECTORY"
        return 1
    }

    local result expected_parent_path
    result="$(which python)" || {
        deactivate
        rm -rf "$PYTHON_VIRTUALENV_DIRECTORY"
        return 1
    }
    result="$(readlink $(dirname "$result"))"
    expected_parent_path=$(readlink "${ANSIBLE_DIRECTORY_PATH}")

    [[ "$result" == "${expected_parent_path%/}/"* ]] || {
        # Clear venv if it was created at other location.
        deactivate
        rm -rf "$PYTHON_VIRTUALENV_DIRECTORY"
        return 1
    }

    return 0
}

main "$@"

