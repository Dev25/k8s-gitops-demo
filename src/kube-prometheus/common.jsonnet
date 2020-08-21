local k = import 'ksonnet/ksonnet.beta.3/k.libsonnet';
local pvc = k.core.v1.persistentVolumeClaim;
local container = k.core.v1.pod.mixin.spec.containersType;
local resourceRequirements = container.mixin.resourcesType;

local _kp =
  (import 'kube-prometheus/kube-prometheus.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-all-namespaces.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-strip-limits.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-anti-affinity.libsonnet') +
  (import 'common.jsonnet') +
  {

    // Dont generate a monitoring namespace
    // Defined outside this stack
    kubePrometheus:: {},

    _config+:: {
      namespace: 'monitoring',

      jobs: {
        Kubelet: $._config.kubeletSelector,
        KubeAPI: $._config.kubeApiserverSelector,
        KubeStateMetrics: $._config.kubeStateMetricsSelector,
        NodeExporter: $._config.nodeExporterSelector,
        Alertmanager: $._config.alertmanagerSelector,
        Prometheus: $._config.prometheusSelector,
        PrometheusOperator: $._config.prometheusOperatorSelector,
      },

      versions+:: {
      },

      kubeStateMetrics+:: {
        baseCPU: '50m',
        baseMemory: '250Mi',
      },

      prometheus+:: {
        names: 'k8s',
        replicas: 1,
      },

      grafana+:: {
        container: {
          requests: { memory: '50Mi' },
          limits: { memory: '100Mi' },
        },
      },

      alertmanager+:: {
        name: 'main',
        replicas: 3,
      },
    },  // End Config

    alertmanager+:: {
      alertmanager+: {
        spec+: {
          securityContext: {
            runAsUser: 10001,
            runAsNonRoot: true,
            fsGroup: 2000,
          },
          resources:
            resourceRequirements.new() +
            resourceRequirements.withRequests({ cpu: '0m', memory: '64Mi' }),
        },
      },
    },

    # prometheusRules+:: {
    # },

    # prometheusAlerts+:: {
    # },

    # nodeExporter+:: {
    #   clusterRoleBinding:
    #     local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;

    #     clusterRoleBinding.new() +
    #     clusterRoleBinding.mixin.metadata.withName('node-exporter') +
    #     clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
    #     clusterRoleBinding.mixin.roleRef.withName('node-exporter') +
    #     clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
    #     clusterRoleBinding.withSubjects([{ kind: 'ServiceAccount', name: 'node-exporter', namespace: $._config.namespace }]),

    #   clusterRole:
    #     local clusterRole = k.rbac.v1.clusterRole;
    #     local policyRule = clusterRole.rulesType;

    #     local authenticationRole = policyRule.new() +
    #                                policyRule.withApiGroups(['authentication.k8s.io']) +
    #                                policyRule.withResources([
    #                                  'tokenreviews',
    #                                ]) +
    #                                policyRule.withVerbs(['create']);

    #     local authorizationRole = policyRule.new() +
    #                               policyRule.withApiGroups(['authorization.k8s.io']) +
    #                               policyRule.withResources([
    #                                 'subjectaccessreviews',
    #                               ]) +
    #                               policyRule.withVerbs(['create']);

    #     local pspRole = policyRule.new() +
    #                     policyRule.withApiGroups(['policy']) +
    #                     policyRule.withResources([
    #                       'podsecuritypolicies',
    #                     ]) +
    #                     policyRule.withVerbs(['use']) +
    #                     policyRule.withResourceNames(['node-exporter']);

    #     local rules = [authenticationRole, authorizationRole, pspRole];

    #     clusterRole.new() +
    #     clusterRole.mixin.metadata.withName('node-exporter') +
    #     clusterRole.withRules(rules),
    # },

    prometheus+:: {
      prometheus+: {
        spec+: {
          enableAdminAPI: true,
          securityContext: {
            runAsUser: 65534,
            runAsNonRoot: true,
            fsGroup: 65534,
          },
        },
      },

    } + import 'service-monitors.jsonnet',  // prometheus

  };

{
  kp: _kp {
    kubeStateMetrics+: {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              securityContext: { runAsNonRoot: true },
              // Make sure all conatiners run as non root uid
              containers: std.map(function(c) c {
                securityContext: { runAsUser: 65534 },
              }, super.containers),
            },
          },
        },
      },
    },
  },
}
