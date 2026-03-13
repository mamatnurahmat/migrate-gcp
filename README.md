# ⎈ GKE Jakarta — Declarative Setup Guide

> Panduan lengkap membangun **GKE Cluster** dengan 3 Node Group di **Jakarta (asia-southeast2)** menggunakan Terraform + kubectl.

---

## 📐 Arsitektur

```
GCP Project (asia-southeast2 — Jakarta)
└── VPC: gke-vpc
    └── Subnet: gke-subnet (10.0.0.0/16)
    └── Cloud NAT (akses internet untuk node)
    └── GKE Cluster: gke-main  [Zonal: asia-southeast2-a]
        ├── Node Pool: general  → e2-small · Spot · label: role=general
        ├── Node Pool: front    → e2-small · Spot · label+taint: role=front
        └── Node Pool: back     → e2-small · Spot · label+taint: role=back
```

### Struktur Direktori

```
migrate-gcp/
├── terraform/
│   ├── main.tf           # VPC, GKE Cluster, 3 Node Pools
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   └── terraform.tfvars  # ← Edit PROJECT_ID di sini
├── k8s/
│   ├── namespaces/ns.yaml
│   ├── dummy-front/deploy.yaml   # nginx:alpine → node pool front
│   └── dummy-back/deploy.yaml    # httpbin      → node pool back
└── Makefile
```

---

## ✅ Prerequisite

> **Distro**: CachyOS (Arch-based) — menggunakan `pacman` + `yay` (AUR helper)

