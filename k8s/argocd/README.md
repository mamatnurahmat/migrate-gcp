# ⎈ ArgoCD — Setup Guide

> Deploy ArgoCD ke GKE cluster menggunakan **Kustomize**, dengan service **NodePort** dan semua pod dijadwalkan di **node pool `general`**.

---

## 📁 Struktur File

```
k8s/argocd/
├── kustomization.yaml            # Kustomize root (pull manifest + patches)
├── namespace.yaml                # Namespace: argocd
├── argocd-server-nodeport.yaml   # Patch: ClusterIP → NodePort (30080/30443)
└── patch-node-general.yaml       # Patch: nodeSelector role=general
```

---

## 🔧 Prerequisite

- `kubectl` sudah terkoneksi ke GKE cluster (`make connect`)
- Node pool `general` sudah running (`kubectl get nodes`)

---

## 🚀 Deploy ArgoCD

### Opsi A — Via Makefile (dari root project)

```bash
cd /home/mamat/migrate-gcp
make argocd
```

### Opsi B — Manual dengan kubectl

```bash
# Apply semua resource via Kustomize (--server-side wajib untuk ArgoCD CRDs)
kubectl apply -k k8s/argocd/ --server-side --force-conflicts

# Tunggu semua pod running
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

# Cek semua pod ArgoCD (pastikan di node pool general)
kubectl get pods -n argocd -o wide
```

**Output yang diharapkan** (semua pod ada di node `general`):
```
NAME                                          READY  STATUS   NODE
argocd-application-controller-0               1/1    Running  gke-...-general-xxx
argocd-applicationset-controller-xxx          1/1    Running  gke-...-general-xxx
argocd-dex-server-xxx                         1/1    Running  gke-...-general-xxx
argocd-notifications-controller-xxx           1/1    Running  gke-...-general-xxx
argocd-redis-xxx                              1/1    Running  gke-...-general-xxx
argocd-repo-server-xxx                        1/1    Running  gke-...-general-xxx
argocd-server-xxx                             1/1    Running  gke-...-general-xxx
```

---

## 🔑 Ambil Initial Admin Password

```bash
# Via Makefile
make argocd-pass

# Atau manual
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

**Login credentials:**

| Field | Value |
|---|---|
| **Username** | `admin` |
| **Password** | hasil perintah di atas |

---

## 🌐 Cara Akses ArgoCD UI

Ada **2 cara** akses — pilih sesuai kebutuhan:

---

### 🥇 Cara 1 — Port-Forward (Recommended untuk dev, tanpa firewall)

Paling aman dan mudah. Tidak perlu membuka port ke internet.

```bash
kubectl port-forward svc/argocd-server -n argocd 8443:443
```

Lalu buka di browser: **`https://localhost:8443`**

> Jalankan di terminal terpisah dan biarkan berjalan selama kamu butuh akses.
> Tekan `Ctrl+C` untuk menghentikan.

---

### 🌍 Cara 2 — NodePort via External IP (Akses permanen dari internet)

#### Step 1: Buka Firewall GCP

```bash
gcloud compute firewall-rules create allow-argocd-nodeport \
  --allow=tcp:30443,tcp:30080 \
  --source-ranges=0.0.0.0/0 \
  --network=gke-vpc \
  --project=project-065701e7-213d-458b-a83 \
  --description="Allow ArgoCD NodePort"
```

#### Step 2: Dapatkan External IP Node General

```bash
kubectl get nodes -o wide | grep general
```

| Node | External IP |
|---|---|
| `gke-gke-main-general-...-9f8z` | `34.101.61.158` |
| `gke-gke-main-general-...-ml4q` | `34.101.230.244` |

#### Step 3: Buka di Browser

```
https://34.101.61.158:30443
```
atau
```
https://34.101.230.244:30443
```

> ⚠️ Browser akan tampilkan peringatan SSL (self-signed cert).
> Klik **Advanced → Proceed anyway**.

---

### 🔒 Matikan Firewall Setelah Selesai (Recommended)

Setelah selesai menggunakan akses NodePort, **nonaktifkan firewall** untuk menutup exposure ke internet:

#### Disable sementara (bisa diaktifkan lagi)

```bash
gcloud compute firewall-rules update allow-argocd-nodeport \
  --disabled \
  --project=project-065701e7-213d-458b-a83
```

#### Aktifkan kembali

```bash
gcloud compute firewall-rules update allow-argocd-nodeport \
  --no-disabled \
  --project=project-065701e7-213d-458b-a83
```

#### Hapus permanen

```bash
gcloud compute firewall-rules delete allow-argocd-nodeport \
  --project=project-065701e7-213d-458b-a83
```

---

## 🔑 Login via ArgoCD CLI (opsional)

```bash
# Install argocd CLI (CachyOS/Arch)
yay -S argocd

# Login (ganti IP sesuai node general kamu)
argocd login 34.101.61.158:30443 \
  --username admin \
  --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) \
  --insecure

# Ganti password setelah login pertama (WAJIB)
argocd account update-password

# Cek status cluster
argocd cluster list
```

---

## ✅ Verifikasi Node Scheduling

```bash
# Pastikan semua pod ada di node general
kubectl get pods -n argocd -o wide

# Cek nodeSelector terpasang di argocd-server
kubectl get deploy argocd-server -n argocd \
  -o jsonpath='{.spec.template.spec.nodeSelector}' | jq
# Expected output: { "role": "general" }
```

---

## 📋 NodePort Summary

| Service | NodePort | Protokol | Keterangan |
|---|---|---|---|
| argocd-server | `30080` | HTTP | Redirect ke HTTPS |
| argocd-server | `30443` | HTTPS | **ArgoCD UI & API** |

---

## 🧹 Uninstall ArgoCD

```bash
kubectl delete -k k8s/argocd/
```

---

## 📋 Quick Makefile Reference

```bash
make argocd       # Deploy ArgoCD ke cluster
make argocd-pass  # Tampilkan initial admin password
make argocd-url   # Tampilkan URL akses via NodePort
```
