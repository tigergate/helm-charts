# TigerGate Helm chart

A single chart that installs every TigerGate in-cluster agent, all sharing
one org API key and one cluster name.

| Component | Kind | Enabled by | Purpose |
|---|---|---|---|
| KSPM posture operator | Deployment | `controller.enabled` | Read-only cluster scan: posture, inventory, KIEM (RBAC), CIS/NSA controls, drift. Also embeds the relay the runtime sensor fleet talks to. |
| Admission controller | Deployment + `ValidatingWebhookConfiguration` | `admission.enabled` | Validates pods against Pod Security + image-trust + custom policy, in `audit` (warn) or `enforce` (deny) mode. |
| Runtime sensor | DaemonSet (privileged, eBPF) | `sensor.enabled` | Per-node runtime telemetry (process/file/network/privilege). |
| CIS node host-scanner | DaemonSet (privileged) | `nodeScanner.enabled` (off by default) | Per-node CIS control-plane/kubelet checks (arguments + file ownership). |
| AI-remediation executor | Deployment, own ServiceAccount | `remediation.enabled` (off by default) | Previews and applies AI-generated fixes to Deployments/StatefulSets/DaemonSets. The only write-capable component in this chart. |

## Prerequisites

- Kubernetes 1.23+
- Helm 3
- A TigerGate org API key (`tg_...`)

## Runs on every KSPM environment

The same chart installs on self-hosted and managed clusters; only
`nodeScanner.enabled` should change based on where you're installing:

| Environment | `nodeScanner.enabled` | Why |
|---|---|---|
| Self-hosted: k3s, kubeadm, bare-metal/VM control planes | `true` | The control plane runs as inspectable host processes, so this turns the relevant CIS control-plane/etcd/kubelet checks from `NOT_ASSESSED` into real `PASS`/`FAIL`. |
| Managed: EKS, AKS, GKE, OKE | `false` (default) | The control plane isn't on a node you can read, so this DaemonSet would run privileged for no benefit. The operator already reports these checks as `NOT_ASSESSED` rather than a false `FAIL`. |

## Install

```bash
helm install tigergate oci://registry.tigergate.dev/charts/tigergate \
  --namespace tigergate-system --create-namespace \
  --set backend.apiKey=tg_<org-api-key> \
  --set clusterName=my-cluster
```

Self-hosted clusters should also enable the node host-scanner:

```bash
--set nodeScanner.enabled=true
```

From a local checkout:

```bash
helm install tigergate ./charts/tigergate \
  --namespace tigergate-system --create-namespace \
  --set backend.apiKey=tg_<org-api-key> --set clusterName=my-cluster
```

The cluster auto-registers under your org on the operator's first report —
there is no separate registration step.

### Multi-region

If your organization was created outside the default region, pass
`--set region=<code>`. This resolves every component's backend and gRPC
ingest endpoints for that region; an API key from a different region is
rejected. Region codes are listed at
<https://docs.tigergate.dev/platform/regions>.

## Configuration

