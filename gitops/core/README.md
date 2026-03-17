# 🌐 GitOps Core — Gateway API Setup

> Setup **NGINX Gateway Fabric** sebagai Gateway API implementation di GKE menggunakan **LoadBalancer** (Google Cloud L4 Network Load Balancer) dan dikelola via **ArgoCD (GitOps)**.

---

## 🏗️ Arsitektur

```
Internet
    ↓
Google Cloud L4 Network Load Balancer  (External IP permanen)
    ↓
NGINX Gateway Fabric Service (LoadBalancer)
    ↓
NGINX Gateway Pod (node pool: general)
    ↓ routing berdasarkan HTTPRoute
    ├── /        → dummy-front-svc (namespace: front, node pool: front)
    └── /api/*   → dummy-back-svc  (namespace: back,  node pool: back)
```

```
GitOps Flow:

git push → ArgoCD detects → kubectl apply → GKE reconciles LB
```

---

## 📁 Struktur File

```
migrate-gcp/
├── gitops/
│   ├── root-app.yaml                    # App of Apps — apply SEKALI saja
│   └── core/
│       ├── README.md                    # ← file ini
│       ├── gateway-crds-app.yaml        # Gateway API CRDs v1.2.0
│       ├── gateway-app.yaml             # NGINX Gateway Fabric (LoadBalancer)
│       ├── gateway-config-app.yaml      # Gateway + HTTPRoute resources
│       └── cert-manager-app.yaml        # cert-manager (TLS)
└── k8s/
    └── gateway/
        ├── kustomization.yaml
        ├── gateway.yaml                 # Gateway resource (HTTP listener)
        ├── httproute-front.yaml         # Route / → front
        └── httproute-back.yaml          # Route /api/* → back
```

---

## ✅ Requirements

| Komponen | Versi | Keterangan |
|---|---|---|
| **GKE** | >= 1.28 | Cluster yang sudah jalan |
| **ArgoCD** | >= 2.9 | Sudah terdeploy di namespace `argocd` |
| **Gateway API CRDs** | v1.2.0 | Di-manage via ArgoCD |
| **NGINX Gateway Fabric** | 1.5.1 | Di-manage via ArgoCD |
| **cert-manager** | v1.14.4 | Untuk TLS (opsional awal) |
| **kubectl** | >= 1.28 | Terkoneksi ke cluster |
| **Git repo** | public/private | ArgoCD harus bisa akses |

### Node Pool Requirements

| Node Pool | Label | Taint | Fungsi |
|---|---|---|---|
| `general` | `role=general` | ❌ None | NGINX Gateway Fabric pods |
| `front` | `role=front` | ✅ `role=front:NoSchedule` | Frontend pods |
| `back` | `role=back` | ✅ `role=back:NoSchedule` | Backend pods |

---

## 🚀 Step-by-Step Setup

### STEP 1 — Pastikan ArgoCD Sudah Jalan

```bash
kubectl get pods -n argocd
# Semua pod harus Running

# Cek koneksi ArgoCD ke git repo (jika private, setup SSH key atau token dulu)
kubectl get applications -n argocd
```

### STEP 2 — Daftarkan Git Repo ke ArgoCD (jika private)

Jika repo kamu private, daftarkan dulu via ArgoCD UI:

```
ArgoCD UI → Settings → Repositories → + Connect Repo

URL    : https://github.com/mamatnurahmat/migrate-gcp.git
Type   : HTTPS
Token  : <GitHub Personal Access Token>
```

Atau via CLI:
```bash
argocd repo add https://github.com/mamatnurahmat/migrate-gcp.git \
  --username mamatnurahmat \
  --password <GitHub_PAT>
```

### STEP 3 — Apply Root App (App of Apps)

Ini adalah **satu-satunya perintah manual** yang diperlukan. Setelah ini semua core apps dikelola ArgoCD otomatis.

```bash
cd /home/mamat/migrate-gcp

kubectl apply -f gitops/root-app.yaml
```

ArgoCD akan otomatis:
1. Mendeteksi semua file di `gitops/core/`
2. Membuat Applications: `gateway-api-crds`, `nginx-gateway-fabric`, `gateway-config`, `cert-manager`
3. Sync semua Applications ke cluster

### STEP 4 — Monitor Sync Progress

```bash
# Cek semua Applications
kubectl get applications -n argocd

# Atau via ArgoCD UI
# https://<node-ip>:30443
```

**Urutan sync yang benar** (ArgoCD menangani ini otomatis via dependency):
```
1. gateway-api-crds   → Install Gateway API CRDs
2. nginx-gateway-fabric → Install NGF + buat LoadBalancer
3. gateway-config     → Buat Gateway + HTTPRoute resources
4. cert-manager       → Install cert-manager (untuk TLS nanti)
```

### STEP 5 — Tunggu External IP

Setelah `nginx-gateway-fabric` sync, tunggu Google Cloud buat Load Balancer:

```bash
# Pantau service NGF sampai dapat EXTERNAL-IP
kubectl get svc -n nginx-gateway --watch

# Output yang diharapkan:
# NAME                     TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)
# nginx-gateway-fabric     LoadBalancer   10.2.x.x      34.101.x.x       80:xxx/TCP,443:xxx/TCP
```

