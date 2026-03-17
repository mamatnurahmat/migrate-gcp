PROJECT_ID  ?= project-065701e7-213d-458b-a83
ZONE        ?= asia-southeast2-a
REGION      ?= asia-southeast2
CLUSTER     ?= gke-main
TF_DIR      := terraform
VM_DIR      := vm
K8S_DIR     := k8s
# Node pools yang akan di-scale (pisahkan dengan spasi)
NODE_POOLS  ?= general front back

.PHONY: help init validate plan apply destroy output connect \
        deploy argocd argocd-pass argocd-url \
        status logs-front logs-back clean \
        scale-down scale-up node-status setup \
        vm-init vm-plan vm-apply vm-destroy vm-ssh vm-output

# ─── DEFAULT ──────────────────────────────────────────────────
help: ## Tampilkan daftar perintah yang tersedia
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ─── TERRAFORM (GKE) ──────────────────────────────────────────
init: ## Init Terraform GKE (download providers)
	cd $(TF_DIR) && terraform init

validate: ## Validasi syntax Terraform GKE
	cd $(TF_DIR) && terraform validate

plan: ## Preview perubahan infrastruktur GKE
	cd $(TF_DIR) && terraform plan -var-file=terraform.tfvars

apply: ## Buat/update infrastruktur GKE di GCP Jakarta
	cd $(TF_DIR) && terraform apply -var-file=terraform.tfvars -auto-approve

destroy: ## ⚠️  Hapus semua infrastruktur GKE
	cd $(TF_DIR) && terraform destroy -var-file=terraform.tfvars -auto-approve

output: ## Lihat output Terraform GKE
	cd $(TF_DIR) && terraform output

# ─── TERRAFORM (VM) ───────────────────────────────────────────
vm-init: ## Init Terraform VM
	cd $(VM_DIR) && terraform init

vm-plan: ## Preview VM yang akan dibuat
	cd $(VM_DIR) && terraform plan -var-file=terraform.tfvars

vm-apply: ## Buat Ubuntu VM di GCP
	cd $(VM_DIR) && terraform apply -var-file=terraform.tfvars -auto-approve

vm-destroy: ## ⚠️  Hapus VM
	cd $(VM_DIR) && terraform destroy -var-file=terraform.tfvars -auto-approve

vm-output: ## Lihat output VM (IP, SSH command)
	cd $(VM_DIR) && terraform output

vm-ssh: ## SSH langsung ke VM
	@SSH_CMD=$$(cd $(VM_DIR) && terraform output -raw ssh_command 2>/dev/null); \
	 echo "Connecting: $$SSH_CMD"; \
	 eval $$SSH_CMD

# ─── KUBECTL ──────────────────────────────────────────────────
connect: ## Konfigurasi kubectl ke GKE cluster
	gcloud container clusters get-credentials $(CLUSTER) \
	  --zone $(ZONE) \
	  --project $(PROJECT_ID)

# ─── KUBERNETES ───────────────────────────────────────────────
deploy: ## Deploy semua K8s manifests (namespace + apps)
	kubectl apply -f $(K8S_DIR)/namespaces/
	kubectl apply -f $(K8S_DIR)/dummy-front/
	kubectl apply -f $(K8S_DIR)/dummy-back/

argocd: ## Deploy ArgoCD via Kustomize (NodePort 30080/30443)
	kubectl apply -k $(K8S_DIR)/argocd/ --server-side --force-conflicts
	@echo "\n⏳ Menunggu ArgoCD siap..."
	kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
	@echo "\n✅ ArgoCD siap!"
	@echo "🔑 Ambil password awal dengan: make argocd-pass"

argocd-pass: ## Tampilkan initial admin password ArgoCD
	@kubectl -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath="{.data.password}" | base64 -d && echo

argocd-url: ## Tampilkan NodePort URL ArgoCD
	@NODE_IP=$$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}'); \
	 echo "ArgoCD UI: https://$$NODE_IP:30443"

status: ## Status nodes dan pods
	@echo "\n=== NODES ==="; kubectl get nodes -o wide
	@echo "\n=== PODS ===";  kubectl get pods -A -o wide
	@echo "\n=== SERVICES ==="; kubectl get svc -A

logs-front: ## Logs dummy-front pod
	kubectl logs -n front -l app=dummy-front --tail=50

logs-back: ## Logs dummy-back pod
	kubectl logs -n back -l app=dummy-back --tail=50

clean: ## Hapus dummy apps dari cluster (tidak hapus infra)
	kubectl delete -f $(K8S_DIR)/dummy-front/ --ignore-not-found
	kubectl delete -f $(K8S_DIR)/dummy-back/ --ignore-not-found

# ─── NODE SCALING ─────────────────────────────────────────────
scale-down: ## 💤 Scale semua node pool ke 0 (hemat biaya)
	@echo "⏬ Scale DOWN semua node pool ke 0..."
	@for pool in $(NODE_POOLS); do \
	  echo "  → Scaling $$pool ke 0..."; \
	  gcloud container clusters resize $(CLUSTER) \
	    --node-pool=$$pool \
	    --num-nodes=0 \
	    --zone=$(ZONE) \
	    --project=$(PROJECT_ID) \
	    --quiet; \
	done
	@echo "\n✅ Semua node pool sudah di-scale ke 0"
	@echo "💡 Jalankan 'make scale-up' untuk aktifkan kembali"

scale-up: ## ▶️  Scale semua node pool kembali ke 1 node
	@echo "⏫ Scale UP semua node pool ke 1..."
	@for pool in $(NODE_POOLS); do \
	  echo "  → Scaling $$pool ke 1..."; \
	  gcloud container clusters resize $(CLUSTER) \
	    --node-pool=$$pool \
	    --num-nodes=1 \
	    --zone=$(ZONE) \
	    --project=$(PROJECT_ID) \
	    --quiet; \
	done
	@echo "\n✅ Semua node pool sudah aktif kembali"
	@echo "💡 Tunggu beberapa menit lalu jalankan 'make status'"

scale-down-pool: ## 💤 Scale satu node pool ke 0 (gunakan: make scale-down-pool POOL=front)
	@echo "⏬ Scaling node pool '$(POOL)' ke 0..."
	gcloud container clusters resize $(CLUSTER) \
	  --node-pool=$(POOL) \
	  --num-nodes=0 \
	  --zone=$(ZONE) \
	  --project=$(PROJECT_ID) \
	  --quiet
	@echo "✅ Node pool '$(POOL)' di-scale ke 0"

scale-up-pool: ## ▶️  Scale satu node pool ke 1 (gunakan: make scale-up-pool POOL=front)
	@echo "⏫ Scaling node pool '$(POOL)' ke 1..."
	gcloud container clusters resize $(CLUSTER) \
	  --node-pool=$(POOL) \
	  --num-nodes=1 \
	  --zone=$(ZONE) \
	  --project=$(PROJECT_ID) \
	  --quiet
	@echo "✅ Node pool '$(POOL)' aktif kembali"

node-status: ## 📊 Lihat jumlah node per pool saat ini
	@echo "\n=== NODE STATUS ==="
	@kubectl get nodes --show-labels | grep -o 'role=[a-z]*' | sort | uniq -c
	@echo ""
	@kubectl get nodes -o wide

# ─── FULL WORKFLOW ────────────────────────────────────────────
setup: init apply connect deploy status ## 🚀 Full setup dari awal (init → apply → connect → deploy)
