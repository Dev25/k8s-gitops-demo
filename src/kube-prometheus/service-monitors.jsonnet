local k = import 'ksonnet/ksonnet.beta.3/k.libsonnet';
local namespace = 'monitoring';

{
 serviceMonitorFlux:
    {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: {
        name: 'flux',
        namespace: namespace,
        labels: { 'k8s-app': 'flux' },
      },
      spec: {
        selector: { matchLabels: { name: 'flux' } },
        namespaceSelector: { matchNames: ['flux'] },
        endpoints: [
          { port: 'http-metrics', interval: '15s', honorLabels: true },
        ],
      },
    },

 serviceMonitorFluxHelmOperator:
    {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: {
        name: 'flux-helm-operator',
        namespace: namespace,
        labels: { 'k8s-app': 'flux-helm-operator' },
      },
      spec: {
        selector: { matchLabels: { name: 'flux-helm-operator' } },
        namespaceSelector: { matchNames: ['flux'] },
        endpoints: [
          { port: 'http-metrics', interval: '15s', honorLabels: true },
        ],
      },
    },
}
