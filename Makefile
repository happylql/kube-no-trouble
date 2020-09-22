.SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
.SECONDEXPANSION:
.DELETE_ON_ERROR:
.EXPORT_ALL_VARIABLES:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

ifeq (, $(shell command -v gtar))
	TAR ?= tar
endif
TAR ?= gtar

ifneq (3.82,$(firstword $(sort $(MAKE_VERSION) 3.82)))
  $(error This Make does not support .ONESHELL, use GNU Make 3.82 and newer)
endif

.DEFAULT_GOAL :=help

GITHUB_REF ?= dev
GIT_REF ?= $(shell echo "$(GITHUB_REF)" | sed "s,refs/[^/]*/,," | tr -cd '[:alnum:]._')
GITHUB_SHA ?= dev
GIT_SHA ?= $(GITHUB_SHA)

CGO_ENABLED ?= 0
GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)

GENERATE_DIR ?= generated
BIN_DIR ?= bin
CMD_DIR ?= cmd
RELEASE_DIR ?= release-artifacts
PACKED_DIR ?= $(BIN_DIR)/packed
CMDS ?= $(shell ls $(CMD_DIR))
BINS ?= $(addsuffix -$(GOOS)-$(GOARCH),$(addprefix $(BIN_DIR)/,$(CMDS)))

BIN_ARCH ?= $(GOOS)-$(GOARCH)
RELEASE_SUFFIX ?= $(GIT_REF)-$(BIN_ARCH).tar.gz
PACKED_BINS ?= $(addsuffix -$(BIN_ARCH),$(addprefix $(PACKED_DIR)/,$(CMDS)))
RELEASE_ARTIFACTS ?= $(addsuffix -$(RELEASE_SUFFIX),$(addprefix $(RELEASE_DIR)/,$(CMDS)))
SRC ?= $(shell find . -iname '*.go')

GOCMD ?= go
GOBUILD ?= $(GOCMD) build
GOGENERATE ?= $(GOCMD) generate
UPXCMD ?= upx

REQ_BINS = upx go opa

_ := $(foreach exec,$(REQ_BINS), \
       $(if $(shell which $(exec)),some string,$(error "No $(exec) binary in $$PATH")))


## Clean, build and pack
all: build pack release-artifacts
.PHONY: all

## Prints list of tasks
help:
	@awk 'BEGIN {FS=":"} /^## .*/,/^[a-zA-Z0-9_-]+:/ { if ($$0 ~ /^## /) { desc=substr($$0, 4) } else { printf "\033[36m%-30s\033[0m %s\n", $$1, desc } }' Makefile | sort
.PHONY: help

## Build binary
build: $(BINS)
.PHONY: build

$(BIN_DIR)/%-$(BIN_ARCH): generated/* $(SRC)
	mkdir -p $(BIN_DIR)
	$(GOBUILD) -ldflags="-s -w -X main.version=$(GIT_REF) -X main.gitSha=$(GIT_SHA)" \
	-o "$@" \
	"./$(CMD_DIR)/$(*)"

## Go generate
generate: generated/*
	mkdir -p $(GENERATE_DIR)
.PHONY: generate

generated/*: rules/*
	$(GOGENERATE)
	go fmt "./generated/..."

## Pack binaries with upx
pack: $(PACKED_BINS)
.PHONY: pack

$(PACKED_DIR)/%-$(BIN_ARCH): $(BIN_DIR)/%-$(BIN_ARCH)
	mkdir -p $(PACKED_DIR)
	$(UPXCMD) --brute -f -o "$@" "$<" \
	&& touch "$@"

## Create release artifacts
release-artifacts: $(RELEASE_ARTIFACTS)
.PHONY: release-artifacts

$(RELEASE_DIR)/%-$(RELEASE_SUFFIX): $(PACKED_DIR)/%-$(BIN_ARCH)
	mkdir -p $(RELEASE_DIR)
	$(TAR) -cvz --transform 's,$(PACKED_DIR)/$(*)-$(BIN_ARCH),$(*),gi' -f "$@" "$<"

## Run Go tests
test: generate test-fmt
	go test -v ./...
.PHONY: test

## Run go and opt fmt checks
test-fmt: generate
	test -z "$$(opa fmt -l rules/*)"
	test -z "$$(go fmt ./...)"
.PHONY: test-fmt

## Clean build artifacts
clean:
	rm -rf $(GENERATE_DIR)
	rm -rf $(BIN_DIR)
.PHONY: clean
