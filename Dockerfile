FROM --platform=linux/amd64 node:alpine3.23 AS deps

WORKDIR /opt/test-runner
COPY package.json ./
RUN npm install --omit=dev \
    && find node_modules -name '*.map' -delete \
    && find node_modules \( -name '*.d.ts' -o -name 'README*' -o -name 'CHANGELOG*' -o -name 'LICENSE*' -o -name '*.md' \) -delete

FROM --platform=linux/amd64 alpine:3.23

RUN apk add --no-cache bash nodejs jq

WORKDIR /opt/test-runner
COPY --from=deps /opt/test-runner/node_modules ./node_modules
COPY . .

ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
