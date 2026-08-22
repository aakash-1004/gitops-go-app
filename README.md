# Go Web App — End-to-End GitOps Pipeline

A production-style GitOps delivery pipeline for a Go web application, deployed to **AWS EKS**, with **ArgoCD** continuously reconciling cluster state against Git, automatic HTTPS, and pod-level high availability.

**Stack:** Go · Docker (multi-stage, distroless) · AWS EKS · Helm · ArgoCD · GitHub Actions · Docker Hub · ingress-nginx · cert-manager · Let's Encrypt

**Live demo:** https://gitops-go-app.duckdns.org

---

## What this demonstrates

- **Multi-stage distroless Docker build** — small, attack-surface-minimal image (no shell, no package manager in the final layer).
- **True GitOps loop** — Git is the single source of truth; nothing is deployed by hand.
- **Self-healing** — manual drift (e.g. `kubectl scale`) is automatically reverted to the Git-declared state.
- **Pod-level high availability** — topology spread constraints guarantee replicas land on separate nodes.
- **Automatic HTTPS** — certificates are issued and renewed by cert-manager with zero manual intervention.

---

## Architecture

```
  Developer push
        │
        ▼
  GitHub Actions ── test ──▶ build image ──▶ tag by commit hash ──▶ push to Docker Hub
        │
        └──▶ bump image tag in Helm values.yaml ──▶ commit back to repo
                                                          │
                                                          ▼
                                                   ArgoCD (watching repo)
                                                          │
                                                   detects new tag ──▶ auto-sync
                                                          │
                                                          ▼
                                            AWS EKS — 2 nodes, 1 pod per node
                                                          │
                                            ingress-nginx (AWS NLB) ── HTTPS (cert-manager)
```

## Pipeline flow

1. Push to `main` (touching `app/` or `Dockerfile`) triggers GitHub Actions.
2. Workflow builds the Docker image and tags it with the **short commit hash** — every running image maps to an exact commit.
3. Image is pushed to Docker Hub.
4. The workflow updates the image tag in the Helm chart's `values.yaml` and commits that change back to the repo.
5. ArgoCD, already watching the repo, detects the change and auto-syncs it to the cluster.
6. New pods roll out — **zero manual `kubectl` or `helm` commands** after the initial push.

## High availability

A `topologySpreadConstraints` rule on the Deployment forces the scheduler to spread the 2 replicas across the 2 EKS nodes (`maxSkew: 1`, `whenUnsatisfiable: DoNotSchedule`). Verified in the running cluster — each replica lands on a different node, so a single node failure doesn't take the app down.

## HTTPS

`cert-manager` watches the Ingress for a `cluster-issuer` annotation, solves an ACME HTTP-01 challenge through the existing ingress-nginx controller, and stores the issued certificate as a Kubernetes Secret that ingress-nginx uses to terminate TLS. Renewal is automatic — no cron jobs, no manual certbot runs.

## Engineering decisions & problems solved

- **`paths-ignore`-equivalent path filter on the workflow trigger** — the pipeline commits back to the same repo it watches (`values.yaml`). Scoping the trigger to `app/**` and `Dockerfile` prevents the pipeline from re-triggering on its own commits.
- **Commit-hash image tags over `latest`** — gives direct, auditable traceability from a running container back to source, and guarantees Helm's `values.yaml` actually changes on every release (a static `latest` tag never produces a Git diff, so ArgoCD would have nothing to sync).
- **`/health` endpoint designed in from the start** — liveness/readiness probes hit this route directly, avoiding the crash-loop that comes from probing a path the app doesn't serve.
- **Topology spread over relying on scheduler defaults** — the default scheduler will happily stack all replicas on one node; this is an explicit constraint, not an assumption.

## Verified end-to-end

Edited application code → pushed → GitHub Actions built and pushed a new image, bumped the tag → ArgoCD detected the commit and synced → new content live in the browser, with no manual deployment step.

Self-healing proven by scaling the deployment to 5 replicas manually — ArgoCD reverted the drift and terminated the extra pods before they even finished starting, restoring the Git-declared `replicaCount: 2`.
