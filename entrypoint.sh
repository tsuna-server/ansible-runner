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
# An option to run "ansible -m ping"
RUNNER="${RUNNER:-ansible-playbook}"

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
    [ "$#" -eq 1 ] && [ "update-requirements-txt" = "$1" ] && {
        update_requirements_txt || {
            log_err "Failed to update requirements.txt due to previous error."
            return 1
        }
        return 0
    }

    [[ -z "$ANSIBLE_DIRECTORY_PATH" ]] && {
        log_err "A variable ANSIBLE_DIRECTORY_PATH must not be empty."
        return 1
    }
    [[ -z "$REQUIREMENTS_TXT_PATH" ]] && {
        log_err "A variable REQUIREMENTS_TXT_PATH must not be empty."
        return 1
    }
    if [[ ! "${RUNNER}" == "ansible-playbook" ]] && [[ ! "${RUNNER}" == "ansible" ]]; then
        log_err "Unknown runner was detected[RUNNER=${RUNNER}]. The variable \"RUNNER\" should be \"ansible-playbook(by default)\" or \"ansible\"."
        return 1
    fi
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

    $RUNNER $@
}

update_requirements_txt() {
    log_notice "Updating requirements.txt in \"${ANSIBLE_DIRECTORY_PATH}\" on the container."

    cd "${ANSIBLE_DIRECTORY_PATH}" || {
        log_err "An Ansible directory \"${ANSIBLE_DIRECTORY_PATH}\" was not existed."
        return 1
    }

    [ ! -d requirements.txt ] || {
        log_err "requirements.txt was not existed in a directory \"${ANSIBLE_DIRECTORY_PATH}\"."
        return 1
    }

    rm -rf venv/
    python -m venv venv/ || {
        log_err "Failed to create python virtual env at \"${ANSIBLE_DIRECTORY_PATH}/venv/\""
        return 1
    }

    source venv/bin/activate
    pip install --upgrade pip || {
        log_err "Failed to upgrade pip by the command \"pip install --upgrade pip\"."
        return 1
    }

    pip install pip-upgrader || {
        log_err "Failed to install pip-upgrader by the command \"pip install pip-upgrader\"."
        return 1
    }

    pip-upgrade requirements.txt || {
        log_err "Failed to upgrade requirements.txt by the command \"pip-upgrade requirements.txt\"."
        return 1
    }

    log_notice "Succeeded in updating requirements.txt in \"${ANSIBLE_DIRECTORY_PATH}\" on the container."
    return 0
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

    if [[ -f "$REQUIREMENTS_YML_PATH" ]] && [[ ! -z "$REQUIREMENTS_YML_PATH" ]];then
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
    if [ -d /root/.ssh ]; then
        log_notice "/root/.ssh directory is already existed. Then skipping to prepare ssh keys."
        return
    elif [ -d /.ssh ]; then
        log_notice "/.ssh directory is existed. Then copying it to /root/.ssh"
        cp -a /.ssh /root/.ssh
    elif [ -f "/private-key" ]; then
        log_notice "/private-key file is existed. Then creating /root/.ssh directory and copying the private key file to it."
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
    [ ! -d "${PYTHON_VIRTUALENV_DIRECTORY_PATH}" ] && return 1

    # If version of python were difference, return the result as not prepared.
    local current_python_version="$(python --version | cut -d ' ' -f 2)"
    local venv_python_version="$(grep -P '^version *= *' ${PYTHON_VIRTUALENV_DIRECTORY_PATH}/pyvenv.cfg | sed -e 's/^version *= *\(.*\)/\1/g')"
    [ ! "$current_python_version" = "$venv_python_version" ] && {
        echo "Versions are not same[current_python_version=${current_python_version}, venv_python_version=${venv_python_version}]"
        rm -rf "${PYTHON_VIRTUALENV_DIRECTORY_PATH}"
        return 1
    }

    source "${PYTHON_VIRTUALENV_DIRECTORY_PATH}/bin/activate" || {
        # Delete venv directory and return flase if activation has failed.
        rm -rf "$PYTHON_VIRTUALENV_DIRECTORY_PATH"
        return 1
    }

    local result_of_which_python expected_parent_path
    result_of_which_python="$(which python)" || {
        # Activation has succeeded but command was not found.
        deactivate
        rm -rf "$PYTHON_VIRTUALENV_DIRECTORY_PATH"
        return 1
    }

    return 0
}

main "$@"

