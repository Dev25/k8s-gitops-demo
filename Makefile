KUBEVAL_VERSION=0.15.0
CONFTEST_VERSION=0.20.0

.PHONY: help
.DEFAULT_GOAL := help
help:
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: lint
lint: yamllint kubeval conftest ## Run all lint checks



.PHONY: yamllint
yamllint: ## Run basic YAML linter
	yamllint -c .yamllint.yaml base clusters

## conftest
## https://github.com/open-policy-agent/conftest
## https://github.com/instrumenta/policies
.PHONY: policies
policies: bin/conftest-$(CONFTEST_VERSION) ## Pull latest example Rego policies for conftest
	conftest pull github.com/instrumenta/policies.git//kubernetes

.PHONY: conftest
conftest: bin/conftest-$(CONFTEST_VERSION) ## Run conftest to check that manifests meet policy conformance
	bin/conftest-$(CONFTEST_VERSION) test base clusters

bin/conftest-$(CONFTEST_VERSION):
	( \
	mkdir bin && \
	cd bin && \
	wget https://github.com/open-policy-agent/conftest/releases/download/v$(CONFTEST_VERSION)/conftest_$(CONFTEST_VERSION)_Linux_x86_64.tar.gz && \
	tar --extract --file=conftest_$(CONFTEST_VERSION)_Linux_x86_64.tar.gz conftest && \
	mv conftest conftest-$(CONFTEST_VERSION) && \
	rm -f *.tar.gz \
	)

## kubeval
## github.com/instrumenta/kubeval
.PHONY: kubeval
kubeval: bin/kubeval-$(KUBEVAL_VERSION) ## Run kubeval to check manifests meet Kubernetes OpenAPI spec
	bin/kubeval-$(KUBEVAL_VERSION) --ignore-missing-schemas --strict --exit-on-error -d base,clusters

bin/kubeval-$(KUBEVAL_VERSION):
	( \
	mkdir bin && \
	cd bin && \
	wget https://github.com/instrumenta/kubeval/releases/download/$(KUBEVAL_VERSION)/kubeval-linux-amd64.tar.gz && \
	tar --extract --file=kubeval-linux-amd64.tar.gz kubeval && \
	mv kubeval kubeval-$(KUBEVAL_VERSION) && \
	rm -f *.tar.gz \
	)
