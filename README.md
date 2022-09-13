# ansible-runner
`ansible-runner` is a runner to run Ansible conveniently on the docker container.
`ansible-runner` requires you to prepare ansible-playbook directory and it should be mounted on `/opt/ansible` in the container.

# Run examples
Here are some examples to run `ansible-runner`.
These examples require you to prepare `ansible-playbook` directory that follows [Best Practices](https://docs.ansible.com/ansible/2.9/user_guide/playbooks_best_practices.html) of ansible-playbook on the host node.

# Build

```
docker build -t tsutomu/tsuna-ansible-runner .
```

## Run Ansible simply

```
$ docker run --rm \
    --add-host target-host01:192.168.0.11 \
    --volume /path/to/ansible-playbook:/opt/ansible \
    -ti tsutomu/ansible-runner -u operator -l production -i target-host01 -k site.yml
```
It assumes that the `/path/to/ansible-playbook` on the host is a root of the ansible-playbook that follows the [Directory Layout](https://docs.ansible.com/ansible/2.9/user_guide/playbooks_best_practices.html#directory-layout).
Arguments of `-u operator -l production -i target-host01 -k site.yml` will be passed to the command `ansible-playbook` in the container.
This command will ask you a password of the user `operator` in order to login the host `target-host01`.
You can abbreviate a user in the arguments if you already declared it in the inventory file `production`.

## Run Ansible by providing a single ssh private key
```
$ docker run --rm \
    --add-host target-host01:192.168.0.11 \
    --add-host target-host02:192.168.0.12 \
    --volume ${PWD}:/opt/ansible \
    --volume /path/to/ssh-private-key.pem:/private-key \
    -ti tsutomu/ansible-runner -u operator -l production -i target-host01:target-host02 site.yml
```
This command will use `/path/to/ssh-private-key.pem` to login to hosts `target-host01` and `target-host02`.
You should mount a file of private key to the file `/private-key` on the container.

## Run Ansible with mounting .ssh directory
```
$ docker run --rm \
    --add-host target-host01:192.168.0.11 \
    --add-host target-host02:192.168.0.12 \
    --volume ${PWD}:/opt/ansible \
    --volume /path/to/.ssh:/.ssh \
    -ti tsutomu/ansible-runner -u operator -l production -i target-host01:target-host02 site.yml
```
This command will use ssh private-keys and configurations in a directory `/path/to/.ssh` on the host.
You can control detailed which private-keys should be used to each hosts to connect by declaring configurations in `.ssh/config`.

