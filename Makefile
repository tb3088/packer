SELF 	    := $(lastword $(MAKEFILE_LIST))

TEST	    ?= $(shell go list ./... | grep -v vendor)
VET 	    ?= $(shell ls -d */ | grep -v vendor | grep -v website)
# Get the current local branch name from git (if we can, this may be blank)
GITBRANCH := $(shell git symbolic-ref --short HEAD 2>/dev/null)
GOOS	    = $(shell go env GOOS)
GOARCH	    = $(shell go env GOARCH)
GOPATH	    = $(shell go env GOPATH)

GOFMT_FILES ?= $(shell find . -path ./vendor -prune -type f -name '*.go' | grep -v ./vendor)
GOFMT_START = 1
GOFMT_CHUNK = 100

# Get the git commit
GIT_DIRTY   = $(shell test -n "`git status --porcelain`" && echo "+CHANGES" || true)
#GIT_SHA:=$(shell git rev-parse HEAD)
GIT_COMMIT  = $(shell git rev-parse --short HEAD)
GIT_IMPORT  = github.com/hashicorp/packer/version
export GOLDFLAGS = -X $(GIT_IMPORT).GitCommit=$(GIT_COMMIT)$(GIT_DIRTY)

VERSION	    ?= $(shell awk '/^const Version / { print $NF; }' version/version.go)
VERSIONPRE  := $(shell awk '/^const VersionPrerelease/ { print $N4; }' version/version.go)


default: deps generate test dev

ci: deps test

release: deps test releasebin package ## Build a release build

.PHONY: bin dev
bin dev: deps ## Build debug/test binary
	@echo "NOTICE: '$@' is for debug / test builds only. Otherwise use 'make release'"
	$(if $(VERSIONPRE), , echo >&2 "WARN: 'VersionPrerelease' in version/version.go should be defined")
	@$(MAKE) -f $(SELF) --no-print-directory _bin

.PHONY: release releasebin
release releasebin: deps ## Build release binary
	$(if $(VERSIONPRE), echo >&2 "ERROR: 'VersionPrerelease' in version/version.go must be blank"; exit 1)
	@$(MAKE) -f $(SELF) --no-print-directory _bin

.PHONY: _bin
_bin:
	go get github.com/mitchellh/gox
	$(CURDIR)/scripts/build.sh

.PHONY: package
package: pkg/$(GOOS)_$(GOARCH)/packer ## Create dist archive (.zip)
	$(if $(VERSION), , @echo >&2 "ERROR: \$VERSION needed to release"; exit 1)
	$(CURDIR)/scripts/dist.sh $(VERSION)

deps:
	@go get golang.org/x/tools/cmd/stringer
	@go get -u github.com/mna/pigeon
	@go get github.com/kardianos/govendor
	@govendor sync
	@touch $@

.PHONY: fmt
.ONESHELL:
fmt: ## Reformat Go code
	if [ -n "$@" ]; then
		gofmt -w -s $@
	else
		@$(eval _files := $(wordlist $(GOFMT_START), $(shell expr $(GOFMT_START) + $(GOFMT_CHUNK)), $(GOFMT_FILES)))
		if [ -n "$(_files)" ]; then
			gofmt -w -s $(_files)
			$(MAKE) -f $(SELF) --no-print-directory -s GOFMT_START=$(shell expr $(GOFMT_START) + 100) $@
		fi
	fi

.PHONY: fmt-check
.ONESHELL:
fmt-check: ## Check Go code formatting
	@echo -n "==> Checking that code complies with gofmt requirements ... "
	$(eval UNFORMATTED_FILES := $(shell $(MAKE) --no-print-directory -s fmt-check-loop))
	@if [ $(words $(UNFORMATTED_FILES)) -eq 0 ]; then
		echo "passed"
	else
		echo -e "failed\nRun \`make fmt\` to reformat the following files:"
		$(foreach item, $(UNFORMATTED_FILES), echo '  '$(item); )
		exit 1
	fi

.PHONY: fmt-check-loop
.ONESHELL:
fmt-check-loop:
	$(eval _files := $(wordlist $(GOFMT_START), $(shell expr $(GOFMT_START) + $(GOFMT_CHUNK)), $(GOFMT_FILES)))
	@if [ -n "$(_files)" ]; then
		gofmt -l -s $(_files)
		$(MAKE) GOFMT_START=$(shell expr $(GOFMT_START) + 100) $@
	fi

fmt-docs: ## Format Markdown files with PanDoc
	@go get github.com/gogap/go-pandoc
	@find ./website/source/docs -name "*.md" -exec pandoc --wrap auto --columns 79 --atx-headers -s -f "markdown_github+yaml_metadata_block" -t "markdown_github+yaml_metadata_block" {} -o {} \;

fmt-examples: ## Apply JS-Beautify to JSON files
	@which js-beautify &>/dev/null || npm install -g js-beautify
	@find examples -name *.json | xargs js-beautify -r -s 2 -n -eol "\n"

# generate runs `go generate` to build the dynamically generated
# source files.
.ONESHELL:
generate: deps ## Generate dynamically generated code
	@go get golang.org/x/tools/cmd/goimports
	go generate .
	gofmt -w common/bootcommand/boot_command.go
	goimports -w common/bootcommand/boot_command.go
	gofmt -w command/plugin.go
	touch $@

.ONESHELL:
test: deps fmt-check ## Run unit tests
	@go test $(TEST) $(TESTARGS) -timeout=2m
	@go tool vet $(VET) || { \
		echo "ERROR: Vet found problems in the code."; \
		exit 1; \
	}

testacc: deps generate ## Run acceptance tests
	@echo "WARN: Acceptance tests will take a long time to run and may cost money. Ctrl-C if you want to cancel."
	PACKER_ACC=1 go test -v $(TEST) $(TESTARGS) -timeout=45m

testrace: deps ## Test for race conditions
	@go test -race $(TEST) $(TESTARGS) -timeout=2m

.PHONY: updatedeps
updatedeps:
	@echo "INFO: Packer deps are managed by govendor. See .github/CONTRIBUTING.md"
	govendor sync
	@touch deps

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "%-20s%s\n", $$1, $$2}'

.PHONY: checkversion ci default fmt-docs fmt-examples test testacc testrace
