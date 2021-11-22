#!/usr/bin/env bash

ANSIBLE_DIRECTORY="/opt/ansible"
PYTHON_VIRTUALENV_DIRECTORY=".venv"

PYTHON_VIRTUALENV_PATH="${ANSIBLE_DIRECTORY}/${PYTHON_VIRTUALENV_DIRECTORY}"

REQUIREMENTS_TXT_PATH="${ANSIBLE_DIRECTORY}/requirements.txt"
REQUIREMENTS_TXT_HASH_PATH="${PYTHON_VIRTUALENV_PATH}/.requirements.txt.hash"

REQUIREMENTS_YML_PATH="${ANSIBLE_DIRECTORY}/requirements.yml"
REQUIREMENTS_YML_HASH_PATH="${PYTHON_VIRTUALENV_PATH}/.requirements.yml.hash"

log_err() {
    echo "ERROR: $1" >&2
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

    cd "$ANSIBLE_DIRECTORY" || {
        log_err "Failed to change directory to $ANSIBLE_DIRECTORY"
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

    #${ANSIBLE_DIRECTORY}/${PYTHON_VIRTUALENV_DIRECTORY}/bin/ansible-playbook --user ubuntu -i "$inventry_file" -l "$target" site.yml
    ${ANSIBLE_DIRECTORY}/${PYTHON_VIRTUALENV_DIRECTORY}/bin/ansible-playbook $@
}

create_ansible_environment() {
    # .gitignore in venv directory will also be usedas a flag file
    # whether Ansible environment has already been prepared or not.
    local prepared_flag_file="${ANSIBLE_DIRECTORY}/${PYTHON_VIRTUALENV_DIRECTORY}/.gitignore"

    # Create symbolic link to cache packages of ansible-galaxy
    ln -s "${ANSIBLE_DIRECTORY}/.ansible" ~/.ansible
    # venv directory has already been prepared?
    venv_has_already_prepared || {
        python3 -m "$PYTHON_VIRTUALENV_DIRECTORY" "${PYTHON_VIRTUALENV_DIRECTORY}/" || {
            log_err "Failed to install python virtual env in $ANSIBLE_DIRECTORY"
            return 1
        }
        ${ANSIBLE_DIRECTORY}/${PYTHON_VIRTUALENV_DIRECTORY}/bin/pip install --upgrade pip
    }

    pip_packages_has_already_up_to_date || {
        ${ANSIBLE_DIRECTORY}/${PYTHON_VIRTUALENV_DIRECTORY}/bin/pip install -r requirements.txt
    }

    ansible_galaxy_packages_has_already_up_to_date || {
        ${ANSIBLE_DIRECTORY}/${PYTHON_VIRTUALENV_DIRECTORY}/bin/ansible-galaxy install -r requirements.yml
    }

    # Create .gitignore under venv directory not to commit.
    [ ! -f "$prepared_flag_file" ] && echo "/*" > "$prepared_flag_file"

    return 0
}

prepare_ssh_key() {
    mkdir ~/.ssh

    [[ ! -f "/private-key" ]] && {
        log_err "private-key file does not existed"
        return 1
    }

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

    chmod 700 ~/.ssh
    chmod -R 600 ~/.ssh/*
}

venv_has_already_prepared() {
    [ ! -f "${PYTHON_VIRTUALENV_DIRECTORY}" ] && return 1
    return 0
}

pip_packages_has_already_up_to_date() {
    _packages_has_already_up_to_date "$REQUIREMENTS_TXT_PATH" "$REQUIREMENTS_TXT_HASH_PATH"
}
ansible_galaxy_packages_has_already_up_to_date() {
    _packages_has_already_up_to_date "$REQUIREMENTS_YML_PATH" "$REQUIREMENTS_YML_HASH_PATH"
}

_packages_has_already_up_to_date() {
    local package_file_path="$1"
    local hash_file_path="$2"

    [ ! -f "${package_file_path}" ] && return 0
    [ ! -f "${hash_file_path}" ] && return 1

    local old_hash current_hash
    read old_hash < "${hash_file_path}"
    read current_hash _ <<< "$(sha256sum ${package_file_path})"

    [ ! "$old_hash" == "$current_hash" ] && return 1

    return 0
}

main "$@"

