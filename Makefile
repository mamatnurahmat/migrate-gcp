PROJECT_ID ?= migrate-gcp-dev
ZONE       ?= asia-southeast2-a
REGION     ?= asia-southeast2
CLUSTER    ?= gke-main
TF_DIR     := terraform
K8S_DIR    := k8s

.PHONY: help init validate plan apply destroy connect deploy status clean logs

# ─── DEFAULT ──────────────────────────────────────────────────
help: ## Tampilkan daftar perintah yang tersedia
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# ─── TERRAFORM ────────────────────────────────────────────────
init: ## Init Terraform (download providers)
	cd $(TF_DIR) && terraform init

validate: ## Validasi syntax Terraform
	cd $(TF_DIR) && terraform validate

plan: ## Preview perubahan infrastruktur
	cd $(TF_DIR) && terraform plan -var-file=terraform.tfvars

apply: ## Buat/update infrastruktur di GCP Jakarta
	cd $(TF_DIR) && terraform apply -var-file=terraform.tfvars -auto-approve

destroy: ## ⚠️  Hapus semua infrastruktur
	cd $(TF_DIR) && terraform destroy -var-file=terraform.tfvars -auto-approve

output: ## Lihat output Terraform
	cd $(TF_DIR) && terraform output

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

# ─── FULL WORKFLOW ────────────────────────────────────────────
setup: init apply connect deploy status ## 🚀 Full setup dari awal (init → apply → connect → deploy)
