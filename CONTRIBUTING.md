# Contributing

## Local dev loop

```bash
helm lint charts/tigergate

helm template test charts/tigergate \
  --namespace tigergate-system \
  --set backend.apiKey=tg_test --set clusterName=test-cluster

# validate the rendered manifests against the real K8s API schema
helm template test charts/tigergate --set backend.apiKey=tg_test --set clusterName=test-cluster \
  | kubeconform -strict -summary -kubernetes-version 1.29.0
```

`lint-test.yml` runs this same trio against three value sets (minimal,
self-hosted-with-everything-on, managed-cluster) on every PR that touches
`charts/**` — reproduce a CI failure locally with the exact `--set` flags in
that workflow file.

## Adding a chart

One chart per directory under `charts/`, following `charts/tigergate`'s
layout: `Chart.yaml`, `values.yaml`, `templates/`, `README.md`. Add it to the
table in the top-level `README.md` and to `lint-test.yml`'s `matrix.chart`
list.

## Testing against a real cluster

```bash
helm install tigergate charts/tigergate \
  --namespace tigergate-system --create-namespace \
  --set backend.apiKey=tg_<org-api-key> --set clusterName=dev

# after edits, without a full reinstall:
helm upgrade tigergate charts/tigergate --namespace tigergate-system --reuse-values
```

For a k3s/kind cluster with a locally-built image (not yet pushed anywhere),
`docker save <image> | sudo k3s ctr images import -` and
`--set image.pullPolicy=IfNotPresent` (or `Never`) so the cluster uses your
local image instead of pulling.

## Releasing

See the top-level `README.md`'s "Releasing a chart" section.