| Tool | Min. Version | Cek |
|------|-------------|-----|
| [gcloud CLI](https://cloud.google.com/sdk/docs/install) | latest | `gcloud version` |
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.7 | `terraform version` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | >= 1.28 | `kubectl version --client` |
| [yay](https://github.com/Jguer/yay) | latest | `yay --version` |
| Akun GCP | Billing aktif | — |

---

## 🚀 Step-by-Step

### STEP 0 — Pastikan yay (AUR Helper) Terinstall

```bash
# Cek apakah yay sudah ada
yay --version

# Jika belum, install via pacman (CachyOS biasanya sudah include)
sudo pacman -S --needed yay
```

---

### STEP 1 — Install Tools

#### 1a. Google Cloud SDK

```bash
# Install dari AUR
yay -S google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin

# Verifikasi
gcloud version
```

#### 1b. Terraform (via tfenv dari AUR)

```bash
# Install tfenv dari AUR (version manager untuk terraform)
yay -S tfenv

# Install & aktifkan Terraform 1.7.5
tfenv install 1.7.5
tfenv use 1.7.5

# Verifikasi
terraform version
```

> **Alternatif**: Install langsung dari community repo (versi terbaru):
> ```bash
> sudo pacman -S terraform
> ```

#### 1c. kubectl

```bash
# Install dari Arch community repo (official)
sudo pacman -S kubectl

# Verifikasi
kubectl version --client
```

#### 1d. kubectx & kubens (opsional tapi recommended)

```bash
sudo pacman -S kubectx
```

---

### STEP 2 — Setup GCP Project

#### 2a. Login ke GCP

```bash
# Login browser interaktif
gcloud auth login

# Untuk Terraform (Application Default Credentials)
gcloud auth application-default login
```

#### 2b. Set Project & Region Default
<!-- project-065701e7-213d-458b-a83 -->
```bash
export PROJECT_ID="project-065701e7-213d-458b-a83"   # ← Ganti dengan project ID kamu

gcloud config set project $PROJECT_ID
gcloud config set compute/region asia-southeast2
gcloud config set compute/zone asia-southeast2-a

# Verifikasi
gcloud config list
```

#### 2c. Buat GCP Project (jika belum ada)

```bash
gcloud projects create $PROJECT_ID --name="Migrate GCP Dev"

# Hubungkan billing account
BILLING_ID=$(gcloud billing accounts list --format='value(ACCOUNT_ID)' --limit=1)
gcloud billing projects link $PROJECT_ID --billing-account=$BILLING_ID
```

#### 2d. Enable APIs yang diperlukan

```bash
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project=$PROJECT_ID

# Cek status API
gcloud services list --enabled --project=$PROJECT_ID
```

---

### STEP 3 — Buat Service Account untuk Terraform

```bash
# export SA_NAME="terraform-sa"
# export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export SA_EMAIL="terraform-sa@project-065701e7-213d-458b-a83.iam.gserviceaccount.com"

# Buat Service Account
gcloud iam service-accounts create $SA_NAME \
  --display-name="Terraform Service Account" \
  --project=$PROJECT_ID

# Assign roles minimal yang diperlukan (Syntax Fish shell)
for ROLE in \
  roles/container.admin \
  roles/compute.networkAdmin \
  roles/iam.serviceAccountUser \
  roles/resourcemanager.projectIamAdmin

  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="$ROLE"
end

# Download credentials ke folder terraform/
gcloud iam service-accounts keys create \
  ./terraform/credentials.json \
  --iam-account=$SA_EMAIL

echo "✅ credentials.json tersimpan di terraform/credentials.json"
```

> **⚠️ PENTING**: `credentials.json` sudah masuk `.gitignore`. Jangan pernah di-commit ke Git!

---

### STEP 4 — Sesuaikan Konfigurasi

Edit file `terraform/terraform.tfvars` dan ganti `project_id`:

```hcl
project_id = "migrate-gcp-dev"   # ← Ganti dengan GCP Project ID kamu
region     = "asia-southeast2"   # Jakarta — sudah benar
zone       = "asia-southeast2-a" # Zone Jakarta A — sudah benar
```

---

### STEP 5 — Terraform Init & Plan

```bash
cd /home/mamat/migrate-gcp

# Download Terraform providers (google ~> 5.0)
make init
# atau: cd terraform && terraform init

# Preview semua resource yang akan dibuat
make plan
# atau: cd terraform && terraform plan -var-file=terraform.tfvars
```

**Output yang diharapkan dari `plan`:**
```
Plan: 7 to add, 0 to change, 0 to destroy.

  + google_compute_network.vpc
  + google_compute_subnetwork.subnet
  + google_compute_router.router
  + google_compute_router_nat.nat
  + google_compute_firewall.internal
  + google_container_cluster.main
  + google_container_node_pool.general
  + google_container_node_pool.front
  + google_container_node_pool.back
```

---

### STEP 6 — Apply Infrastruktur

```bash
make apply
# atau: cd terraform && terraform apply -var-file=terraform.tfvars -auto-approve
```

> ⏱️ Estimasi waktu: **10–15 menit** (GKE cluster provisioning memerlukan waktu)

**Cek output setelah selesai:**
```bash
make output
# Akan menampilkan cluster_name, get_credentials_cmd, dsb.
```

---

### STEP 7 — Connect kubectl ke GKE

```bash
make connect
# atau:
gcloud container clusters get-credentials gke-main \
  --zone asia-southeast2-a \
  --project $PROJECT_ID

# Verifikasi koneksi
kubectl get nodes -o wide
```

**Output yang diharapkan (3 node dari 3 node pool berbeda):**
```
NAME                                    STATUS   ROLES    AGE   VERSION
gke-gke-main-front-xxxxx    Ready    <none>   3m    v1.28.x
gke-gke-main-back-xxxxx     Ready    <none>   3m    v1.28.x
gke-gke-main-general-xxxxx  Ready    <none>   3m    v1.28.x
```

**Verifikasi label & taint node:**
```bash
# Lihat label semua node
kubectl get nodes --show-labels

# Lihat taint di node front dan back
kubectl describe nodes | grep -A3 "Taints:"
```

---

### STEP 8 — Deploy Dummy Apps

```bash
make deploy
# Equivalent dengan:
# kubectl apply -f k8s/namespaces/
# kubectl apply -f k8s/dummy-front/
# kubectl apply -f k8s/dummy-back/
```

**Monitor deployment:**
```bash
# Tunggu semua pod running
kubectl rollout status deployment/dummy-front -n front
kubectl rollout status deployment/dummy-back -n back

# Cek semua pod (pastikan ada di node yang tepat)
make status
```

---

### STEP 9 — Verifikasi & Test

#### 9a. Pastikan Pod di Node yang Benar

```bash
kubectl get pods -A -o wide
```

Output yang diharapkan:
```
NAMESPACE  NAME              READY  STATUS   NODE
front      dummy-front-xxx   1/1    Running  gke-gke-main-front-xxx   ✅
back       dummy-back-xxx    1/1    Running  gke-gke-main-back-xxx    ✅
```

#### 9b. Akses Dummy Frontend (External IP)

```bash
# Tunggu external IP dari LoadBalancer (bisa 1-2 menit)
kubectl get svc dummy-front-svc -n front --watch

# Setelah dapat IP, akses via browser atau curl:
FRONTEND_IP=$(kubectl get svc dummy-front-svc -n front \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl http://$FRONTEND_IP
# Harus menampilkan halaman HTML dummy frontend
```

#### 9c. Test Backend dari dalam Cluster

```bash
# Masuk ke pod frontend untuk test akses ke backend
kubectl exec -it -n front \
  $(kubectl get pod -n front -l app=dummy-front -o jsonpath='{.items[0].metadata.name}') \
  -- sh

# Di dalam pod:
wget -qO- http://dummy-back-svc.back.svc.cluster.local/get
# Harus mengembalikan JSON dari httpbin
```

---

## 🧹 Cleanup

```bash
# Hapus K8s apps saja (infrastruktur tetap jalan)
make clean

# Hapus SEMUA infrastruktur GCP (⚠️ tidak bisa di-undo!)
make destroy
```

---

## 💡 Tips & Troubleshooting

### Pod `Pending` tidak ter-schedule?
```bash
# Cek event pod
kubectl describe pod <pod-name> -n <namespace>
# Paling sering: nodeSelector tidak cocok, atau taint tidak di-tolerate
```

### Node pool belum siap?
```bash
gcloud container node-pools list --cluster=gke-main --zone=asia-southeast2-a
```

### Lihat semua resource Terraform yang terbuat:
```bash
cd terraform && terraform state list
```

### Reset kubectl context:
```bash
kubectl config get-contexts
kubectl config use-context <nama-context>
```

---

## 💰 Estimasi Biaya (Jakarta / asia-southeast2)

> Berdasarkan setup **aktual yang sedang berjalan** — region Jakarta (`asia-southeast2`), semua node menggunakan **Spot VM** (preemptible).

---

### 📊 State Saat Ini (4 Node Aktif)

GKE autoscaler men-scale `general` ke 2 node karena ArgoCD + workload lain berjalan di sana.

| Resource | Detail | Harga/jam | Harian | Bulanan |
|---|---|---|---|---|
| **GKE Cluster** | Zonal — 1 cluster gratis | **$0** | **$0** | **$0** |
| **Node: general ×2** | e2-small Spot | $0.006/jam × 2 | ~$0.29 | ~$8.70 |
| **Node: front ×1** | e2-small Spot | $0.006/jam | ~$0.14 | ~$4.35 |
| **Node: back ×1** | e2-small Spot | $0.006/jam | ~$0.14 | ~$4.35 |
| **Boot Disk ×4** | 20 GB pd-standard | $0.048/GB/bln | ~$0.13 | ~$3.84 |
| **Cloud NAT** | 1 gateway | $0.045/jam | ~$1.08 | ~$32.40 |
| **LoadBalancer** | dummy-front (Network LB) | $0.025/jam | ~$0.60 | ~$18.00 |
| **Network Egress** | Estimasi minimal | — | ~$0.07 | ~$2.00 |
| | | | | |
| **Total (Saat Ini)** | | | **~$2.45/hari** | **~$73.64/bln** |

> ⚠️ **Cloud NAT** ($32/bln) dan **LoadBalancer** ($18/bln) adalah komponen paling mahal dalam setup ini.

---

### 📉 Skenario Minimum (3 Node, Tanpa LB & NAT)

Jika `dummy-front` service diubah ke `ClusterIP` (tanpa LoadBalancer) dan Cloud NAT dihapus:

| Resource | Harian | Bulanan |
|---|---|---|
| Node general ×1 + front ×1 + back ×1 (Spot) | ~$0.43 | ~$13.05 |
| Boot Disk ×3 (20 GB pd-std) | ~$0.10 | ~$2.88 |
| Network egress | ~$0.03 | ~$1.00 |
| **Total minimum** | **~$0.56/hari** | **~$16.93/bln** |

---

### 📈 Skenario Maximum (Autoscaling penuh, semua 2 node)

Jika 3 node pool masing-masing scale ke max (2 node):

| Resource | Harian | Bulanan |
|---|---|---|
| Node ×6 e2-small Spot | ~$0.86 | ~$26.10 |
| Boot Disk ×6 | ~$0.19 | ~$5.76 |
| Cloud NAT | ~$1.08 | ~$32.40 |
| LoadBalancer | ~$0.60 | ~$18.00 |
| Network egress | ~$0.10 | ~$3.00 |
| **Total maximum** | **~$2.83/hari** | **~$85.26/bln** |

---

### 💡 Tips Hemat Biaya

#### 1. Hapus LoadBalancer dummy-front saat tidak dipakai

```bash
# Ganti type menjadi ClusterIP (hemat ~$18/bln)
kubectl patch svc dummy-front-svc -n front \
  -p '{"spec": {"type": "ClusterIP"}}'
```

#### 2. Hapus Cloud NAT jika node sudah punya External IP

Node GKE kamu sudah punya External IP (`34.101.x.x`), sehingga Cloud NAT sebenarnya tidak wajib. Hapus melalui Terraform:

```hcl
# Comment/hapus resource ini di terraform/main.tf
# resource "google_compute_router_nat" "nat" { ... }
# resource "google_compute_router" "router" { ... }
```

Lalu:
```bash
make plan && make apply  # hemat ~$32/bln
```

#### 3. Scale down node pool ke 0 saat tidak dipakai

```bash
# Scale front & back ke 0 saat jam kerja selesai (hemat ~$8.70/bln)
gcloud container clusters resize gke-main \
  --node-pool=front --num-nodes=0 \
  --zone=asia-southeast2-a \
  --project=project-065701e7-213d-458b-a83

gcloud container clusters resize gke-main \
  --node-pool=back --num-nodes=0 \
  --zone=asia-southeast2-a \
  --project=project-065701e7-213d-458b-a83
```

#### 4. Bandingkan On-demand vs Spot

| Tipe | e2-small/jam | 4 node/bln |
|---|---|---|
| On-demand | $0.02010 | ~$58 |
| **Spot (current)** | **$0.00603** | **~$17** |
| **Hemat** | | **~$41/bln (71%)** |

---

### 🔢 Ringkasan Cepat

| Skenario | Harian | Bulanan |
|---|---|---|
| Minimum (3 node, no LB, no NAT) | ~$0.56 | ~$17 |
| **Saat ini (4 node, dengan NAT & LB)** | **~$2.45** | **~$74** |
| Maximum (6 node, semua aktif) | ~$2.83 | ~$85 |

> Gunakan [GCP Pricing Calculator](https://cloud.google.com/products/calculator) untuk estimasi yang lebih presisi sesuai usage pattern kamu.


---

## ⚡ Node Scaling — Hemat Biaya

Scale node pool ke 0 saat tidak dipakai, aktifkan kembali saat diperlukan.

### Scale DOWN — Matikan semua node (hemat maks)

```bash
make scale-down
```

Scale **general + front + back** ke 0 node sekaligus. Berguna saat mau istirahat / malam hari.

> ⚠️ Pod yang berjalan (termasuk ArgoCD) akan **evicted**. Data persistent tidak hilang, tapi pod perlu di-reschedule saat scale-up.

### Scale UP — Aktifkan kembali semua node

```bash
make scale-up
```

Scale semua pool kembali ke **1 node**. Tunggu ~2-3 menit sampai node `Ready`, lalu cek status:

```bash
make node-status   # Lihat jumlah node per pool
make status        # Lihat semua pods
```

### Scale Pool Tertentu (Satu Pool)

```bash
# Scale down hanya front
make scale-down-pool POOL=front

# Scale down hanya back
make scale-down-pool POOL=back

# Aktifkan kembali front
make scale-up-pool POOL=front

# Aktifkan kembali back
make scale-up-pool POOL=back
```

### Lihat Status Node Saat Ini

```bash
make node-status
```

Output contoh:
```
=== NODE STATUS ===
      2 role=general
      1 role=front
      1 role=back

NAME                                   STATUS   ROLES    AGE   EXTERNAL-IP
gke-gke-main-general-...-9f8z          Ready    <none>   20m   34.101.61.158
gke-gke-main-general-...-ml4q          Ready    <none>   18m   34.101.230.244
gke-gke-main-front-...-dws0            Ready    <none>   20m   34.101.203.0
gke-gke-main-back-...-dfb0             Ready    <none>   20m   34.101.147.50
```

### Estimasi Penghematan dari Scaling

| Scenario | Biaya/hari | Biaya/bln |
|---|---|---|
| Semua UP 24 jam | ~$2.45 | ~$74 |
| Scale DOWN 16 jam/hari (kerja 8 jam) | ~$0.82 | ~$25 |
| Scale DOWN sepenuhnya (weekend) | $0 | hemat ~$16/minggu |

---

## 📋 Quick Reference — Makefile

```bash
# ─── Infrastructure ───────────────────────────────
make help              # Lihat semua perintah
make init              # Terraform init
make plan              # Preview infrastruktur
make apply             # Buat/update infrastruktur
make destroy           # ⚠️  Hapus semua infra
make output            # Lihat output Terraform

# ─── Cluster ──────────────────────────────────────
make connect           # Setup kubectl ke GKE
make status            # Status nodes & pods
make node-status       # Jumlah node per pool

# ─── Node Scaling ─────────────────────────────────
make scale-down                  # Matikan SEMUA node pool (ke 0)
make scale-up                    # Aktifkan SEMUA node pool (ke 1)
make scale-down-pool POOL=front  # Matikan satu pool tertentu
make scale-up-pool   POOL=front  # Aktifkan satu pool tertentu

# ─── Kubernetes Apps ──────────────────────────────
make deploy            # Deploy dummy front & back
make clean             # Hapus dummy apps
make logs-front        # Logs dummy-front
make logs-back         # Logs dummy-back

# ─── ArgoCD ───────────────────────────────────────
make argocd            # Deploy ArgoCD via Kustomize
make argocd-pass       # Tampilkan initial admin password
make argocd-url        # Tampilkan URL akses NodePort

# ─── Full Setup ───────────────────────────────────
make setup             # init → apply → connect → deploy (sekaligus)
```
