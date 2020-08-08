VERSION=1.6.7
CLUSTER=
OUTPUT_PATH="../../clusters/$(CLUSTER)/"

.PHONY: help
.DEFAULT_GOAL := help
help:
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: operator
operator: bin/istioctl-$(VERSION) ## Install istio-operator manifests
	mkdir -p $(OUTPUT_PATH)/istio-operator
	rm -rf $(OUTPUT_PATH)/istio-operator/operator.yaml
	bin/istioctl-$(VERSION) operator dump > $(OUTPUT_PATH)/istio-operator/operator.yaml

.PHONY: dump-profiles
dump-profiles: bin/istioctl-$(VERSION) ## Dump all default istio profile values
	rm -rf profiles && mkdir profiles
	for p in demo default minimal ; do \
		bin/istioctl-$(VERSION) profile dump $$p > profiles/$$p.yaml ; \
	done

bin/istioctl-$(VERSION):
	rm -f istioctl-$(VERSION)-linux-amd64.tar.gz
	wget https://github.com/istio/istio/releases/download/$(VERSION)/istioctl-$(VERSION)-linux-amd64.tar.gz
	tar -xvf istioctl-$(VERSION)-linux-amd64.tar.gz
	mkdir -p bin
	mv istioctl bin/istioctl-$(VERSION)
	rm -rf istioctl-$(VERSION)-linux-amd64.tar.gz