> ⏱️ Estimasi waktu: **2–5 menit** untuk GKE provision Network Load Balancer

### STEP 6 — Verifikasi Gateway

```bash
# Cek status Gateway
kubectl get gateway -n nginx-gateway

# Output yang diharapkan:
# NAME           CLASS   ADDRESS        PROGRAMMED   AGE
# main-gateway   nginx   34.101.x.x     True         2m

# Cek HTTPRoutes
kubectl get httproute -A

# Output yang diharapkan:
# NAMESPACE  NAME         HOSTNAMES   PARENT                    AGE
# front      route-front              nginx-gateway/main-gateway  2m
# back       route-back               nginx-gateway/main-gateway  2m
```

### STEP 7 — Test Akses

```bash
# Ambil External IP gateway
GATEWAY_IP=$(kubectl get gateway main-gateway -n nginx-gateway \
  -o jsonpath='{.status.addresses[0].value}')

echo "Gateway IP: $GATEWAY_IP"

# Test frontend (/)
curl -v http://$GATEWAY_IP/
# Harus mengembalikan HTML dari nginx dummy-front

# Test backend (/api/)
curl -v http://$GATEWAY_IP/api/get
# Harus mengembalikan JSON dari httpbin dummy-back
```

---

## 🔒 Setup HTTPS dengan cert-manager (Opsional)

Aktifkan HTTPS setelah kamu punya domain yang mengarah ke `GATEWAY_IP`.

### STEP A — Buat ClusterIssuer

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: tiyassulistiya96@gmail.com  # ganti dengan email kamu
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        gatewayHTTPRoute:
          parentRefs:
          - name: main-gateway
            namespace: nginx-gateway
            kind: Gateway
EOF
```

### STEP B — Uncomment HTTPS listener di gateway.yaml

Edit `k8s/gateway/gateway.yaml`, uncomment bagian `https` listener dan set `certificateRefs`.

### STEP C — Commit & Push

```bash
git add k8s/gateway/gateway.yaml
git commit -m "feat: enable HTTPS listener"
git push

# ArgoCD akan otomatis sync dan apply perubahan
```

---

## 🔄 Update Routing

Semua perubahan routing dilakukan via **git**, ArgoCD sync otomatis:

### Tambah route baru

```bash
# Buat file httproute-xxx.yaml di k8s/gateway/
# Tambahkan ke k8s/gateway/kustomization.yaml
git add k8s/gateway/
git commit -m "feat: add route for xxx service"
git push
# ArgoCD sync dalam ~3 menit (interval default)
```

### Force sync manual

```bash
# Via CLI
argocd app sync gateway-config

# Atau via UI: ArgoCD → gateway-config → Sync
```

---

## 🛠️ Troubleshooting

### Gateway STATUS bukan "Programmed: True"

```bash
kubectl describe gateway main-gateway -n nginx-gateway
# Lihat bagian Conditions
```

Penyebab umum:
- GatewayClass `nginx` belum terbuat (tunggu NGF sync selesai)
- NGF pods belum Running (`kubectl get pods -n nginx-gateway`)

### Service NGF tidak dapat External IP

```bash
kubectl describe svc nginx-gateway-fabric -n nginx-gateway
# Lihat Events
```

Penyebab umum:
- GKE perlu 2-5 menit untuk provision LB
- Node pool `general` di-scale ke 0 → jalankan `make scale-up-pool POOL=general`

### HTTPRoute tidak ter-attach ke Gateway

```bash
kubectl describe httproute route-front -n front
# Cek bagian "Parents" dan "Conditions"
```

Penyebab umum:
- Namespace `front`/`back` belum ada → `kubectl apply -f k8s/namespaces/`
- Service `dummy-front-svc` / `dummy-back-svc` belum ada → `make deploy`

### ArgoCD App berstatus OutOfSync

```bash
# Force refresh
argocd app get gateway-config --refresh

# Hard refresh (bersihkan cache)
argocd app sync gateway-config --force
```

---

## 📋 Referensi Perintah Cepat

```bash
# Status semua Applications
kubectl get applications -n argocd

# Status Gateway
kubectl get gateway,httproute -A

# External IP
kubectl get svc nginx-gateway-fabric -n nginx-gateway

# Logs NGF controller
kubectl logs -n nginx-gateway \
  -l app.kubernetes.io/name=nginx-gateway-fabric \
  --tail=50

# Force sync semua core apps
argocd app sync core-apps --cascade
```

---

## 💰 Estimasi Biaya Tambahan

| Resource | Spec | ~Biaya/bln |
|---|---|---|
| Google Cloud L4 Network LB | Regional, Standard | ~$18 |
| Forwarding Rules (2: HTTP+HTTPS) | per rule $0.025/jam | ~$18 |
| **Total tambahan** | | **~$18–36/bln** |

> Tip: Jika hanya butuh 1 port (HTTP/HTTPS), biaya forwarding rule berkurang setengah.
