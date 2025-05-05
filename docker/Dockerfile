FROM us-docker.pkg.dev/oplabs-tools-artifacts/images/op-geth:v1.101503.4

# Install jq
RUN apk add --no-cache jq

# Copy deployment artifacts from local directory
COPY . /deployment

# Print confirmation message
RUN echo "Successfully copied deployment artifacts to /deployment"
