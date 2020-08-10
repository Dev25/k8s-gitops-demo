Kubernetes Gitops Demo
---

A example repository that demonstrates managing workloads and configuration for Kubernetes clusters using [Flux] for a GitOps CD platform.

* [Repo Structure](#repo-structure)
* [Deploying](#deploying)
   * [Terraform](#terraform)
   * [Manually](#manually)
* [Sync Notifications](#sync-notifications)
* [Real Time Syncing](#real-time-syncing)
* [Secrets](#secrets)
   * [Encrypted in Git](#encrypted-in-git)
   * [GCP Secrets Manager](#gcp-secrets-manager)
      * [Berglas](#berglas)
      * [Syncing as Kubernetes Secrets](#syncing-as-kubernetes-secrets)


## Repo Structure

The directory layout is split into the following main areas


| Directory | |
| --------- | ----- |
| base | Global manifests to apply to all clusters defined in branch e.g. PodSecurityPolicies |
| clusters/<cluster>/<namespace>/ | Cluster specific manifests e.g. application or environment specific components |
| src | Config used to generate manifests saved in `base/` or `clusters/` |
| scripts | Helper scripts |
| policies | [conftest] policies for enforcing policy|


```bash
.
├── base                                     # Everything under base/ deployed in all clusters
│   ├── namespace
│   │   └── kube-system
│   └── security                             # Global Security config e.g PSP
│       ├── psp-privileged.yaml
│       ├── psp-restricted.yaml
│       ├── rbac-clusterrolebinding.yaml
│       └── rbac-clusterroles.yaml
├── clusters                                 # Cluster specific deployments
│   ├── gke-eu-1
│   │   ├── flux
│   │   ├── istio-operator
│   │   ├── istio-system
│   │   └── kube-system
│   │       └── k8s-node-termination-handler # Preemptive instance handler
│   └── kind
│       ├── default
│       ├── flux
│       ├── istio-operator
│       ├── istio-system
│       ├── kube-system
│       └── metallb-system                   # LoadBalancer implmentation required for kind clusters
└── src                                      # Config used in templating YAML manifiests
    ├── istio
    └── kube-prometheus
```


## Deploying

### Terraform
[terraform-kubernetes-flux-module] provides a way to bootstrap your flux cluster with a minimal _one shot_ deployment that will pull and then overwrite itself with the flux config stored in your gitops repo. This allows you to keep a separation of duty between using Terraform to manage your cluster infrastructure and Flux to apply cluster workloads.


### Manually

`kubectl apply -f clusters/<cluster>/flux` to deploy flux on your cluster, if your repository is private or you want to give flux write access then you will need to additionally grant access to the SSH key `flux` will [generate at first boot](https://docs.fluxcd.io/en/1.20.1/tutorials/get-started/#giving-write-access).


## Sync Notifications

[fluxcloud] can be used as a sidecar or deployment to post sync notifications to your favourite chat service.

<details>
  <summary>Sidecar Config: Slack Example</summary>

```yaml
      containers:
      - name: flux
        image: docker.io/fluxcd/flux:1.20.1
        args:
        - --connect=ws://127.0.0.1:3032

      - name: fluxcloud
        image: devan2502/fluxcloud:v0.3.9-1
        imagePullPolicy: Always
        ports:
        - containerPort: 3032
        env:
        - name: SLACK_URL
          value: "https://hooks.slack.com/services/...."
        - name: SLACK_CHANNEL
          value: "#flux"
        - name: SLACK_ICON_EMOJI
          value: ":duck:"
        - name: SLACK_USERNAME
          value: Foo Cluster
        - name: GITHUB_URL
          value: "https://github.com/Dev25/k8s-gitops-demo"
        - name: LISTEN_ADDRESS
          value: ":3032"
        - name: TITLE_TEMPLATE
          value: |
            Flux Event: {{ .EventType }}
        - name: BODY_TEMPLATE
          value: |
            {{ if and (ne .EventType "commit") (gt (len .Commits) 0) }}{{ range .Commits }}
            * {{ call $.FormatLink (print $.VCSLink "/commit/" .Revision) (truncate .Revision 7) }} ```{{ .Message }}```
            {{end}}{{end}}
            {{ if and (eq .EventType "sync") (gt (len .EventServiceIDs) 0) }}```Resources {{ range .EventServiceIDs }}
            * {{ . }}{{ end }}```{{ end }}
            {{ if gt (len .Errors) 0 }}Errors:
            ```{{ range .Errors }}
            Resource {{ .ID }}, file: {{ .Path }}:
            > {{ .Error }}
            {{ end }}```{{ end }}
```
</details>

## Real Time Syncing

By default `flux` will automatically pull and sync changes on a regular interval as well as poll for new images for automated deployments. In order to speed up time to detect a new commit or image built you can expose your flux deployment using [flux-recv] and set webhooks on your git provider or container registry, see [flux-recv] for further instructions to setup.

[Supported Sources](https://github.com/fluxcd/flux-recv#supported-webhook-sources):
- `GitHub` push events (and ping events)
- `DockerHub` image push events
- `Quay` image push events
- `GitLab` push events
- `Bitbucket` push events
- `GoogleContainerRegistry` image push events via pubsub
- `Nexus` image push events


<details>
  <summary>Sidecar Config</summary>

```yaml
    containers:
      # ...
      # GitHub Sync Webhook
      - name: recv
        image: fluxcd/flux-recv:0.5.0
        imagePullPolicy: IfNotPresent
        args:
        - --config=/etc/fluxrecv/fluxrecv.yaml
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
        volumeMounts:
        - name: fluxrecv-config
          mountPath: /etc/fluxrecv
---
apiVersion: v1
kind: Secret
metadata:
  name: fluxrecv-conf
  namespace: flux
type: Opaque
stringData:
  fluxrecv.yaml: |-
    fluxRecvVersion: 1
    endpoints:
    - keyPath: github.key
      source: GitHub

  # Generated from `ruby -rsecurerandom -e 'print SecureRandom.hex(20)'`
  github.key: 92b8c5df36099ccf0378723bda5e0661a0753178
---
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: flux
  namespace: flux
  labels:
    app: flux
  annotations:
    kubernetes.io/ingress.class: external
    nginx.ingress.kubernetes.io/client-body-buffer-size: 1m
spec:
  rules:
  - host: your.domain.io
    http:
      paths:
      - backend:
          serviceName: flux
          servicePort: 8080
  tls:
  - hosts:
    - your.domain.io
---
apiVersion: v1
kind: Service
metadata:
  name: flux
  namespace: flux
  labels:
    name: flux
spec:
  type: ClusterIP
  ports:
    - name: http-metrics
      port: 3031
      targetPort: 3031
    - name: http-recv
      port: 8080
      targetPort: 8080
  selector:
    name: flux
```
</details>

## Secrets

Secrets should either be stored encrypted in the repo or in a secret manager such as Hashicorp [Vault] or [GCP](https://cloud.google.com/secret-manager)/[AWS](https://aws.amazon.com/secrets-manager/) Secrets Manager and injected at runtime.


### Encrypted in Git

[sealed-secrets] provides a way to encrypt your secrets using a public key that can be stored in git and then decrypted on the clusters automatically using a private key.


### GCP Secrets Manager

To consume secrets from [GCP Secrets Manager] you can either read directly when your application starts or sync to [Kubernetes Secrets] and consume them as normal.

#### Berglas

[Berglas] is a CLI tool and go library that can store and retrieve secrets stored in GCP, it automates the process of injecting secrets to Kubernetes Pods at container startup.

<details>
  <summary>Add beglas CLI to docker image</summary>

```dockerfile
FROM runatlantis/atlantis:v0.14.0
# Build image as normal

# Install berglas CLI
COPY --from=europe-docker.pkg.dev/berglas/berglas/berglas:0.5.3 /bin/berglas /bin/berglas

# berglas runs first and then executes your application after injecting secrets
ENTRYPOINT exec /bin/berglas exec -- /usr/local/bin/atlantis server
```
</details>


<details>
  <summary>Example of injecting secrets as environmental variables</summary>

```yaml
      env:
        # WEBHOOK_SECRET becomes secret value
        - name: WEBHOOK_SECRET
          value: sm://your-gcp-project-id/webhook-secret
        # KEY_FILE becomes /tmp/github.key and the secret value is written to that file path.
        - name: KEY_FILE
          value: sm://your-gcp-project-id/webhook-keyfile?destination=/tmp/github.key
```
</details>

#### Syncing as Kubernetes Secrets

See [gsm-controller] or [external-secrets].


[terraform-kubernetes-flux-module]: https://github.com/Dev25/terraform-kubernetes-flux-module
[gsm-controller]: https://github.com/Dev25/gsm-controller

[flux]: https://github.com/fluxcd/flux
[flux-recv]: https://github.com/fluxcd/flux-recv
[fluxcloud]: https://github.com/justinbarrick/fluxcloud

[Kubernetes Secrets]: https://kubernetes.io/docs/concepts/configuration/secret/
[Vault]: https://www.vaultproject.io/
[sealed-secrets]: https://github.com/bitnami-labs/sealed-secrets
[GCP Secrets Manager]: https://cloud.google.com/secret-manager
[external-secrets]: https://github.com/godaddy/kubernetes-external-secrets
[berglas]: https://github.com/GoogleCloudPlatform/berglas
[conftest]:
