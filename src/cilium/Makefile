VERSION=1.8.2

.PHONY: template
template: charts/cilium-$(VERSION).tgz ## Generate cilium manifests
	helm template cilium charts/cilium-$(VERSION).tgz --namespace kube-system --output-dir out -f values.yaml
	rm -rf ../../clusters/kind-cilium/kube-system/cilium
	mv out/cilium/charts ../../clusters/kind-cilium/kube-system/cilium
	rm -rf out

charts/cilium-$(VERSION).tgz:
	helm repo add cilium https://helm.cilium.io/
	helm repo update
	mkdir -p charts/
	cd charts/ && helm fetch cilium/cilium --version $(VERSION)
