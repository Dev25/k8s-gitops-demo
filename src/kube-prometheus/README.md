kube-prometheus
---

Manage Promethes/Alertmanager/Grafana via [prometheus-operator/kube-prometheus](https://github.com/prometheus-operator/kube-prometheus)


### Setup

```bash
go get -u -v github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb
jb install # Install deps as per jsonnetfile.lock.json

jb update # Update deps
```

### Generating Manifests

A base config is stored in `common.jsonnet`

Create a `cluster-$CLUSTER.jsonnet` file containing your cluster specific config which extends `common.jsonnet` and then run `./build.sh $CLUSTER` to generate manifests in `clusters/<cluster>/monitoring/kube-prometheus`

```bash
❯ ./build.sh kind
+ rm -rf manifests
+ mkdir manifests
+ CLUSTER=kind
+ jsonnet -J vendor -m manifests cluster-kind.jsonnet
+ xargs '-I{}' sh -c 'cat {} | gojsontoyaml > {}.yaml; rm -f {}' -- '{}'
+ rm -rf ../../clusters/kind/monitoring/kube-prometheus
+ mv manifests ../../clusters/kind/monitoring/kube-prometheus
```
