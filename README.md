# TigerGate Helm charts

Official Helm charts for TigerGate's in-cluster agents.

| Chart | Purpose |
|---|---|
| [`charts/tigergate`](charts/tigergate) | KSPM posture operator, admission-control webhook, per-node CIS host-scanner, AI-remediation executor, and the TigerEye runtime eBPF sensor — one install for everything that runs in your cluster. |

## Usage

```bash
helm install tigergate oci://registry.tigergate.dev/charts/tigergate \
  --namespace tigergate-system --create-namespace \
  --set backend.apiKey=tg_<org-api-key> \
  --set clusterName=my-cluster
```

Distributed via TigerGate's own private OCI registry (`registry.tigergate.dev`) —
not a classic `index.yaml`/GitHub Pages repo, so there's no `helm repo add`
step. See each chart's own README for the full configuration reference.

## Platform support

Every chart in this repo targets both self-hosted clusters (k3s, kubeadm,
bare-metal/VM control planes) and every major managed control plane — EKS,
AKS, GKE, and OKE — with the same install. The one flavor-specific toggle is
`nodeScanner.enabled` (see `charts/tigergate`'s README): on for self-hosted
so CIS control-plane/kubelet checks resolve to real PASS/FAIL, off for
managed where the control plane isn't reachable from inside the cluster.

GKE Autopilot is the one environment that categorically cannot run the
runtime sensor (Autopilot rejects privileged pods at admission, unrelated to
this chart) — set `sensor.enabled=false` there, or run a Standard node pool
alongside Autopilot if you need runtime coverage.

## Repository layout

```
charts/
  tigergate/            one chart, one directory — see DataDog/helm-charts
                         for the convention this mirrors
.github/workflows/
  lint-test.yml          helm lint + template + kubeconform on every PR
  release.yml             helm package + push to the OCI registry on tag
```

## Releasing a chart

1. Bump the `version` (and `appVersion` if the underlying image moved) in
   the chart's `Chart.yaml`.
2. `git tag <chart>-chart-v<version>` (e.g. `tigergate-chart-v0.3.0`) and
   push the tag — `release.yml` packages and pushes it to
   `oci://registry.tigergate.dev/charts/<chart>`.
3. Or trigger `release.yml` manually (Actions ▸ Release Chart ▸ Run workflow)
   with the chart name + version.

See `CONTRIBUTING.md` for the local dev loop.
