FROM node:lts-alpine@sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd AS builder

WORKDIR /opt/test-runner

COPY package.json package-lock.json ./

RUN npm ci --omit=dev \
    && find node_modules -name '*.map' -delete \
    && find node_modules \( -name '*.d.ts' -o -name 'README*' -o -name 'CHANGELOG*' -o -name 'LICENSE*' -o -name '*.md' \) -delete \
    # Remove legacy tooling
    && rm node_modules/@rescript/linux-*/bin/rescript-editor-analysis.exe \
          node_modules/@rescript/linux-*/bin/rescript-tools.exe \
          node_modules/@rescript/linux-*/bin/rescript-legacy.exe \
          node_modules/@rescript/linux-*/bin/bsb_helper.exe \
          node_modules/@rescript/linux-*/bin/ninja.exe \
    # Keep .cmi/.cmj files for compiler.
    && find node_modules/@rescript/runtime -type f \( -name '*.cmt' -o -name '*.cmti' \) -delete

FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS runner

RUN apk add --no-cache bash nodejs jq

WORKDIR /opt/test-runner
COPY --from=builder /opt/test-runner/node_modules ./node_modules
COPY bin/run.sh ./bin/run.sh

ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
