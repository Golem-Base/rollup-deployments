FROM us-docker.pkg.dev/oplabs-tools-artifacts/images/op-geth:v1.101503.4

RUN apk add --no-cache jq

RUN mkdir -p /artifacts /init /peers /scripts /execution

COPY ./artifacts/* /artifacts/
COPY ./scripts/* /scripts/

RUN chmod +x /scripts/init.sh

ENTRYPOINT ["/scripts/init.sh"]
