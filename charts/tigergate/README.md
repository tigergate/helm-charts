# TigerGate Helm chart

A **single** chart that installs every TigerGate in-cluster agent:

| Component | Kind | What it does |
|---|---|---|
| **KSPM posture operator** (`controller`) | Deployment ×1 | Read-only cluster scan: posture, inventory, KIEM (RBAC), CIS/NSA controls, drift. Reports to the backend every `controller.scanIntervalPosture`. Also relays the runtime sensor fleet's policy sync (`relay.port`) — see the sensor row below. |
| **Admission controller** (`admission`) | Deployment + `ValidatingWebhookConfiguration` | Validates pods against Pod Security + image-trust + custom policy. Audit (warn) or enforce (deny). Admission events are **batched** to the backend. |
| **TigerGate runtime sensor** (`sensor`) | DaemonSet (privileged, eBPF) | Per-node runtime telemetry (process/file/network/privilege), container `tigergate-sensor`. Events stream **directly to the platform** by default (`sensor.ingestGrpcAddr` empty → `backend.ingestGrpcAddr`); policy sync (custom tracing policies + billing gate) routes through this cluster's `controller` relay instead when `TIGEREYE_OPERATOR_ADDR` is set via `sensor.extraArgs`, so every sensor on a node shares one cached fetch rather than each polling the platform independently. Either path lands at `runtime-consumer` upstream. |
| _CIS node host-scanner_ (`nodeScanner`, optional) | DaemonSet (privileged) | Per-node CIS control-plane/kubelet controls (arguments + §4.1 file ownership). Off by default; enable on self-hosted clusters. |
| _AI-remediation executor_ (`remediation`, optional) | Deployment ×1, own ServiceAccount | Previews (dry-run) and applies AI-generated fixes for KSPM findings against Deployments/StatefulSets/DaemonSets. **The only write-capable component in this chart** — off by default. |

All components share **one org API key** and **one cluster name**.

## Runs on every KSPM environment

This is the same chart for self-hosted and managed clusters — nothing about
the operator, admission controller, or remediator is environment-specific;
they're generic `client-go` against the Kubernetes API. The **one** setting
that should change based on where you're installing is `nodeScanner.enabled`:

| Environment | `nodeScanner.enabled` | Why |
|---|---|---|
| Self-hosted: **k3s**, **kubeadm**, bare-metal/VM control planes | `true` | The control plane runs as inspectable host processes — enabling this turns CIS §1.2/§1.3/§1.4 control-plane, §2 etcd, and §4.1/§4.2 kubelet controls from `NOT_ASSESSED` into real `PASS`/`FAIL`. |
| Managed: **EKS**, **AKS**, **GKE**, **OKE** | `false` (default) | The control plane isn't on a node you can read — this DaemonSet would run privileged for zero benefit. The operator already reports these controls as `NOT_ASSESSED` (never a false `FAIL`), so nothing is silently missed by leaving it off. |

Everything else — RBAC, admission enforcement, KIEM, remediation — behaves
identically across flavors. Set `clusterFlavor` values on the KSPM dashboard's
cluster registration (`vanilla`/`k3s`/`eks`/`aks`/`gke`/`oke`) purely for
labeling/CIS-context; it doesn't gate any chart behavior itself.

## Install

```bash
helm install tigergate oci://registry.tigergate.dev/charts/tigergate \
  --namespace tigergate-system --create-namespace \
  --set backend.apiKey=tg_<org-api-key> \
  --set clusterName=my-cluster
```

Self-hosted (k3s/kubeadm) — also turn on the node host-scanner:

```bash
helm install tigergate oci://registry.tigergate.dev/charts/tigergate \
  --namespace tigergate-system --create-namespace \
  --set backend.apiKey=tg_<org-api-key> \
  --set clusterName=my-cluster \
  --set nodeScanner.enabled=true
```

Or from a local checkout:

```bash
helm install tigergate ./tigergate-helm-charts/tigergate \
  -n tigergate-system --create-namespace \
  --set backend.apiKey=tg_xxx --set clusterName=my-cluster
```

