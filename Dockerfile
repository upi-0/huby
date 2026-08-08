FROM debian:stable

RUN apt update && apt upgrade && \
    apt install build-essential -y

RUN apt install -y \ 
    libpq5 \
    git \
    curl \
    python3 \
    python3-pip \
    python3.13-venv

RUN curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y
RUN curl -LsSf https://hf.co/cli/install.sh | bash -s -- --force

ENV PATH="/root/.nimble/bin:${PATH}"

RUN nimble install -y \
    prologue \
    hmac \
    norm \
    uuids

WORKDIR /app
COPY . .    

RUN nim c -d:release /app/src/hf_b.nim
CMD ["/app/build/hf_b"]
