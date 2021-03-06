PACKAGE  = stash.kopano.io/kc/kapi
PACKAGE_NAME = kopano-$(shell basename $(PACKAGE))

# Tools

GO      ?= go
GOFMT   ?= gofmt
DEP     ?= dep
GOLINT  ?= golint

GO2XUNIT ?= go2xunit
GOCOV    ?= gocov
GOCOVXML ?= gocov-xml
GOCOVMERGE ?= gocovmerge

CHGLOG ?= git-chglog

# Cgo
CGO_ENABLED ?= 0

# Variables
ARGS    ?=
PWD     := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
DATE    ?= $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
VERSION ?= $(shell git describe --tags --always --dirty --match=v* 2>/dev/null | sed 's/^v//' || \
			cat $(CURDIR)/.version 2> /dev/null || echo 0.0.0-unreleased)
GOPATH   = $(CURDIR)/.gopath
BASE     = $(GOPATH)/src/$(PACKAGE)
PKGS     = $(or $(PKG),$(shell cd $(BASE) && env GOPATH=$(GOPATH) $(GO) list ./... | grep -v "^$(PACKAGE)/vendor/"))
TESTPKGS = $(shell env GOPATH=$(GOPATH) $(GO) list -f '{{ if or .TestGoFiles .XTestGoFiles }}{{ .ImportPath }}{{ end }}' $(PKGS) 2>/dev/null)
CMDS     = $(or $(CMD),$(addprefix cmd/,$(notdir $(shell find "$(PWD)/cmd/" -type d))))
PLUGINS  = $(or $(PLUGIN),$(addprefix plugins/,$(notdir $(shell find "$(PWD)/plugins/" -maxdepth 1 -type d))))
TIMEOUT  = 30

export GOPATH CGO_ENABLED

# Build

.PHONY: all
all: fmt vendor | $(CMDS) $(PLUGINS)

plugins: fmt vendor | $(PLUGINS)

$(BASE): ; $(info creating local GOPATH ...)
	@mkdir -p $(dir $@)
	@ln -sf $(CURDIR) $@

.PHONY: $(CMDS)
$(CMDS): vendor | $(BASE) ; $(info building $@ ...) @
	cd $(BASE) && CGO_ENABLED=1 $(GO) build \
		-tags release \
		-asmflags '-trimpath=$(GOPATH)' \
		-gcflags '-trimpath=$(GOPATH)' \
		-ldflags '-s -w -X $(PACKAGE)/version.Version=$(VERSION) -X $(PACKAGE)/version.BuildDate=$(DATE)' \
		-o bin/$(notdir $@) $(PACKAGE)/$@

.PHONY: $(PLUGINS)
$(PLUGINS): vendor | $(BASE) ; $(info building $@ ...) @
	cd $(BASE) && CGO_ENABLED=1 $(GO) build \
		-buildmode plugin \
		-tags release \
		-asmflags '-trimpath=$(GOPATH)' \
		-gcflags '-trimpath=$(GOPATH)' \
		-ldflags '-s -w -X $(PACKAGE)/version.Version=$(VERSION) -X $(PACKAGE)/version.BuildDate=$(DATE)' \
		-o bin/plugins/$(notdir $@).so $(PACKAGE)/$(@)

# Helpers

.PHONY: lint
lint: vendor | $(BASE) ; $(info running golint ...)	@
	@cd $(BASE) && ret=0 && for pkg in $(PKGS); do \
		test -z "$$($(GOLINT) $$pkg | tee /dev/stderr)" || ret=1 ; \
	done ; exit $$ret

.PHONY: vet
vet: vendor | $(BASE) ; $(info running go vet ...)	@
	@cd $(BASE) && ret=0 && for pkg in $(PKGS); do \
		test -z "$$($(GO) vet $$pkg)" || ret=1 ; \
	done ; exit $$ret