The cluster **auto-registers** under your org on the operator's first report — no
separate registration step.

## Enable runtime event shipping and pod metadata

The sensor collects events as soon as it starts, but **ships nothing and
carries no pod metadata until these flags are set** — none are on by default:

```bash
helm upgrade tigergate oci://registry.tigergate.dev/charts/tigergate \
  --namespace tigergate-system --reuse-values \
  --set sensor.extraArgs[0]=--export-filename=/var/run/tigereye/tigereye-events.log \
  --set sensor.extraArgs[1]=--enable-k8s-api=true \
  --set sensor.extraArgs[2]=--enable-tracing-policy-crd=false
```

`--export-filename` enables the export pipeline event shipping is wired into
(the path itself is just a rotated local log). `--enable-k8s-api` adds
`pod.namespace`/`pod.name`/`container.name` to every event (the chart's
ClusterRole already grants the `pods`/`namespaces` `get`/`list`/`watch` this
needs). `--enable-tracing-policy-crd=false` disables Tetragon's native
CRD-based policy loading, which this chart doesn't use (policies come from
the dashboard via the heartbeat/`GetPolicy` path instead) and which otherwise
errors on missing cluster-scoped CRD RBAC once `--enable-k8s-api` is on.
`--set sensor.extraArgs[N]=...` replaces the whole list — always specify
every flag together, not just the one you're adding.

To route the sensor's **policy sync** specifically through the `controller`
relay instead of polling the platform directly (one egress point per node
rather than per sensor):

```bash
--set sensor.extraArgs[3]=--tigereye-operator-addr=RELEASE-tigergate-operator-relay.NAMESPACE.svc.cluster.local:8090
```

(there's no dedicated values.yaml key for this yet — set the
`TIGEREYE_OPERATOR_ADDR` env var directly via `sensor.extraEnv` if you'd
rather not hardcode the Service DNS name in `extraArgs`)

## Images & non-Kubernetes hosts

Images dual-publish to **Docker Hub** (default) and **GHCR** (mirror), built by
`tigergate`'s `.github/workflows/agents-release.yml`:
`tigergate/tigergate-kspm-agent` / `ghcr.io/tigergate/tigergate-kspm-agent`
(operator + admission-controller + node-scanner + remediator, one multi-binary
image) and `tigergate/tigergate-sensor` / `ghcr.io/tigergate/tigergate-sensor`
(built from the separate `tigereye` repo — see its own release workflow).
Override `image.repository` / `sensor.image.repository` for a private mirror.

For **bare-metal / VM hosts** (no Kubernetes), install the runtime sensor directly
instead of via this chart:

```bash
curl -fsSL https://download.tigergate.dev/tigereye-sensor/install.sh | sudo bash -s -- \
  --api-key tg_<org-api-key> --cluster my-host
```

See [deploy/tigereye-sensor/](../../tigergate/deploy/tigereye-sensor/) in the main repo.

## Common configurations

**Audit everything, enforce nothing (default, safest):**
```bash
--set admission.mode=audit
```

**Enforce admission + restrict images to trusted registries:**
```bash
--set admission.mode=enforce \
--set admission.level=restricted \
--set 'admission.allowedRegistries={registry.tigergate.dev,docker.io/library}'
```

**KSPM only (no runtime sensor):**
```bash
--set sensor.enabled=false
```

**Self-hosted cluster — add CIS control-plane + kubelet-file scanning:**
```bash
--set nodeScanner.enabled=true
```

