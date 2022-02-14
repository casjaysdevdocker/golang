FROM casjaysdev/alpine:latest as build

RUN apk update
# set up nsswitch.conf for Go's "netgo" implementation
# - https://github.com/golang/go/blob/go1.9.1/src/net/conf.go#L194-L275
# - docker run --rm debian:stretch grep '^hosts:' /etc/nsswitch.conf

ENV GOPATH /go
ENV PATH /usr/local/go/bin:$PATH
ENV GOLANG_VERSION 1.17.6
ENV SHA256SUM 4dc1bbf3ff61f0c1ff2b19355e6d88151a70126268a47c761477686ef94748c8
ENV GOLANG_SRC_URL https://dl.google.com/go/go$GOLANG_VERSION.src.tar.gz

RUN set -eux; \
  apk add --no-cache --virtual .fetch-deps gnupg git; \
  arch="$(apk --print-arch)"; \
  url=; \
  case "$arch" in \
  'x86_64') \
  export GOARCH='amd64' GOOS='linux'; \
  ;; \
  'armhf') \
  export GOARCH='arm' GOARM='6' GOOS='linux'; \
  ;; \
  'armv7') \
  export GOARCH='arm' GOARM='7' GOOS='linux'; \
  ;; \
  'aarch64') \
  export GOARCH='arm64' GOOS='linux'; \
  ;; \
  'x86') \
  export GO386='softfloat' GOARCH='386' GOOS='linux'; \
  ;; \
  'ppc64le') \
  export GOARCH='ppc64le' GOOS='linux'; \
  ;; \
  's390x') \
  export GOARCH='s390x' GOOS='linux'; \
  ;; \
  *) echo >&2 "error: unsupported architecture '$arch' (likely packaging update needed)"; exit 1 ;; \
  esac; \
  build=; \
  if [ -z "$url" ]; then \
  # https://github.com/golang/go/issues/38536#issuecomment-616897960
  build=1; \
  url="$GOLANG_SRC_URL"; \
  sha256="$SHA256SUM"; \
  # the precompiled binaries published by Go upstream are not compatible with Alpine, so we always build from source here 😅
  fi; \
  \
  wget -O go.tgz.asc "$url.asc"; \
  wget -O go.tgz "$url"; \
  echo "$sha256 *go.tgz" | sha256sum -c -; \
  \
  # https://github.com/golang/go/issues/14739#issuecomment-324767697
  GNUPGHOME="$(mktemp -d)"; export GNUPGHOME; \
  # https://www.google.com/linuxrepositories/
  gpg --batch --keyserver keyserver.ubuntu.com --recv-keys 'EB4C 1BFD 4F04 2F6D DDCC  EC91 7721 F63B D38B 4796'; \
  # let's also fetch the specific subkey of that key explicitly that we expect "go.tgz.asc" to be signed by, just to make sure we definitely have it
  gpg --batch --keyserver keyserver.ubuntu.com --recv-keys '2F52 8D36 D67B 69ED F998  D857 78BD 6547 3CB3 BD13'; \
  gpg --batch --verify go.tgz.asc go.tgz; \
  gpgconf --kill all; \
  rm -rf "$GNUPGHOME" go.tgz.asc; \
  \
  tar -C /usr/local -xzf go.tgz; \
  rm go.tgz; \
  \
  if [ -n "$build" ]; then \
  apk add --no-cache --virtual .build-deps gcc go musl-dev \
  ; \
  \
  ( \
  cd /usr/local/go/src; \
  # set GOROOT_BOOTSTRAP + GOHOST* such that we can build Go successfully
  export GOROOT_BOOTSTRAP="$(go env GOROOT)" GOHOSTOS="$GOOS" GOHOSTARCH="$GOARCH"; \
  ./make.bash; \
  ); \
  \
  apk del --no-network .build-deps; \
  \
  # pre-compile the standard library, just like the official binary release tarballs do
  go install std; \
  # remove a few intermediate / bootstrapping files the official binary release tarballs do not contain
  rm -rf \
  /usr/local/go/pkg/*/cmd \
  /usr/local/go/pkg/bootstrap \
  /usr/local/go/pkg/obj \
  /usr/local/go/pkg/tool/*/api \
  /usr/local/go/pkg/tool/*/go_bootstrap \
  /usr/local/go/src/cmd/dist/dist \
  ; \
  fi; \
  \
  apk del --no-network .fetch-deps; \
  \
  go version

ENV GOPATH /app
RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

FROM build
ARG BUILD_DATE="$(date +'%Y-%m-%d %H:%M')" 

LABEL \
  org.label-schema.name="golang" \
  org.label-schema.description="container to build go packages" \
  org.label-schema.url="https://github.com/casjaysdev/golang" \
  org.label-schema.vcs-url="https://github.com/casjaysdev/golang" \
  org.label-schema.build-date=$BUILD_DATE \
  org.label-schema.version=$BUILD_DATE \
  org.label-schema.vcs-ref=$BUILD_DATE \
  org.label-schema.license="MIT" \
  org.label-schema.vcs-type="Git" \
  org.label-schema.schema-version="1.0" \
  org.label-schema.vendor="CasjaysDev" \
  maintainer="CasjaysDev <docker-admin@casjaysdev.com>" 

ENV GOPATH /app
ENV PATH $GOPATH/bin:$PATH
WORKDIR $GOPATH

HEALTHCHECK CMD [ "/usr/local/bin/entrypoint-golang.sh", "healthcheck" ]
ENTRYPOINT [ "/usr/local/bin/entrypoint-golang.sh" ]
CMD [ "/bin/bash", "-l" ]