| Key | Default | Notes |
|---|---|---|
| `region` | `""` (default region) | Must match the region your org was created in. Resolves `backend.url` and `backend.ingestGrpcAddr` when they're left empty. |
| `backend.url` | `""` (from `region`) | Backend base URL, used for image-policy/custom-rules reads. Override only for a self-hosted or staging platform. |
| `backend.apiKey` | `""` | Org `tg_` API key. Required unless `backend.existingSecret` is set. |
| `backend.existingSecret` | `""` | Name of a pre-created Secret with key `apiKey`, used instead of templating one from `backend.apiKey`. |
| `backend.ingestGrpcAddr` | `""` (from `region`) | gRPC address for scan reports, admission events, node controls and (by default) sensor events. |
| `clusterName` | `""` | **Required.** Customer-chosen cluster name. |
| `imagePullSecrets` | `[]` | Applied to every pod. |
| `image.repository` / `.tag` | `tigergate/tigergate-kspm-agent` / `latest` | Image for the operator, admission-controller, node-scanner and remediator. |
| `controller.enabled` | `true` | KSPM posture operator. |
| `controller.scanIntervalPosture` | `30m` | How often the operator scans. |
| `relay.port` | `8090` | Port the operator's embedded sensor relay listens on. |
| `blockKspm` / `blockRuntime` | `false` | Run scans/collect events locally but stop forwarding that product's data upstream. |
| `admission.enabled` | `true` | Admission webhook. |
| `admission.mode` | `audit` | `audit` (warn) or `enforce` (deny). |
| `admission.level` | `baseline` | `baseline` or `restricted` Pod Security level. |
| `admission.allowedRegistries` | `[]` | Non-empty enables image-trust enforcement. |
| `admission.failurePolicy` | `Ignore` | `Ignore` keeps the cluster working if the webhook is down. |
| `sensor.enabled` | `true` | Runtime eBPF DaemonSet. |
| `sensor.image.repository` / `.tag` | `tigergate/tigergate-sensor` / `v1.1.0` | Pinned, not `latest` — see [Sensor image pinning](#sensor-image-pinning). |
| `sensor.ingestGrpcAddr` | `""` | Event-shipping address. Empty falls back to `backend.ingestGrpcAddr` (direct to the platform). Set to route events through the operator relay instead. |
| `sensor.privileged` / `.hostPID` | `true` / `true` | Required for eBPF and reading kernel state. |
| `sensor.mountKernelDebug` | `true` | Mounts `/sys/kernel/debug` and `/sys/fs/bpf`. |
| `sensor.enableK8sApi` | `true` | Attaches pod/namespace/label metadata to events. |
| `sensor.enableTracingPolicyCrd` | `false` | Leave off — this chart delivers tracing policies as files, not CRDs. |
| `sensor.enablePolicyFilter` | `true` | Required for runtime policies scoped by namespace, pod or container selector. |
| `sensor.disableKprobeMulti` | `false` | Set `true` only for sensor images 1.0.1 and earlier. |
| `sensor.export.enabled` | `true` | Required for events to actually ship; the export file feeds the gRPC sender. |
| `sensor.export.maxSizeMb` / `.maxBackups` | `10` / `3` | Bounds the export file's on-disk footprint. |
| `sensor.extraArgs` / `.extraEnv` | `[]` | Extra CLI flags / env vars for the sensor container. |
| `nodeScanner.enabled` | `false` | CIS host-scanner. On for self-hosted, off for managed clusters. |
| `nodeScanner.checkKubeletFiles` | `true` | CIS §4.1 kubelet file ownership/permission checks. |
| `remediation.enabled` | `false` | AI-fix preview/apply executor. |
| `remediation.pollInterval` | `15s` | How often the remediator polls for approved fixes. |
| `network.restrictEgress` | `true` | Adds a NetworkPolicy limiting egress to DNS, HTTPS and gRPC ingest. |
| `network.apiServerPorts` | `[6443, 8443, 16443]` | Extra ports allowed for API server access, alongside 443, by distro. |

See [values.yaml](values.yaml) for the complete, authoritative list.

### Sensor image pinning

`sensor.image.tag` is pinned to a specific version rather than `latest`
because the sensor is privileged and loads eBPF into every node's kernel; an
unpinned tag could let different nodes silently run different sensor
versions after a reboot or reschedule. Bump it deliberately when you upgrade.

## Common configurations

Audit everything, enforce nothing (default):
```bash
--set admission.mode=audit
```

Enforce admission and restrict images to trusted registries:
```bash
--set admission.mode=enforce \
--set admission.level=restricted \
--set 'admission.allowedRegistries={registry.tigergate.dev,docker.io/library}'
```

KSPM only, no runtime sensor:
```bash
--set sensor.enabled=false
```

Self-hosted cluster, add CIS control-plane and kubelet-file scanning:
```bash
--set nodeScanner.enabled=true
```

Enable AI-assisted remediation (read [Security model](#security-model) first):
```bash
--set remediation.enabled=true
```

Bring your own Secret instead of templating one from `backend.apiKey`:
```bash
kubectl -n tigergate-system create secret generic tg-key --from-literal=apiKey=tg_xxx
helm install tigergate ... --set backend.existingSecret=tg-key
```

## Non-Kubernetes hosts

For bare-metal or VM hosts that aren't part of a Kubernetes cluster, install
the runtime sensor directly instead of via this chart:

```bash
curl -fsSL https://download.tigergate.dev/tigergate-sensor/install.sh | sudo bash -s -- \
  --api-key tg_<org-api-key> --cluster my-host
```

## Security model

- **Operator, admission controller, node-scanner:** granted only read-only
  cluster RBAC (`get`/`list`/`watch`); nothing here mutates cluster state.
- **Remediator** (opt-in, off by default): a separate Deployment with its own
  ServiceAccount, not a second credential on the operator's pod — a
  Kubernetes pod has exactly one ServiceAccount identity, so real blast-radius
  isolation needs a separate pod. Its ClusterRole grants only `get`+`patch`
  on Deployments/StatefulSets/DaemonSets — never Pods, Secrets, RBAC objects,
  or Jobs/CronJobs. It only ever applies a patch that was already dry-run
  previewed through the full admission chain, including this chart's own
  admission controller.
- **Admission webhook:** served over a self-signed certificate generated at
  install/upgrade; the `caBundle` is wired from the same render so it always
  matches. System namespaces and the release namespace are never intercepted.
- **Sensor / node-scanner:** `privileged` and `hostPID` are required for eBPF
  and for reading host `/proc`. Both mount the host read-only — the sensor
  mounts only the kernel debug/bpf filesystems, and the node-scanner mounts
  host `/proc` and (when `checkKubeletFiles` is on) a handful of kubelet
  config paths.
- **Network policy:** when `network.restrictEgress` is true, a NetworkPolicy
  limits non-host-network pod egress to DNS, the backend over HTTPS, the
  gRPC ingest port, and the Kubernetes API server. Does not apply to the
  sensor when `sensor.hostNetwork=true`, since host-network pods bypass
  NetworkPolicy.

## Validate before installing

```bash
helm lint ./charts/tigergate \
  --set backend.apiKey=tg_test --set clusterName=test
helm template tigergate ./charts/tigergate \
  --set backend.apiKey=tg_test --set clusterName=test | kubectl apply --dry-run=client -f -
```