**Enable AI-assisted remediation** (apply previewed fixes to live workloads —
read the [Security model](#security-model) section below first):
```bash
--set remediation.enabled=true
```

**Bring your own secret** (instead of templating one from `backend.apiKey`):
```bash
kubectl -n tigergate-system create secret generic tg-key --from-literal=apiKey=tg_xxx
helm install tigergate ... --set backend.existingSecret=tg-key
```

## Key values

| Key | Default | Notes |
|---|---|---|
| `backend.url` | `https://api.tigergate.dev` | Backend base URL (image-policy/custom-rules reads only) |
| `backend.apiKey` | `""` | Org `tg_` API key (required unless `existingSecret`) |
| `backend.existingSecret` | `""` | Pre-created Secret with key `apiKey` |
| `backend.ingestGrpcAddr` | `sensor.tigergate.dev:443` | gRPC address for scan reports/admission events/node controls — and the sensor's own event-shipping default (see `sensor.ingestGrpcAddr`) |
| `clusterName` | `""` | **Required.** Customer-chosen cluster name |
| `controller.enabled` | `true` | KSPM posture operator |
| `admission.enabled` / `.mode` | `true` / `audit` | `audit` \| `enforce` |
| `admission.failurePolicy` | `Ignore` | `Ignore` keeps cluster safe if webhook is down |
| `sensor.enabled` | `true` | TigerEye eBPF DaemonSet |
| `sensor.ingestGrpcAddr` | `""` | Sensor's **event**-shipping address. Empty → falls back to `backend.ingestGrpcAddr` (direct to platform). Set explicitly to route events through the `controller` relay instead. |
| `sensor.extraArgs` | `[]` | Extra CLI flags passed to the sensor binary — **required** for event shipping/pod metadata to work at all, see [Enable runtime event shipping](#enable-runtime-event-shipping-and-pod-metadata) above. |
| `sensor.privileged` / `.hostPID` | `true` / `true` | eBPF needs kernel access |
| `sensor.image.repository` | `tigergate/tigergate-sensor` | Override for your registry |
| `relay.port` | `8090` | Port the `controller`'s embedded relay listens on — forwards sensor events when `sensor.ingestGrpcAddr` is set to it, and always serves sensor **policy sync** when `TIGEREYE_OPERATOR_ADDR` targets it |
| `nodeScanner.enabled` | `false` | CIS host-scanner — **on** for self-hosted, **off** for managed (EKS/AKS/GKE/OKE) |
| `nodeScanner.checkKubeletFiles` | `true` | CIS §4.1 kubelet file ownership/permissions (only meaningful when nodeScanner is on) |
| `remediation.enabled` | `false` | AI-fix preview/apply executor — the only write-capable component |
| `network.restrictEgress` | `true` | NetworkPolicy: DNS + 443 + 50051 only |

See [values.yaml](values.yaml) for the full list.

## Security model

- **Operator / admission-controller / node-scanner:** the only cluster RBAC
  granted is **read-only** (`get`/`list`/`watch`); nothing here mutates
  cluster state.
- **Remediator** (opt-in, off by default): a genuinely separate Deployment
  with its **own** ServiceAccount — not a second credential bolted onto the
  operator's pod (a Kubernetes pod has exactly one ServiceAccount identity,
  so real read/write blast-radius isolation requires a separate pod). Its
  ClusterRole grants **only** `get`+`patch` on Deployments/StatefulSets/
  DaemonSets — never Pods, Secrets, RBAC objects, or Jobs/CronJobs (whose pod
  templates are immutable or affect only future runs). It only ever applies a
  patch that was already dry-run previewed through the full admission chain,
  including this chart's own admission-controller.
- **Admission webhook:** served over a self-signed cert generated at install/upgrade
  (`genSignedCert`); the `caBundle` is wired in the same render so they stay
  consistent. System namespaces and the release namespace are never intercepted.
- **Sensor / node-scanner:** privileged + `hostPID` are required for eBPF / reading
  host `/proc`. Root FS is read-only; the sensor mounts only the kernel
  debug/bpf fs; the node-scanner mounts host `/proc` and (when
  `checkKubeletFiles` is on) 3 kubelet-config paths, all **read-only**.

## Validate before installing

```bash
helm lint ./tigergate-helm-charts/tigergate \
  --set backend.apiKey=tg_test --set clusterName=test
helm template tigergate ./tigergate-helm-charts/tigergate \
  --set backend.apiKey=tg_test --set clusterName=test | kubectl apply --dry-run=client -f -
```
