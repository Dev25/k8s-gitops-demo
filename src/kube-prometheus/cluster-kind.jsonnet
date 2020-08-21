local k = import 'ksonnet/ksonnet.beta.3/k.libsonnet';
local container = k.core.v1.pod.mixin.spec.containersType;
local resourceRequirements = container.mixin.resourcesType;

local common = import 'common.jsonnet';
local kp = common.kp {

  _config+:: {
    versions+:: {
      prometheus: 'v2.20.1',
    },
    grafana+:: {
      config+: {
        sections+: {
          server+: {
            root_url: 'http://kind.test/grafana/',
          },
          'auth.anonymous': {
              enabled: true,
              org_name: "Main Org.",
              org_role: "Editor",
          },
        },
      },
    },
    prometheus+:: {
      names: 'k8s',
      replicas: 1,
    },
    alertmanager+:: {
      config: |||
        global:
          resolve_timeout: 5m
        route:
          group_by: ['job']
          group_wait: 30s
          group_interval: 5m
          repeat_interval: 12h
          receiver: 'null'
          routes:
          # Things we never want to alert on in our environment
          - match_re:
              alertname: DeadMansSwitch|Watchdog
            receiver: 'null'
          - match_re:
              alertname: KubeVersionMismatch|KubeControllerManagerDown|KubeSchedulerDown
            receiver: 'null'
          - match_re:
              alertname: PrometheusDuplicateTimestamps|PrometheusOutOfOrderTimestamps
            receiver: 'null'

        inhibit_rules:
        - source_match:
            severity: 'critical'
          target_match:
            severity: 'warning'
          equal: ['alertname']

        receivers:
        - name: 'null'
       |||,
    },
  },  // End Config

  alertmanager+:: {
    alertmanager+: {
      spec+: {
        externalUrl: 'http://kind.test/alertmanager/',
        routePrefix: '/',
      },
    },
  },

  prometheus+:: {
    prometheus+: {
      spec+: {
        retention: '3d',
        externalUrl: 'http://kind.test/prometheus/',
        routePrefix: '/',
        resources:
          resourceRequirements.new() +
          resourceRequirements.withRequests({ cpu: '100m', memory: '512Mi' }),
      },
    },
  },
};


{ ['00namespace-' + name]: kp.kubePrometheus[name] for name in std.objectFields(kp.kubePrometheus) } +
{ ['0prometheus-operator-' + name]: kp.prometheusOperator[name] for name in std.objectFields(kp.prometheusOperator) } +
{ ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
{ ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
{ ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
{ ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } +
{ ['grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) }