.PHONY: fmt
fmt: $(BASE) ; $(info running gofmt ...)	@
	@cd $(BASE) && ret=0 && for d in $$($(GO) list -f '{{.Dir}}' ./... | grep -v /vendor/); do \
		$(GOFMT) -l -w $$d/*.go || ret=$$? ; \
	done ; exit $$ret

.PHONY: check
check: $(BASE) ; $(info checking dependencies ...) @
	@cd $(BASE) && $(DEP) check && echo OK

# Tests

TEST_TARGETS := test-default test-bench test-short test-race test-verbose
.PHONY: $(TEST_TARGETS)
test-bench:   ARGS=-run=_Bench* -test.benchmem -bench=.
test-short:   ARGS=-short
test-race:    ARGS=-race
test-race:    CGO_ENABLED=1
test-verbose: ARGS=-v
$(TEST_TARGETS): NAME=$(MAKECMDGOALS:test-%=%)
$(TEST_TARGETS): test

.PHONY: test
test: vendor | $(BASE) ; $(info running $(NAME:%=% )tests ...)	@
	@cd $(BASE) && CGO_ENABLED=1 $(GO) test -timeout $(TIMEOUT)s $(ARGS) $(TESTPKGS)

TEST_XML_TARGETS := test-xml-default test-xml-short test-xml-race
.PHONY: $(TEST_XML_TARGETS)
test-xml-short: ARGS=-short
test-xml-race:  ARGS=-race
test-xml-race:  CGO_ENABLED=1
$(TEST_XML_TARGETS): NAME=$(MAKECMDGOALS:test-%=%)
$(TEST_XML_TARGETS): test-xml

.PHONY: test-xml
test-xml: vendor | $(BASE) ; $(info running $(NAME:%=% )tests ...)	@
	@mkdir -p test
	cd $(BASE) && 2>&1 CGO_ENABLED=1 $(GO) test -timeout $(TIMEOUT)s $(ARGS) -v $(TESTPKGS) | tee test/tests.output
	$(shell test -s test/tests.output && $(GO2XUNIT) -fail -input test/tests.output -output test/tests.xml)

COVERAGE_PROFILE = $(COVERAGE_DIR)/profile.out
COVERAGE_XML = $(COVERAGE_DIR)/coverage.xml
COVERAGE_HTML = $(COVERAGE_DIR)/coverage.html
.PHONY: test-coverage
test-coverage: COVERAGE_DIR := $(CURDIR)/test/coverage.$(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
test-coverage: vendor | $(BASE); $(info running coverage tests ...)
	@mkdir -p $(COVERAGE_DIR)/coverage
	@rm -f test/tests.output
	@cd $(BASE) && for pkg in $(TESTPKGS); do \
		CGO_ENABLED=1 $(GO) test -timeout $(TIMEOUT)s -v \
			-coverpkg=$$($(GO) list -f '{{ join .Deps "\n" }}' $$pkg | \
					grep '^$(PACKAGE)/' | grep -v '^$(PACKAGE)/vendor/' | \
					tr '\n' ',')$$pkg \
			-covermode=atomic \
			-coverprofile="$(COVERAGE_DIR)/coverage/`echo $$pkg | tr "/" "-"`.cover" $$pkg | tee -a test/tests.output ;\
	done
	@$(GO2XUNIT) -fail -input test/tests.output -output test/tests.xml
	@$(GOCOVMERGE) $(COVERAGE_DIR)/coverage/*.cover > $(COVERAGE_PROFILE)
	@$(GO) tool cover -html=$(COVERAGE_PROFILE) -o $(COVERAGE_HTML)
	@$(GOCOV) convert $(COVERAGE_PROFILE) | $(GOCOVXML) > $(COVERAGE_XML)

# Dep

Gopkg.lock: Gopkg.toml | $(BASE) ; $(info updating dependencies ...)
	@cd $(BASE) && $(DEP) ensure -update
	@touch $@

vendor: Gopkg.lock | $(BASE) ; $(info retrieving dependencies ...)
	@cd $(BASE) && $(DEP) ensure -vendor-only
	@touch $@

# Dist

.PHONY: licenses
licenses: ; $(info building licenses files ...)
	cd $(BASE) && $(CURDIR)/scripts/go-license-ranger.py > $(CURDIR)/3rdparty-LICENSES.md

3rdparty-LICENSES.md: licenses

.PHONY: dist
dist: 3rdparty-LICENSES.md ; $(info building dist tarball ...)
	@rm -rf "dist/${PACKAGE_NAME}-${VERSION}"
	@mkdir -p "dist/${PACKAGE_NAME}-${VERSION}"
	@mkdir -p "dist/${PACKAGE_NAME}-${VERSION}/scripts"
	@mkdir -p "dist/${PACKAGE_NAME}-${VERSION}/db/kvs"
	@cd dist && \
	cp -avf ../LICENSE.txt "${PACKAGE_NAME}-${VERSION}" && \
	cp -avf ../README.md "${PACKAGE_NAME}-${VERSION}" && \
	cp -avf ../3rdparty-LICENSES.md "${PACKAGE_NAME}-${VERSION}" && \
	cp -avf ../bin/* "${PACKAGE_NAME}-${VERSION}" && \
	cp -avf ../bin/plugins "${PACKAGE_NAME}-${VERSION}" && \
	cp -avf ../scripts/kopano-kapid.binscript "${PACKAGE_NAME}-${VERSION}/scripts" && \
	cp -avf ../scripts/kopano-kapid.service "${PACKAGE_NAME}-${VERSION}/scripts" && \
	cp -avf ../scripts/kapid.cfg "${PACKAGE_NAME}-${VERSION}/scripts" && \
	cp -avfr ../plugins/kvs/kv/migrations  "${PACKAGE_NAME}-${VERSION}/db/kvs" && \
	tar --owner=0 --group=0 -czvf ${PACKAGE_NAME}-${VERSION}.tar.gz "${PACKAGE_NAME}-${VERSION}" && \
	cd ..

.PHONE: changelog
changelog: ; $(info updating changelog ...)
	$(CHGLOG) --output CHANGELOG.md $(ARGS)

# Rest

.PHONY: clean
clean: ; $(info cleaning ...)	@
	@rm -rf $(GOPATH)
	@rm -rf bin
	@rm -rf test/test.*

.PHONY: version
version:
	@echo $(VERSION)
