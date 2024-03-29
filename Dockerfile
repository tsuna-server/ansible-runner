#FROM ubuntu:22.04
FROM python:3.11.5-bullseye
LABEL maintainer "Tsutomu Nakamura<tsuna.0x00@gmail.com>"

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3-venv ssh sshpass && \
        apt-get clean

COPY entrypoint.sh /opt/entrypoint.sh

RUN chmod 755 /opt/entrypoint.sh

ENTRYPOINT ["/opt/entrypoint.sh"]

