FROM us-docker.pkg.dev/oplabs-tools-artifacts/images/op-geth:v1.101503.4

RUN apk add --no-cache jq openssl && \
    wget -O foundry.tar.gz https://github.com/foundry-rs/foundry/releases/download/v1.1.0/foundry_v1.1.0_alpine_amd64.tar.gz && \
    mkdir -p /usr/local/bin && \
    tar -xzf foundry.tar.gz -C /usr/local/bin && \
    chmod +x /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil && \
    rm foundry.tar.gz

RUN mkdir -p /artifacts /init /peers /scripts /execution

COPY ./artifacts/* /artifacts/
COPY ./scripts/* /scripts/

RUN chmod +x /scripts/init.sh

ENTRYPOINT ["/scripts/init.sh"]
