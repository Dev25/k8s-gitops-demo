Kubernetes Gitops Demo
---

A example repository that demonstrates managing workloads and configuration for Kubernetes clusters using [Flux] for a GitOps CD platform.

* [Repo Structure](#repo-structure)
* [Deploying](#deploying)
   * [Terraform](#terraform)
   * [Manually](#manually)
* [Enforcing Policy for Workloads](#enforcing-policy-for-workloads)
   * [Static Tools](#static-tools)
      * [yamllint](#yamllint)
      * [kubeval](#kubeval)
      * [conftest](#conftest)
   * [Admission Controllers](#admission-controllers)
      * [PodSecurityPolicy](#podsecuritypolicy)
      * [OPA Gatekeeper](#opa-gatekeeper)
* [Flux](#flux)
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
| clusters/`cluster`/`namespace`/ | Cluster specific manifests e.g. application or environment specific components |
| src | Config used to generate manifests saved in `base/` or `clusters/` |
| scripts | Helper scripts |
| policies | Rego policies for [conftest] |


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
├── policy                                   # Rego policies
│   ├── lib
│   │   └── kubernetes.rego
│   ├── security.rego
│   └── security_test.rego
└── src                                      # Config used in templating YAML manifiests
    ├── istio
    └── kube-prometheus
```


## Deploying

### Terraform
[terraform-kubernetes-flux-module] provides a way to bootstrap your flux cluster with a minimal _one shot_ deployment that will pull and then overwrite itself with the flux config stored in your gitops repo. This allows you to keep a separation of duty between using Terraform to manage your cluster infrastructure and Flux to apply cluster workloads.


### Manually

`kubectl apply -f clusters/<cluster>/flux` to deploy flux on your cluster, if your repository is private or you want to give flux write access then you will need to additionally grant access to the SSH key `flux` will [generate at first boot](https://docs.fluxcd.io/en/1.20.1/tutorials/get-started/#giving-write-access).


## Enforcing Policy for Workloads

Enforcing policy can be done at multiple stages of the CI/CD pipeline from using static analysis tools running in CI to admission controllers that can block workloads at deploy time.

### Static Tools

These tools can be configured to run as part of CI and made a requirement to pass in order to merge a PR to apply changes to a cluster.

```bash
❯ make
lint                           Run all lint checks
yamllint                       Run basic YAML linter
policies                       Pull latest example Rego policies for conftest
conftest                       Run conftest to check that manifests meet policy conformance
kubeval                        Run kubeval to check manifests meet Kubernetes OpenAPI spec
```

#### yamllint
[yamllint] is a basic YAML linter that can catch syntax errors or issues such as duplicate keys.

```bash
❯ make yamllint
yamllint -c .yamllint.yaml base clusters
clusters/kind/istio-system/01-controlplane.yaml
  9:3       error    duplication of key "profile" in mapping  (key-duplicates)

clusters/kind/default/00-namespace.yaml
  5:3       error    syntax error: expected <block end>, but found '<block mapping start>' (syntax)
```

#### kubeval

[kubeval] is a tool that validates if manifests satisfy a specific version of the Kubernetes API spec, providing a quick and easy way to catch invalid or missing object properties.

```bash
❯ make kubeval
bin/kubeval-0.15.0 --ignore-missing-schemas --strict --exit-on-error -d base,clusters
WARN - Set to ignore missing schemas
PASS - base/namespace/kube-system/kube-dns-pdb.yaml contains a valid PodDisruptionBudget (kube-system.kube-dns)
PASS - base/security/psp-privileged.yaml contains a valid PodSecurityPolicy (privileged)
PASS - base/security/psp-restricted.yaml contains a valid PodSecurityPolicy (restricted)
PASS - base/security/rbac-clusterrolebinding.yaml contains a valid ClusterRoleBinding (privileged-psp-users)
PASS - base/security/rbac-clusterrolebinding.yaml contains a valid ClusterRoleBinding (restricted-psp-users)
PASS - base/security/rbac-clusterrolebinding.yaml contains a valid ClusterRoleBinding (edit)
PASS - base/security/rbac-clusterroles.yaml contains a valid ClusterRole (restricted-psp-user)
PASS - base/security/rbac-clusterroles.yaml contains a valid ClusterRole (privileged-psp-user)
ERR  - clusters/kind/default/00-namespace.yaml: Missing 'kind' key
make: *** [Makefile:43: kubeval] Error 1
```

#### conftest

OPA [conftest] is a generic tool that can be used to write tests against a configuration. It uses the [Rego] language from [OpenPolicyAgent] and
has `push` and `pull` commands in order to easily share Rego policies. Policies can check for anything from running as unprivileged to ensuring a specific label such as `app` or `team` exists.

```
❯ make policies
conftest pull github.com/instrumenta/policies.git//kubernetes

❯ ls policy
lib/  security.rego  security_test.rego

❯ head -16 policy/security.rego
package main

import data.lib.kubernetes

violation[msg] {
  kubernetes.containers[container]
  [image_name, "latest"] = kubernetes.split_image(container.image)
  msg = kubernetes.format(sprintf("%s in the %s %s has an image, %s, using the latest tag", [container.name, kubernetes.kind, image_name, kubernetes.name]))
}

# https://kubesec.io/basics/containers-resources-limits-memory
violation[msg] {
  kubernetes.containers[container]
  not container.resources.limits.memory
  msg = kubernetes.format(sprintf("%s in the %s %s does not have a memory limit set", [container.name, kubernetes.kind, kubernetes.name]))
}

❯ make conftest
bin/conftest-0.20.0 test base clusters
FAIL - clusters/kind/flux/flux-deployment.yaml - flux in the Deployment flux does not have a memory limit set
FAIL - clusters/kind/flux/flux-deployment.yaml - flux in the Deployment flux does not have a CPU limit set
FAIL - clusters/kind/flux/flux-deployment.yaml - flux in the Deployment flux doesn't drop all capabilities
FAIL - clusters/kind/flux/flux-deployment.yaml - flux in the Deployment flux is not using a read only root filesystem
FAIL - clusters/kind/flux/flux-deployment.yaml - flux in the Deployment flux allows priviledge escalation
FAIL - clusters/kind/flux/flux-deployment.yaml - flux in the Deployment flux is running as root
FAIL - clusters/kind/flux/helm-operator/helm-operator-deployment.yaml - flux-helm-operator in the Deployment flux-helm-operator does not have a memory limit set
FAIL - clusters/kind/flux/helm-operator/helm-operator-deployment.yaml - flux-helm-operator in the Deployment flux-helm-operator does not have a CPU limit set
FAIL - clusters/kind/flux/helm-operator/helm-operator-deployment.yaml - flux-helm-operator in the Deployment flux-helm-operator doesn't drop all capabilities
FAIL - clusters/kind/flux/helm-operator/helm-operator-deployment.yaml - flux-helm-operator in the Deployment flux-helm-operator is not using a read only root filesystem
FAIL - clusters/kind/flux/helm-operator/helm-operator-deployment.yaml - flux-helm-operator in the Deployment flux-helm-operator allows priviledge escalation
FAIL - clusters/kind/flux/helm-operator/helm-operator-deployment.yaml - flux-helm-operator in the Deployment flux-helm-operator is running as root
FAIL - clusters/kind/kube-system/metrics-server-v0.3.7.yaml - metrics-server in the Deployment metrics-server does not have a memory limit set
FAIL - clusters/kind/kube-system/metrics-server-v0.3.7.yaml - metrics-server in the Deployment metrics-server does not have a CPU limit set
FAIL - clusters/kind/kube-system/metrics-server-v0.3.7.yaml - metrics-server in the Deployment metrics-server doesn't drop all capabilities
FAIL - clusters/kind/kube-system/metrics-server-v0.3.7.yaml - metrics-server in the Deployment metrics-server has a UID of less than 10000
FAIL - clusters/kind/default/httpbin.yaml - httpbin in the Deployment docker.io/kennethreitz/httpbin has an image, httpbin, using the latest tag

```

### Admission Controllers

[Admission controllers] provide a way to validate or mutate requests on objects, mutating can modify objects such as [injecting a sidecar container](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/#automatic-sidecar-injection) to a `Pod`. Due to the dynamic nature of mutating webhooks  validating controllers provide a last layer of defence to ensure workloads are still compliant with policy because unlike static tooling it is aware of the final representation of a object after any mutations.


Kubernetes provides several built in admission controllers such as `PodSecurityPolicy` or `ResourceQuota` and allows custom controllers for further control such as using [Gatekeeper].


#### PodSecurityPolicy
[PodSecurityPolicy] enabled clusters allow you to control security aspects of Pods such as running as non root or restricting access to `hostNetwork`. By defining a restricted PSP and applying to all authenticated service accounts you can ensure workloads by default must satisfy your restrictied policy unless they opt in to using their own custom or higher privileged PSP.

<details>
<summary>Example: Restricted PSP</summary>

```yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
    name: restricted-psp-users
subjects:
  # All users
- kind: Group
  apiGroup: rbac.authorization.k8s.io
  name: system:authenticated
roleRef:
   apiGroup: rbac.authorization.k8s.io
   kind: ClusterRole
   name: restricted-psp-user
---
# restricted-psp-user grants access to use the restricted PSP.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: restricted-psp-user
rules:
- apiGroups:
  - policy
  resources:
  - podsecuritypolicies
  resourceNames:
  - restricted
  verbs:
  - use
---
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: 'docker/default'
    apparmor.security.beta.kubernetes.io/allowedProfileNames: 'runtime/default'
    seccomp.security.alpha.kubernetes.io/defaultProfileName: 'docker/default'
    apparmor.security.beta.kubernetes.io/defaultProfileName: 'runtime/default'
spec:
  privileged: false
  # Required to prevent escalations to root.
  allowPrivilegeEscalation: false
  # This is redundant with non-root + disallow privilege escalation,
  # but we can provide it for defense in depth.
  requiredDropCapabilities:
    - ALL
  # Allow core volume types.
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    # Assume that persistentVolumes set up by the cluster admin are safe to use.
    - 'persistentVolumeClaim'
  hostNetwork: false
  hostIPC: false
  hostPID: false
  runAsUser:
    # Require the container to run without root privileges.
    rule: 'MustRunAsNonRoot'
  seLinux:
    # This policy assumes the nodes are using AppArmor rather than SELinux.
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'MustRunAs'
    ranges:
      # Forbid adding the root group.
      - min: 1
        max: 65535
  fsGroup:
    rule: 'MustRunAs'
    ranges:
      # Forbid adding the root group.
      - min: 1
        max: 65535
  readOnlyRootFilesystem: false
```
</details>

#### OPA Gatekeeper

[Gatekeeper] is a admission controller for Kubernetes that can be deployed in a cluster and act as a validating webhook, every time a object is modified such as updating a `Ingress` or when a `Pod` is created, it can execute your Rego policy stored as `ConstraintTemplate` and reject the request if it fails to meet your policy.

## Flux

### Sync Notifications

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

### Real Time Syncing

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
[flux]: https://github.com/fluxcd/flux
[flux-recv]: https://github.com/fluxcd/flux-recv
[fluxcloud]: https://github.com/justinbarrick/fluxcloud

[Kubernetes Secrets]: https://kubernetes.io/docs/concepts/configuration/secret/
[Vault]: https://www.vaultproject.io/
[sealed-secrets]: https://github.com/bitnami-labs/sealed-secrets
[GCP Secrets Manager]: https://cloud.google.com/secret-manager
[external-secrets]: https://github.com/godaddy/kubernetes-external-secrets
[berglas]: https://github.com/GoogleCloudPlatform/berglas
[gsm-controller]: https://github.com/Dev25/gsm-controller

[conftest]: https://github.com/open-policy-agent/conftest
[PodSecurityPolicy]: https://kubernetes.io/docs/concepts/policy/pod-security-policy/
[Gatekeeper]: https://github.com/open-policy-agent/gatekeeper
[yamllint]: https://github.com/adrienverge/yamllint
[kubeval]: https://github.com/instrumenta/kubeval
[OpenPolicyAgent]: https://www.openpolicyagent.org/
[Rego]: https://www.openpolicyagent.org/docs/latest/policy-language/
[Admission Controllers]: https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers
